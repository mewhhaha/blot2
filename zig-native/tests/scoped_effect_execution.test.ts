import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const header = `type State a is effect = {get: Unit -> a, set: a -> Unit}\n`;
const nested = header + `
entry const answer = func () => return @effect.scope (func (left: State U32) => return
  @effect.scope (func (right: State U32) => return do:
    let (outer, result) = do (@effect.state left.get left.set 10):
      use nested <- do (@effect.state right.get right.set 100):
        use a <- left.get ()
        use b <- right.get ()
        use left.set (@u32.add a 1)
        use right.set (@u32.add b 2)
        break #[a, b]
      let (inner, reads) = nested
      break @array.concat #[inner] reads
    break @array.concat #[outer] result
  )
)
`;

const aliases = header + `
entry const answer = func () => return @effect.scope (func (s: State U32) => return do:
  let capability = s
  let read = capability.get
  let write = capability.set
  let local = func () => return read ()
  let (state, result) = do (@effect.state read write 7):
    break local ()
  break result
)
`;
const forwarding = header + `
entry const answer = func () => return @effect.scope (func (left: State U32) => return
  @effect.scope (func (right: State U32) => return do (@effect.provider left.get (func () => return 20)):
    break do (@effect.provider right.get (func () => return left.get ())):
      break do (@effect.provider left.get (func () => return 99)):
        use direct <- left.get ()
        use forwarded <- right.get ()
        break @u32.add direct forwarded
  )
)
entry const shadow = func () => return @effect.scope (func (s: State U32) => return do:
  let (outer, result) = do (@effect.state s.get s.set 10):
    use nested <- do (@effect.state s.get s.set 100):
      break s.get ()
    let (inner, read) = nested
    use current <- s.get ()
    break @u32.add current read
  break result
)
`;

Deno.test("scoped same-typed effect owners route independently on repeated entries", async () => {
  await compileAndRun(nested, (guest) => {
    for (let i = 0; i < 10; i++) {
      assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
        11,
        102,
        10,
        100,
      ]);
    }
  }, { prelude: "none" });
});

Deno.test("scoped capability operation aliases retain their owner in local callbacks", async () => {
  await compileAndRun(aliases, (guest) => {
    assert.equal(guest.call("answer", null), 7);
  }, { prelude: "none" });
});

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const hostSource = header + `
entry const answer = func (host: U32 -> U32 ! {Foreign}) => return @effect.scope (func (s: State U32) => return do:
  let provider = @effect.state s.get s.set 10
  use nested <- do provider:
    use previous <- s.get ()
    use next <- host previous
    use s.set next
    break s.get ()
  let (state, result) = nested
  break result
)
entry const trapped = func (divisor: U32) => return @effect.scope (func (s: State U32) => return do:
  let (state, result) = do (@effect.state s.get s.set 10):
    use previous <- s.get ()
    break @u32.div previous divisor
  break result
)
`;
for (const codegenTier of ["optimized", "development"] as const) {
  Deno.test(`scoped routing forwarding and aliases survive retained edits and checkpoints (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-scoped-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      for (const source of [nested, aliases, forwarding, nested]) {
        const sources = { [entry]: source };
        const built = await compiler.build({ sources });
        assert(built.success, JSON.stringify(built));
        const guest = await instantiateGuest(built.bytes);
        try {
          for (let i = 0; i < 5; i++) {
            if (source === nested) {
              assert.deepEqual(
                Array.from(guest.call("answer", null) as Uint32Array),
                [11, 102, 10, 100],
              );
            }
            if (source === aliases) assert.equal(guest.call("answer", null), 7);
            if (source === forwarding) {
              assert.equal(guest.call("answer", null), 119);
              assert.equal(guest.call("shadow", null), 110);
            }
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
      const rejected = await compiler.build({
        sources: {
          [entry]: header +
            "entry const bad = func () => return @effect.scope (func (s: State U32) => return s)\n",
        },
      });
      assert(!rejected.success);
      assert.equal(rejected.diagnostics[0].code, "capability_escape");
      const recovered = await compiler.build({ sources: { [entry]: nested } });
      assert(recovered.success, JSON.stringify(recovered));
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
  Deno.test(`scoped providers survive host suspension and clean up rejection/trap (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-scoped-host-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: null,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: hostSource } });
      assert(built.success, JSON.stringify(built));
      const synchronousGuest = await instantiateGuest(built.bytes);
      try {
        const host = synchronousGuest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => Number(value) + 2,
        });
        assert.equal(synchronousGuest.call("answer", host), 12);
        assert.throws(
          () => synchronousGuest.call("trapped", 0),
          WebAssembly.RuntimeError,
        );
        assert.equal(synchronousGuest.call("trapped", 2), 5);
      } finally {
        synchronousGuest.dispose();
      }
      const guest = await instantiateGuest(built.bytes, { asynchronous: true });
      try {
        const synchronous = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => Number(value) + 2,
        });
        assert.equal(await guest.callAsync("answer", synchronous), 12);
        let settle: ((value: number) => void) | undefined;
        const asynchronous = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            assert.equal(value, 10);
            return new Promise<number>((resolve) => {
              settle = resolve;
            });
          },
        });
        const pending = guest.callAsync("answer", asynchronous);
        assert(settle);
        settle(42);
        assert.equal(await pending, 42);
        const rejecting = guest.capabilityAsync({
          parameter: "U32",
          result: "U32",
          call: () => Promise.reject(new Error("scope host rejection")),
        });
        await assert.rejects(guest.callAsync("answer", rejecting), (error) => {
          assert.equal((error as { code: string }).code, "host_exception");
          assert.equal(
            (error as Error).cause instanceof Error &&
              ((error as Error).cause as Error).message,
            "scope host rejection",
          );
          return true;
        });
        assert.equal(await guest.callAsync("answer", synchronous), 12);
        await assert.rejects(
          guest.callAsync("trapped", 0),
          WebAssembly.RuntimeError,
        );
        assert.equal(await guest.callAsync("trapped", 2), 5);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}

Deno.test("scoped source consumes the same imported effect declaration through compiled dependencies", async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-scoped-dependency-",
  });
  const entry = `${directory}/main.blot`;
  const dependency = `${directory}/state.blot`;
  const archive = `${directory}/state.blotdep`;
  const source = aliases.replace(header, 'import { State } from "./state"\n');
  try {
    await Deno.writeTextFile(entry, source);
    await Deno.writeTextFile(dependency, header);
    const packed = await new Deno.Command(executable, {
      args: ["dependencies", entry, archive, "--prelude", "none"],
      stdout: "piped",
      stderr: "piped",
    }).output();
    assert(
      packed.success,
      new TextDecoder().decode(packed.stdout) +
        new TextDecoder().decode(packed.stderr),
    );
    for (const dependencies of [undefined, archive]) {
      for (const codegenTier of ["optimized", "development"] as const) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: null,
          codegenTier,
          dependencies,
          cacheDirectory: false,
        });
        try {
          const built = await compiler.build();
          assert(built.success, JSON.stringify(built));
          const guest = await instantiateGuest(built.bytes);
          try {
            assert.equal(guest.call("answer", null), 7);
          } finally {
            guest.dispose();
          }
        } finally {
          await compiler.dispose();
        }
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
