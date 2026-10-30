import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const source = `import * as array from "std/array"
const accepted = func (trace: GrowArray U32) -> (value: U32): Bool => return do:
  @storage.push trace (@u32.mul value 10)
  return value != 2
const recorded = func (trace: GrowArray U32) -> (value: U32): U32 => return do:
  @storage.push trace (@u32.add (@u32.mul value 10) 1)
  return value
const flatten = func rows: Array F32 => return #[value | row <- rows, value <- #[row.x, row.y]]
const traced_flatten = func trace -> rows: Array F32 => return
  #[@u32.to_f32 (recorded trace (@f32.to_u32 value)) | row <- rows, accepted trace (@f32.to_u32 row.x), value <- #[row.x, row.y]]
const table = #run (@array.get (#[@u32.mul x 2 | x <- #[1, 2, 3], @u32.lt x 3]) 1)
type Row is data = $Row {x: F32, count: U32}
entry const ordered = func () => return do:
  let trace: GrowArray U32 = #[]
  let input: Array U32 = #[1, 2, 3]
  let kept = #[recorded trace x | x <- input, accepted trace x]
  return array.concat kept (@storage.freeze trace)
entry const selected = func (limit: U32) => return do:
  let input: Array U32 = #[1, 2, 3, 4]
  return #[@u32.mul x 10 | x <- input, @u32.lt x limit]
entry const nested = func () => return do:
  let left: Array U32 = #[1, 2]
  let right: Array U32 = #[3, 4]
  return #[@u32.add (@u32.mul x 10) y | x <- left, y <- right, @u32.lt y 4]
entry const closure_guard = func () => return do:
  let input: Array U32 = #[1, 2, 3]
  let selected: Array U32 = #[1, 3]
  return #[x | x <- input, array.any (func wanted => return @u32.eq x wanted and @u32.lt 0 (@array.length selected)) selected]
entry const aggregate = func () => return do:
  let input: Array F32 = #[1.25, 2.5]
  let output = #[$Row {x, count: 1} | x <- input]
  return @f32.add output[0].x output[1].x
entry const generic = func () => return do:
  let rows: Array {x: F32, y: F32} = #[{x: 1.0, y: 2.0}, {x: 3.0, y: 4.0}]
  return flatten rows
entry const generic_ordered = func (count: U32) => return do:
  let rows = array.generate count (func index => return {x: @u32.to_f32 (@u32.add (@u32.mul index 2) 1), y: @u32.to_f32 (@u32.add (@u32.mul index 2) 2)})
  let trace: GrowArray U32 = #[]
  let kept = traced_flatten trace rows
  let observed = @storage.freeze trace
  return array.concat kept #[@u32.to_f32 item | item <- observed]
entry const staged = func () => return do:
  let owner: Array U32 = #[0]
  return @u32.add table owner[0]
`;
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`owned Array comprehensions preserve order staging and fixed payloads (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-owned-comprehension-",
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
      const result = await compiler.build({ sources: { [entry]: source } });
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = async (name: string, arg: unknown = null) =>
          asynchronous
            ? await guest.callAsync(name, arg)
            : guest.call(name, arg);
        try {
          assert.deepEqual(
            await call("ordered"),
            new Uint32Array([1, 3, 10, 11, 20, 30, 31]),
          );
          assert.deepEqual(await call("selected", 0), new Uint32Array([]));
          assert.deepEqual(
            await call("selected", 4),
            new Uint32Array([10, 20, 30]),
          );
          assert.deepEqual(await call("nested"), new Uint32Array([13, 23]));
          assert.deepEqual(
            await call("closure_guard"),
            new Uint32Array([1, 3]),
          );
          assert.equal(await call("aggregate"), 3.75);
          assert.deepEqual(
            await call("generic"),
            new Float32Array([1, 2, 3, 4]),
          );
          assert.deepEqual(
            await call("generic_ordered", 0),
            new Float32Array([]),
          );
          assert.deepEqual(
            await call("generic_ordered", 2),
            new Float32Array([1, 2, 3, 4, 10, 11, 21, 30, 31, 41]),
          );
          assert.equal(await call("staged"), 4);
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
