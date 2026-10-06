import { strict as assert } from "node:assert";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("direct and wrapped array replacement use linear storage while retaining snapshots", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
const replace = array.replace
entry const wrapped = fn (count: U32) => do:
  let values = array.fill count 0
  for i in 0..count:
    values := replace i (i + 1) values
  return values
entry const direct = fn (count: U32) => do:
  let values = array.fill count 0.0
  for i in 0..count:
    values := @array.set values i (F32.from i)
  return values
entry const snapshots = fn () => do:
  let original = #[1, 2, 3]
  let values = original
  let saved = fn () => values[0]
  values := replace 0 99 values
  return #[original[0], saved (), values[0]]
entry const nested = fn () => do:
  let original = #[#[1], #[2]]
  let changed = replace 0 99 original[0]
  return #[original[0][0], changed[0]]
`,
    (guest) => {
      const count = 2049;
      assert.deepEqual(
        guest.call("wrapped", count),
        Uint32Array.from({ length: count }, (_, i) => i + 1),
      );
      assert.deepEqual(
        guest.call("direct", count),
        Float32Array.from({ length: count }, (_, i) => i),
      );
      assert.deepEqual(
        guest.call("snapshots", null),
        new Uint32Array([1, 1, 99]),
      );
      assert.deepEqual(guest.call("nested", null), new Uint32Array([1, 99]));
      assert(
        guest.memoryBytes() <= 256 * 1024,
        `Replacement copied whole arrays: ${guest.memoryBytes()}`,
      );
    },
  );
});

Deno.test("array replacement evaluates written arguments before bounds checks and preserves iterator borrows", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
entry const order = fn (host: U32 -> U32 ! {Foreign}) =>
  array.replace (host 0) (host 1) (do:
    use value <- host 2
    return #[value])
entry const bounds = fn (host: U32 -> U32 ! {Foreign}) => do:
  let values = #[1]
  use changed <- array.replace 1 (host 42) values
  return changed
entry const borrowed = fn () => do:
  let values = #[1, 2, 3]
  let sum = 0
  for item in values:
    sum := sum + item
    values := array.replace 2 99 values
  return #[sum, values[2]]
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
      assert.deepEqual(guest.call("order", host), new Uint32Array([1]));
      assert.deepEqual(calls, [0, 1, 2]);
      calls.length = 0;
      assert.throws(() => guest.call("bounds", host));
      assert.deepEqual(calls, [42]);
      assert.deepEqual(guest.call("borrowed", null), new Uint32Array([6, 99]));
    },
  );
});

Deno.test("staged appends comprehensions and alternating builders preserve immutable versions within bounded storage", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
import * as list from "../../std/list"
const build = fn count => do:
  let forward: List U32 = []
  let backward: List U32 = []
  let packed: Array U32 = #[]
  for i in 0..count:
    forward := list.append i self
    backward := list.prepend i self
    packed := array.push i self
  return (Array.from_list forward, Array.from_list backward, packed)
const grown = build 8193
entry const ends = do:
  let (forward, backward, packed) = grown
  return forward[8192] + backward[0] + packed[8192]
const selected = array.filter_map (fn x => if x % 2 == 0 then #Some x else #Nothing) (array.generate 4097 identity)
entry const selected_last = selected[2048]
const branches = do:
  let values = [20]
  let saved = fn () => values
  let old = values
  values := [...self, 22]
  let other = [10, ...old]
  return #[Array.from_list values, Array.from_list other, Array.from_list (saved ())]
entry const branching = branches[0][1] + branches[1][0] + branches[2][0]
`,
    (guest) => {
      equal(guest.read("ends"), 24576);
      equal(guest.read("selected_last"), 4096);
      equal(guest.read("branching"), 52);
    },
  );
});

Deno.test("Result iteration stops on errors and allows distinct state result and error types without loop scaffolding", async () => {
  await compileAndRun(
    `
entry const run = fn (count: U32) => Result.unwrap_or 0 (Result.iterate 0 (fn i =>
  #Ok (if i < count then #Continue (i + 1) else #Done i)))
entry const stop = fn (host: U32 -> Bool ! {Foreign}) => do:
  use outcome <- Result.iterate 0 (fn i => do:
    use failed <- host i
    if failed:
      return #Err i
    if i == 10:
      return #Ok (#Done #[42.0])
    return #Ok (#Continue (i + 1)))
  return case outcome of
    #Ok value => value[0]
    #Err error => F32.from error
`,
    (guest) => {
      equal(guest.call("run", 100000), 100000);
      assert(guest.memoryBytes() <= 128 * 1024);
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "Bool",
        call(value) {
          calls.push(value as number);
          return value === 3;
        },
      });
      equal(guest.call("stop", host), 3);
      assert.deepEqual(calls, [0, 1, 2, 3]);
    },
  );
});
