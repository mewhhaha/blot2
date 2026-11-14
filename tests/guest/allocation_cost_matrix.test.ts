import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

const source = `
import * as array from "std/array"
type Box is data = $Box { a: U32, b: U32 }
type Fields = { a: U32, b: U32 }
const fields = func (value: U32): Fields => return { a: value, b: value + 1 }
const read = func (row: Fields): U32 => return row.a + row.b
const named = read
const apply = func (callback: Fields -> U32) -> (row: Fields): U32 => return callback row
const boxed = func (value: U32): Box => return $Box { a: value, b: value + 1 }
const read_box = func (row: Box): U32 => return row.a + row.b
entry const direct = func (value: U32): U32 => return do:
  let row = fields value
  break row.a + row.b
entry const helper = func (value: U32): U32 => return read (fields value)
entry const named_callback = func (value: U32): U32 => return named (fields value)
entry const inline_callback = func (value: U32): U32 => return apply (func (row: Fields) => return row.a + row.b) (fields value)
entry const generic_callback = func (value: U32): U32 => return apply read (fields value)
entry const aliased_callback = func (value: U32): U32 => return apply named (fields value)
entry const local_callback = func (value: U32): U32 => return do:
  let callback = func (row: Fields) => return row.a + row.b
  break apply callback (fields value)
entry const nominal_record = func (value: U32): U32 => return read_box (boxed value)
const replace = array.replace
const wrapped_replace = func (index: U32) -> (value: U32) -> (values: Array U32): Array U32 => return replace index value values
const direct_wrapper = func (index: U32) -> (value: U32) -> (values: Array U32): Array U32 => return array.replace index value values
const reordered_wrapper = func (values: Array U32) -> (index: U32) -> (value: U32): Array U32 => return array.replace index value values
entry const array_generate = func (count: U32): U32 => return do:
  let values = array.generate count (func (index: U32) => return index + 1)
  break values[count - 1]
entry const update_direct = func (count: U32): U32 => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1]
entry const update_wrapped = func (count: U32): U32 => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := wrapped_replace index (index + 1) values
  break values[count - 1]
entry const update_direct_wrapper = func (count: U32): U32 => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := direct_wrapper index (index + 1) values
  break values[count - 1]
entry const update_reordered_wrapper = func (count: U32): U32 => return do:
  let values = array.fill count 0
  for index in 0..count:
    values := reordered_wrapper values index (index + 1)
  break values[count - 1]
entry const update_snapshot = func (count: U32): U32 => return do:
  let values = array.fill count 0
  let previous = values
  for index in 0..count:
    values := array.replace index (index + 1) values
  break values[count - 1] + previous[count - 1]
`;

Deno.test("allocation cost matrix programs keep equivalent results in both tiers", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-cost-matrix-" });
  const entry = `${directory}/main.blot`;
  const executable = Deno.args[0] ??
    new URL("../../compiler/zig-out/bin/blotc", import.meta.url);
  const run = (bytes: Uint8Array<ArrayBuffer>, name: string, input: number) => {
    const exports =
      new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
    return (exports[name] as CallableFunction)(input);
  };
  try {
    {
      const compiler = await createZigProjectCompiler({
        executable,
        entry,
        prelude: new URL("../../std/prelude.blot", import.meta.url),
        stdRoot: new URL("../../std", import.meta.url),
      });
      try {
        const result = await compiler.build({ sources: { [entry]: source } });
        assert(result.success, JSON.stringify(result));
        for (
          const name of [
            "direct",
            "helper",
            "named_callback",
            "inline_callback",
            "generic_callback",
            "aliased_callback",
            "local_callback",
            "nominal_record",
          ]
        ) {
          assert.equal(run(result.bytes, name, 5), 11, `${name}`);
        }
        for (const count of [32, 128, 512]) {
          for (
            const name of [
              "array_generate",
              "update_direct",
              "update_wrapped",
              "update_direct_wrapper",
              "update_reordered_wrapper",
              "update_snapshot",
            ]
          ) {
            assert.equal(
              run(result.bytes, name, count),
              count,
              `${name} ${count}`,
            );
          }
        }
        {
          const changedSource = source.replace(
            "return replace index value values",
            "return replace index (value + 1) values",
          );
          assert.notEqual(changedSource, source);
          const changed = await compiler.build({
            sources: { [entry]: changedSource },
          });
          assert(changed.success, JSON.stringify(changed));
          assert.equal(run(changed.bytes, "update_wrapped", 32), 33);
          const restored = await compiler.build({
            sources: { [entry]: source },
          });
          assert(restored.success, JSON.stringify(restored));
          assert.deepEqual(restored.bytes, result.bytes);
        }
      } finally {
        await compiler.dispose();
      }
    }
  } finally {
    await Deno.remove(directory, { recursive: true });
  }
});
