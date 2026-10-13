import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const header = `type State a is effect = {get: Unit -> a, set: a -> Unit}\n`;
const nested = header + `
entry const answer = fn () => @effect.scope (fn (left: State U32) =>
  @effect.scope (fn (right: State U32) => do:
    let (outer, result) = do (@effect.state left.get left.set 10):
      use nested <- do (@effect.state right.get right.set 100):
        use a <- left.get ()
        use b <- right.get ()
        use left.set (@u32.add a 1)
        use right.set (@u32.add b 2)
        return #[a, b]
      let (inner, reads) = nested
      return @array.concat #[inner] reads
    return @array.concat #[outer] result
  )
)
`;

const aliases = header + `
entry const answer = fn () => @effect.scope (fn (s: State U32) => do:
  let capability = s
  let read = capability.get
  let write = capability.set
  let local = fn () => read ()
  let (state, result) = do (@effect.state read write 7):
    return local ()
  return result
)
`;
const forwarding = header + `
entry const answer = fn () => @effect.scope (fn (left: State U32) =>
  @effect.scope (fn (right: State U32) => do (@effect.provider left.get (fn () => 20)):
    return do (@effect.provider right.get (fn () => left.get ())):
      return do (@effect.provider left.get (fn () => 99)):
        use direct <- left.get ()
        use forwarded <- right.get ()
        return @u32.add direct forwarded
  )
)
entry const shadow = fn () => @effect.scope (fn (s: State U32) => do:
  let (outer, result) = do (@effect.state s.get s.set 10):
    use nested <- do (@effect.state s.get s.set 100):
      return s.get ()
    let (inner, read) = nested
    use current <- s.get ()
    return @u32.add current read
  return result
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
entry const answer = fn (host: U32 -> U32 ! {Foreign}) => @effect.scope (fn (s: State U32) => do:
  let provider = @effect.state s.get s.set 10
  use nested <- do provider:
    use previous <- s.get ()
    use next <- host previous
    use s.set next
    return s.get ()
  let (state, result) = nested
  return result
)
entry const trapped = fn (divisor: U32) => @effect.scope (fn (s: State U32) => do:
  let (state, result) = do (@effect.state s.get s.set 10):
    use previous <- s.get ()
    return @u32.div previous divisor
  return result
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
            "entry const bad = fn () => @effect.scope (fn (s: State U32) => s)\n",
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
