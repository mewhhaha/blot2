import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
entry const local = fn (count: U32) => do:
  let sum = 0
  for index in 0..count:
    let pair = (#[index, index + 1], index)
    let first = pair
    let second = first
    let (left, _) = first
    let (right, _) = second
    let pressure = @array.fill 8192 index
    sum := self + left[0] + right[1] + pressure[8191]
  break sum
entry const carries = fn (count: U32) => do:
  let current = (#[7, 42], 0)
  let previous = current
  let saved = current
  let sum = 0
  for index in 0..count:
    let old = current
    let replacement = (#[index, index + 1], index)
    previous := old
    current := replacement
    for nested in 0..2:
      let shadow = old
      let (child, _) = shadow
      let pressure = @array.fill 8192 nested
      sum := self + child[0] + pressure[8191]
  let (before, _) = previous
  let (after, _) = current
  let (original, _) = saved
  break #[sum, before[0], after[0], original[1]]
entry const suspended = fn (host: Array U32 -> U32 ! {Foreign}) => do:
  let pair = (#[7, 42], 99)
  let first = pair
  let second = first
  let (left, _) = first
  let (right, _) = second
  use answer <- host left
  let pressure = @array.fill 8192 answer
  break #[right[0], right[1], pressure[8191]]
`;

Deno.test("single activation owners preserve immutable aliases old carries nested snapshots and suspended failures", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-activation-" });
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
        const built = await compiler.build({ sources: { [entry]: source } });
        assert(built.success, JSON.stringify(built));
        const reused = await compiler.build({ sources: { [entry]: source } });
        assert(reused.success, JSON.stringify(reused));
        assert.deepEqual(built.bytes, reused.bytes);
        const module = new WebAssembly.Module(built.bytes);
        assert.deepEqual([
          ...new Uint8Array(
            WebAssembly.Module.customSections(module, "blot:ownership")[0],
          ),
        ], [2, 2, 0]);
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(built.bytes, { asynchronous });
          const invoke = (name: string, value: number) => {
            if (asynchronous) return guest.callAsync(name, value);
            return guest.call(name, value);
          };
          try {
            let warmed = 0;
            for (const count of [8, 200, 8]) {
              assert.equal(
                await invoke("local", count),
                3 * count * (count - 1) / 2 + count,
              );
              const sum = 14 + (count - 1) * (count - 2) + count;
              assert.deepEqual(
                await invoke("carries", count),
                Uint32Array.of(sum, count - 2, count - 1, 42),
              );
              if (warmed) assert(guest.memoryBytes() <= warmed + 65536);
              else warmed = guest.memoryBytes();
            }
            const cause = new Error("activation callback failed");
            const fail = (values: Uint32Array): never => {
              assert.deepEqual(values, Uint32Array.of(7, 42));
              throw cause;
            };
            if (asynchronous) {
              const host = guest.capabilityAsync({
                parameter: "Array U32",
                result: "U32",
                call: async (values) => {
                  await Promise.resolve();
                  return fail(values);
                },
              });
              await assert.rejects(
                guest.callAsync("suspended", host),
                (error) => error instanceof Error && error.cause === cause,
              );
              const good = guest.capabilityAsync({
                parameter: "Array U32",
                result: "U32",
                call: async (values) => {
                  await Promise.resolve();
                  return values[1];
                },
              });
              assert.deepEqual(
                await guest.callAsync("suspended", good),
                Uint32Array.of(7, 42, 42),
              );
            } else {
              const host = guest.capability({
                parameter: "Array U32",
                result: "U32",
                call: fail,
              });
              assert.throws(
                () => guest.call("suspended", host),
                (error) => error instanceof Error && error.cause === cause,
              );
              const good = guest.capability({
                parameter: "Array U32",
                result: "U32",
                call: (values) => values[1],
              });
              assert.deepEqual(
                guest.call("suspended", good),
                Uint32Array.of(7, 42, 42),
              );
            }
            assert(guest.memoryBytes() <= warmed + 65536);
          } finally {
            guest.dispose();
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
