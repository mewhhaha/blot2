import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
entry const run = fn (host: U32 -> Array U32 ! {Foreign}) => do:
  use initial <- host 0
  let seed = initial[0]
  let count = initial[1]
  let worker = fn (value: U32) => do:
    use reply <- host (value + 1)
    let local = #[value, value + 1]
    let pressure = @array.fill 8192 value
    if value % 2 == 0:
      return seed + reply[0] + local[0] + pressure[0] - value
    return seed + reply[1] + local[1] + pressure[0] - value
  let sum = 0
  for index in 0..count:
    use produced <- worker index
    sum := self + produced
  return sum
entry const floating = fn (host: F32 -> Array F32 ! {Foreign}) => do:
  use initial <- host 0.0
  let seed = initial[0]
  let worker = fn (value: F32) => do:
    use reply <- host value
    let local = #[value]
    if value == 0.0:
      return seed
    return local[0] + reply[0]
  use answer <- worker (-0.0)
  return answer
`;

Deno.test("private scalar captures preserve early exits loop reentry host suspension and failed producer edits", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-scalar-capture-" });
  const entry = `${directory}/main.blot`;
  try {
    for (const codegenTier of ["development", "optimized"] as const) {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        cacheDirectory: false,
        codegenTier,
        shareMachineCode: true,
      });
      try {
        const edited = source.replace(
          "return seed + reply[1]",
          "return seed + 1 + reply[1]",
        );
        for (const [revision, text] of [source, edited, source].entries()) {
          const built = await compiler.build({ sources: { [entry]: text } });
          assert(built.success, JSON.stringify(built));
          if (revision === 0) {
            const failed = await compiler.build({
              sources: {
                [entry]: text.replace("return sum", "return missing"),
              },
            });
            assert(!failed.success);
          }
          const fresh = await createZigProjectCompiler({
            executable,
            entry,
            prelude: new URL("../../std/prelude.blot", import.meta.url),
            cacheDirectory: false,
            codegenTier,
            shareMachineCode: true,
          });
          try {
            const repeated = await fresh.build({ sources: { [entry]: text } });
            assert(repeated.success, JSON.stringify(repeated));
            assert.deepEqual(built.bytes, repeated.bytes);
          } finally {
            await fresh.dispose();
          }
          for (const asynchronous of [false, true]) {
            const guest = await instantiateGuest(built.bytes, { asynchronous });
            try {
              const cause = new Error("private scalar callback failed");
              const values = (value: number, count: number, failAt: number) => {
                if (value === failAt) throw cause;
                if (value === 0) return Uint32Array.of(41, count);
                return Uint32Array.of(value - 1, value);
              };
              const hostFor = (count: number, failAt = -1) => {
                if (asynchronous) {
                  return guest.capabilityAsync({
                    parameter: "U32",
                    result: "Array U32",
                    call: async (value) => {
                      await Promise.resolve();
                      return values(value, count, failAt);
                    },
                  });
                }
                return guest.capability({
                  parameter: "U32",
                  result: "Array U32",
                  call: (value) => values(value, count, failAt),
                });
              };
              let warmed = 0;
              for (const count of [8, 200, 8]) {
                let expected = count * 41 + count * (count - 1) +
                  2 * Math.floor(count / 2);
                if (revision === 1) expected += Math.floor(count / 2);
                let result;
                if (asynchronous) {
                  result = await guest.callAsync("run", hostFor(count));
                } else result = guest.call("run", hostFor(count));
                assert.equal(result, expected);
                if (warmed) assert(guest.memoryBytes() <= warmed + 65536);
                else warmed = guest.memoryBytes();
              }
              if (asynchronous) {
                await assert.rejects(
                  guest.callAsync("run", hostFor(8, 2)),
                  (error) => error instanceof Error && error.cause === cause,
                );
                assert.equal(await guest.callAsync("run", hostFor(0)), 0);
              } else {
                assert.throws(
                  () => guest.call("run", hostFor(8, 2)),
                  (error) => error instanceof Error && error.cause === cause,
                );
                assert.equal(guest.call("run", hostFor(0)), 0);
              }
              let floating;
              if (asynchronous) {
                const floats = guest.capabilityAsync({
                  parameter: "F32",
                  result: "Array F32",
                  call: async () => {
                    await Promise.resolve();
                    return Float32Array.of(-0);
                  },
                });
                floating = await guest.callAsync("floating", floats);
              } else {
                const floats = guest.capability({
                  parameter: "F32",
                  result: "Array F32",
                  call: () => Float32Array.of(-0),
                });
                floating = guest.call("floating", floats);
              }
              assert(Object.is(floating, -0));
              assert(guest.memoryBytes() <= warmed + 65536);
            } finally {
              guest.dispose();
            }
          }
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
