import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("owned selected call cycles reject direct mutual and known callback recursion", async () => {
  const cases = [
    `const recurse = func (value: U32): U32 => return recurse value`,
    `const recurse = func (value: U32): U32 => return other value
const other = func (value: U32): U32 => return recurse value`,
    `const invoke = func callback -> value => return callback value
const recurse = func (value: U32): U32 => return invoke recurse value`,
  ];
  for (const source of cases) {
    await compileExpectedFailure(
      `${source}
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  return recurse rows[0]
`,
      "storage_unsupported",
      "Recursive selected calls are not supported by the owned-storage backend",
    );
  }
});

Deno.test("owned finite nested callbacks distinguish selected callback identities", async () => {
  await compileAndRun(
    `
const invoke = func callback -> value => return callback value
const successor = func (value: U32) => return @u32.add value 1
const outer = func (value: U32) => return invoke successor value
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  return invoke outer rows[0]
`,
    (guest) => {
      for (const input of [0, 1, 40]) {
        assert.equal(guest.call("answer", input), input + 1);
      }
    },
  );
});

Deno.test("owned partial and oversaturated applications do not become selected cycles", async () => {
  await compileAndRun(
    `
const successor = func (value: U32) => return @u32.add value 1
const choose = func callback -> (left: U32) -> (right: U32) => return callback (@u32.add left right)
const shifted = func (base: U32) => return do:
  let saved = base
  return func (value: U32) => return @u32.add saved value
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  let partial = choose successor rows[0]
  return @u32.add (shifted rows[0] 2) (@u32.add (partial 1) (partial 2))
`,
    (guest) => {
      for (const input of [0, 1, 40]) {
        assert.equal(guest.call("answer", input), input * 3 + 7);
      }
    },
  );
});

Deno.test("owned source operators honor associated declarations without changing explicit primitives", async () => {
  await compileAndRun(
    `
infixl 60 (+) = add
const add = func left -> right => return @type.call "add" left right
type Number is data = $Number U32
const Number.add = func (left: Number) -> (right: U32) => return do:
  let $Number value = left
  return @u32.sub value right
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  return @u32.add (($Number rows[0]) + 2) 1
`,
    (guest) => assert.equal(guest.call("answer", 43), 42),
    { prelude: "none" },
  );
});

Deno.test("reusable scalar results retain their semantic type through generic callers", async () => {
  await compileAndRun(
    `
const successor = func (value: U32) => return @u32.add value 1
const use_result = func callback -> value => return callback value > 2
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  let captured = func value => return @u32.add value 1
  return use_result successor rows[0] and use_result captured rows[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), true);
      assert.equal(guest.call("answer", 1), false);
    },
  );
});

Deno.test("owned calls select associated declarations from checked operands and destinations", async () => {
  await compileAndRun(
    `
type Left is data = $Left U32
type Right is data = $Right U32
type Pair is data = $Pair { x: F32, y: F32 }
const Left.add = func (left: Left) -> (right: U32) => return right
const Right.add = func (left: Left) -> (right: Right) => return do:
  let $Left first = left
  let $Right second = right
  return first - second
const Pair.add = func (left: Pair) -> (right: Pair): Pair => return
  $Pair { x: left.x + right.x, y: left.y + right.y }
const combine = func left -> right => return left + right
const convert = func value => return from value
entry const run = func (input: U32): F32 => return do:
  let calls: GrowArray U32 = #[0]
  let difference = combine (do:
    calls[0] := calls[0] + 1
    break $Left input
  ) (do:
    calls[0] := calls[0] + 10
    break $Right 2
  )
  let point = combine ($Pair { x: convert difference, y: 2.0 }) ($Pair { x: 1.0, y: 3.0 })
  let count: F32 = convert calls[0]
  return point.x + point.y + count
`,
    (guest) => {
      assert.equal(guest.call("run", 44), 59);
      assert.equal(guest.call("run", 3), 18);
    },
  );
});

Deno.test("owned call destinations and scalar captures survive repeated invocations", async () => {
  await compileAndRun(
    `
const row = func (value: U32) => return #[value, 7]
const number = func (value: U32) => return value + 1
const captured = func (base: U32) => return do:
  let add = func (value: U32) => return base + value
  break add 2 + add 3
entry const answer = func (input: U32) => return do:
  let mode: GrowArray U32 = #[]
  let first = row input
  let second = row (input + 1)
  break number first[0] + number second[0] + first[1] + captured input
`,
    (guest) => {
      for (const value of [0, 10, 40, 1, 0]) {
        assert.equal(guest.call("answer", value), 4 * value + 15);
      }
    },
  );
});

Deno.test("generic array traversal retains cursor identity and known stage callbacks", async () => {
  await compileAndRun(
    `
const run = func stages -> access -> events => return do:
  for event in events:
    stages.update access event
const update = func access -> event => return do:
  let rows: GrowArray U32 = access.rows
  rows[0] := rows[0] + event
const policy = {update}
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[input]
  let access = {rows}
  run policy access #[1, 2, 3]
  let empty: Array U32 = #[]
  run policy access empty
  return rows[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", 10), 16);
      assert.equal(guest.call("answer", 0), 6);
    },
  );
});

Deno.test("inline call results preserve record fields and reclaim caller scratch", async () => {
  await compileAndRun(
    `
type Pair is data = $Pair { left: U32, right: F32 }
const calculate = func (input: Pair) => return do:
  if @u32.eq input.left 0:
    return $Pair { left: 7, right: input.right }
  return $Pair { left: @u32.add input.left 1, right: @f32.add input.right 0.5 }
const adjust = func (input: Pair) => return calculate input
entry const answer = func (input: U32) => return do:
  let rows: GrowArray U32 = #[0]
  for index in 0 .. input:
    let result = adjust ($Pair { left: index, right: 1.5 })
    rows[0] := @u32.add rows[0] result.left
  let last = adjust ($Pair { left: 1, right: 1.5 })
  return @u32.add rows[0] (F32.to_u32 last.right)
`,
    (guest) => {
      assert.equal(guest.call("answer", 0), 2);
      assert.equal(guest.call("answer", 3), 14);
      assert.equal(guest.call("answer", 100000), 705082712);
      assert.equal(guest.call("answer", 3), 14);
    },
  );
});

Deno.test("reusable readers keep caller owners epochs and view offsets", async () => {
  await compileAndRun(
    `
const read = func (rows: &[U32]) -> (index: U32) => return @storage.read rows index
const linked = func (value: ^U32) => return @storage.load value
const owned = func (rows: ResizeArray U32) => return @storage.read rows 0
entry const answer = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[input, 9]
  let other: ResizeArray U32 = #[7, 11]
  let view = &rows[1..2]
  let alternate = &other[0..1]
  let first = read view 0
  let second = read alternate 0
  rows[1] := 12
  let last = read view 0
  let links: GrowArray U32 = #[12]
  let link = @storage.link links 0
  return @u32.add (owned rows) (@u32.add first (@u32.add second (@u32.add last (linked link))))
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 42);
      assert.equal(guest.call("answer", 0), 40);
      assert.equal(guest.call("answer", 7), 47);
    },
  );
});

Deno.test("partially applied global constructors retain each remaining argument type", async () => {
  await compileAndRun(
    `
type Rect is data = $Rect {x: U32}
type Node is data = $Node {role: U32, id: U32, parent: U32, name: &[U32], rect: Rect}
const node = func (role: U32) -> (id: U32) -> (parent: U32) -> (name: &[U32]) -> (rect: Rect) => return
  $Node {role, id, parent, name, rect}
const group = node 7
entry const answer = func (input: U32) => return do:
  let names: GrowArray U32 = #[input]
  let made = group 2 3 (&names[0..1]) ($Rect {x: 5})
  return made.role + made.id + made.parent + made.name[0] + made.rect.x
`,
    (guest) => {
      assert.equal(guest.call("answer", 25), 42);
      assert.equal(guest.call("answer", 0), 17);
    },
  );
});

Deno.test("generic dependent readers establish empty owner element types before emission", async () => {
  await compileAndRun(
    `
import * as array from "std/array"
type Reader is data = $Reader { value: F32 }
const Reader.length = func (reader: Reader): U32 => return 3
const Reader.at = func (reader: Reader) -> (index: U32): F32 => return reader.value + U32.to_f32 index
entry const answer = func (input: U32): F32 => return do:
  let values: GrowArray U32 = #[input, 2, 9]
  let selected = array.filter (func value => return value > 3) (&values[0..values.length])
  let floats = array.filter (func value => return value > 1.5) ($Reader { value: 1.0 })
  let empty = array.filter (func value => return value > 10) selected
  let positions = array.generate 3 identity
  let copied = array.map identity floats
  return U32.to_f32 (selected.length + empty.length + positions[2] - 2) + copied[0] + copied[1]
`,
    (guest) => {
      assert.equal(guest.call("answer", 5), 7);
      assert.equal(guest.call("answer", 1), 6);
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("owned selected bodies have separate bounded syntax and call depths", async () => {
  // Every wrapper has shallow syntax, but cumulative AST expansion formerly
  // exceeded 128 before reaching this finite, nonrecursive leaf.
  const chain = Array.from(
    { length: 44 },
    (_, index) =>
      `const call${index} = func (rows: &[U32]) => return call${
        index + 1
      } rows`,
  ).join("\n");
  await compileAndRun(
    `${chain}
const call44 = func (rows: &[U32]) => return @storage.read rows 0
entry const answer = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[input]
  return call0 (&rows[0..1])
`,
    (guest) => assert.equal(guest.call("answer", 42), 42),
  );
  const tooMany = Array.from(
    { length: 130 },
    (_, index) =>
      `const call${index} = func (rows: &[U32]) => return call${
        index + 1
      } rows`,
  ).join("\n");
  await compileExpectedFailure(
    `${tooMany}
const call130 = func (rows: &[U32]) => return @storage.read rows 0
entry const answer = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[input]
  return call0 (&rows[0..1])
`,
    "storage_unsupported",
    "Selected calls exceeded their active call bound",
  );
  // Deep syntax is rejected by the parser before backend expansion; separating
  // selected call depth does not remove this existing syntax guard.
  let nested = "rows[0]";
  for (let index = 0; index < 140; index++) nested = `@u32.add 0 (${nested})`;
  await compileExpectedFailure(
    `entry const answer = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[input]
  return ${nested}
`,
    "nesting_limit",
  );
});

Deno.test("owned descriptor callbacks keep runtime owners offsets and fresh contents", async () => {
  await compileAndRun(
    `
const reading = func (rows: &[U32]) -> (index: U32) => return do:
  let callback = func (at: U32) => return @storage.read rows at
  return callback index
entry const answer = func (input: U32) => return do:
  let first: ResizeArray U32 = #[input, 9]
  let second: ResizeArray U32 = #[7, 11]
  let view = &first[1..2]
  let before = reading view 0
  let other = reading (&second[0..1]) 0
  first[1] := 12
  let after = reading view 0
  return @u32.add input (@u32.add before (@u32.add other after))
`,
    (guest) => {
      assert.equal(guest.call("answer", 14), 42);
      assert.equal(guest.call("answer", 0), 28);
    },
  );
  await compileAndRun(
    `
const reading = func (rows: &[U32]) -> (index: U32) => return do:
  let callback = func (at: U32) => return @storage.read rows at
  return callback index
entry const answer = func (input: U32) => return do:
  let rows: ResizeArray U32 = #[7]
  return reading (&rows[0..1]) input
`,
    (guest) => {
      assert.equal(guest.call("answer", 0), 7);
      assert.throws(() => guest.call("answer", 1), WebAssembly.RuntimeError);
      assert.equal(guest.call("answer", 0), 7);
    },
  );
});

Deno.test("associated function results retain selected latent effect rows", async () => {
  await compileExpectedFailure(
    `
entry const answer = func (input: F32): U32 => return do:
  let rows: ResizeArray F32 = #[input, 10.0]
  let wrong: F32 -> U32 = lerp rows[0] rows[1]
  return wrong 0.5
`,
    "type_mismatch",
  );
  await compileAndRun(
    `
entry const answer = func (input: F32): F32 => return do:
  let rows: ResizeArray F32 = #[input, 10.0]
  let partial = lerp rows[0] rows[1]
  return partial 0.5
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 6);
      assert.equal(guest.call("answer", 10), 10);
    },
  );
  await compileAndRun(
    `
import { Vec3 } from "std/vector"
entry const answer = func (input: F32): F32 => return do:
  let rows: ResizeArray F32 = #[input]
  let left = $Vec3 {x: rows[0], y: 2.0, z: 4.0}
  let right = $Vec3 {x: 10.0, y: 6.0, z: 8.0}
  let value = lerp left right 0.5
  return value.x + value.y + value.z
`,
    (guest) => assert.equal(guest.call("answer", 2), 16),
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});

Deno.test("captured callbacks keep each checked nominal result instance", async () => {
  await compileAndRun(
    `
type Box is data = $Box U32
const mapped = func transform -> candidate => return Maybe.map transform candidate
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let first = mapped (func value => return $Some (value + rows[0])) ($Some 2)
  let second = mapped (func value => return $Box (value + rows[0])) ($Some 3)
  let $Some ($Some a) = first else:
    return 0
  let $Some ($Box b) = second else:
    return 0
  return a + b
`,
    (guest) => {
      assert.equal(guest.call("answer", 10), 25);
      assert.equal(guest.call("answer", 0), 5);
    },
  );
  await compileExpectedFailure(
    `
type First is data = $First U32
type Second is data = $Second U32
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let callback: U32 -> First = func value => return $Second (value + rows[0])
  let $First value = callback 2
  return value
`,
    "type_mismatch",
  );
});

Deno.test("nested active Maybe maps isolate captured actual type environments", async () => {
  await compileAndRun(
    `
type Box is data = $Box U32
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let result = Maybe.map (func (outer: U32) => return do:
    let previous = Maybe.map (func value => return $Some (value + rows[0])) ($Some outer)
    return Maybe.map (func candidate => return do:
      let $Some value = candidate else:
        return $Box 0
      return $Box (value + 3)) previous) ($Some 2)
  let $Some ($Some ($Box value)) = result else:
    return 0
  return value
`,
    (guest) => {
      assert.equal(guest.call("answer", 10), 15);
      assert.equal(guest.call("answer", 0), 5);
    },
  );
});

Deno.test("selected generic numeric helpers preserve arithmetic and overload boundaries", async () => {
  await compileAndRun(
    `
const difference = func left -> right => return if left > right then left - right else right - left
const choose = func (hash: U32) -> (x: F32) -> (y: F32): F32 => return do:
  let value = if (hash & 1) == 0 then x else 0.0 - x
  return value + (if (hash & 2) == 0 then y else 0.0 - y)
type Number is data = $Number U32
const Number.add = func (left: Number) -> (right: U32) => return do:
  let $Number value = left
  return value - right
entry const answer = func (input: U32): F32 => return do:
  let rows: ResizeArray U32 = #[input, 2]
  let count = difference rows[0] rows[1]
  let first = choose rows[0] 2.0 4.0
  let second = choose rows[1] 3.0 5.0
  let custom = ($Number 10) + 3
  return U32.to_f32 (count + custom) + first + second
`,
    (guest) => {
      assert.equal(guest.call("answer", 4), 13);
      assert.equal(guest.call("answer", 1), 8);
    },
  );
});

Deno.test("selected inline data helpers preserve nominal fields and result independence", async () => {
  await compileAndRun(
    `
type Point is data = $Point {x: F32, y: F32}
const adjust = func (point: Point) -> (amount: F32): Point => return
  $Point {x: point.x + amount, y: point.y - amount}
const finish = func (point: Point) -> (amount: F32): Point => return do:
  let next = adjust point amount
  return $Point {x: next.x * 2.0, y: next.y + 1.0}
entry const answer = func (input: F32): F32 => return do:
  let rows: ResizeArray F32 = #[input]
  let first = finish ($Point {x: rows[0], y: 10.0}) 2.0
  let second = finish ($Point {x: 3.0, y: 8.0}) 1.0
  return first.x + first.y + second.x + second.y
`,
    (guest) => {
      assert.equal(guest.call("answer", 1), 31);
      assert.equal(guest.call("answer", 5), 39);
    },
  );
});

Deno.test("readonly descriptor records preserve nested owners and independent results", async () => {
  await compileAndRun(
    `
type Bundle is data = $Bundle {rows: &[U32], bias: U32}
const folded = func (input: Bundle) => return do:
  let total = input.bias
  for index in 0..input.rows.length:
    total := self + input.rows[index]
  return {total, count: input.rows.length}
entry const answer = func (input: U32): U32 => return do:
  let first: ResizeArray U32 = #[99, input, 7]
  let second: ResizeArray U32 = #[11]
  let older = folded ($Bundle {rows: &first[1..3], bias: 1})
  let other = folded ($Bundle {rows: &second[0..1], bias: 2})
  first[1] := 5
  let fresh = folded ($Bundle {rows: &first[1..3], bias: 1})
  return older.total + other.total + fresh.total + older.count
`,
    (guest) => {
      assert.equal(guest.call("answer", 6), 42);
      assert.equal(guest.call("answer", 0), 36);
    },
  );
  await compileAndRun(
    `
const read = func (rows: &[Maybe U32]): U32 => return case rows[0] of
  $Some value => value
  $Nothing => 3
entry const answer = func (input: U32): U32 => return do:
  let first: ResizeArray (Maybe U32) = #[$Some input]
  let second: ResizeArray (Maybe U32) = #[$Nothing]
  return read (&first[0..1]) + read (&second[0..1])
`,
    (guest) => {
      assert.equal(guest.call("answer", 39), 42);
      assert.equal(guest.call("answer", 4), 7);
    },
  );
});

Deno.test("static readonly callbacks preserve captures targets and mutable fallback", async () => {
  await compileAndRun(
    `
const folded = func transform -> (rows: &[U32]): U32 => return do:
  let total = 0
  for value in rows:
    total := self + transform value
  return total
entry const answer = func (input: U32): U32 => return do:
  let first: ResizeArray U32 = #[input, 2]
  let second: ResizeArray U32 = #[3]
  let bias: ResizeArray U32 = #[7]
  let captured = &bias[0..1]
  let add = func (value: U32): U32 => return value + captured[0]
  let subtract = func (value: U32): U32 => return value - 1
  let a = folded add (&first[0..2])
  let b = folded add (&second[0..1])
  let c = folded subtract (&first[0..2])
  bias[0] := 9
  let d = folded add (&second[0..1])
  return a + b + c + d
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 42);
      assert.equal(guest.call("answer", 0), 38);
    },
  );
  await compileAndRun(
    `
const apply_callback = func callback -> (value: U32): U32 => return callback value
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[1]
  let change = func (value: U32): U32 => return do:
    rows[0] := rows[0] + value
    return rows[0]
  let first = apply_callback change input
  let second = apply_callback change 2
  return first + second + rows[0]
`,
    (guest) => assert.equal(guest.call("answer", 3), 16),
  );
});

Deno.test("returned reader aliases remap owners variants and captured view bounds", async () => {
  await compileAndRun(
    `
type Pick is data = $First | $Second
type Buffer is data = $Buffer {rows: ResizeArray U32, label: U32}
type Pair is data = $Pair {first: Buffer, second: Buffer}
const choose = func (pair: Pair) -> (pick: Pick): Buffer => return case pick of
  $First => pair.first
  $Second => pair.second
const window = func (rows: &[U32]) -> (start: U32) -> (end: U32) => return &rows[start..end]
entry const answer = func (input: U32): U32 => return do:
  let first: ResizeArray U32 = #[input, 2]
  let second: ResizeArray U32 = #[3, 4]
  let third: ResizeArray U32 = #[5, 6]
  let pair = $Pair {first: $Buffer {rows: first, label: 11}, second: $Buffer {rows: second, label: 22}}
  let a = choose pair $First
  let b = choose pair $Second
  let c = choose ($Pair {first: $Buffer {rows: third, label: 33}, second: $Buffer {rows: first, label: 44}}) $First
  let saved = a.rows[0]
  a.rows[0] := 7
  let view = window (&a.rows[0..2]) 1 2
  a.rows[1] := 9
  return saved + a.rows[0] + b.rows[0] + c.rows[0] + view[0] + a.label + b.label + c.label
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 92);
      assert.equal(guest.call("answer", 10), 100);
    },
  );
  await compileAndRun(
    `
const window = func (rows: &[U32]) -> (end: U32) => return &rows[1..end]
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[7, 11]
  let returned = window (&rows[0..2]) input
  return returned[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 11);
      assert.throws(() => guest.call("answer", 3), WebAssembly.RuntimeError);
      assert.equal(guest.call("answer", 2), 11);
    },
  );
  await compileAndRun(
    `
const copied = func (rows: ResizeArray U32) => return @storage.copy rows
entry const answer = func (input: U32): U32 => return do:
  let original: ResizeArray U32 = #[input]
  let independent = copied original
  independent[0] := 9
  return original[0] + independent[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", 3), 12);
      assert.equal(guest.call("answer", 7), 16);
    },
  );
});

Deno.test("returned optional views preserve impossible and dynamic borrow alternatives", async () => {
  await compileAndRun(
    `
const absent = func (rows: &[U32]): Maybe (&[U32]) => return $Nothing
const maybe = func (rows: &[U32]) -> (present: Bool): Maybe (&[U32]) => return
  if present then $Some rows else $Nothing
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input, 7]
  let empty = absent (&rows[0..2])
  let first = maybe (&rows[1..2]) (input > 0)
  let second = maybe (&rows[0..1]) (input == 0)
  let a = case empty of
    $Nothing => 1
    $Some view => view[0]
  let b = case first of
    $Nothing => 2
    $Some view => view[0]
  let c = case second of
    $Nothing => 3
    $Some view => view[0]
  return a + b + c
`,
    (guest) => {
      assert.equal(guest.call("answer", 9), 11);
      assert.equal(guest.call("answer", 0), 3);
    },
  );
});

Deno.test("Unit writers preserve callback aliases growth views and ordered updates", async () => {
  await compileAndRun(
    `
const execute = func callback -> (rows: ResizeArray U32) -> (amount: U32): Unit => return do:
  callback amount
  rows[0] := rows[0] + 1
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let other: ResizeArray U32 = #[10]
  let view = &rows[0..1]
  let grow = func (amount: U32): Unit => return do:
    rows[0] := rows[0] + amount
    @storage.push rows amount
  execute grow rows 2
  execute grow other 3
  execute grow rows 1
  return rows[0] + other[0] + rows.length + view[0]
`,
    (guest) => {
      assert.equal(guest.call("answer", 5), 41);
      assert.equal(guest.call("answer", 0), 31);
    },
  );
  await compileAndRun(
    `
type Stage is data = $Cold | $Hot U32
const publish = func (rows: ResizeArray Stage) -> (value: U32): Unit => return
  @storage.write (@storage.at rows 0) ($Hot value)
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray Stage = #[$Cold]
  let total = 0
  for index in 0..3:
    publish rows (input + index)
    let value = case rows[0] of
      $Cold => 0
      $Hot value => value
    total := self + value
  return total
`,
    (guest) => {
      assert.equal(guest.call("answer", 3), 12);
      assert.equal(guest.call("answer", 0), 3);
    },
  );
  await compileExpectedFailure(
    `
const shrink = func (rows: ResizeArray U32): Unit => return @storage.truncate rows 0
entry const answer = func (input: U32): U32 => return do:
  let rows: ResizeArray U32 = #[input]
  let view = &rows[0..1]
  shrink rows
  return view[0]
`,
    "storage_borrow_conflict",
  );
});

Deno.test("selected pure reference aliases preserve numeric conversion boundaries", async () => {
  await compileAndRun(
    `
const round_down = floor
const again = round_down
const cell = func (value: F32): U32 => return do:
  let rounded = again value
  return if rounded >= 0.0 then F32.to_u32 rounded else 0 - F32.to_u32 (0.0 - rounded)
entry const answer = func (input: F32): U32 => return do:
  let rows: ResizeArray F32 = #[input, 1.25]
  return cell rows[0] + cell rows[1]
`,
    (guest) => {
      assert.equal(guest.call("answer", 3.9), 4);
      assert.equal(guest.call("answer", -2.3), 4294967294);
      assert.equal(guest.call("answer", 0), 1);
    },
  );
});

Deno.test("selected associated partials preserve nested descriptor interpolation", async () => {
  await compileAndRun(
    `
type Grid is data = $Grid {values: &[F32]}
const sample = func (grid: Grid) -> (x: F32) -> (y: F32): F32 => return do:
  let gx = clamp 0.0 1.0 x
  let gy = clamp 0.0 1.0 y
  return lerp (lerp grid.values[0] grid.values[1] gx) (lerp grid.values[2] grid.values[3] gx) gy
entry const answer = func (input: F32): F32 => return do:
  let values: ResizeArray F32 = #[input, 2.0, 4.0, 8.0]
  return sample ($Grid {values: &values[0..4]}) 0.25 0.5
`,
    (guest) => {
      assert.equal(guest.call("answer", 2), 3.5);
      assert.equal(guest.call("answer", 6), 5);
    },
  );
});
