import { strict as assert } from "node:assert";
import { compileAndRun } from "./reduction_helpers.ts";
import { compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("summary trees preserve range folds, updates and concatenation", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
import * as iter from "std/iter"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
entry const queries = fn (count: U32) => do:
  let tree = summary.build add 0 (iter.range 0 count)
  break #[summary.query add 0 start length tree | start <- iter.range 0 (@u32.add count 1), length <- iter.range 0 (@u32.add (@u32.sub count start) 1)]
entry const values = fn (count: U32) => do:
  let tree = summary.build add 0 (iter.range 0 count)
  break #[summary.get index tree | index <- iter.range 0 count]
entry const updates = fn (count: U32) => do:
  let original = summary.build add 0 (iter.range 0 count)
  let changed = original
  for index in 0..count:
    changed := summary.set add index (@u32.add index 1000) self
  let pressure = @array.fill 8192 99
  break #[summary.query add 0 0 count original, summary.query add 0 0 count changed, summary.length changed]
entry const concatenate = fn (count: U32) => do:
  let tree = summary.build add 0 #[]
  for index in 0..count:
    let leaf = summary.build add 0 #[index]
    tree := summary.concat add self leaf
  break #[summary.query add 0 0 count tree, summary.length tree]
entry const bounds = fn (input: Array U32) => summary.query add 0 input[0] input[1] (summary.build add 0 (iter.range 0 3))
entry const get = fn (index: U32) => summary.get index (summary.build add 0 (iter.range 0 3))
entry const set = fn (index: U32) => summary.length (summary.set add index 99 (summary.build add 0 (iter.range 0 3)))
`,
    (guest) => {
      for (const count of [0, 1, 2, 3, 31, 63, 257]) {
        const expected: number[] = [];
        for (let start = 0; start <= count; start++) {
          for (let length = 0; length <= count - start; length++) {
            expected.push(length * (2 * start + length - 1) / 2);
          }
        }
        assert.deepEqual(
          guest.call("queries", count),
          Uint32Array.from(expected),
        );
        assert.deepEqual(
          guest.call("values", count),
          Uint32Array.from({ length: count }, (_, i) => i),
        );
        const total = count * (count - 1) / 2;
        assert.deepEqual(
          guest.call("updates", count),
          Uint32Array.of(total, total + 1000 * count, count),
        );
        assert.deepEqual(
          guest.call("concatenate", count),
          Uint32Array.of(total, count),
        );
      }
      for (
        const [start, count] of [[4, 0], [0, 4], [1, 3], [4294967295, 2], [
          2,
          4294967295,
        ]]
      ) {
        assert.throws(
          () => guest.call("bounds", Uint32Array.of(start, count)),
          WebAssembly.RuntimeError,
        );
        assert.equal(guest.call("bounds", Uint32Array.of(3, 0)), 0);
      }
      for (const index of [3, 4294967295]) {
        for (const name of ["get", "set"]) {
          assert.throws(
            () => guest.call(name, index),
            WebAssembly.RuntimeError,
          );
        }
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("summary intervals preserve noncommutative order and reference snapshots", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
import * as iter from "std/iter"
const combine = fn (left: {mul: U32, add: U32}) => fn (right: {mul: U32, add: U32}) => {mul: @u32.mul left.mul right.mul, add: @u32.add (@u32.mul left.mul right.add) left.add}
const identity = {mul: 1, add: 0}
const measure = fn (index: U32) => {mul: @u32.add index 1, add: index}
entry const query = fn (input: Array U32) => do:
  let size = input[2]
  let split = input[3]
  let left = summary.build combine identity (iter.map measure (iter.range 0 split))
  let right = summary.build combine identity (iter.map measure (iter.range split size))
  let tree = summary.concat combine left right
  let value = summary.query combine identity input[0] input[1] tree
  break #[value.mul, value.add]
entry const references = fn (count: U32) => do:
  let combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
  let original = summary.build combine #[] (iter.map (fn index => #[index]) (iter.range 0 count))
  if @u32.eq count 0:
    break summary.query combine #[] 0 0 original
  let changed = summary.set combine (@u32.div count 2) #[99] original
  let pressure = @array.fill 8192 88
  break @array.concat (summary.query combine #[] 0 count original) (summary.query combine #[] 0 count changed)
`,
    (guest) => {
      for (const size of [0, 1, 2, 3, 31, 63, 257, 4096]) {
        for (const split of new Set([0, 1, Math.floor(size / 2), size])) {
          if (split > size) continue;
          for (
            const [start, count] of [[0, size], [size, 0], [
              Math.floor(size / 2),
              size - Math.floor(size / 2),
            ], [0, Math.min(size, 3)]]
          ) {
            let mul = 1, add = 0;
            for (let i = start; i < start + count; i++) {
              add = (Math.imul(mul, i) + add) >>> 0;
              mul = Math.imul(mul, i + 1) >>> 0;
            }
            assert.deepEqual(
              guest.call("query", Uint32Array.of(start, count, size, split)),
              Uint32Array.of(mul, add),
            );
          }
        }
      }
      for (const count of [0, 1, 2, 3, 31, 63, 257]) {
        const original = Uint32Array.from({ length: count }, (_, i) => i);
        const changed = original.slice();
        if (count > 0) changed[Math.floor(count / 2)] = 99;
        assert.deepEqual(
          guest.call("references", count),
          Uint32Array.of(...original, ...changed),
        );
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("summary build pulls once and queries do not repull effects", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
type Input is data = #Input {index: U32, count: U32, host: U32 -> U32 ! {Foreign}}
const Input.iter = fn (cursor: Input) => do:
  use cursor.host 777
  break cursor
const Input.next = fn (cursor: Input) => do:
  use value <- cursor.host cursor.index
  if @u32.eq cursor.index cursor.count:
    break #Nothing
  break #Some (value, #Input {index: @u32.add cursor.index 1, count: cursor.count, host: cursor.host})
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  use tree <- summary.build add 0 (#Input {index: 0, count: 7, host})
  let changed = summary.set add 3 99 tree
  let joined = summary.concat add tree changed
  break #[summary.query add 0 0 7 tree, summary.query add 0 0 14 joined, summary.get 3 tree, summary.get 3 changed]
`,
    (guest) => {
      const seen: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          seen.push(value);
          return value;
        },
      });
      assert.deepEqual(guest.call("run", host), Uint32Array.of(21, 138, 3, 99));
      assert.deepEqual(seen, [777, 0, 1, 2, 3, 4, 5, 6, 7]);
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("summary bounds trap before callbacks and fast arrows stay pure", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const bad = fn (left: U32) => fn (right: U32) => @u32.div left right
entry const query = fn (input: Array U32) => summary.query bad 0 input[0] input[1] (summary.build add 0 #[0,0,0])
entry const set = fn (index: U32) => summary.length (summary.set bad index 0 (summary.build add 0 #[0,0,0]))
`,
    (guest) => {
      for (
        const input of [
          Uint32Array.of(4, 0),
          Uint32Array.of(1, 3),
          Uint32Array.of(1, 4294967295),
        ]
      ) {
        assert.throws(() => guest.call("query", input), /unreachable/);
      }
      assert.throws(() => guest.call("set", 3), /unreachable/);
      assert.throws(() => guest.call("set", 1), /divide by zero/);
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
  for (
    const operation of [
      "summary.build callback 0 #[1,2]",
      "summary.query callback 0 0 2 tree",
      "summary.set callback 0 9 tree",
      "summary.concat callback tree tree",
    ]
  ) {
    await compileExpectedFailure(
      `
import * as summary from "std/summary"
entry const run = fn (host: U32 -> U32 ! {Foreign}) => do:
  let callback = fn (left: U32) => fn (right: U32) => host (@u32.add left right)
  let tree = summary.build (fn left => fn right => @u32.add left right) 0 #[1,2]
  break ${operation}
`,
      "effect_mismatch",
      undefined,
      { stdRoot: new URL("../../std", import.meta.url).pathname },
    );
  }
});

Deno.test("summary shared trees preserve large lengths and check concatenation overflow before callbacks", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const doubled = fn (rounds: U32) => do:
  let tree = summary.build add 0 #[1]
  for index in 0..rounds:
    tree := summary.concat add self self
  break tree
entry const huge = fn () => do:
  let original = doubled 31
  let changed = summary.set add 2147483647 7 original
  break #[summary.length original, summary.query add 0 0 2147483648 original, summary.query add 0 0 2147483648 changed, summary.query add 0 2147483646 2 changed, summary.get 2147483647 original, summary.get 2147483647 changed]
entry const overflow = fn () => do:
  let tree = doubled 31
  let bad = fn (left: U32) => fn (right: U32) => @u32.div left 0
  break summary.length (summary.concat bad tree tree)
`,
    (guest) => {
      const expected = Uint32Array.of(
        2147483648,
        2147483648,
        2147483654,
        8,
        1,
        7,
      );
      assert.deepEqual(guest.call("huge", null), expected);
      assert.throws(() => guest.call("overflow", null), /unreachable/);
      assert.deepEqual(guest.call("huge", null), expected);
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("summary static versions and rolling copies survive entry resets", async () => {
  await compileAndRun(
    `
import * as summary from "std/summary"
import * as rolling from "std/rolling"
import * as iter from "std/iter"
const combine = fn (left: Array U32) => fn (right: Array U32) => @array.concat left right
const original = summary.build combine #[] (iter.map (fn index => #[index]) (iter.range 0 32))
const add = fn (left: U32) => fn (right: U32) => @u32.add left right
const cursor = rolling.monoid add 0 3 (iter.range 0 32)
entry const old = fn () => summary.query combine #[] 0 32 original
entry const updated = fn (index: U32) => summary.query combine #[] 0 32 (summary.set combine index #[99] original)
entry const first = fn () => do:
  use step <- cursor.next
  let #Some (value, _) = step else:
    break 999
  break value
entry const pressure = fn (count: U32) => @array.fill count 88
`,
    (guest) => {
      const original = Uint32Array.from({ length: 32 }, (_, i) => i);
      for (const index of [0, 1, 15, 16, 31]) {
        const updated = original.slice();
        updated[index] = 99;
        assert.deepEqual(guest.call("updated", index), updated);
        assert.equal(guest.call("first", null), 3);
        guest.call("pressure", 8192);
        assert.deepEqual(guest.call("old", null), original);
        assert.equal(guest.call("first", null), 3);
      }
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});
