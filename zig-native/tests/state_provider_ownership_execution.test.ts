import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type State a is effect = {get: Unit -> a, set: a -> Unit}
const selected = func () => return State.get (Array U32) ()
const borrow = func () => return do:
  let local = @effect.state (State.get (Array U32)) (State.set (Array U32)) #[7, 42]
  let (_, old) = do local:
    use value <- selected ()
    use State.set (Array U32) #[90, 91]
    break value
  break old
entry const run = func (count: U32) => return do:
  use old <- borrow ()
  for index in 0..count:
    let pressure = @array.fill 8192 index
    if pressure[8191] != index:
      @panic "lost pressure"
  break old
entry const failed = func (host: Array U32 -> Unit ! {Foreign}) => return do:
  use old <- borrow ()
  use host old
  break old[1]
entry const floating = func () => return do:
  let local = @effect.state (State.get F32) (State.set F32) (-0.0)
  let (_, value) = do local:
    break State.get F32 ()
  break value
`;
const callback = `
entry const alternate = func (seed: U32) => return do:
  let local = @effect.provider (State.get (Array U32)) (func () => return #[seed + 1, 42])
  let result = do local:
    break selected ()
  break result
`;

Deno.test("State provider reads keep replaced fields alive across owner destruction cancellation and callback-mode edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-state-owner-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      for (const shareMachineCode of [false, true]) {
        const compiler = await createZigProjectCompiler({
          executable,
          entry,
          prelude: new URL("../../std/prelude.blot", import.meta.url),
          cacheDirectory: false,
          codegenTier,
          shareMachineCode,
        });
        try {
          for (const text of [source, source + callback, source]) {
            const built = await compiler.build({ sources: { [entry]: text } });
            assert(built.success, JSON.stringify(built));
            const fresh = await createZigProjectCompiler({
              executable,
              entry,
              prelude: new URL("../../std/prelude.blot", import.meta.url),
              cacheDirectory: false,
              codegenTier,
              shareMachineCode,
            });
            try {
              const rebuilt = await fresh.build({ sources: { [entry]: text } });
              assert(rebuilt.success, JSON.stringify(rebuilt));
              assert.deepEqual(built.bytes, rebuilt.bytes);
            } finally {
              await fresh.dispose();
            }
            for (const asynchronous of [false, true]) {
              const guest = await instantiateGuest(built.bytes, {
                asynchronous,
              });
              try {
                let warmed = 0;
                for (const count of [8, 200, 8]) {
                  let result;
                  if (asynchronous) {
                    result = await guest.callAsync("run", count);
                  } else result = guest.call("run", count);
                  assert.deepEqual(result, Uint32Array.of(7, 42));
                  if (warmed) assert(guest.memoryBytes() <= warmed + 65536);
                  else warmed = guest.memoryBytes();
                }
                let floating;
                if (asynchronous) {
                  floating = await guest.callAsync("floating", null);
                } else floating = guest.call("floating", null);
                assert(Object.is(floating, -0));
                if (text !== source) {
                  let result;
                  if (asynchronous) {
                    result = await guest.callAsync("alternate", 9);
                  } else result = guest.call("alternate", 9);
                  assert.deepEqual(result, Uint32Array.of(10, 42));
                }
                const cause = new Error("State field callback canceled");
                const check = (values: Uint32Array): never => {
                  assert.deepEqual(values, Uint32Array.of(7, 42));
                  throw cause;
                };
                if (asynchronous) {
                  const host = guest.capabilityAsync({
                    parameter: "Array U32",
                    result: "Unit",
                    call: async (values) => {
                      await Promise.resolve();
                      return check(values);
                    },
                  });
                  await assert.rejects(
                    guest.callAsync("failed", host),
                    (error) =>
                      error instanceof Error &&
                      (error === cause || error.cause === cause),
                  );
                  assert.deepEqual(
                    await guest.callAsync("run", 8),
                    Uint32Array.of(7, 42),
                  );
                } else {
                  const host = guest.capability({
                    parameter: "Array U32",
                    result: "Unit",
                    call: check,
                  });
                  assert.throws(
                    () => guest.call("failed", host),
                    (error) =>
                      error instanceof Error &&
                      (error === cause || error.cause === cause),
                  );
                  assert.deepEqual(guest.call("run", 8), Uint32Array.of(7, 42));
                }
              } finally {
                guest.dispose();
              }
            }
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
