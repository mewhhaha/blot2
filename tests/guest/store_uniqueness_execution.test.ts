import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

// The `=` borrowed-mutator store statement was removed in Phase 3.
// A `:=` through storage is accepted only when its root is unique; the
// rest are `aliased_update` (tasks/MEMORY_MODEL.md).
const stdRoot = new URL("../../std", import.meta.url).pathname;

Deno.test("legacy = store statements are rejected as syntax errors", async () => {
  for (
    const snippet of [
      `#entry func element (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  rows[1] = n
  break rows[1]`,
      `#entry func run (n: U32) : U32 => return do:
  let point = { x: 1, y: 2 }
  point.x = n
  break point.x`,
      `#entry func run (n: U32) : U32 => return do:
  let total = 0
  total = n
  break total`,
    ]
  ) {
    await compileExpectedFailure(snippet + "\n", "GPU_FRONTEND_SYNTAX_ERROR");
  }
});

Deno.test(":= through storage updates unique roots in place and keeps successor results", async () => {
  await compileAndRun(`
import * as array from "std/array"
type World is data = $World { counts: Array U32, other: Array U32 }
#entry func literal (n: U32) : U32 => return do:
  let rows = #[1, 2, 3]
  rows[0] := n
  rows[1] := self + n
  break rows[0] + rows[1]
#entry func intrinsics (n: U32) : U32 => return do:
  let filled = @array.fill 3 0
  let generated = @array.generate 3 (func index => return index)
  filled[1] := n
  generated[2] := self + n
  break filled[1] + generated[2]
#entry func copied (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let saved = rows
  let snapshot = @storage.copy rows
  snapshot[0] := n
  break saved[0] * 100 + snapshot[0]
#entry func comprehension (n: U32) : U32 => return do:
  let doubled = #[x * 2 | x <- #[1, 2, 3]]
  doubled[0] := n
  break doubled[0] + doubled[2]
#entry func looped (n: U32) : U32 => return do:
  let rows = #[0, 0, 0]
  for i in 0..3:
    rows[i] := n + i
  break rows[0] + rows[2]
#entry func early_exit (n: U32) : U32 => return do:
  let rows = #[1, 2]
  if n == 0:
    return array.fold_left U32.add 0 rows
  rows[0] := n
  break rows[0]
#entry func sibling (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let total = 0
  if n == 0:
    total := array.fold_left U32.add 0 rows
  else:
    rows[0] := n
  break total + rows[0]
#entry func deep (n: U32) : U32 => return do:
  let grid = #[#[1, 2], #[3, 4]]
  grid[1][0] := n
  break grid[1][0] + grid[0][1]
#entry func record_root (n: U32) : U32 => return do:
  let shared = #[0, 0]
  let world = { counts: shared, other: #[1, 1] }
  world.other[1] := n
  world.counts := #[5, 5]
  world.counts[0] := n
  break world.other[1] + world.counts[0] + shared[0]
#entry func nominal_root (n: U32) : U32 => return do:
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
#entry func run (n: U32) : U32 => return do:${body}
`;
    const start = source.indexOf("] :=") + 2;
    const line = source.lastIndexOf("\n", start) + 1;
    const place = source.slice(line, start).trimStart();
    try {
      await compileExpectedFailure(
        source,
        "aliased_update",
        "This := writes through storage that something else may still observe; take values.copy first to keep the old value, or end earlier borrows before updating",
        { stdRoot, span: [start - place.length, source.indexOf("\n", start)] },
      );
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});

Deno.test("each rejected := keeps its snapshot after an explicit copy", async () => {
  await compileAndRun(`
#entry func snapshot (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let before = rows
  rows := rows.copy
  rows[0] := n
  break before[0] + rows[0]
#entry func grown (n: U32) : U32 => return do:
  let rows: Array U32 = #[1]
  let before = rows
  let fresh = rows.copy
  @storage.push fresh n
  fresh[0] := n
  break before.length * 100 + before[0] * 10 + fresh[1]
`, (guest) => {
    equal(guest.call("snapshot", 5), 6);
    equal(guest.call("grown", 5), 115);
  });
});

Deno.test("a value moves at its local's last read and stays unique under the new holder", async () => {
  await compileAndRun(`
type Grid is data = $Grid { cells: Array U32, width: U32 }
#entry func renamed (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let other = rows
  other[0] := n
  break other[0] * 10 + other[1]
#entry func built (n: U32) : U32 => return do:
  let cells = #[n, n]
  let grid = $Grid { cells: cells, width: 2 }
  grid.cells[1] := 7
  break grid.cells[0] * 10 + grid.cells[1]
#entry func nested (n: U32) : U32 => return do:
  let row = #[5, 6]
  let grid = #[#[1, 2], #[3, 4]]
  grid[1] := row
  grid[1][0] := n
  break grid[0][0] * 100 + grid[1][0] * 10 + grid[1][1]
#entry func from_block (flag: Bool) : U32 => return do:
  let rows = do:
    let inner = #[1, 2]
    if flag:
      break inner
    break #[3, 4]
  rows[1] := 9
  break rows[0] * 10 + rows[1]
#entry func before_return (flag: Bool) : U32 => return do:
  let rows = #[1, 2]
  if flag:
    let taken = rows
    taken[0] := 5
    return taken[0] * 10 + taken[1]
  rows[1] := 8
  break rows[0] * 10 + rows[1]
#entry func each_iteration (n: U32) : U32 => return do:
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
    const source = `#entry func run (n: U32) : U32 => return do:${body}\n`;
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
#entry func lent (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let total = array.fold_left U32.add 0 rows
  rows[0] := n
  break total * 10 + rows[0]
#entry func from_call (n: U32) : U32 => return do:
  let rows = array.fill 2 0
  rows[0] := n
  break rows[0] * 10 + rows[1]
`, (guest) => {
    equal(guest.call("lent", 5), 35);
    equal(guest.call("from_call", 4), 40);
  }, { stdRoot });
});

Deno.test("an own parameter updates in place and a closure gives back what it captured", async () => {
  await compileAndRun(`func fill (rows: own Array U32) -> (n: U32) : (Array U32, U32) => return do:
  rows[0] := n
  let size = rows.length
  break (rows, size)
func each (count: U32) -> (visit: U32 -> Unit) : U32 => return do:
  for index in 0..count:
    visit index
  break count
func through (make: U32 -> Array U32) -> (n: U32) : Array U32 => return do:
  let rows = make n
  rows[0] := self + 1
  break rows
#entry func owned (n: U32) : U32 => return do:
  let rows = #[1, 2]
  let (updated, size) = fill rows n
  updated[1] := size
  break updated[0] * 10 + updated[1]
#entry func collected (n: U32) : U32 => return do:
  let seen: Array U32 = #[1, 2, 3, 4]
  let count = each n (func index => return do:
    let _ = seen[index]
    return ())
  seen[0] := count
  break seen[0] * 100 + seen[n - 1]
#entry func made (n: U32) : U32 => return (through (func k => return #[k, k]) n)[0]
`, (guest) => {
    equal(guest.call("owned", 5), 52);
    equal(guest.call("collected", 4), 404);
    equal(guest.call("made", 8), 9);
  }, { stdRoot });
  const lentPush = `func put (grid: Array (Array U32)) -> (row: Array U32) : U32 => return do:
  @storage.push grid row
  break 0
#entry func run (n: U32) : U32 => return do:
  let grid: Array (Array U32) = #[#[n], #[2]]
  break put grid #[3] + grid[0][0]
`;
  const start = lentPush.indexOf("@storage.push grid row");
  await compileExpectedFailure(lentPush, "aliased_update", undefined, { span: [start, lentPush.indexOf("\n", start)] });
  const sharedReturn = `func put (grid: own Array (Array U32)) -> (row: Array U32) : Array (Array U32) => return do:
  @storage.push grid row
  break grid
#entry func run (n: U32) : U32 => return do:
  let grid: Array (Array U32) = #[#[n], #[2]]
  let next = put grid #[3]
  break next[0][0]
`;
  await compileExpectedFailure(sharedReturn, "result_not_owned");
});

Deno.test("taking a value nothing else holds apart gives each part to its name", async () => {
  await compileAndRun(`func parts (n: U32) => return { first: #[n, 2], second: #[3] }
func pair (n: U32) => return (#[n, 2], #[3])
#entry func record (n: U32) : U32 => return do:
  let { first, second } = parts n
  first[1] := self + second[0]
  second[0] := n
  break first[0] * 100 + first[1] * 10 + second[0]
#entry func tuple (n: U32) : U32 => return do:
  let (left, right) = pair n
  left[0] := self + 1
  right[0] := self + left[1]
  break left[0] * 10 + right[0]
`, (guest) => {
    equal(guest.call("record", 4), 454);
    equal(guest.call("tuple", 4), 55);
  }, { stdRoot });
  const shared = `#entry func run (n: U32) : U32 => return do:
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
  await compileAndRun(`#entry func back (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  let seen = counts[0]
  world.counts[0] := seen + 1
  break world.counts[0]
#entry func nested (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], size: 2 }
  let counts = world.counts
  let total = 0
  if n > 1:
    total := counts[0]
  for index in 0..2:
    total := total + counts[index]
  world.counts[0] := total
  break world.counts[0]
#entry func other_field (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], more: #[3] }
  let more = world.more
  world.counts[0] := self + more[0]
  break world.counts[0] * 10 + more[0]
func window (rows: Array U32) => return &rows[0..1]
#entry func view (n: U32) : U32 => return do:
  let world = { counts: #[n, 2], more: #[3] }
  let seen = window world.counts
  world.more[0] := seen[0]
  let got = seen[0]
  world.counts[0] := got + 1
  break world.counts[0] * 10 + world.more[0]
#entry func each_round (n: U32) : U32 => return do:
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
    const source = `#entry func run (n: U32) : U32 => return do:${body}\n`;
    const start = source.indexOf("world.counts[0] :=");
    try {
      await compileExpectedFailure(source, "aliased_update", undefined, { span: [start, source.indexOf("\n", start)] });
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});

Deno.test("an owned update cannot write through a slice or through a helper with a field constraint", async () => {
  const declarations = `type Row is data = $Row {value: U32}
func change (own state) => return do:
  let old = state.rows[0].value
  state.rows[0].value := old + 40
  return state
func slice (rows: Array Row): &[Row] => return &rows[0..rows.length]
`;
  for (const assignment of ["view[0].value := 42", "let _ = change {rows: view}"]) {
    await compileExpectedFailure(declarations + `#entry func test (): U32 => return do:
  let rows = #[$Row {value: 1}]
  let view = slice rows
  ${assignment}
  return rows[0].value
`, "type_mismatch");
  }
  await compileAndRun(declarations + `#entry func test () => return do:
  let fixed = #[$Row {value: 1}]
  let resized: Array Row = #[$Row {value: 2}]
  let fixed_state = change {rows: fixed}
  let resized_state = change {rows: resized}
  return fixed_state.rows[0].value + resized_state.rows[0].value
`, guest => equal(guest.call("test", null), 83));
});

Deno.test("references, views, links, and shared handles reject writes (Phase 5)", async () => {
  for (
    const [snippet, expectedCode] of [
      [
        `#entry func bad (): U32 =>
  let rows = #[1, 2]
  let r: &#[U32] = &rows
  r[0] := 9
  return 0`,
        "type_mismatch",
      ],
      [
        `#entry func bad (): U32 =>
  let pool: Array #[U32] = #[#[1, 2]]
  let lk: ^#[U32] = ^pool[0]
  lk[0] := 9
  return 0`,
        "type_mismatch",
      ],
      [
        `#entry func bad (): U32 =>
  let s: *#[U32] = freeze #[1, 2]
  s[0] := 9
  return 0`,
        "type_mismatch",
      ],
      [
        `#entry func bad (): U32 =>
  let p = { x: 1, y: 2 }
  let r: &{ x: U32, y: U32 } = &p
  r.x := 9
  return 0`,
        "missing_field",
      ],
      [
        `#entry func bad (): U32 =>
  let pool: Array { x: U32, y: U32 } = #[{ x: 1, y: 2 }]
  let lk: ^{ x: U32, y: U32 } = ^pool[0]
  lk.x := 9
  return 0`,
        "missing_field",
      ],
      [
        `#entry func bad (): U32 =>
  let s: *{ x: U32, y: U32 } = freeze { x: 1, y: 2 }
  s.x := 9
  return 0`,
        "missing_field",
      ],
      [
        `#entry func bad (): U32 =>
  let rows: Array U32 = #[1, 2]
  let view = &rows[0..2]
  @storage.push view 3
  return 0`,
        "type_mismatch",
      ],
      [
        `#entry func bad (): U32 =>
  let rows: Array U32 = #[1, 2]
  let s = freeze rows
  @storage.push s 3
  return 0`,
        "type_mismatch",
      ],
    ] as [string, string][]
  ) {
    await compileExpectedFailure(snippet + "\n", expectedCode);
  }
});

Deno.test("@simd.store and @storage.push/truncate/pop/share enforce unique ownership (Phase 5)", async () => {
  await compileAndRun(
    `
func step_move (p: own #[U32]) -> (v: U32): #[U32] =>
  for i in 0..1:
    p := @simd.store p i (v, v + 1, v + 2, v + 3)
  return p

func step_inplace (p: own #[U32]) -> (v: U32): #[U32] =>
  for i in 0..1:
    @simd.store p i (v, v + 1, v + 2, v + 3)
  return p

type ViewAccess is data = $ViewAccess { view: &[U32], count: U32 }

func push_check (checks: own #[U32]) -> (v: U32): #[U32] =>
  @storage.push checks v
  return checks

func inspect_access (access: own ViewAccess) -> (v: U32) -> (checks: own #[U32]): (ViewAccess, #[U32]) =>
  checks := push_check self v
  checks := push_check self (v + 1)
  return (access, checks)

#entry func ok (v: U32): U32 =>
  let a = @simd.store #[0, 0, 0, 0] 0 (v, 1, 2, 3)
  let b = step_move a (v + 10)
  let c = step_inplace b (v + 20)
  let rec = { lanes: #[0, 0, 0, 0], tag: 1 }
  let _ = @simd.store rec.lanes 0 (1, 2, 3, 4)
  let g: #[U32] = #[v]
  let frozen = freeze g
  let seed: #[U32] = #[10, 20]
  let access = $ViewAccess { view: @storage.view seed 0 2, count: 0 }
  let checks: #[U32] = #[]
  let (access, checks) = inspect_access access v checks
  let frozen_checks = freeze checks
  return c[0] + c[3] + rec.lanes[2] + frozen[0] + access.view[0] + frozen_checks[0] + frozen_checks[1]
`,
    (guest) => {
      equal(guest.call("ok", 5), 25 + 28 + 3 + 5 + 10 + 5 + 6);
    },
  );

  const rejected: [string, string][] = [
    [
      "@simd.store on borrowed parameter",
      `func touch (xs: #[U32]): U32 =>
  let _ = @simd.store xs 0 (1, 2, 3, 4)
  return xs[0]
#entry func bad (): U32 => return touch #[0, 0, 0, 0]`,
    ],
    [
      "@simd.store on module const",
      `const table: #[U32] = #[1, 2, 3, 4]
#entry func bad (): U32 =>
  let _ = @simd.store table 0 (9, 0, 0, 0)
  return table[0]`,
    ],
    [
      "@simd.store on aliased local",
      `#entry func bad (): U32 =>
  let xs = #[1, 2, 3, 4]
  let alias = xs
  let _ = @simd.store xs 0 (9, 0, 0, 0)
  return alias[0]`,
    ],
    [
      "@simd.store while &xs borrow is live",
      `#entry func bad (): U32 =>
  let xs = #[1, 2, 3, 4]
  let r = &xs
  let _ = @simd.store xs 0 (9, 0, 0, 0)
  return (@storage.load r)[0]`,
    ],
    [
      "@simd.store of nested arrays weakens deep to shell",
      `#entry func bad (): U32 =>
  let grid = #[#[1], #[2], #[3], #[4]]
  let shared = #[9]
  let g2 = @simd.store grid 0 (shared, #[5], #[6], #[7])
  g2[0][0] := 99
  return shared[0]`,
    ],
    [
      "@simd.store overlapping call argument",
      `func pair (a: #[U32]) -> (b: #[U32]): U32 => return a[0] + b[0]
#entry func bad (): U32 =>
  let xs = #[1, 2, 3, 4]
  return pair xs (@simd.store xs 0 (9, 0, 0, 0))`,
    ],
    [
      "@simd.store on outer local captured by closure",
      `#entry func bad (): U32 =>
  let xs = #[1, 2, 3, 4]
  let mutate = func () => do:
    let _ = @simd.store xs 0 (9, 0, 0, 0)
    return 0
  let _ = mutate ()
  return xs[0]`,
    ],
    [
      "@storage.push on borrowed parameter",
      `func sneak (xs: #[U32]): U32 =>
  @storage.push xs 2
  return xs[0]
#entry func bad (): U32 =>
  let items: #[U32] = #[1]
  return sneak items`,
    ],
    [
      "@storage.push on module const",
      `const table: #[U32] = #[1]
#entry func bad (): U32 =>
  @storage.push table 2
  return table[0]`,
    ],
    [
      "@storage.push on aliased local",
      `#entry func bad (): U32 =>
  let items: #[U32] = #[1]
  let alias = items
  @storage.push items 2
  return alias[0] + items[1]`,
    ],
    [
      "@storage.push on local alias of borrowed parameter",
      `func sneak (xs: #[U32]): U32 =>
  let alias = xs
  @storage.push alias 2
  return alias[0]
#entry func bad (): U32 =>
  let items: #[U32] = #[1]
  return sneak items`,
    ],
    [
      "@storage.push on borrowed field beside owned sibling field",
      `func sneak (xs: #[U32]): U32 =>
  let r = { g: xs, other: #[1] }
  @storage.push r.g 2
  return r.g[0] + r.other[0]
#entry func bad (): U32 =>
  let items: #[U32] = #[1]
  return sneak items`,
    ],
    [
      "@storage.push on outer local captured by closure",
      `func run (f: U32 -> U32): U32 => return f 0
#entry func bad (): U32 =>
  let xs: #[U32] = #[1, 2]
  let _ = run (func i => return do:
    @storage.push xs 3
    break xs[0])
  return xs[2]`,
    ],
    [
      "@storage.push on indexed shell array element",
      `#entry func bad (): U32 =>
  let left = #[1]
  let rows = #[left, #[2]]
  @storage.push rows[0] 9
  return left[0]`,
    ],
    [
      "@storage.push on indexed shared array inside owned box",
      `type Box is data = $Box { s: *#[#[U32]] }
func touch (b: own Box): U32 =>
  @storage.push b.s[0] 9
  return b.s[0][0]
#entry func bad (): U32 =>
  return touch ($Box { s: freeze #[#[1]] })`,
    ],
    [
      "@storage.push overlapping mutation inside value expression",
      `#entry func bad (): U32 =>
  let xs = #[1, 2]
  @storage.push xs (do:
    @storage.truncate xs 0
    break 3)
  return xs[0]`,
    ],
    [
      "@storage.truncate on borrowed parameter",
      `func trim (xs: #[U32]): U32 =>
  @storage.truncate xs 0
  return xs.length
#entry func bad (): U32 => return trim #[1, 2]`,
    ],
    [
      "@storage.pop on borrowed parameter",
      `func drop_last (xs: #[U32]): U32 => return @storage.pop xs
#entry func bad (): U32 => return drop_last #[1, 2]`,
    ],
    // Council regression laws (Opus 5.5 + Neon):
    [
      "@simd.store in loop aliased by later keep := xs",
      `#entry func bad (): U32 =>
  let xs = #[0, 0, 0, 0]
  let keep = #[0, 0, 0, 0]
  let seen = 0
  for i in 0..2:
    let _ = @simd.store xs 0 (@u32.add i 10, 0, 0, 0)
    seen := keep[0]
    keep := xs
  return seen`,
    ],
    [
      "@simd.store in loop aliased by later r := &xs",
      `#entry func bad (): U32 =>
  let xs = #[0, 0, 0, 0]
  let seed = #[0, 0, 0, 0]
  let r = &seed
  let seen = 0
  for i in 0..2:
    let _ = @simd.store xs 0 (@u32.add i 10, 0, 0, 0)
    seen := (@storage.load r)[0]
    r := &xs
  return seen`,
    ],
    [
      "@simd.store in loop aliased before continue",
      `#entry func bad (): U32 =>
  let xs = #[0, 0, 0, 0]
  let keep = #[0, 0, 0, 0]
  let seen = 0
  for i in 0..2:
    let _ = @simd.store xs 0 (@u32.add i 10, 0, 0, 0)
    seen := keep[0]
    if i == 0:
      keep := xs
      continue
  return seen`,
    ],
    [
      "@simd.store inside closure overlapping sibling borrowed argument",
      `func call_with (a: #[U32]) -> (f: U32 -> U32): U32 =>
  let before = a[0]
  let _ = f 0
  let after = a[0]
  return before * 100 + after
#entry func bad (): U32 =>
  let xs = #[1, 2, 3, 4]
  return call_with xs (func i => return do:
    let _ = @simd.store xs 0 (9, 0, 0, 0)
    break 0)`,
    ],
    [
      "@simd.store inside closure cannot smuggle shared nested lane past capture restore",
      `func run (f: U32 -> U32): U32 => return f 0
#entry func bad (): U32 =>
  let grid = #[#[1], #[2], #[3], #[4]]
  let shared = #[9]
  let _ = run (func i => return do:
    let _ = @simd.store grid 0 (shared, #[5], #[6], #[7])
    break 0)
  grid[0][0] := 99
  return shared[0]`,
    ],
    [
      "@storage.push in loop aliased by later keep := xs",
      `#entry func bad (): U32 =>
  let xs = #[0]
  let keep = #[0]
  let seen = 0
  for i in 0..2:
    @storage.push xs i
    seen := keep[0]
    keep := xs
  return seen`,
    ],
    [
      "@storage.push rejects aliased record escape",
      `#entry func bad (): U32 =>
  let xs = #[1]
  let box = { g: xs }
  @storage.push xs 2
  return box.g[0]`,
    ],
    [
      "@storage.push rejects aliased two-hop local",
      `#entry func bad (): U32 =>
  let xs = #[1]
  let a = xs
  let b = a
  @storage.push xs 2
  return b[0]`,
    ],
    [
      "@storage.push rejects live &xs borrow",
      `func hide_ref (xs: #[U32]): &(#[U32]) => return &xs
#entry func bad (): U32 =>
  let xs = #[1]
  let r = hide_ref xs
  @storage.push xs 2
  return (@storage.load r)[0]`,
    ],
    [
      "@storage.push rejects aliased polymorphic reader return",
      `func id_poly x => return x
#entry func bad (): U32 =>
  let xs = #[1]
  let alias = #[0]
  alias := id_poly xs
  @storage.push xs 2
  return alias[0]`,
    ],
  ];
  for (const [name, source] of rejected) {
    try {
      await compileExpectedFailure(source + "\n", "aliased_update");
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }

  for (
    const [name, source, code] of [
      [
        "freeze consumes ownership (spent on push)",
        `#entry func bad (): U32 =>
  let xs = #[1, 2]
  let _ = freeze xs
  @storage.push xs 3
  return xs[2]`,
        "spent_value",
      ],
      [
        "freeze on record field consumes that field",
        `#entry func bad (): U32 =>
  let g = #[1, 2]
  let rec = { g: g, tag: 0 }
  let _ = freeze rec.g
  @storage.push rec.g 3
  return rec.g[2]`,
        "spent_value",
      ],
      [
        "freeze on borrowed parameter rejected",
        `func sneak (xs: #[U32]): *#[U32] => return freeze xs
#entry func bad (): U32 =>
  let s = sneak #[1]
  return s[0]`,
        "own_argument",
      ],
      [
        "freeze on aliased local rejected",
        `#entry func bad (): U32 =>
  let xs = #[1]
  let alias = xs
  let s = freeze xs
  return alias[0] + s[0]`,
        "own_argument",
      ],
    ] as [string, string, string][]
  ) {
    try {
      await compileExpectedFailure(source + "\n", code);
    } catch (error) {
      throw new Error(`${name}: ${error}`);
    }
  }
});
