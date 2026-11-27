import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";
import { compileExpectedFailure } from "./compile_helpers.ts";

const sources = [{
  name: "generated scratch appends cleanly into owned destination",
  source:
    `const write = func (destination: own Array F32) -> (input: F32): Array F32 => return do:
  let seed = @array.fill 3 input
  for index in 0 .. 3:
    @storage.push destination (input + U32.to_f32 index)
  let generated = @array.generate 3 (func (index: U32) => return seed[index] * 2.0 + U32.to_f32 index)
  for value in generated:
    @storage.push destination value
  return destination
io const answer = func (input: F32) => return do:
  let destination: Array F32 = #[]
  destination := write self input
  destination := write self (input + 10.0)
  return destination
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
}];
for (const item of sources) {
  Deno.test(`${item.name}`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "squid-scratch-generators-",
    });
    const entry = `${directory}/main.sq`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.sq`,
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

Deno.test("generated scratch rejects mutating captured destination or module global", async () => {
  await compileExpectedFailure(
    `const write = func (destination: own Array F32) -> (input: F32): Array F32 => return do:
  let _ = @array.generate 3 (func (index: U32) => return do:
    @storage.push destination (input + U32.to_f32 index)
    return input)
  return destination
io const answer = func (input: F32) => return write #[] input
`,
    "aliased_update",
  );
  await compileExpectedFailure(
    `const pool: Array U32 = #[0]
io const answer = func (input: U32) => return do:
  @storage.push pool input
  return pool[0]
`,
    "aliased_update",
  );
});
