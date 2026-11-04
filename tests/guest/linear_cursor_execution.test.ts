import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("linear cursor paths keep old versions across leaf changes pressure and repeated activations", async () => {
  await compileAndRun(
    `
entry const run = func (encoded: U32) => return do:
  let count = encoded / 8192
  let steps = encoded % 8192
  let rows = @list.generate count (func i => return {x: i, y: i + 1, z: i + 2})
  let total = 0
  for pass in 0..3:
    let original = @list.cursor rows
    let cursor = original
    for index in 0..steps:
      let old = cursor
      cursor := @cursor.advance self
      let pressure = @array.fill 256 index
      if pressure[255] != index:
        @panic "pressure"
      total := self + (@cursor.value old).x
      if @cursor.has cursor:
        total := self + (@cursor.value cursor).y
    if @cursor.has original:
      total := self + (@cursor.value original).z
  return total
entry const uneven = func (count: U32) => return do:
  let source = @list.generate (count + 19) (func i => return {x: i, y: i + 1, z: i + 2})
  let rows = @list.slice source 7 count
  let original = @list.cursor rows
  let cursor = original
  let total = 0
  for index in 0..count:
    total := self + (@cursor.value cursor).x
    cursor := @cursor.advance self
  if @cursor.has original:
    total := self + (@cursor.value original).x
  return total
const shifted = func (steps: U32) => return do:
  let source = @list.generate 4096 (func i => return {x: i, y: i + 1, z: i + 2})
  let rows = @list.slice source 7 4080
  let cursor = @list.cursor rows
  for index in 0..steps:
    cursor := @cursor.advance self
  return cursor
const early = func (steps: U32) => return do:
  let rows = @list.generate 4096 (func i => return {x: i, y: i + 1, z: i + 2})
  let cursor = @list.cursor rows
  for index in 0..4096:
    if index == steps:
      return cursor
    cursor := @cursor.advance self
  return cursor
entry const read_early = func (steps: U32) => return do:
  let cursor = early steps
  let pressure = @array.fill 512 99
  if pressure[511] != 99:
    @panic "pressure"
  if @cursor.has cursor:
    return (@cursor.value cursor).y
  return 0
entry const read_shifted = func (steps: U32) => return do:
  let cursor = shifted steps
  let pressure = @array.fill 512 99
  if pressure[511] != 99:
    @panic "pressure"
  if @cursor.has cursor:
    return (@cursor.value cursor).x
  return 0
entry const probe = func (seed: U32) => return #[seed]
`,
    (guest) => {
      for (const steps of [0, 1, 80, 81, 82, 243, 999, 4095, 4096]) {
        assert.equal(
          guest.call("read_early", steps),
          steps < 4096 ? steps + 1 : 0,
        );
      }
      for (const steps of [0, 1, 80, 81, 82, 243, 999, 4079, 4080]) {
        assert.equal(
          guest.call("read_shifted", steps),
          steps < 4080 ? steps + 7 : 0,
        );
      }
      for (const count of [0, 1, 2, 80, 81, 82, 243, 244, 245, 999, 4096]) {
        assert.equal(
          guest.call("uneven", count),
          (count * (count - 1) / 2 + 7 * count + (count ? 7 : 0)) >>> 0,
        );
        for (const steps of new Set([0, Math.min(count, 82), count])) {
          let expected = count === 0 ? 0 : 2;
          for (let index = 0; index < steps; index++) {
            expected += index;
            if (index + 1 < count) expected += index + 2;
          }
          assert.equal(guest.call("run", count * 8192 + steps), expected * 3);
        }
      }
      const expected = (4095 * 4096 + 4095 + 2) * 3;
      assert.equal(guest.call("run", 4096 * 8192 + 4096), expected);
      const warm = guest.memoryBytes();
      for (let repeat = 0; repeat < 16; repeat++) {
        assert.equal(guest.call("run", 4096 * 8192 + 4096), expected);
      }
      assert.equal(guest.memoryBytes(), warm);
    },
    { stdRoot },
  );
});
