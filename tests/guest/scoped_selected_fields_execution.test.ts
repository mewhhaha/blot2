import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `type Point is data = $Point {padding: U32, x: F32, y: F32}
type Row is data = $Row {prefix: U32, count: U32, untouched: U32, point: Point}
const row = func (value: U32): Row => return $Row {point: $Point {y: -0.0, padding: 29, x: 1.25}, untouched: 100, count: value, prefix: 71}
const index = func (effects: GrowArray U32): U32 => return do:
  effects[0] := @u32.add self 1
  return 0
const update = func (rows: GrowArray Row) -> (effects: GrowArray U32): Unit => return do:
  let alias = rows
  rows[index effects].count := do:
    effects[0] := @u32.add (@u32.mul effects[0] 10) 2
    alias[0].untouched := 77
    break @u32.add self 5
  rows[0].count := do:
    for item in 0 .. 64:
      @storage.push alias (row item)
    alias[0].prefix := 83
    break @u32.add self 7
  return ()
entry const ordered = func (input: U32) => return do:
  let rows: GrowArray Row = #[row input]
  let effects: GrowArray U32 = #[0]
  update rows effects
  let selected = rows[index effects].count
  return #[rows[0].count, rows[0].untouched, rows[0].prefix, effects[0], @storage.length rows, rows[64].count, selected]
entry const floating = func (input: F32) => return do:
  let rows: GrowArray Row = #[row 0]
  rows[0].point.x := input
  rows[0].point.y := do:
    rows[0].point.padding := 47
    break self
  return #[rows[0].point.x, rows[0].point.y, @u32.to_f32 rows[0].point.padding, @u32.to_f32 rows[0].prefix]
entry const joined = func (choose_left: Bool) => return do:
  let left: GrowArray Row = #[row 10]
  let right: GrowArray Row = #[row 20]
  let selected = if choose_left then left else right
  selected[0].count := @u32.add self 9
  return #[left[0].count, right[0].count, left[0].untouched, right[0].untouched]
const side_effects: GrowArray U32 = #[0]
const record_effect = func (): U32 => return do:
  let counter = side_effects
  counter[0] := @u32.add self 1
  return 99
entry const effects = func (): U32 => return side_effects[0]
entry const out_of_bounds = func (at: U32): U32 => return do:
  let rows: GrowArray Row = #[row 1]
  rows[at].count := record_effect ()
  return rows[0].count
entry const empty = func (): U32 => return do:
  let rows: GrowArray Row = #[]
  rows[0].count := record_effect ()
  return 0
const getter_rows: ResizeArray Row = #[]
const Row.consume = func (value: Row): U32 => return do:
  @storage.truncate getter_rows 0
  return value.count
entry const getter = func (input: U32) => return do:
  @storage.push getter_rows (row input)
  let value = (&getter_rows[0..1])[0].consume
  return #[value, @storage.length getter_rows]
entry const view_bound = func (at: U32): U32 => return do:
  let rows: GrowArray Row = #[row 10, row 20, row 30]
  return (&rows[1..2])[at].count
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`selected stored fields preserve update order and bounds (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-selected-fields-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    let compiler:
      | Awaited<ReturnType<typeof createZigProjectCompiler>>
      | undefined;
    try {
      compiler = await createZigProjectCompiler({
        executable: Deno.args[0],
        entry,
        stdRoot,
        prelude: `${stdRoot}/prelude.blot`,
        cacheDirectory: false,
        codegenTier,
        startupTimeoutMs: 5_000,
      });
      const result = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5_000),
      });
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        try {
          const call = async (name: string, input: number | boolean | null) => {
            if (asynchronous) return await guest.callAsync(name, input);
            return guest.call(name, input);
          };
          for (const input of [0, 1, 41, 0xfffffffd, 3, 0]) {
            assert.deepEqual(
              await call("getter", input),
              new Uint32Array([input, 0]),
            );
            assert.deepEqual(
              await call("ordered", input),
              new Uint32Array([
                input + 12,
                77,
                83,
                13,
                65,
                63,
                input + 12,
              ]),
            );
          }
          for (const input of [-0, 1.25, -10.5, -0]) {
            assert.deepEqual(
              await call("floating", input),
              new Float32Array([
                input,
                -0,
                47,
                71,
              ]),
            );
          }
          assert.deepEqual(
            await call("joined", true),
            new Uint32Array([19, 20, 100, 100]),
          );
          assert.deepEqual(
            await call("joined", false),
            new Uint32Array([10, 29, 100, 100]),
          );
          assert.equal(await call("effects", null), 0);
          assert.equal(await call("view_bound", 0), 20);
          await assert.rejects(() => call("view_bound", 1));
          await assert.rejects(() => call("out_of_bounds", 1));
          assert.equal(await call("effects", null), 0);
          await assert.rejects(() => call("empty", null));
          assert.equal(await call("effects", null), 0);
          assert.equal(await call("out_of_bounds", 0), 99);
          assert.equal(await call("effects", null), 1);
        } finally {
          guest.dispose();
        }
      }
    } finally {
      await compiler?.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
