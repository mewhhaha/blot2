import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `type Point is data = $Point {padding: U32, x: F32, y: F32}
type Row is data = $Row {prefix: U32, count: U32, untouched: U32, point: Point}
const row = func (value: U32): Row => return $Row {point: $Point {y: -0.0, padding: 29, x: 1.25}, untouched: 100, count: value, prefix: 71}
const last_u32 = func (xs: Array U32): U32 => return xs[@u32.sub (@storage.length xs) 1]
#entry const ordered = func (input: U32) => return do:
  let rows: Array Row = #[row input]
  let effects: Array U32 = #[0]
  let idx0 = do:
    @storage.push effects (@u32.add (last_u32 effects) 1)
    break 0
  rows[idx0].count := do:
    @storage.push effects (@u32.add (@u32.mul (last_u32 effects) 10) 2)
    rows[0].untouched := 77
    break @u32.add self 5
  rows[0].count := do:
    for item in 0 .. 64:
      @storage.push rows (row item)
    rows[0].prefix := 83
    break @u32.add self 7
  let idx1 = do:
    @storage.push effects (@u32.add (last_u32 effects) 1)
    break 0
  let selected = rows[idx1].count
  return #[rows[0].count, rows[0].untouched, rows[0].prefix, last_u32 effects, @storage.length rows, rows[64].count, selected]
#entry const floating = func (input: F32) => return do:
  let rows: Array Row = #[row 0]
  rows[0].point.x := input
  rows[0].point.y := do:
    rows[0].point.padding := 47
    break self
  return #[rows[0].point.x, rows[0].point.y, @u32.to_f32 rows[0].point.padding, @u32.to_f32 rows[0].prefix]
#entry const joined = func (choose_left: Bool) => return do:
  let left: Array Row = #[row 10]
  let right: Array Row = #[row 20]
  if choose_left:
    left[0].count := @u32.add self 9
  else:
    right[0].count := @u32.add self 9
  return #[left[0].count, right[0].count, left[0].untouched, right[0].untouched]
#entry const out_of_bounds_trap = func (at: U32): U32 => return do:
  let rows: Array Row = #[row 1]
  rows[at].count := @u32.div 99 0
  return rows[0].count
#entry const out_of_bounds_ok = func (): Array U32 => return do:
  let rows: Array Row = #[row 1]
  let trace: Array U32 = #[]
  rows[0].count := do:
    @storage.push trace 1
    break 99
  return #[rows[0].count, @storage.length trace]
#entry const empty = func (): U32 => return do:
  let rows: Array Row = #[]
  rows[0].count := @u32.div 99 0
  return 0
const Row.consume = func (value: Row): U32 => return value.count
#entry const getter = func (input: U32) => return do:
  let getter_rows: Array Row = #[]
  @storage.push getter_rows (row input)
  let value = (&getter_rows[0..1])[0].consume
  @storage.truncate getter_rows 0
  return #[value, @storage.length getter_rows]
#entry const view_bound = func (at: U32): U32 => return do:
  let rows: Array Row = #[row 10, row 20, row 30]
  return (&rows[1..2])[at].count
`;

Deno.test(`selected stored fields preserve update order and bounds`, async () => {
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
        const call = async (name: string, input: unknown) => {
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
        assert.equal(await call("view_bound", 0), 20);
        await assert.rejects(() => call("view_bound", 1));
        await assert.rejects(() => call("out_of_bounds_trap", 1), /unreachable/);
        await assert.rejects(() => call("empty", null), /unreachable/);
        await assert.rejects(() => call("out_of_bounds_trap", 0), /divide by zero/);
        assert.deepEqual(
          await call("out_of_bounds_ok", null),
          new Uint32Array([99, 1]),
        );
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler?.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
