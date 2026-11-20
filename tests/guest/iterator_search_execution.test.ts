import { deepStrictEqual, equal } from "node:assert/strict";
import { compileAndRun } from "./compile_helpers.ts";

const stdRoot = new URL("../../std/", import.meta.url).pathname;

Deno.test("drop, find and position compose with source iterators", async () => {
  await compileAndRun(
    `
import * as iter from "std/iter"

func pack values: Array U32 => do:
  let out: GrowArray U32 = #[]
  for value in values:
    out.push value
  return @storage.freeze out

entry func skipped (count: U32): Array U32 => return
  pack (iter.drop count #[10, 20, 30])

entry func empty (count: U32): Array U32 => do:
  let values: Array U32 = #[]
  return pack (iter.drop count values)

func sum_pair pair => do:
  let (left, right) = pair
  return left + right

entry func paired (count: U32): Array U32 => return
  pack (iter.map sum_pair
    (iter.zip (iter.range 0 5) (iter.drop count (iter.range 0 5))))

entry func search (needle: U32): Array U32 => do:
  let values = #[5, 10, 5, 20]
  let $Some value = iter.find (func n => return n >= needle) values else:
    return #[]
  let $Some index = iter.position (func n => return n >= needle) values else:
    return #[]
  return #[value, index]

entry func filtered_position (needle: U32): Array U32 => do:
  let values = iter.filter (func n => return n % 2 == 0) (iter.range 0 10)
  return case iter.position (func n => return n == needle) values of
    $Some index => #[index]
    $Nothing => #[]

entry func empty_search (): Bool => do:
  let values: Array U32 = #[]
  let found = iter.find (func n => return n > 0) values
  let index = iter.position (func n => return n > 0) values
  return case found, index of
    $Nothing, $Nothing => true
    _, _ => false

entry func independent (count: U32): Array U32 => do:
  let cursor = (iter.drop count (iter.range 10 15)).iter
  let $Some (a, next) = cursor.next else:
    return #[]
  let $Some (b, _) = next.next else:
    return #[a]
  let $Some (again, _) = cursor.next else:
    return #[]
  return #[a, b, again]
`,
    (guest) => {
      deepStrictEqual(guest.call("skipped", 0), Uint32Array.of(10, 20, 30));
      deepStrictEqual(guest.call("skipped", 2), Uint32Array.of(30));
      deepStrictEqual(guest.call("skipped", 3), Uint32Array.of());
      deepStrictEqual(guest.call("skipped", 0xFFFF_FFFF), Uint32Array.of());
      deepStrictEqual(guest.call("empty", 0xFFFF_FFFF), Uint32Array.of());
      deepStrictEqual(guest.call("paired", 2), Uint32Array.of(2, 4, 6));
      deepStrictEqual(guest.call("paired", 6), Uint32Array.of());
      deepStrictEqual(guest.call("search", 5), Uint32Array.of(5, 0));
      deepStrictEqual(guest.call("search", 9), Uint32Array.of(10, 1));
      deepStrictEqual(guest.call("search", 20), Uint32Array.of(20, 3));
      deepStrictEqual(guest.call("search", 21), Uint32Array.of());
      deepStrictEqual(guest.call("filtered_position", 6), Uint32Array.of(3));
      deepStrictEqual(guest.call("filtered_position", 9), Uint32Array.of());
      equal(guest.call("empty_search", null), true);
      deepStrictEqual(guest.call("independent", 1), Uint32Array.of(11, 12, 11));
      deepStrictEqual(guest.call("independent", 4), Uint32Array.of(14));
    },
    { stdRoot },
  );
});

Deno.test("drop delays pulls and searches stop at the first match", async () => {
  await compileAndRun(
    `
import * as iter from "std/iter"

entry func first (tick: U32 -> U32 ! {Foreign}): U32 => do:
  let values = iter.drop 2 (iter.map tick (iter.range 0 8))
  let check = func n => do:
    use seen <- tick (100 + n)
    return seen == 104
  use result <- iter.find check values
  return case result of
    $Some n => n
    $Nothing => 999

entry func position (tick: U32 -> U32 ! {Foreign}): U32 => do:
  let values = iter.drop 2 (iter.map tick (iter.range 0 8))
  let check = func n => do:
    use seen <- tick (100 + n)
    return seen == 104
  use result <- iter.position check values
  return case result of
    $Some n => n
    $Nothing => 999

entry func unused (tick: U32 -> U32 ! {Foreign}): U32 => do:
  let values = iter.drop 3 (iter.map tick (iter.range 0 8))
  use result <- iter.fold_left add 0 (iter.take 0 values)
  return result
`,
    (guest) => {
      for (const [name, expected] of [["first", 4], ["position", 2], ["unused", 0]] as const) {
        const calls: number[] = [];
        const tick = guest.capability({
          parameter: "U32",
          result: "U32",
          call: (value) => {
            calls.push(value as number);
            return value;
          },
        });
        equal(guest.call(name, tick), expected);
        deepStrictEqual(calls, name === "unused" ? [] : [0, 1, 2, 102, 3, 103, 4, 104]);
      }
    },
    { stdRoot },
  );
});
