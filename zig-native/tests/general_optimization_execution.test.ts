import { strict as assert } from "node:assert";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("user-defined checked edits and nested paths retain snapshots across early exits", async () => {
  await compileAndRun(
    `
type Outcome a is data = #Updated a | #Refused
const replace_if = fn index => fn value => fn values => do:
  if index < @array.length values:
    return #Updated (@array.set values index value)
  return #Refused
type Store is data = #Store { left: Array U32, right: Array U32 }
entry const checked = fn (count: U32) => do:
  let values = @array.fill count 0
  for i in 0..(count + 1):
    let #Updated next = replace_if i (i + 1) values else:
      return values
    values := next
  return values
entry const nested = fn (count: U32) => do:
  let store = #Store { left: @array.fill count 0, right: @array.fill count 1 }
  for i in 0..count:
    if i == 2049:
      break
    store.left[i] := i + 1
  return store.left
entry const forever = fn (count: U32) => do:
  let values = @array.fill count 0
  let i = 0
  for ever:
    if i == count:
      break
    values[i] := i + 1
    i := i + 1
  return values
entry const versions = fn () => do:
  let leaf = #[1, 2]
  let store = #Store { left: leaf, right: leaf }
  let saved = fn () => store.left[0]
  for i in 0..2:
    store.left[i] := 9
    if i == 0:
      break
  store.left[1] := 8
  return #[saved (), leaf[0], store.right[0], store.left[0], store.left[1]]
entry const extracted = fn () => do:
  let values = #[#[1], #[2]]
  let first = values[0]
  values[0][0] := 9
  return #[first[0], values[0][0]]
entry const after_break = fn () => do:
  let values = #[1, 2]
  let saved = values
  for ever:
    values[0] := 8
    break
  values[1] := 9
  return #[saved[0], saved[1], values[0], values[1]]
`,
    (guest) => {
      for (const name of ["checked", "nested", "forever"]) {
        for (const count of [0, 1, 2049]) {
          assert.deepEqual(
            guest.call(name, count),
            Uint32Array.from({ length: count }, (_, i) => i + 1),
          );
        }
      }
      assert.deepEqual(guest.call("extracted", null), new Uint32Array([1, 9]));
      assert.deepEqual(
        guest.call("versions", null),
        new Uint32Array([1, 1, 1, 9, 8]),
      );
      assert.deepEqual(
        guest.call("after_break", null),
        new Uint32Array([1, 2, 8, 9]),
      );
      assert(
        guest.memoryBytes() <= 256 * 1024,
        `Unexpected copy growth: ${guest.memoryBytes()}`,
      );
    },
  );
});

Deno.test("scalar replacement preserves record loop versions, branches and mixed scalar bits", async () => {
  await compileAndRun(
    `
type Pair is data = #Pair { count: U32, value: F32 }
const advance = fn pair => #Pair { count: pair.count + 1, value: pair.value + 0.25 }
entry const iterate = fn (count: U32) => do:
  let value = #Pair { count: 0, value: -0.5 }
  let previous = value
  for i in 0..count:
    previous := value
    value := advance value
  return #[F32.from value.count, value.value, F32.from previous.count, previous.value]
entry const branch = fn (flag: Bool) => do:
  let original = #Pair { count: 7, value: -0.0 }
  let changed = if flag then advance original else #Pair { count: 3, value: 1.5 }
  return #[F32.from original.count, original.value, F32.from changed.count, changed.value]
entry const captured = fn () => do:
  let value = #Pair { count: 1, value: 1.0 }
  let read = fn () => value.count
  value := advance value
  return read () + value.count
`,
    (guest) => {
      for (const count of [0, 1, 8193]) {
        const previous = Math.max(0, count - 1);
        assert.deepEqual(
          guest.call("iterate", count),
          new Float32Array([
            count,
            -0.5 + count * 0.25,
            previous,
            -0.5 + previous * 0.25,
          ]),
        );
      }
      assert.deepEqual(
        guest.call("branch", true),
        new Float32Array([7, -0, 8, 0.25]),
      );
      assert.deepEqual(
        guest.call("branch", false),
        new Float32Array([7, -0, 3, 1.5]),
      );
      equal(guest.call("captured", null), 3);
      assert(
        guest.memoryBytes() <= 128 * 1024,
        `Record carries still allocate: ${guest.memoryBytes()}`,
      );
    },
  );
});

Deno.test("user constructor demand matches and known callbacks preserve effects and lexical captures", async () => {
  await compileAndRun(
    `
type Choice a is data = #Chosen a | #Absent
const select = fn ~(fallback: U32) => fn choice => case choice of
  #Chosen value if @u32.lt 0 value => value
  #Chosen _ => @u32.add (@demand fallback) (@demand fallback)
  #Absent => @demand fallback
const generate = fn count => fn callback => @array.generate count callback
entry const demand = fn (host: U32 -> U32 ! {Foreign}) => do:
  use a <- select (host 10) (#Chosen 42)
  use b <- select (host 11) (#Chosen 0)
  use c <- select (host 12) #Absent
  return #[a, b, c]
entry const callback = fn (host: U32 -> U32 ! {Foreign}) => do:
  use amount <- host 10
  let callback = fn i => @u32.add i amount
  amount := 99
  return generate 4 callback
entry const untouched = fn (host: U32 -> U32 ! {Foreign}) => generate (host 0) (do:
  use offset <- host 20
  return fn i => i + offset)
`,
    (guest) => {
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return value;
        },
      });
      assert.deepEqual(
        guest.call("demand", host),
        new Uint32Array([42, 22, 12]),
      );
      assert.deepEqual(calls, [11, 12]);
      calls.length = 0;
      assert.deepEqual(
        guest.call("callback", host),
        new Uint32Array([10, 11, 12, 13]),
      );
      assert.deepEqual(calls, [10]);
      calls.length = 0;
      assert.deepEqual(guest.call("untouched", host), new Uint32Array());
      assert.deepEqual(calls, [0, 20]);
    },
  );
});

Deno.test("staged indexed construction freezes once and preserves input aliases and repeated indices", async () => {
  await compileAndRun(
    `
const build = fn values => do:
  let saved = fn () => values[0]
  for i in 0..4096:
    values[i] := i + 1
  return (values, saved ())
const source = @array.fill 4096 7
const constructed = build source
const repeated = do:
  let values = #[10, 20]
  for i in 0..4096:
    values[i % 2] := self + 1
  return values
const primitive = do:
  let values = @array.fill 4096 0
  for i in 0..4096:
    values := @array.set values i (i + 1)
  return values
entry const answer = fn () => do:
  let (values, old) = constructed
  return #[source[0], old, values[0], values[4095], repeated[0], repeated[1], primitive[4095]]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answer", null),
        new Uint32Array([7, 7, 1, 4096, 2058, 2068, 4096]),
      );
    },
  );
});

Deno.test("staged nested builders and concatenation keep storage proportional to the result", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
const chunks = @array.generate 2048 (fn i => #[i, i + 1])
const flattened = array.flatten chunks
const joined = array.concat flattened flattened
const custom = do:
  let output = @array.fill 4096 0
  let start = 0
  for chunk in chunks:
    for i in 0..2:
      output[start + i] := chunk[i]
    start := start + 2
  return output
entry const answers = fn () => #[flattened[4095], joined[8191], custom[4095]]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answers", null),
        new Uint32Array([2048, 2048, 2048]),
      );
    },
  );
});
