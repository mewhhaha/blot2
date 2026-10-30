import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("closed catalog layouts reuse proof without sharing owner or field state", async () => {
  const fields = Array.from({ length: 305 }, (_, i) => `f${i}: U32`).join(", ");
  const values = Array.from({ length: 305 }, (_, i) => `f${i}: ${i}`).join(
    ", ",
  );
  const owners = Array.from(
    { length: 160 },
    (_, i) => `const owner_${i}: Array Catalog = #[]`,
  ).join("\n");
  const reads = Array.from(
    { length: 160 },
    (_, i) => `  total := @u32.add total (@array.length owner_${i})`,
  ).join("\n");
  await compileAndRun(
    `type Catalog is data = $Catalog {${fields}}
const catalog: Catalog = $Catalog {${values}}
${owners}
entry const answer = func () => return do:
  let selected: ResizeArray U32 = #[0]
  let changed = #[catalog]
  let independent = #[catalog]
  changed[0].f0 := 900
  let total = selected[0]
${reads}
  return #[total, changed[0].f0, independent[0].f0]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answer", null),
        new Uint32Array([0, 900, 0]),
      );
      assert.deepEqual(
        guest.call("answer", null),
        new Uint32Array([0, 900, 0]),
      );
    },
  );
});

Deno.test("impossible borrowed variant arms need no fabricated owner", async () => {
  await compileAndRun(
    `
type Choice is data = $No | $Rows &[U32]
const count = func (choice: Choice): U32 => return case choice of
  $No => 42
  $Rows rows => do:
    let total = 0
    for value in rows:
      total := self + value
    break total
entry const answer = func (): U32 => return do:
  let marker: GrowArray U32 = #[]
  let rows: Array Choice = #[$No]
  return count rows[0]
`,
    (guest) => assert.equal(guest.call("answer", null), 42),
  );
});

Deno.test("nested inactive payloads stay uninitialized when a different outer arm joins", async () => {
  await compileAndRun(
    `
type Choice is data = $No | $Rows &[U32]
const choose = func (absent: Bool): Maybe Choice => return do:
  if absent:
    return $Nothing
  return $Some $No
entry const answer = func (absent: Bool): U32 => return do:
  let marker: GrowArray U32 = #[]
  let values: Array (Maybe Choice) = #[choose absent]
  return case values[0] of
    $Nothing => 7
    $Some $No => 42
    $Some ($Rows rows) => rows[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", false), 42);
      assert.equal(guest.call("answer", true), 7);
    },
  );
});

Deno.test("empty owner alternatives contribute no fabricated stored borrow", async () => {
  await compileAndRun(
    `
entry const answer = func (present: Bool): U32 => return do:
  let source: GrowArray U32 = #[21]
  let early_empty: Array {rows: &[U32]} = #[]
  let populated: Array {rows: &[U32]} = #[{rows: &source[0..1]}]
  let late_empty: Array {rows: &[U32]} = #[]
  let first = if present then populated else early_empty
  let second = if present then populated else late_empty
  let total = 0
  for item in first:
    total := self + item.rows[0]
  for item in second:
    total := self + item.rows[0]
  return total
`,
    (guest) => {
      assert.equal(guest.call("answer", true), 42);
      assert.equal(guest.call("answer", false), 0);
    },
  );
});

Deno.test("data stacks inline named records and preserve constructor and field order", async () => {
  await compileAndRun(
    `
type Position is data = $Position {z: U32, x: F32}
type Box a is data = $Box {value: a}
const positions: GrowArray Position = #[$Position (7, 1.5)]
entry const read = func (): Array F32 => return do:
  let first = positions[0]
  let $Position (z, x) = first
  let boxes: GrowArray (Box U32) = #[$Box 40]
  let pushed = @storage.push positions ($Position {x: 2.5, z: 9})
  let written = @storage.write (&boxes[0]) ($Box 42)
  let $Box number = boxes[0]
  return #[first.x, x, U32.to_f32 z, positions[1].x, U32.to_f32 boxes[0].value, U32.to_f32 number]
`,
    (guest, bytes) => {
      assert.deepEqual(
        guest.call("read", null),
        new Float32Array([1.5, 1.5, 7, 2.5, 42, 42]),
      );
      assert.deepEqual(
        guest.call("read", null),
        new Float32Array([1.5, 1.5, 7, 2.5, 42, 42]),
      );
      assert(
        !WebAssembly.Module.exports(new WebAssembly.Module(bytes)).some((
          { name },
        ) => /retain|release|cycle/.test(name)),
      );
    },
  );
});

Deno.test("nominal wrappers preserve borrow lifetime checks", async () => {
  await compileExpectedFailure(
    `
type Borrow is data = $Borrow {target: &U32}
const escape = func () => return do:
  let items: GrowArray U32 = #[42]
  return $Borrow (&items[0])
entry const answer = func () => return @storage.load (escape ()).target
`,
    "storage_escape",
  );
  await compileAndRun(
    `
type Borrow is data = $Borrow {target: &U32}
entry const answer = func () => return do:
  let items: GrowArray U32 = #[40]
  let borrowed = $Borrow (&items[0])
  let written = @storage.write borrowed.target 42
  return @storage.load borrowed.target
`,
    (guest) => assert.equal(guest.call("answer", null), 42),
  );
});

Deno.test("inline updates copy records while array writes reach aliases and explicit copies stay independent", async () => {
  await compileAndRun(
    `
type Point is data = $Point {z: U32, x: F32}
type World is data = $World {points: GrowArray Point}
const points: GrowArray Point = #[$Point (7, 1.5)]
entry const answer = func (): Array F32 => return do:
  let world = $World points
  let alias = world
  let checkpoint = @storage.copy points
  let before = world.points[0]
  world.points[0].x := self + 1.0
  let row = world.points[0]
  row.z := 42
  let record = {nested: {z: 3, x: 2.0}, count: 1}
  let old = record
  record.nested.x := self * 2.0
  return #[alias.points[0].x, checkpoint[0].x, before.x, U32.to_f32 row.z, U32.to_f32 points[0].z, record.nested.x, old.nested.x]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answer", null),
        new Float32Array([2.5, 1.5, 1.5, 42, 7, 4, 2]),
      );
      assert.deepEqual(
        guest.call("answer", null),
        new Float32Array([3.5, 2.5, 2.5, 42, 7, 4, 2]),
      );
    },
  );
});

Deno.test("indexed updates select once before RHS and pin the selected extent", async () => {
  await compileAndRun(
    `
const calls: GrowArray U32 = #[0]
const select = func () => return do:
  let incremented = @storage.write (&calls[0]) (calls[0] + 1)
  return 0
entry const answer = func () => return do:
  let values: GrowArray U32 = #[40]
  values[select ()] := self + calls[0] + 1
  return values[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", null), 42);
    },
  );
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let values: ResizeArray U32 = #[40]
  values[0] := do:
    let removed = @storage.pop values
    break 42
  return values[0]
`,
    "storage_borrow_conflict",
  );
  await compileExpectedFailure(
    `
const owners: GrowArray U32 = #[0]
entry const bad = func () => return do:
  let rows: GrowArray {target: &U32} = #[{target: &owners[0]}]
  let escaped = do:
    let local: GrowArray U32 = #[42]
    rows[0].target := &local[0]
    break 0
  return @storage.load rows[0].target
`,
    "storage_escape",
  );
});

Deno.test("generic pool helpers specialize empty owners and inline records per call", async () => {
  await compileAndRun(
    `
type Pool a is data = $Pool {values: GrowArray a}
const empty = func (): Pool a => return $Pool #[]
const add = func (pool: Pool a) -> (value: a) => return @storage.push pool.values value
const first = func (pool: Pool a): a => return pool.values[0]
const create = func (value: a): Pool a => return do:
  let pool: Pool a = empty ()
  let added = add pool value
  return pool
entry const answer = func (): Array F32 => return do:
  let integers = create 41
  let floats = create 2.5
  let points = create {x: 1.5, z: 9}
  let add_integer = add integers
  let appended = add_integer 42
  return #[U32.to_f32 (first integers), first floats, (first points).x, U32.to_f32 integers.values[1]]
`,
    (guest) =>
      assert.deepEqual(
        guest.call("answer", null),
        new Float32Array([41, 2.5, 1.5, 42]),
      ),
  );
});

Deno.test("nested field writes preserve sibling mutations performed by the RHS", async () => {
  await compileAndRun(
    `
type Point is data = $Point {z: U32, x: U32}
entry const answer = func (): Array U32 => return do:
  let rows: GrowArray {point: Point, count: U32} = #[{point: $Point (7, 1), count: 3}]
  let alias = rows
  rows[0].point.x := do:
    alias[0].point.z := 9
    alias[0].count := 4
    break self + 1
  return #[rows[0].point.x, rows[0].point.z, rows[0].count]
`,
    (guest) =>
      assert.deepEqual(guest.call("answer", null), new Uint32Array([2, 9, 4])),
  );
});

Deno.test("fixed array builders specialize generic callbacks without implicit snapshots", async () => {
  await compileAndRun(
    `
import * as array from "std/array"
const copied = func (items: Array a): Array a => return array.generate items.length (func index => return items[index])
entry const answer = func (count: U32): Array U32 => return do:
  let storage: GrowArray U32 = #[1]
  let values = array.generate count (func index => return index + 10)
  let checkpoint = copied values
  let replaced = array.replace 0 42 values
  let filled = array.fill 2 7
  let joined = array.concat (array.slice 0 1 replaced) filled
  let borrowed = joined.view 1 joined.length
  let extended = array.push 9 borrowed
  joined[1] := 100
  return array.concat #[values[0], checkpoint[0], @storage.length storage] extended
`,
    (guest) =>
      assert.deepEqual(
        guest.call("answer", 3),
        new Uint32Array([42, 10, 1, 7, 7, 9]),
      ),
    { stdRoot: new URL("../../std/", import.meta.url).pathname },
  );
});

Deno.test("language tasks cannot enter data-stack programs", async () => {
  await compileExpectedFailure(
    `
entry const bad = func () => return do:
  let values: GrowArray U32 = #[42]
  let task = @task.scope (func group => return 1)
  return values[0] + task
`,
    "storage_unsupported",
    "Language tasks are not part of the data-stack model; use isolated host worker jobs and copied packets",
  );
});

Deno.test("local scalar demands memoize once on either branch and preserve short circuiting", async () => {
  await compileAndRun(
    `
const calls: GrowArray U32 = #[0]
const bump = func () => return do:
  let changed = @storage.write (&calls[0]) (calls[0] + 1)
  return 42
const twice = func ~(value: U32) -> (flag: Bool) => return do:
  let first = if flag then @demand value else 0
  return first + @demand value
entry const answer = func (flag: Bool): Array U32 => return do:
  let guarded = (false and (@panic "unreachable right")) or (true or (@panic "unreachable right"))
  let result = twice (bump ()) flag
  return #[result, calls[0], if guarded then 1 else 0]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answer", false),
        new Uint32Array([42, 1, 1]),
      );
      assert.deepEqual(guest.call("answer", true), new Uint32Array([84, 2, 1]));
    },
  );
});

Deno.test("local optional owners retain selected descriptors across branches and calls", async () => {
  await compileAndRun(
    `
const choose = func (value: U32): Maybe (Array U32) => return do:
  if value == 0:
    return $Nothing
  let rows: GrowArray U32 = #[value, value + 1]
  return $Some (@storage.freeze rows)
entry const answer = func (value: U32): U32 => return do:
  let result = choose value
  let other = choose (value + 2)
  let total = case result of
    $Some rows => rows[0] + rows[1]
    $Nothing => 10
  let $Some rows = other else:
    return 999
  return total + rows[0] + rows[1]
`,
    (guest) => {
      for (let i = 0; i < 100; i++) {
        assert.equal(guest.call("answer", 0), 15);
        assert.equal(guest.call("answer", 3), 18);
      }
    },
  );
});

Deno.test("inactive generic variant payloads use their constructor owned type binders", async () => {
  await compileAndRun(
    `
type Wrapped [left, right] is data = $Wrapped { value: left, count: right }
type Read is data = $Items { rows: Wrapped [&[U32], U32], next: U32 } | $Reset U32
const read = func (rows: &[U32]) -> (reset: Bool): Read => return
  if reset then $Reset 7 else $Items { rows: $Wrapped { value: rows, count: 1 }, next: 3 }
entry const answer = func (reset: Bool): U32 => return do:
  let values: GrowArray U32 = #[42]
  return case read (&values[0..1]) reset of
    $Reset next => next
    $Items {rows, next} => rows.value[0] + next
`,
    (guest) => {
      assert.equal(guest.call("answer", true), 7);
      assert.equal(guest.call("answer", false), 45);
    },
  );
});

Deno.test("copying variants preserves only initialized borrow alternatives", async () => {
  await compileAndRun(
    `
type Choice is data = $No | $Rows &[U32] | $Other Bool
entry const answer = func (borrow: Bool): U32 => return do:
  let owner: GrowArray U32 = #[42]
  let plain: Array Choice = #[$No, $Other true]
  let copied = @array.generate plain.length (func i => return plain[i])
  let mixed: Array Choice = #[if borrow then $Rows (&owner[0..1]) else copied[1]]
  let again = @array.generate mixed.length (func i => return mixed[i])
  return case again[0] of
    $No => 0
    $Rows rows => rows[0]
    $Other flag => if flag then 7 else 8
`,
    (guest) => {
      assert.equal(guest.call("answer", false), 7);
      assert.equal(guest.call("answer", true), 42);
    },
  );
  await compileExpectedFailure(
    `
type Choice is data = $No | $Rows &[U32]
entry const answer = func () => return do:
  let escaped: GrowArray Choice = #[$No]
  let ignored = do:
    let owner: GrowArray U32 = #[42]
    let rows: Array Choice = #[$Rows (&owner[0..1])]
    escaped[0] := rows[0]
    break 0
  return 0
`,
    "storage_escape",
  );
});

Deno.test("loop reads cannot acquire later variants or borrowed roots on a backedge", async () => {
  await compileExpectedFailure(
    `
type Choice is data = $No | $Rows &[U32]
entry const answer = func () => return do:
  let owner: GrowArray U32 = #[42]
  let rows: Array Choice = #[$No]
  let count = 0
  for i in 0 .. 2:
    for j in 0 .. 1:
      let copied = @storage.copy rows
      count := self + copied.length
    let written = @storage.write (&rows[0]) ($Rows (&owner[0..1]))
  return count
`,
    "storage_escape",
    "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
  );
  await compileExpectedFailure(
    `
type Choice is data = $No | $Rows {left: &[U32], right: &[U32]}
entry const answer = func () => return do:
  let first: GrowArray U32 = #[41]
  let second: GrowArray U32 = #[42]
  let rows: Array Choice = #[$Rows {left: &first[0..1], right: &second[0..1]}]
  let count = 0
  for i in 0 .. 2:
    let copied = @storage.copy rows
    count := self + copied.length
    let written = @storage.write (&rows[0]) ($Rows {left: &second[0..1], right: &second[0..1]})
  return count
`,
    "storage_escape",
    "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
  );
  await compileExpectedFailure(
    `
type Choice is data = $No | $Rows &[U32]
entry const answer = func () => return do:
  let owner: GrowArray U32 = #[42]
  let rows: Array Choice = #[$No]
  let total = 0
  for i in 0 .. 2:
    let copied = @storage.copy rows
    total := self + copied.length
    let written = @storage.write (&rows[0]) ($Rows (&owner[0..1]))
    continue
  return total
`,
    "storage_escape",
    "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
  );
  await compileExpectedFailure(
    `
type Choice is data = $No | $Rows &[U32]
entry const answer = func () => return do:
  let owner: GrowArray U32 = #[42]
  let rows: Array Choice = #[$No]
  let counts = @array.generate 2 (func i => return do:
    let copied = @storage.copy rows
    let written = @storage.write (&rows[0]) ($Rows (&owner[0..1]))
    return copied.length)
  return counts[0]
`,
    "storage_escape",
    "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
  );
});

Deno.test("writing the complete borrow shape before a loop read remains admitted", async () => {
  await compileAndRun(
    `
type Choice is data = $No | $Rows &[U32]
entry const answer = func (): Array U32 => return do:
  let owner: GrowArray U32 = #[42]
  let rows: Array Choice = #[$No]
  let total = 0
  for i in 0 .. 2:
    let written = @storage.write (&rows[0]) ($Rows (&owner[0..1]))
    let copied = @storage.copy rows
    total := self + (case copied[0] of
      $No => 0
      $Rows view => view[0])
  let generated_rows: Array Choice = #[$No]
  let counts = @array.generate 2 (func i => return do:
    let written = @storage.write (&generated_rows[0]) ($Rows (&owner[0..1]))
    let copied = @storage.copy generated_rows
    return case copied[0] of
      $No => 0
      $Rows view => view[0])
  return #[total, counts[0], counts[1]]
`,
    (guest) =>
      assert.deepEqual(
        guest.call("answer", null),
        new Uint32Array([84, 42, 42]),
      ),
  );
});
