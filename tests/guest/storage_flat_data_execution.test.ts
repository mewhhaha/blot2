import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("source storage admission covers a reached library beyond 128 declarations", async () => {
  const helpers = Array.from({length: 150}, (_, index) => `const part_${index} = func (value: U32): U32 => return value + ${index}`).join("\n");
  const calls = Array.from({length: 150}, (_, index) => `  total := self + part_${index} 1`).join("\n");
  await compileAndRun(`${helpers}
io const sum = func () => return do:
  let anchor: Array U32 = #[]
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
io const lengths = func () => return do:
  let growing: Array U32 = #[10, 20]
  let changing: Array U32 = #[30]
  let pushed = @storage.push growing 40
  let borrowed = &growing[0..2]
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
const bump = func (own access) => return do:
  access.rows[0] := access.rows[0] + 1
  return access
const run_known = func (callback: own {rows: Array U32} -> {rows: Array U32}) -> (access: own {rows: Array U32}) => return callback access
io const inspect = func (present: Bool) => return do:
  let calls: Array U32 = #[]
  let rows: Array {label: U32, item: Maybe (U32, F32)} = #[
    {label: 7, item: if present then $Some (40, 2.0) else $Nothing}
  ]
  let amount = case rows[0].item of
    $Some (value, scale) if (do:
      @storage.push calls 1
      break value > 0) => value + @f32.to_u32 scale
    $Some _ => @panic "unchosen payload"
    $Nothing => 9
  return amount + @storage.length calls
io const generic_update = func (chosen: Bool) => return do:
  let rows: Array U32 = #[0]
  let access = run_known bump {rows}
  let selected = case chosen of
    true => do:
      if access.rows[0] == 1:
        access.rows[0] := 41
      break true
    false => false
  return access.rows[0] + (if selected then 1 else 0)
io const inferred_field = func () => return do:
  let rows: Array (Maybe Span) = #[$Some ($Span {start: 7, count: 11})]
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
io const branch = func (early: Bool) => return do:
  let anchor: Array U32 = #[]
  let rows = if early then (do:
    return 7
  ) else #[40, 2]
  return rows[0] + rows[1]
io const traverse = func (count: U32) => return do:
  let anchor: Array U32 = #[]
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
io const sort_three = func () => return do:
  let anchor: Array U32 = #[]
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
io const match_rebind = func () => return do:
  let anchor: Array U32 = #[]
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

Deno.test("scope and loop frames recover scratch allocated before a transferred result", async () => {
  await compileAndRun(`
const create = func (n: U32) => return do:
  let scratch = #[n, n]
  return #[scratch[0]]
io const repeat = func () => return do:
  let anchor: Array U32 = #[]
  let total = 0
  for index in 0..5000:
    let rows = create index
    total := self + rows[0]
  return total
`, guest => equal(guest.call("repeat", null), 12497500));
});

