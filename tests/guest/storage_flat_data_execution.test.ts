import { compileAndRun, compileExpectedFailure, equal } from "./compile_helpers.ts";

Deno.test("source storage admission covers a reached library beyond 128 declarations", async () => {
  const helpers = Array.from({length: 150}, (_, index) => `const part_${index} = func (value: U32): U32 => return value + ${index}`).join("\n");
  const calls = Array.from({length: 150}, (_, index) => `  total := self + part_${index} 1`).join("\n");
  await compileAndRun(`${helpers}
entry const sum = func () => return do:
  let anchor: GrowArray U32 = #[]
  let total = 0
${calls}
  return total
`, guest => equal(guest.call("sum", null), 11325));
});

Deno.test("capability length accessors preserve captured view length through growth", async () => {
  await compileAndRun(`
import * as array from "std/array"
const bonus: U32 = 7
const sum_pool = func values => return do:
  let total = 0
  for value in values:
    total := self + value
  return total
entry const lengths = func () => return do:
  let growing: GrowArray U32 = #[10, 20]
  let changing: ResizeArray U32 = #[30]
  let borrowed = &growing[0..2]
  let pushed = @storage.push growing 40
  let total = 0
  for value in borrowed:
    total := self + value
  for value in changing:
    total := self + value
  let copied: Array U32 = array.map (func (value: U32): U32 => return value + 1) borrowed
  let found = array.any (func (value: U32): Bool => return value == 40) growing
  return growing.length * 100 + changing.length * 10 + borrowed.length + total + bonus + copied[0] + (if found then 1 else 0) + sum_pool borrowed + sum_pool changing + sum_pool growing
`, guest => equal(guest.call("lengths", null), 521), {stdRoot: new URL("../../std", import.meta.url).pathname});
});

Deno.test("owned flat Maybe rows preserve nested records guards and F32 payloads", async () => {
  await compileAndRun(`
type Span is data = $Span {start: U32, count: U32}
const read_optional = func rows -> (id: U32) => return if id < rows.length then rows.at id else $Nothing
const bump = func access => return do:
  access.rows[0] := access.rows[0] + 1
const run_known = func callback -> access => return callback access
const accept = func (calls: GrowArray U32) => return func (value: U32) => return do:
  let wrote = @storage.write (&calls[0]) (calls[0] + 1)
  return value > 0
entry const inspect = func (present: Bool) => return do:
  let calls: GrowArray U32 = #[0]
  let rows: Array {label: U32, item: Maybe (U32, F32)} = #[
    {label: 7, item: if present then $Some (40, 2.0) else $Nothing}
  ]
  let amount = case rows[0].item of
    $Some (value, scale) if accept calls value => value + @f32.to_u32 scale
    $Some _ => @panic "unchosen payload"
    $Nothing => 9
  return amount + calls[0]
entry const generic_update = func (chosen: Bool) => return do:
  let rows: Array U32 = #[0]
  let access = {rows}
  run_known bump access
  let selected = case chosen of
    true => do:
      if rows[0] == 1:
        rows[0] := 41
      break true
    false => false
  return rows[0] + (if selected then 1 else 0)
entry const inferred_field = func () => return do:
  let rows: ResizeArray (Maybe Span) = #[$Some ($Span {start: 7, count: 11})]
  let $Some found = read_optional rows 0 else:
    return 0
  return found.start + found.count
`, guest => {
    equal(guest.call("inspect", true), 43);
    equal(guest.call("inspect", false), 9);
    equal(guest.call("inferred_field", null), 18);
    equal(guest.call("generic_update", true), 42);
    equal(guest.call("generic_update", false), 1);
  });
});

Deno.test("normal branch joins array results while exits and aggregate carries retain meaning", async () => {
  await compileAndRun(`
type Change is data = $Plus U32 | $Set U32 | $Scale U32 | $Skip
entry const branch = func (early: Bool) => return do:
  let anchor: GrowArray U32 = #[]
  let rows = if early then (do:
    return 7
  ) else #[40, 2]
  return rows[0] + rows[1]
entry const traverse = func (count: U32) => return do:
  let anchor: GrowArray U32 = #[]
  let state = (1, 2)
  for index in 0..count:
    let (left, right) = state
    state := (right, left)
    if index == 1:
      continue
  let (left, right) = state
  let total = 0
  let rows = #[{amount: left}, {amount: right}]
  for row in rows:
    total := self + row.amount
  return left * 10 + total
entry const sort_three = func () => return do:
  let anchor: GrowArray U32 = #[]
  let rows: Array U32 = #[3, 1, 2]
  for i in 1..3:
    let j = i
    for 0..3:
      if j == 0 or rows[j - 1] <= rows[j]:
        break
      let saved = rows[j]
      rows[j] := rows[j - 1]
      rows[j - 1] := saved
      j := self - 1
  return rows[0] * 100 + rows[1] * 10 + rows[2]
entry const match_rebind = func () => return do:
  let anchor: GrowArray U32 = #[]
  let rows: Array U32 = #[0]
  let total = 0
  for change in #[$Plus 3, $Skip, $Set 7, $Scale 2]:
    case change of
      $Plus value => do:
        total := self + value
        rows[0] := total
      $Set value => do:
        total := value
        rows[0] := total
      $Scale value => do:
        total := self * value
        rows[0] := total
      $Skip => ()
  return total * 100 + rows[0]
`, guest => {
    equal(guest.call("branch", true), 7);
    equal(guest.call("branch", false), 42);
    equal(guest.call("traverse", 2), 13);
    equal(guest.call("traverse", 3), 23);
    equal(guest.call("sort_three", null), 123);
    equal(guest.call("match_rebind", null), 1414);
  });
});

Deno.test("flat List copies and cursor snapshots survive writes and concatenation", async () => {
  await compileAndRun(`
entry const snapshots = func () => return do:
  let source: Array U32 = #[40, 2]
  let saved: List U32 = @list.from_array source
  let cursor = @list.cursor saved
  let advanced = @cursor.advance cursor
  let wrote = @storage.write (&source[0]) 7
  let extended = @list.append saved 9
  let joined = @list.concat extended [1]
  let copied: Array U32 = @array.from_list joined
  let total = 0
  for value in saved:
    total := self + value
  return @cursor.value cursor + @cursor.value advanced + copied[2] + copied[3] + total + source[0]
`, guest => equal(guest.call("snapshots", null), 101));
});

Deno.test("scope and loop frames recover scratch allocated before a transferred result", async () => {
  await compileAndRun(`
const create = func (n: U32) => return do:
  let scratch = #[n, n]
  return #[scratch[0]]
entry const repeat = func () => return do:
  let anchor: GrowArray U32 = #[]
  let total = 0
  for index in 0..5000:
    let rows = create index
    total := self + rows[0]
  return total
`, guest => equal(guest.call("repeat", null), 12497500));
});

Deno.test("hidden ADT borrows and loop-carried iteration borrows cannot escape owners", async () => {
  await compileExpectedFailure(`
type Held is data = $Held &U32 | $Empty
const bad = func () => return do:
  let rows: GrowArray U32 = #[42]
  return $Held (&rows[0])
entry const escape = func () => return case bad () of
  $Held value => @storage.load value
  $Empty => 0
`, "storage_escape");
  await compileExpectedFailure(`
entry const escape = func () => return do:
  let outer: GrowArray U32 = #[42]
  let held = &outer[0]
  for index in 0..2:
    let local: GrowArray U32 = #[index]
    held := &local[0]
  return @storage.load held
`, "storage_escape");
  await compileExpectedFailure(`
entry const replace = func () => return do:
  let anchor: GrowArray U32 = #[]
  let rows: Array U32 = #[42]
  for index in 0..2:
    rows := #[index]
  return rows[0]
`, "storage_escape");
});
