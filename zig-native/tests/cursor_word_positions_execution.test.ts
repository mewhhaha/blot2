import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("private word cursors preserve has empty exhausted advance and cross-leaf snapshots", async () => {
  await compileAndRun(
    `
entry const status = fn count => do:
  let cursor = @list.generate count (fn i => {x: i, y: i + 1, z: i + 2})
  let cursor = @list.cursor cursor
  let old = cursor
  let total = 0
  for 0..count:
    if Bool.not (@cursor.has cursor):
      @panic "early end"
    let row = @cursor.value cursor
    total := self + row.x + row.y + row.z
    cursor := @cursor.advance self
  if @cursor.has cursor:
    @panic "late end"
  if @cursor.has old:
    return total + (@cursor.value old).z
  return total
entry const exhausted = fn count => do:
  let cursor = @list.cursor (@list.fill count (1,2,3))
  for 0..count:
    cursor := @cursor.advance self
  let (value, _, _) = @cursor.value cursor
  return value
entry const beyond = fn count => do:
  let cursor = @list.cursor (@list.fill count (1,2,3))
  for 0..count:
    cursor := @cursor.advance self
  let next = @cursor.advance cursor
  return @cursor.has next
`,
    (guest) => {
      for (const count of [0, 1, 80, 81, 82, 243, 244, 245, 1000]) {
        let total = 3 * count * (count + 1) / 2;
        if (count !== 0) total += 2;
        assert.equal(guest.call("status", count), total);
        assert.throws(() => guest.call("exhausted", count));
        assert.throws(() => guest.call("beyond", count));
      }
    },
    { stdRoot },
  );
});

Deno.test("private word cursors keep ordinary owned extraction through calls and pressure", async () => {
  await compileAndRun(
    `
const hold = fn row => fn () => row
entry const run = fn count => do:
  let cursor = @list.cursor (@list.generate 1001 (fn i => {x: i, y: i + 1, z: i + 2}))
  let saved = hold (@cursor.value cursor)
  for 0..count:
    cursor := @cursor.advance self
    let pressure = @array.fill 8192 41
    if pressure[8191] != 41:
      @panic "pressure"
  let old = saved ()
  let last = @cursor.value cursor
  return #[old.x, old.y, old.z, last.x, last.y, last.z]
`,
    (guest) => {
      for (const count of [0, 1, 81, 82, 244, 245, 1000]) {
        assert.deepEqual(
          guest.call("run", count),
          Uint32Array.of(0, 1, 2, count, count + 1, count + 2),
        );
      }
    },
    { stdRoot },
  );
});
