import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const header = `type State a is effect = {get: Unit -> a, set: a -> Unit}\n`;
const source = header + `
entry const answer = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let right_read = right.get
  let computation = @computation (func () => return do:
    use a <- left.get ()
    use b <- right_read ()
    break @u32.add a b
  )
  for request in @requests computation:
    case request of
      effect left.get () =>
        yield 11
      effect right_read () =>
        yield 102
      complete value =>
        break value
))
entry const forwarded = func () => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do (@effect.provider left.get (func () => return 20)):
  let computation = @computation (func () => return do:
    use a <- left.get ()
    use b <- right.get ()
    break @u32.add a b
  )
  for request in @requests computation:
    case request of
      effect right.get () =>
        yield left.get ()
      complete value =>
        break value
))
entry const cancelled = func () => return @effect.scope (func (s: State U32) => return do:
  let computation = @computation (func () => return do:
    use s.get ()
    break @panic "cancelled computation continued"
  )
  for request in @requests computation:
    case request of
      effect s.get () =>
        break 42
      complete value =>
        break value
)
type Validate is effect = {check: U32 -> U32}
const keep = func ~value => return func () => return @force value
entry const retry = func () => return do:
  let delayed = keep (@effect.scope (func (s: State U32) => return do:
    use nested <- do (@effect.state s.get s.set 7):
      use previous <- s.get ()
      use reply <- Validate.check previous
      use s.set reply
      break s.get ()
    let (state, result) = nested
    break result
  ))
  let computation = @computation (func () => return delayed ())
  let first = do:
    for request in @requests computation:
      case request of
        effect Validate.check value =>
          break 40
        complete value =>
          break value
  let second = do:
    for request in @requests computation:
      case request of
        effect Validate.check value =>
          yield @u32.sub value 5
        complete value =>
          break value
  break @u32.add first second
entry const host = func (callback: U32 -> U32 ! {Foreign}) => return @effect.scope (func (left: State U32) => return @effect.scope (func (right: State U32) => return do:
  let computation = @computation (func () => return do:
    use a <- left.get ()
    use b <- right.get ()
    break @u32.add a b
  )
  for request in @requests computation:
    case request of
      effect left.get () =>
        yield callback 10
      effect right.get () =>
        yield 100
      complete value =>
        break value
))
`;

for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`scoped request keys forward cancel retry and survive checkpoints (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-request-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      for (
        const text of [source, source.replace("yield 102", "yield 103"), source]
      ) {
        const sources = { [entry]: text };
        const built = await compiler.build({ sources });
        assert(built.success, JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes);
        try {
          for (let i = 0; i < 5; i++) {
            let expected = 113;
            if (text !== source) expected = 114;
            assert.equal(guest.call("answer", null), expected);
            assert.equal(guest.call("forwarded", null), 40);
            assert.equal(guest.call("cancelled", null), 42);
            assert.equal(guest.call("retry", null), 42);
          }
        } finally {
          guest.dispose();
        }
        const checkpoint = await compiler.exportCheckpoint();
        const restored = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          codegenTier,
          cacheDirectory: false,
          checkpoint,
        });
        try {
          const rebuilt = await restored.build({ sources });
          assert(rebuilt.success, JSON.stringify(rebuilt));
          assert.deepEqual(rebuilt.bytes, built.bytes);
        } finally {
          await restored.dispose();
        }
      }
      const duplicated = source.replace(
        "effect right_read ()",
        "effect left.get ()",
      );
      const rejected = await compiler.build({
        sources: { [entry]: duplicated },
      });
      assert(!rejected.success);
      assert.equal(rejected.diagnostics[0].code, "duplicate_request_handler");
      const recovered = await compiler.build({ sources: { [entry]: source } });
      assert(recovered.success, JSON.stringify(recovered));
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });

  Deno.test(`scoped request owners remain active through JSPI callbacks and revoke on rejection (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scoped-request-host-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes, { asynchronous: true });
      try {
        const synchronous = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => Number(value) + 2,
        });
        assert.equal(await guest.callAsync("host", synchronous), 112);
        let settle: ((value: number) => void) | undefined;
        const suspended = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            assert.equal(value, 10);
            return new Promise<number>((resolve) => {
              settle = resolve;
            });
          },
        });
        const pending = guest.callAsync("host", suspended);
        assert(settle);
        settle(42);
        assert.equal(await pending, 142);
        const rejected = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: () => Promise.reject(new Error("request host rejection")),
        });
        await assert.rejects(guest.callAsync("host", rejected), (error) => {
          assert.equal((error as { code: string }).code, "host_exception");
          return true;
        });
        assert.equal(await guest.callAsync("host", synchronous), 112);
        assert.equal(await guest.callAsync("cancelled", null), 42);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
