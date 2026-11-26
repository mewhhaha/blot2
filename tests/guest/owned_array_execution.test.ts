import { compileAndRun, equal } from "./compile_helpers.ts";
Deno.test("exclusive fresh arrays update through nested loop carries", async () => {
  await compileAndRun(
    `
const fill = func count => return func value => return @array.fill count value
io const build = func (count: U32) : Array U32 => return do:
  let values = fill (@u32.mul count 2) 0
  for outer in 0 .. count:
    for inner in 0 .. 2:
      values[@u32.add (@u32.mul outer 2) inner] := outer
  break values
io const floating = func (count: U32) : Array F32 => return do:
  let values = @array.generate count (func index => return @u32.to_f32 index)
  for index in 0 .. count:
    values[index] := @f32.add self 0.5
  break values
`,
    (guest) => {
      for (const count of [0, 1, 32, 20020]) {
        const values = guest.call("build", count) as Uint32Array;
        equal(values.length, count * 2);
        for (let index = 0; index < values.length; index++) {
          equal(
            values[index],
            Math.floor(index / 2),
          );
        }
      }
      const values = guest.call("floating", 1000) as Float32Array;
      for (let index = 0; index < values.length; index++) {
        equal(
          values[index],
          index + 0.5,
        );
      }
    },
  );
});
// Unique owners update in place with `:=`; explicit copies preserve prior
// snapshots and `own` parameters transfer ownership (tasks/MEMORY_MODEL.md).
Deno.test("owned array updates preserve explicit copies, parameters, state, and nested rows", async () => {
  await compileAndRun(
    `
type Cell value is data = $Cell value
const stored = #[1, 2]
const read = func values => return values[1]
const delay = func (value: Array U32) => return func () => return value[1]
io const copy_snapshot = func () => return do:
  let values = #[1, 2]
  let before = values.copy
  values[1] := 9
  break @u32.add before[1] values[1]
io const callback = func () => return do:
  let values = #[1, 2]
  let before = values.copy
  let read_before = func () => return before[1]
  values[1] := 9
  break @u32.add (read_before ()) values[1]
io const suspended = func () => return do:
  let values = #[1, 2]
  let before = delay values.copy
  values[1] := 9
  break @u32.add (before ()) values[1]
io const parameter = func (values: own Array U32) => return do:
  values[1] := 9
  break values
io const global_copy = func () => return do:
  let values = stored.copy
  values[1] := 9
  break @u32.add stored[1] values[1]
io const retained = func () => return do:
  let values = #[1, 2]
  let state = $Cell values.copy
  values[1] := 9
  let ($Cell before, _) = @state.run state (func () => return ())
  break @u32.add before[1] values[1]
io const calls = func () => return do:
  let values = #[1, 2]
  let before = read values
  values[1] := 9
  break @u32.add before values[1]
io const nested = func () => return do:
  let values = #[#[1], #[1]]
  values[0][0] := 9
  break @u32.add values[0][0] values[1][0]
`,
    (guest) => {
      for (
        const name of [
          "copy_snapshot",
          "callback",
          "suspended",
          "global_copy",
          "retained",
          "calls",
        ]
      ) for (let i = 0; i < 4; i++) equal(guest.call(name, null), 11);
      equal(guest.call("nested", null), 10);
      const values = new Uint32Array([1, 2]);
      equal((guest.call("parameter", values) as Uint32Array)[1], 9);
      equal(values[1], 2);
    },
  );
});

Deno.test("read-only callees and dropped generators read an array updated in place", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
const get1 = func index => return func values => return values[index]
const total = func (values: Array F32) => return do:
  let sum = 0.0
  for value in values:
    sum := sum + value
  break sum
const matched = func (values: Array F32) -> (index: U32) => return case true of
  true => values[index]
  false => 0.0
io const inlined = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  for i in 0..n:
    let x = get1 i values
    values[i] := x * 0.5 + 0.25
  break values[n - 1]
io const called = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  for i in 0..n:
    values[i] := total values / @u32.to_f32 n + 1.0
  break values[n - 1]
const double_values = func (n: U32) -> (values: Array F32) => return @array.generate n (func i => return values[i] * 2.0)
io const generated = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  let doubled = double_values n values
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  break values[n - 1]
io const mapped = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  let doubled = array.map (func value => return value * 2.0) values
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  break values[n - 1]
io const local = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  let read = func (xs: Array F32) -> (index: U32) => return xs[index]
  for i in 0..n:
    let x = read values i
    values[i] := x + 1.0
  break values[n - 1]
io const match_read = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  for i in 0..n:
    let x = matched values i
    values[i] := x + 1.0
  break values[n - 1]
`,
    (guest) => {
      const called = (n: number) => {
        const values = new Float32Array(n).fill(1);
        for (let i = 0; i < n; i++) {
          const sum = values.reduce((sum, value) => Math.fround(sum + value), 0);
          values[i] = Math.fround(Math.fround(sum / n) + 1);
        }
        return values[n - 1];
      };
      for (const n of [8, 64, 512]) {
        const cases: [string, number][] = [
          ["inlined", (n - 1) * 0.5 + 0.25],
          ["called", called(n)],
          ["generated", 3 * (n - 1)],
          ["mapped", 3 * (n - 1)],
          ["local", 2],
          ["match_read", 2],
        ];
        for (const [name, expected] of cases) {
          equal(guest.call(name, n), expected);
        }
      }
    },
  );
});

// Copies returned, stored, paired or captured from an array keep their snapshot
// across later updates; `@array.set` and `@array.generate` produce new arrays.
Deno.test("explicit copies stay independent across borrowed helpers and updates", async () => {
  await compileAndRun(
    `
type Cell value is data = $Cell value
const pass = func values => return values
const wrap = func values => return $Cell values
const pair = func values => return (values, 1)
const first_elem = func (values: Array (Array U32)) => return values[0][0]
const reader = func values => return func index => return values[index]
const left = func a => return func b => return a[0] + b[0]
io const returned = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let before = pass values.copy
    values[i] := 9
    sum := sum + before[i] + values[i]
  break sum
io const stored = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let $Cell before = wrap values.copy
    values[i] := 9
    sum := sum + before[i] + values[i]
  break sum
io const paired = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let (before, _) = pair values.copy
    values[i] := 9
    sum := sum + before[i] + values[i]
  break sum
io const captured = func (n: U32) => return do:
  let values = @array.fill n 1
  let snapshot = values.copy
  let read = reader snapshot
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + read i + values[i]
  break sum
const copy_values = func (n: U32) -> (values: Array U32) => return @array.generate n (func index => return values[index])
io const kept = func (n: U32) => return do:
  let values = @array.fill n 1
  let copied = copy_values n values
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + values[i] + copied[i]
  break sum
io const nested = func (n: U32) => return do:
  let values = @array.generate n (func i => return @array.fill 2 i)
  let sum = 0
  for i in 0..n:
    let before = first_elem values
    values[0] := #[9, values[0][1]]
    sum := sum + values[0][0] - (if i == 0 then before else 0)
  break sum
io const ordered = func (n: U32) => return do:
  let values = @array.fill n 1
  break left values (@array.set values 0 9)
io const indexed = func (n: U32) => return do:
  let values = @array.fill n 1
  break values[(@array.set values 0 5)[1] - 1]
`,
    (guest) => {
      for (const n of [8, 64]) {
        for (const name of ["returned", "stored", "paired", "captured", "kept"]) {
          equal(guest.call(name, n), 10 * n);
        }
        equal(guest.call("nested", n), 9 * n);
        equal(guest.call("ordered", n), 10);
        equal(guest.call("indexed", n), 1);
      }
    },
  );
});

// Slices and explicit copies keep sources independent across branch writes.
Deno.test("fresh copies and disjoint writes preserve sources across branches and slices", async () => {
  await compileAndRun(`
io const sliced = func (count: U32) => return do:
  let source = @array.generate count (func i => return i)
  let values = @array.slice source 0 count
  for i in 0 .. count:
    values[i] := self + 1
  break #[source[0], source[count - 1], values[0], values[count - 1]]
io const branched = func (count: U32) => return do:
  let values = @array.fill count 0
  for i in 0 .. count:
    if i % 2 == 0:
      values[i] := i + 1
    else:
      values[i] := i + 3
  break values
io const retained = func (flag: Bool) => return do:
  let values = #[10, 20]
  let previous = values.copy
  if flag:
    values[0] := 1
  else:
    values[0] := 3
  break #[previous[0], previous[1], values[0], values[1]]
io const nested_slice = func (value: U32) => return do:
  let source = #[#[value], #[value]]
  let values = #[source[0].copy, source[1].copy]
  values[0][0] := value + 1
  break #[source[0][0], source[1][0], values[0][0], values[1][0]]
`, (guest) => {
    for (const count of [1, 32, 4096, 20020]) {
      equal([...guest.call("sliced", count) as Uint32Array].join(","), `0,${count - 1},1,${count}`);
      const values = guest.call("branched", count) as Uint32Array;
      for (let i = 0; i < count; i++) equal(values[i], i + (i % 2 === 0 ? 1 : 3));
    }
    equal([...guest.call("retained", true) as Uint32Array].join(","), "10,20,1,20");
    equal([...guest.call("retained", false) as Uint32Array].join(","), "10,20,3,20");
    equal([...guest.call("nested_slice", 9) as Uint32Array].join(","), "9,9,10,9");
  });
});
