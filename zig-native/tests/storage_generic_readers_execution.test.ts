import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const longField = "x".repeat(7000);
const source = `import * as array from "std/array"
type Magnitude is data = $Magnitude F32
const Magnitude.abs = func (value: Magnitude) => return case value of
  $Magnitude number => number.abs + 10.0
const Magnitude.plus = func (value: Magnitude) -> (extra: F32) => return case value of
  $Magnitude number => number + extra
entry const primitive_getters = func (input: F32) => return do:
  let rows: ResizeArray F32 = #[input]
  let value = rows[0]
  let magnitude = $Magnitude value
  let add = magnitude.plus
  return #[value.abs, abs value, magnitude.abs, add 2.0]
entry const nested_readers = func (input: U32) => return do:
  let values: Array U32 = if input == 0 then #[] else if input == 1 then #[1, 99] else #[2]
  let needles: Array U32 = #[1]
  return array.any (func outer => return do:
    if outer == 99:
      @panic "unvisited suffix"
    return array.any (func inner => return inner == outer) needles) values
type Shifted is data = $Shifted {rows: ResizeArray U32}
const Shifted.length = func (value: Shifted) => return @u32.add (@storage.length value.rows) 100
const Shifted.at = func (value: Shifted) -> (index: U32) => return @u32.add value.rows[index] 200
const add_three = func first -> second -> third => return first + second + third
const write_three = func (rows: ResizeArray U32) -> (first: U32) -> (second: U32) => return do:
  rows.push (@u32.add first second)
  return rows.length
entry const staged_effect = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[]
  let first = write_three rows
  let second = first input
  let before = rows.length
  let result = second 1
  return #[before, result, rows[0]]
entry const partial_integer = func (input: U32) => return do:
  let first = add_three input
  let second = first 2
  return second 3
entry const partial_floating = func (input: F32) => return do:
  let first = add_three input
  let second = first 2.25
  return second 3.5
entry const getters = func (input: U32) => return do:
  let first: ResizeArray U32 = #[input]
  let second: ResizeArray U32 = #[10]
  let read = first.at
  first[0] := @u32.add input 2
  first.push 99
  let shifted = $Shifted {rows: second}
  return #[first.length, read 0, shifted.length, shifted.at 0]
const encoded_writer = func (destination: ResizeArray U32) -> (input: U32) => return do:
  let encode = func (value: U32): Array U32 => return #[value, @u32.add value 1]
  let encoded = encode input
  let scratch: GrowArray U32 = #[]
  scratch.push encoded[0]
  for value in encoded:
    destination.push value
  destination.push scratch[0]
entry const scratch_writer = func (input: U32) => return do:
  let destination: ResizeArray U32 = #[]
  for index in 0 .. 100:
    encoded_writer destination (@u32.add input index)
  return #[destination.length, destination[0], destination[1], destination[2], destination[297], destination[298], destination[299]]
type LargeState = {${longField}: ResizeArray U32}
const write_large = func (state: LargeState) -> (amount: U32) => return do:
  state.${longField}[0] := @u32.add state.${longField}[0] amount
const read_large = func (state: LargeState) => return state.${longField}[0]
entry const large_key = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[10]
  let state = {${longField}: rows}
  write_large state input
  let before = read_large state
  write_large state 1
  return #[before, read_large state, rows[0]]
type Research rows is data = $Research {rows: rows, add: U32}
type Box value is data = $Box value
const read = func (research: Research (&[U32])): U32 => return @u32.add research.rows[0] research.add
const unwrap = func (box: Box value) => return case box of
  $Box value => value
const present = func (maybe: Maybe value) => return case maybe of
  $Some value => value
  $Nothing => @panic "missing"
const factory = func base => return func extra => return $Box (base + extra)
entry const answer = func (input: U32) => return do:
  let first: ResizeArray U32 = #[input]
  let second: ResizeArray U32 = #[@u32.add input 10]
  let before = read ($Research {rows: &first[0..1], add: 1})
  first[0] := @u32.add input 100
  let after = read ($Research {rows: &first[0..1], add: 2})
  let other = read ($Research {rows: &second[0..1], add: 3})
  return #[before, after, other]
entry const integer = func () => return do:
  let rows: ResizeArray U32 = #[1]
  let wrap = factory rows[0]
  return unwrap (present ($Some (wrap 2)))
entry const floating = func () => return do:
  let rows: ResizeArray F32 = #[1.25]
  let wrap = factory rows[0]
  return unwrap (present ($Some (wrap 2.5)))
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`selected generic readers retain nominal payloads and captured instantiations (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-generic-reader-",
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
        try {
          const call = async (name: string, input: unknown = null) =>
            asynchronous
              ? await guest.callAsync(name, input)
              : guest.call(name, input);
          for (const input of [-100, -1.25, -0, 0, 1.25]) {
            assert.deepEqual(
              await call("primitive_getters", input),
              new Float32Array([
                Math.abs(input),
                Math.abs(input),
                Math.abs(input) + 10,
                input + 2,
              ]),
            );
          }
          for (const input of [0, 1, 100]) {
            assert.equal(await call("nested_readers", input), input == 1);
            assert.deepEqual(
              await call("answer", input),
              new Uint32Array([input + 1, input + 102, input + 13]),
            );
            assert.equal(await call("integer"), 3);
            assert.equal(await call("floating"), 3.75);
            assert.equal(await call("partial_integer", input), input + 5);
            assert.equal(await call("partial_floating", input), input + 5.75);
            assert.deepEqual(
              await call("staged_effect", input),
              new Uint32Array([0, 1, input + 1]),
            );
            assert.deepEqual(
              await call("getters", input),
              new Uint32Array([2, input + 2, 101, 210]),
            );
            assert.deepEqual(
              await call("large_key", input),
              new Uint32Array([input + 10, input + 11, input + 11]),
            );
            assert.deepEqual(
              await call("scratch_writer", input),
              new Uint32Array([
                300,
                input,
                input + 1,
                input,
                input + 99,
                input + 100,
                input + 99,
              ]),
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
