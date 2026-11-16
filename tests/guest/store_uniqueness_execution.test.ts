import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// The store `place = value` writes storage in place, and every alias sees
// it. A `:=` through storage is accepted only when its root is unique; the
// rest are `aliased_update` (tasks/MEMORY_MODEL.md rules 2, 4 and 5).
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("stores write elements, element fields and nested rows in place through every alias", async () => {
  await compileAndRun(`
type Point is data = $Point { x: U32, y: U32 }
const pool: GrowArray U32 = #[1, 2]
lent const pick = func (flag: Bool) -> (left: Array U32) -> (right: Array U32) => return if flag then left else right
entry func element (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  let alias = rows
  rows[1] = n
  break alias[1] * 10 + rows[1]
entry func field (n: U32) : U32 => return do:
  let points = #[$Point { x: 1, y: 2 }, $Point { x: 3, y: 4 }]
  let alias = points
  points[1].y = self + n
  break alias[1].y + points[1].x
entry func nested (n: U32) : U32 => return do:
  let grid = #[#[1, 2], #[3, 4]]
  let row = grid[1]
  grid[1][0] = n
  break row[0]
entry func record_field (n: U32) : U32 => return do:
  let world = { counts: #[0, 0], size: 2 }
  let counts = world.counts
  world.counts[1] = n
  break counts[1] + world.size
entry func global (n: U32) : U32 => return do:
  pool[0] = n
  break pool[0] + pool[1]
entry func expression_root (flag: Bool) : U32 => return do:
  let left = #[1]
  let right = #[2]
  (pick flag left right)[0] = 9
  break left[0] * 10 + right[0]
entry func captured (n: U32) : U32 => return do:
  let rows = #[0, 0]
  let set = func (i: U32) => return do:
    rows[i] = n
  set 1
  break rows[1]
entry func looped (n: U32) : U32 => return do:
  let rows: GrowArray U32 = #[]
  for i in 0..n:
    @storage.push rows 0
    rows[i] = i * 2
  let total = 0
  for value in rows:
    total := self + value
  break total
`, (guest) => {
    equal(guest.call("element", 7), 77);
    equal(guest.call("field", 5), 12);
    equal(guest.call("nested", 8), 8);
    equal(guest.call("record_field", 6), 8);
    equal(guest.call("global", 40), 42);
    equal(guest.call("expression_root", true), 92);
    equal(guest.call("expression_root", false), 19);
    equal(guest.call("captured", 5), 5);
    equal(guest.call("looped", 4), 12);
  }, { stdRoot });
});

Deno.test("a store on a path that never reaches storage is rejected", async () => {
  await compileExpectedFailure(`
entry func run (n: U32) : U32 => return do:
  let point = { x: 1, y: 2 }
  point.x = n
  break point.x
`, "store_without_storage", undefined, { span: [76, 87] });
  await compileExpectedFailure(`
entry func run (n: U32) : U32 => return do:
  let total = 0
  total = n
  break total
`, "store_without_storage");
});

Deno.test(":= through storage updates unique roots in place and keeps successor results", async () => {
  await compileAndRun(`
import * as array from "std/array"
type World is data = $World { counts: Array U32, other: Array U32 }
entry func literal (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  rows[0] := n
  rows[1] := self + n
  break rows[0] + rows[1]
entry func intrinsics (n: U32) : U32 => return do:
  let filled = @array.fill 3 0
  let generated = @array.generate 3 (func index => return index)
  filled[1] := n
  generated[2] := self + n
  break filled[1] + generated[2]
entry func copied (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let saved = rows
  let snapshot = @storage.copy rows
  snapshot[0] := n
  break saved[0] * 100 + snapshot[0]
entry func comprehension (n: U32) : U32 => return do:
  let doubled = #[x * 2 | x <- #[1, 2, 3]]
  doubled[0] := n
  break doubled[0] + doubled[2]
entry func looped (n: U32) : U32 => return do:
  let rows = #[0, 0, 0]
  for i in 0..3:
    rows[i] := n + i
  break rows[0] + rows[2]
entry func early_exit (n: U32) : U32 => return do:
  let rows = #[1, 2]
  if n == 0:
    return array.fold_left U32.add 0 rows
  rows[0] := n
  break rows[0]
entry func sibling (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let total = 0
  if n == 0:
    total := array.fold_left U32.add 0 rows
  else:
    rows[0] := n
  break total + rows[0]
entry func deep (n: U32) : U32 => return do:
  let grid = #[#[1, 2], #[3, 4]]
  grid[1][0] := n
  break grid[1][0] + grid[0][1]
entry func record_root (n: U32) : U32 => return do:
  let shared = #[0, 0]
  let world = { counts: shared, other: #[1, 1] }
  world.other[1] := n
  world.counts := #[5, 5]
  world.counts[0] := n
  break world.other[1] + world.counts[0] + shared[0]
entry func nominal_root (n: U32) : U32 => return do:
  let world = $World { counts: #[0, 0], other: #[1] }
  world.counts[1] := n
  break world.counts[1]
`, (guest) => {
    equal(guest.call("literal", 5), 12);
    equal(guest.call("intrinsics", 4), 10);
    equal(guest.call("copied", 9), 109);
    equal(guest.call("comprehension", 1), 7);
    equal(guest.call("looped", 10), 22);
    equal(guest.call("early_exit", 0), 3);
    equal(guest.call("early_exit", 5), 5);
    equal(guest.call("sibling", 0), 4);
    equal(guest.call("sibling", 6), 6);
    equal(guest.call("deep", 9), 11);
    equal(guest.call("record_root", 5), 10);
    equal(guest.call("nominal_root", 3), 3);
  }, { stdRoot });
});

// Each program's only `:=` through storage has an aliased root.
const aliased: [string, string][] = [
  ["bound to another name", `
  let rows = #[1, 2]
  let before = rows
  rows[0] := n
  break before[0]`],
  ["captured by a closure", `
  let rows = #[1, 2]
  let read = func (i: U32) => return rows[i]
  rows[0] := n
  break read 0`],
  ["placed in a constructor", `
  let rows = #[1, 2]
  let held = $Some rows
  rows[0] := n
  break case held of
    $Some inner => inner[0]
    $Nothing => 0`],
  ["placed in a record", `
  let rows = #[1, 2]
  let world = { rows: rows }
  world.rows[0] := n
  break rows[0]`],
  ["returned on the same path", `
  let rows = #[1, 2]
  if n == 0:
    let kept = rows
    rows[0] := n
    return kept[0]
  break rows[1]`],
  ["read out as a storage-holding element", `
  let grid = #[#[1, 2], #[3, 4]]
  let row = grid[0]
  grid[0][1] := n
  break row[1]`],
  ["a parameter", `
  let rows = #[n]
  break (func (values: Array U32) => return do:
    values[0] := 1
    break values[0]) rows`],
  ["aliased later in a loop by a name that lives on", `
  let rows = #[0, 0]
  let held = #[0]
  for i in 0..2:
    rows[i] := n
    held := rows
  break held[0]`],
  ["aliased in a sibling branch of a loop", `
  let rows = #[0, 0]
  let held = #[0]
  for i in 0..2:
    if i == 0:
      held := rows
    else:
      rows[i] := n
  break held[0]`],
  ["iterated by its own loop", `
  let rows = #[1, 2, 3]
  let total = 0
  for value in rows:
    total := self + value
    rows[0] := n
  break total`],
  ["rows that share one fill", `
  let grid = @array.fill 2 #[0, 0]
  grid[0][0] := n
  break grid[1][0]`],
  ["bound by a pattern from a value that is read again", `
  let whole = (#[1, 2], 3)
  let (rows, other) = whole
  rows[0] := n
  let (again, same) = whole
  break rows[0] + other + again[0] + same`],
];

Deno.test(":= through an aliased root is rejected with both fixes named", async () => {
  for (const [name, body] of aliased) {
    const source = `import * as array from "std/array"
entry func run (n: U32) : U32 => return do:${body}
`;
    const start = source.indexOf("] :=") + 2;
    const line = source.lastIndexOf("\n", start) + 1;
    const place = source.slice(line, start).trimStart();
    try {
      await compileExpectedFailure(
        source,
        "aliased_update",
        "This := writes through storage that something else may still observe; store in place with = (aliases see the write), or take values.copy first to keep the old value",
        { stdRoot, span: [start - place.length, source.indexOf("\n", start)] },
      );
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});

Deno.test("each rejected := keeps its meaning as a store, or its snapshot after an explicit copy", async () => {
  await compileAndRun(`
entry func stored (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let before = rows
  rows[0] = n
  break before[0] + rows[0]
entry func snapshot (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let before = rows
  rows := rows.copy
  rows[0] := n
  break before[0] + rows[0]
entry func grown (n: U32) : U32 => return do:
  let rows: GrowArray U32 = #[1]
  let before = rows
  let fresh = rows.copy
  @storage.push fresh n
  fresh[0] := n
  break before.length * 100 + before[0] * 10 + fresh[1]
`, (guest) => {
    equal(guest.call("stored", 5), 10);
    equal(guest.call("snapshot", 5), 6);
    equal(guest.call("grown", 5), 115);
  });
});

Deno.test("a value moves at its local's last read and stays unique under the new holder", async () => {
  await compileAndRun(`
type Grid is data = $Grid { cells: Array U32, width: U32 }
entry func renamed (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let other = rows
  other[0] := n
  break other[0] * 10 + other[1]
entry func built (n: U32) : U32 => return do:
  let cells = #[n, n]
  let grid = $Grid { cells: cells, width: 2 }
  grid.cells[1] := 7
  break grid.cells[0] * 10 + grid.cells[1]
entry func nested (n: U32) : U32 => return do:
  let row = #[5, 6]
  let grid = #[#[1, 2], #[3, 4]]
  grid[1] := row
  grid[1][0] := n
  break grid[0][0] * 100 + grid[1][0] * 10 + grid[1][1]
entry func from_block (flag: Bool) : U32 => return do:
  let rows = do:
    let inner = #[1, 2]
    if flag:
      break inner
    break #[3, 4]
  rows[1] := 9
  break rows[0] * 10 + rows[1]
entry func before_return (flag: Bool) : U32 => return do:
  let rows = #[1, 2]
  if flag:
    let taken = rows
    taken[0] := 5
    return taken[0] * 10 + taken[1]
  rows[1] := 8
  break rows[0] * 10 + rows[1]
entry func each_iteration (n: U32) : U32 => return do:
  let sum = 0
  for i in 0..n:
    let rows = #[i, 1]
    let other = rows
    other[1] := i
    sum := sum + other[0] + other[1]
  break sum
`, (guest) => {
    equal(guest.call("renamed", 7), 72);
    equal(guest.call("built", 4), 47);
    equal(guest.call("nested", 8), 186);
    equal(guest.call("from_block", true), 19);
    equal(guest.call("from_block", false), 39);
    equal(guest.call("before_return", true), 52);
    equal(guest.call("before_return", false), 18);
    equal(guest.call("each_iteration", 4), 12);
  });
});

Deno.test("a local read again after another holder took its value is still aliased", async () => {
  const cases: [string, string][] = [
    ["read after the rename", `
  let rows = #[1, 2]
  let other = rows
  other[0] := n
  break other[0] + rows[0]`],
    ["given away inside a loop that runs again", `
  let rows = #[1, 2]
  let sum = 0
  for i in 0..n:
    let other = rows
    other[0] := i
    sum := sum + other[0]
  break sum`],
    ["captured by a closure afterwards", `
  let rows = #[1, 2]
  let other = rows
  let read = func (i: U32) => return rows[i]
  other[0] := n
  break read 0 + other[0]`],
    ["carried into a loop afterwards", `
  let rows = #[1, 2]
  let other = rows
  for i in 0..n:
    rows := #[i, i]
  other[0] := n
  break other[0] + rows[0]`],
  ];
  for (const [name, body] of cases) {
    const source = `entry func run (n: U32) : U32 => return do:${body}\n`;
    const start = source.indexOf("other[0] :=");
    try {
      await compileExpectedFailure(source, "aliased_update", undefined, { span: [start, source.indexOf("\n", start)] });
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});

Deno.test("a call only borrows its arguments, and its result is the caller's to update", async () => {
  await compileAndRun(`import * as array from "std/array"
entry func lent (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let total = array.fold_left U32.add 0 rows
  rows[0] := n
  break total * 10 + rows[0]
entry func from_call (n: U32) : U32 => return do:
  let rows = array.fill 2 0
  rows[0] := n
  break rows[0] * 10 + rows[1]
`, (guest) => {
    equal(guest.call("lent", 5), 35);
    equal(guest.call("from_call", 4), 40);
  }, { stdRoot });
});

Deno.test("a store writes through what was lent, a lent function shares, and a closure gives back what it captured", async () => {
  await compileAndRun(`func fill (rows: Array U32) -> (n: U32) : U32 => return do:
  rows[0] = n
  break rows.length
lent func same (rows: Array U32) => return rows
func each (count: U32) -> (visit: U32 -> Unit) : U32 => return do:
  for index in 0..count:
    visit index
  break count
func through (make: U32 -> Array U32) -> (n: U32) : Array U32 => return do:
  let rows = make n
  rows[0] := self + 1
  break rows
entry func stored (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let size = fill rows n
  rows[1] := size
  break rows[0] * 10 + rows[1]
entry func shared (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let again = same rows
  rows[0] = n
  break again[0] * 10 + rows[0]
entry func collected (n: U32) : U32 => return do:
  let seen: GrowArray U32 = #[]
  let count = each n (func index => return @storage.push seen (index * 2))
  let rows = @storage.freeze seen
  rows[0] := count
  break rows[0] * 100 + rows[n - 1]
entry func made (n: U32) : U32 => return (through (func k => return #[k, k]) n)[0]
`, (guest) => {
    equal(guest.call("stored", 5), 52);
    equal(guest.call("shared", 7), 77);
    equal(guest.call("collected", 4), 406);
    equal(guest.call("made", 8), 9);
  }, { stdRoot });
  const kept = `func put (grid: Array (Array U32)) -> (row: Array U32) : U32 => return do:
  grid[0] = row
  break 0
entry func run (n: U32) : U32 => return do:
  let grid = #[#[n], #[2]]
  break put grid #[3] + grid[0][0]
`;
  const start = kept.indexOf("grid[0] = row");
  await compileExpectedFailure(kept, "kept_value", undefined, { span: [start, kept.indexOf("\n", start)] });
  const value = `lent func same (rows: Array U32) => return rows
entry func run (n: U32) : U32 => return do:
  let pick = same
  break (pick #[n])[0]
`;
  const named = value.indexOf("= same") + 2;
  await compileExpectedFailure(value, "lent_result_value", undefined, { span: [named, named + 4] });
});

Deno.test("taking a value nothing else holds apart gives each part to its name", async () => {
  await compileAndRun(`func parts (n: U32) => return { first: #[n, 2], second: #[3] }
func pair (n: U32) => return (#[n, 2], #[3])
entry func record (n: U32) : U32 => return do:
  let { first, second } = parts n
  first[1] := self + second[0]
  second[0] := n
  break first[0] * 100 + first[1] * 10 + second[0]
entry func tuple (n: U32) : U32 => return do:
  let (left, right) = pair n
  left[0] := self + 1
  right[0] := self + left[1]
  break left[0] * 10 + right[0]
`, (guest) => {
    equal(guest.call("record", 4), 454);
    equal(guest.call("tuple", 4), 55);
  }, { stdRoot });
  const shared = `entry func run (n: U32) : U32 => return do:
  let whole = (#[n, 2], #[3])
  let (left, right) = whole
  left[0] := 9
  let (again, other) = whole
  break left[0] + again[0]
`;
  const start = shared.indexOf("left[0] := 9");
  await compileExpectedFailure(shared, "aliased_update", undefined, { span: [start, shared.indexOf("\n", start)] });
});

Deno.test("a name that borrows gives the value back after its last use", async () => {
  await compileAndRun(`entry func back (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  let seen = counts[0]
  world.counts[0] := seen + 1
  break world.counts[0]
entry func nested (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  let total = 0
  if n > 1:
    total := counts[0]
  for index in 0..2:
    total := total + counts[index]
  world.counts[0] := total
  break world.counts[0]
entry func other_field (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], more: #[3] }
  let more = world.more
  world.counts[0] := self + more[0]
  break world.counts[0] * 10 + more[0]
func window (rows: Array U32) => return &rows[0..1]
entry func view (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], more: #[3] }
  let seen = window world.counts
  world.more[0] := seen[0]
  let got = seen[0]
  world.counts[0] := got + 1
  break world.counts[0] * 10 + world.more[0]
entry func each_round (n: U32) : U32 => return do:
  let rows = #[0, 0]
  let total = 0
  for i in 0..2:
    rows[i] := n
    let kept = rows
    total := self + kept[i]
  break total
`, (guest) => {
    equal(guest.call("back", 4), 5);
    equal(guest.call("nested", 4), 10);
    equal(guest.call("each_round", 4), 8);
    equal(guest.call("other_field", 4), 73);
    equal(guest.call("view", 4), 54);
  }, { stdRoot });
  const cases: [string, string][] = [
    ["read again afterwards", `
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  world.counts[0] := 9
  break counts[0]`],
    ["handed on to another name", `
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  let other = counts
  world.counts[0] := 9
  break other[0]`],
    ["one of two names for the same field still in use", `
  let world = { counts: #[n, 2], more: #[3] }
  let counts = world.counts
  let again = world.counts
  let seen = counts[0]
  world.counts[0] := seen
  break again[0]`],
  ];
  for (const [name, body] of cases) {
    const source = `entry func run (n: U32) : U32 => return do:${body}\n`;
    const start = source.indexOf("world.counts[0] :=");
    try {
      await compileExpectedFailure(source, "aliased_update", undefined, { span: [start, source.indexOf("\n", start)] });
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});
