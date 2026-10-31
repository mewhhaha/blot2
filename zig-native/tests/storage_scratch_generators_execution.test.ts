import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const sources = [{
  name: "generated scratch preserves captured destination effects",
  source:
    `const write = func (destination: GrowArray F32) -> (input: F32) => return do:
  let seed = @array.fill 3 input
  let generated = @array.generate 3 (func (index: U32) => return do:
    @storage.push destination (input + U32.to_f32 index)
    return seed[index] * 2.0 + U32.to_f32 index)
  for value in generated:
    @storage.push destination value
entry const answer = func (input: F32) => return do:
  let destination: GrowArray F32 = #[]
  write destination input
  write destination (input + 10.0)
  return @storage.freeze destination
`,
  expected: (
    input: number,
  ) => [
    input,
    input + 1,
    input + 2,
    input * 2,
    input * 2 + 1,
    input * 2 + 2,
    input + 10,
    input + 11,
    input + 12,
    (input + 10) * 2,
    (input + 10) * 2 + 1,
    (input + 10) * 2 + 2,
  ],
}, {
  name: "generated scratch declines implicit mutable global reads",
  source: `const pool: Array U32 = #[0]
const write = func (destination: GrowArray U32) => return do:
  let generated = @array.generate 2 (func (index: U32) => return do:
    @storage.push destination index
    return pool[0] + index)
  for value in generated:
    @storage.push destination value
entry const answer = func (input: U32) => return do:
  let destination: GrowArray U32 = #[]
  let live = pool
  live[0] := input
  write destination
  live[0] := input + 10
  write destination
  return @storage.freeze destination
`,
  expected: (
    input: number,
  ) => [0, 1, input, input + 1, 0, 1, input + 10, input + 11],
}];
for (const codegenTier of ["development", "optimized"] as const) {
  for (const item of sources) {
    Deno.test(`${item.name} (${codegenTier})`, async () => {
      const directory = await Deno.makeTempDir({
        prefix: "blot-scratch-generators-",
      });
      const entry = `${directory}/main.blot`;
      const stdRoot = new URL("../../std", import.meta.url).pathname;
      const compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.blot`,
        cacheDirectory: false,
        codegenTier,
      });
      try {
        const result = await compiler.build({
          sources: { [entry]: item.source },
        });
        assert(result.success, JSON.stringify(result));
        for (const asynchronous of [false, true]) {
          const guest = await instantiateGuest(result.bytes, { asynchronous });
          try {
            for (const input of [0, 3, 100]) {
              const value = asynchronous
                ? await guest.callAsync("answer", input)
                : guest.call("answer", input);
              assert.deepEqual(
                Array.from(value as Float32Array | Uint32Array),
                item.expected(input),
              );
            }
          } finally {
            guest.dispose();
          }
        }
      } finally {
        await compiler.dispose();
        await Deno.remove(directory, { recursive: true });
      }
    });
  }
}
