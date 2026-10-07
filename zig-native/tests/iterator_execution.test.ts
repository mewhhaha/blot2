import { deepStrictEqual, ok, throws } from "node:assert/strict";
import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("source list splices preserve snapshots and apply batches in original coordinates", async () => {
  await compileAndRun(`
import * as list from "std/list"
const edits = [
  {start: 1, delete_count: 1, replacement: [10, 11]},
  {start: 4, delete_count: 0, replacement: [40]},
  {start: 4, delete_count: 0, replacement: [41]}]
const batch = fn values => list.splice_many edits values
const staged = batch [0, 1, 2, 3, 4]
entry const staged_result = fn () => Array.from_list staged
entry const run = fn size => Array.from_list (batch (@list.generate size identity))
entry const changed = fn seed => do:
  let original = [seed, seed + 1, seed + 2, seed + 3, seed + 4]
  let saved = original.iter
  let changed = list.splice 1 2 [10, 11, 12] original
  let #Some (first, _) = saved.next else:
    return #[]
  let before = Array.from_list original
  let after = Array.from_list changed
  return #[first, before[1], after[1], after.length, before.length]
entry const single = fn seed => Array.from_list (list.splice 1 2 [10, 11, 12] [seed, seed + 1, seed + 2, seed + 3])
entry const noop = fn start => Array.from_list (list.splice start 0 [] [1, 2])
entry const empty_batch = fn (seed: U32) => Array.from_list (list.splice_many [] [seed])
entry const overlap = fn start => Array.from_list (list.splice_many [
  {start: 1, delete_count: 2, replacement: []},
  {start: start, delete_count: 0, replacement: [9]}] [0, 1, 2, 3])
`, guest => {
    deepStrictEqual(guest.call("staged_result", null), Uint32Array.of(0, 10, 11, 2, 3, 40, 41, 4));
    deepStrictEqual(guest.call("run", 5), Uint32Array.of(0, 10, 11, 2, 3, 40, 41, 4));
    deepStrictEqual(guest.call("single", 5), Uint32Array.of(5, 10, 11, 12, 8));
    deepStrictEqual(guest.call("changed", 5), Uint32Array.of(5, 6, 10, 6, 5));
    deepStrictEqual(guest.call("noop", 2), Uint32Array.of(1, 2));
    deepStrictEqual(guest.call("empty_batch", 7), Uint32Array.of(7));
    throws(() => guest.call("noop", 3));
    throws(() => guest.call("overlap", 2));
    throws(() => guest.call("overlap", 5));
  }, { stdRoot });
});

Deno.test("source iterators compose across imports, comprehensions and constant evaluation", async () => {
  await compileAndRun(`
import * as iter from "std/iter"
const values = fn count => iter.collect_array (iter.map (fn value => value * 2)
  (iter.filter (fn value => value % 2 == 0) (iter.take count [1, 2, 3, 4, 5, 6])))
entry const runtime = fn count => values count
const staged_values = values 6
entry const staged = fn () => staged_values
entry const empty_chunks = iter.fold_left (fn sum => fn chunk => sum + chunk.length) 0 #[#[], #[]]
entry const empty_wrapped = iter.fold_left (fn sum => fn chunk => sum + chunk.length) 0 (iter.take 2 #[#[], #[]])
entry const comprehension = fn count => #[x + y | x <- iter.range 0 count, y <- iter.take 2 #[10, 20, 30], x != 1]
entry const windows = fn width => iter.collect_array (iter.map (iter.fold_left add 0) (iter.windows width #[1, 2, 3, 4]))
entry const zip = fn count => iter.collect_array (iter.map (fn pair => do:
  let (index, value) = pair
  return index + value) (iter.enumerate (iter.take count #[10, 20, 30])))
entry const paired = fn count => iter.collect_array (iter.map (fn pair => do:
  let (left, right) = pair
  return left + right) (iter.zip (iter.range 0 count) [10, 20, 30]))
entry const strict = fn count => iter.collect_array (iter.map (fn pair => do:
  let (left, right) = pair
  return left + right) (iter.zip_strict (iter.range 0 count) [10, 20, 30]))
`, guest => {
    equal(guest.read("empty_chunks"), 0);
    equal(guest.read("empty_wrapped"), 0);
    deepStrictEqual(Array.from(guest.call("staged", null) as Uint32Array), [4, 8, 12]);
    deepStrictEqual(Array.from(guest.call("runtime", 6) as Uint32Array), [4, 8, 12]);
    deepStrictEqual(Array.from(guest.call("runtime", 0) as Uint32Array), []);
    deepStrictEqual(Array.from(guest.call("comprehension", 3) as Uint32Array), [10, 20, 12, 22]);
    deepStrictEqual(Array.from(guest.call("windows", 2) as Uint32Array), [3, 5, 7]);
    deepStrictEqual(Array.from(guest.call("windows", 5) as Uint32Array), []);
    throws(() => guest.call("windows", 0));
    deepStrictEqual(Array.from(guest.call("zip", 10) as Uint32Array), [10, 21, 32]);
    deepStrictEqual(Array.from(guest.call("paired", 2) as Uint32Array), [10, 21]);
    deepStrictEqual(Array.from(guest.call("strict", 3) as Uint32Array), [10, 21, 32]);
    throws(() => guest.call("strict", 2));
    throws(() => guest.call("strict", 4));
  }, { stdRoot });
});

Deno.test("cursor positions and retained collections are immutable snapshots", async () => {
  await compileAndRun(`
import * as iter from "std/iter"
import * as list from "std/list"
const first = fn cursor => case cursor.next of
  #Some (value, _) => value
  #Nothing => 999
const check = fn (size: U32) => do:
  let values = @list.generate size (fn index => index)
  let cursor = values.iter
  let #Some (_, second) = cursor.next else:
    return 0
  values := [999, ...self]
  let from_start = iter.collect_list cursor
  let from_second = iter.collect_list second
  return first cursor + first second + from_start.length + from_second.length + first values.iter
entry const run = fn size => check size
entry const staged = check 500
entry const array = fn seed => do:
  let values = #[seed, seed + 1, seed + 2]
  let cursor = values.iter
  values[0] := 1000
  let #Some (_, second) = cursor.next else:
    return 0
  return first cursor + first second + values[0]
const frozen_cursor = @cursor.advance [40, 41, 42].iter
entry const frozen = fn () => first frozen_cursor
entry const empty = fn () => case [].iter.next of
  #Nothing => 42
  #Some (_, _) => 0
`, guest => {
    equal(guest.call("run", 500), 1999);
    equal(guest.read("staged"), 1999);
    equal(guest.call("array", 5), 1011);
    equal(guest.call("frozen", null), 41);
    equal(guest.call("empty", null), 42);
  }, { stdRoot });
});

Deno.test("iterator effects run in pull order and stop on take, break and return", async () => {
  await compileAndRun(`
import * as iter from "std/iter"
type Count is data = #Count U32
type Counter is data = #Counter U32
const Counter.iter = fn (cursor: Counter) => cursor
const Counter.next = fn (cursor: Counter) => do:
  let #Counter value = cursor
  use count <- @state.get #Count
  let #Count before = count
  use @state.set (#Count (before + 1))
  return #Some (value, #Counter (value + 1))
const sum = fn limit => do:
  let result = 0
  for value in iter.take limit (#Counter 0):
    result := self + value
  return result
entry const taken = fn limit => do:
  let (#Count pulls, result) = @state.run (#Count 0) (fn () => sum limit)
  return pulls * 100 + result
entry const broken = fn limit => do:
  let (#Count pulls, result) = @state.run (#Count 0) (fn () => do:
    let total = 0
    for value in #Counter 0:
      total := self + value
      if value == limit:
        break
    return total)
  return pulls * 100 + result
entry const returned = fn limit => do:
  let (#Count pulls, result) = @state.run (#Count 0) (fn () => do:
    for value in #Counter 0:
      if value == limit:
        return value
    return 999)
  return pulls * 100 + result
entry const filtered = fn limit => do:
  let (#Count pulls, result) = @state.run (#Count 0) (fn () =>
    iter.fold_left add 0 (iter.take_while (fn value => value < limit) (iter.map (fn value => value * 2) (#Counter 0))))
  return pulls * 100 + result
`, guest => {
    equal(guest.call("taken", 0), 0);
    equal(guest.call("taken", 3), 303);
    equal(guest.call("broken", 2), 303);
    equal(guest.call("returned", 2), 302);
    equal(guest.call("filtered", 5), 406);
  }, { stdRoot });
});

Deno.test("custom iteration preserves Maybe short circuit and nested loop carries", async () => {
  await compileAndRun(`
import * as iter from "std/iter"
const sequence = fn stop => do (monad Maybe):
  let sum = 0
  for value in iter.range 0 5:
    if value == stop:
      use missing <- #Nothing
    sum := self + value
  return sum
entry const run = fn stop => case sequence stop of
  #Some value => value
  #Nothing => 999
entry const nested = fn count => do:
  let result = 0
  for outer in iter.range 0 count:
    for inner in iter.range 0 5:
      if inner == 2:
        break
      result := self + outer + inner
  return result
`, guest => {
    equal(guest.call("run", 2), 999);
    equal(guest.call("run", 10), 10);
    equal(guest.call("nested", 3), 9);
  }, { stdRoot });
});

Deno.test("opaque cursors do not add indexing to lists", async () => {
  await compileExpectedFailure(`entry const run = fn () => [1, 2, 3][0]`, "type_mismatch");
});

Deno.test("generic iteration retains the collection element type through source methods", async () => {
  await compileAndRun(`
import * as iter from "std/iter"
const valid = fn values => do:
  for value in values:
    if abs value > 3.402823466e38:
      return #False
    if value != value:
      return #False
  return #True
entry const array = fn (values: Array F32) => valid values
entry const list = fn (values: Array F32) => valid (@list.from_array values)
entry const adapted = fn (values: Array F32) => valid (iter.take 2 values)
`, guest => {
    for (const name of ["array", "list", "adapted"]) {
      equal(guest.call(name, new Float32Array([1, -2])), true);
      equal(guest.call(name, new Float32Array([NaN])), false);
      equal(guest.call(name, new Float32Array([Infinity])), false);
      equal(guest.call(name, new Float32Array()), true);
    }
    equal(guest.call("adapted", new Float32Array([1, 2, NaN])), true);
  }, { stdRoot });
});

Deno.test("ordinary local cursor wrappers and finite loop carries use scalar storage", async () => {
  await compileAndRun(`
type Moved a is data = #Moved a
const move = fn cursor => #Moved (@cursor.advance cursor)
entry const run = fn count => do:
  let values = @array.generate (count + 1) (fn index => index)
  let cursor = values.iter
  let total = 0
  for index in 0..count:
    let #Moved next = move cursor
    total := self + @cursor.value next
    cursor := next
  return total
`, guest => {
    for (const count of [0, 1, 8193]) equal(guest.call("run", count), count * (count + 1) / 2);
    ok(guest.memoryBytes() <= 192 * 1024, `Local cursor versions still allocate: ${guest.memoryBytes()}`);
  });
});

Deno.test("leaf traversal survives nested cache changes and nested collection", async () => {
  await compileAndRun(`
entry const nested = fn count => do:
  let values = @list.generate count (fn index => index)
  let total = 0
  for repeat in 0..2:
    for value in values:
      let prefix = 0
      for probe in values:
        if probe == 300:
          break
        prefix := self + probe
      total := self + value + prefix
  return total
entry const collected = fn count => do:
  let values = @list.generate count (fn index => index)
  let total = 0
  for value in values:
    let round = 0
    for ever:
      if round == 2:
        break
      let garbage = @array.fill 8192 value
      round := self + 1
    total := self + value
  return total
`, guest => {
    equal(guest.call("nested", 500), 45_099_500);
    equal(guest.call("nested", 0), 0);
    equal(guest.call("collected", 500), 124_750);
  });
});

Deno.test("retained cursor, structural-list and SIMD bodies match fresh compilation through edits and recovery", async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-iterator-revision-" });
  const entry = `${directory}/main.blot`, dependency = `${directory}/values.blot`;
  const executable = Deno.args[0] ?? new URL("../zig-out/bin/blotc", import.meta.url).pathname;
  const options = { executable, entry, stdRoot, prelude: `${stdRoot}/prelude.blot` };
  const before = `import * as list from "std/list"
const cursor = (list.slice 1 3 [10, 20, 30, 40, 50]).iter
const numbers = fn count => @array.generate count (fn index => index * 3 + 1)
`;
  const main = `import * as iter from "std/iter"
import * as values from "./values"
entry const answer = fn count => iter.fold_left add 0 (iter.take count values.cursor)
entry const numbers = fn count => values.numbers count
`;
  let retained: Awaited<ReturnType<typeof createZigProjectCompiler>> | undefined;
  try {
    await Deno.writeTextFile(entry, main);
    await Deno.writeTextFile(dependency, before);
    retained = await createZigProjectCompiler(options);
    for (const source of [before, before.replace("20, 30", "21, 30"), "const cursor = absent\n", before.replace("index * 3", "index * 5"), before]) {
      await Deno.writeTextFile(dependency, source);
      const result = await retained.build();
      if (source.includes("absent")) { ok(!result.success); continue; }
      ok(result.success, JSON.stringify(result.success ? {} : result.diagnostics));
      const fresh = await createZigProjectCompiler(options);
      try {
        const expected = await fresh.build();
        ok(expected.success);
        deepStrictEqual(result.bytes, expected.bytes);
      } finally { await fresh.close(); }
      const guest = await instantiateGuest(result.bytes);
      try {
        equal(guest.call("answer", 3), source.includes("21, 30") ? 91 : 90);
        const multiplier = source.includes("index * 5") ? 5 : 3;
        deepStrictEqual(Array.from(guest.call("numbers", 9) as Uint32Array), Array.from({ length: 9 }, (_, index) => index * multiplier + 1));
      } finally { guest.dispose(); }
    }
  } finally {
    await retained?.close();
    await Deno.remove(directory, { recursive: true });
  }
});
