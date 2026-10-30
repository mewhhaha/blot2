import { compileAndRun, equal } from "./compile_helpers.ts";
Deno.test("exclusive fresh arrays update through nested loop carries", async () => {
  await compileAndRun(
    `
const fill = func count => return func value => return @array.fill count value
entry const build = func (count: U32) : Array U32 => return do:
  let values = fill (@u32.mul count 2) 0
  for outer in 0 .. count:
    for inner in 0 .. 2:
      values[@u32.add (@u32.mul outer 2) inner] := outer
  break values
entry const floating = func (count: U32) : Array F32 => return do:
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
      if (guest.memoryBytes() > 2 * 1024 * 1024) {
        throw new Error(
          `Unexpected copied-array heap: ${guest.memoryBytes()}`,
        );
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
Deno.test("persistent versions survive aliases captures state calls and iterator borrows", async () => {
  await compileAndRun(
    `
data Cell value = #Cell value
const stored = #[1, 2]
const read = func values => return values[1]
const delay = func ~value => return value
entry const alias = func () => return do:
  let values = #[1, 2]
  let before = values
  values[1] := 9
  break @u32.add before[1] values[1]
entry const callback = func () => return do:
  let values = #[1, 2]
  let before = func () => return values[1]
  values[1] := 9
  break @u32.add (before ()) values[1]
entry const suspended = func () => return do:
  let values = #[1, 2]
  let before = delay values
  values[1] := 9
  break @u32.add (@array.get (@force before) 1) values[1]
entry const iterator = func () => return do:
  let values = #[1, 2]
  let sum = 0
  for value in values:
    values[1] := 9
    sum := @u32.add sum value
  break sum
entry const parameter = func (values: Array U32) => return do:
  values[1] := 9
  break values
entry const global = func () => return do:
  let values = stored
  values[1] := 9
  break @u32.add stored[1] values[1]
entry const retained = func () => return do:
  let values = #[1, 2]
  let state = #Cell values
  values[1] := 9
  let (#Cell before, _) = @state.run state (func () => return ())
  break @u32.add before[1] values[1]
entry const calls = func () => return do:
  let values = #[1, 2]
  let before = read values
  values[1] := 9
  break @u32.add before values[1]
entry const nested = func () => return do:
  let leaf = #[1]
  let values = @array.fill 2 leaf
  values[0][0] := 9
  break @u32.add values[0][0] values[1][0]
`,
    (guest) => {
      for (
        const name of [
          "alias",
          "callback",
          "suspended",
          "global",
          "retained",
          "calls",
        ]
      ) for (let i = 0; i < 4; i++) equal(guest.call(name, null), 11);
      equal(guest.call("iterator", null), 3);
      equal(guest.call("nested", null), 10);
      const values = new Uint32Array([1, 2]);
      equal((guest.call("parameter", values) as Uint32Array)[1], 9);
      equal(values[1], 2);
    },
  );
});

// Raw exports expose the counted-ownership diagnostics. Each copied array is
// destroyed when its next version replaces it, so `destroyed` counts copies.
function counted(bytes: Uint8Array<ArrayBuffer>) {
  const raw = new WebAssembly.Instance(new WebAssembly.Module(bytes)).exports;
  return (name: string, count: number) => {
    const read = (counter: string) =>
      Number((raw[`blot:rc_${counter}`] as WebAssembly.Global).value);
    const destroyed = read("destroyed");
    const retains = read("retains");
    const result = (raw[name] as CallableFunction)(count) as number;
    return {
      result,
      destroyed: read("destroyed") - destroyed,
      retains: read("retains") - retains,
    };
  };
}

Deno.test("read-only callees and dropped generators borrow an exclusive array in place", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
const get1 = func index => return func values => return values[index]
const total = func (values: Array F32) => return do:
  let sum = 0.0
  for value in values:
    sum := sum + value
  break sum
const matched = func (values: Array F32) => return func (index: U32) => return case true of
  true => values[index]
  false => 0.0
entry const inlined = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  for i in 0..n:
    let x = get1 i values
    values[i] := x * 0.5 + 0.25
  break values[n - 1]
entry const called = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  for i in 0..n:
    values[i] := total values / @u32.to_f32 n + 1.0
  break values[n - 1]
entry const generated = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  let doubled = @array.generate n (func i => return values[i] * 2.0)
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  break values[n - 1]
entry const mapped = func (n: U32) : F32 => return do:
  let values = @array.generate n (func i => return @u32.to_f32 i)
  let doubled = array.map (func value => return value * 2.0) values
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  break values[n - 1]
entry const local = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  let read = func (xs: Array F32) => return func (index: U32) => return xs[index]
  for i in 0..n:
    let x = read values i
    values[i] := x + 1.0
  break values[n - 1]
entry const match_read = func (n: U32) : F32 => return do:
  let values = @array.fill n 1.0
  for i in 0..n:
    let x = matched values i
    values[i] := x + 1.0
  break values[n - 1]
`,
    (_guest, bytes) => {
      const run = counted(bytes);
      const called = (n: number) => {
        const values = new Float32Array(n).fill(1);
        for (let i = 0; i < n; i++) {
          const sum = values.reduce((sum, value) => Math.fround(sum + value), 0);
          values[i] = Math.fround(Math.fround(sum / n) + 1);
        }
        return values[n - 1];
      };
      // Retains stay constant with size: no copy publishes a new version.
      const retains = new Map<string, number>();
      for (const n of [8, 64, 512]) {
        // Two arrays; scalar-reader inlining also removes the direct
        // generator environment. A copied update adds one per iteration.
        const cases: [string, number, number][] = [
          ["inlined", (n - 1) * 0.5 + 0.25, 1],
          ["called", called(n), 1],
          ["generated", 3 * (n - 1), 2],
          ["mapped", 3 * (n - 1), 3],
          ["local", 2, 1],
          ["match_read", 2, 1],
        ];
        for (const [name, expected, allocations] of cases) {
          const observed = run(name, n);
          equal(observed.result, expected);
          if (observed.destroyed !== allocations) throw new Error(`${name}(${n}): expected ${allocations} retirements, observed ${observed.destroyed}`);
          retains.set(name, retains.get(name) ?? observed.retains);
          equal(observed.retains, retains.get(name));
        }
      }
    },
  );
});

Deno.test("surviving aliases of a borrowed array keep the copy", async () => {
  await compileAndRun(
    `
data Cell value = #Cell value
const pass = func values => return values
const wrap = func values => return #Cell values
const pair = func values => return (values, 1)
const first = func values => return values[0]
const reader = func values => return func index => return values[index]
const left = func a => return func b => return a[0] + b[0]
const merged = func (flag: Bool) => return func (values: Array U32) => return do:
  if flag:
    values := #[7]
  break values
const carried = func (count: U32) => return func (values: Array U32) => return do:
  for index in 0..count:
    values := #[index]
  break values
entry const reassigned = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let before = merged (i == n) values
    let after = carried 0 values
    values[i] := 9
    sum := sum + before[i] + after[i]
  break sum
entry const returned = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let before = pass values
    values[i] := 9
    sum := sum + before[i]
  break sum
entry const stored = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let #Cell before = wrap values
    values[i] := 9
    sum := sum + before[i]
  break sum
entry const paired = func (n: U32) => return do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let (before, _) = pair values
    values[i] := 9
    sum := sum + before[i]
  break sum
entry const captured = func (n: U32) => return do:
  let values = @array.fill n 1
  let read = reader values
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + read i
  break sum
entry const kept = func (n: U32) => return do:
  let values = @array.fill n 1
  let read = func index => return values[index]
  let copied = @array.generate n read
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + read i + copied[i]
  break sum
entry const nested = func (n: U32) => return do:
  let values = @array.generate n (func i => return @array.fill 2 i)
  let sum = 0
  for i in 0..n:
    let inner = first values
    values[0][0] := 9
    sum := sum + inner[0]
  break sum
entry const ordered = func (n: U32) => return do:
  let values = @array.fill n 1
  break left values (@array.set values 0 9)
entry const indexed = func (n: U32) => return do:
  let values = @array.fill n 1
  break values[(@array.set values 0 5)[1] - 1]
`,
    (_guest, bytes) => {
      const run = counted(bytes);
      for (const n of [8, 64]) {
        for (const name of ["returned", "stored", "paired", "captured"]) {
          const observed = run(name, n);
          equal(observed.result, n);
          if (observed.destroyed < n) {
            throw new Error(`${name} reused an aliased array`);
          }
        }
        equal(run("kept", n).result, 2 * n);
        equal(run("reassigned", n).result, 2 * n);
        equal(run("nested", n).result, 9 * (n - 1));
        equal(run("ordered", n).result, 10);
        equal(run("indexed", n).result, 1);
      }
    },
  );
});

Deno.test("fresh copies and disjoint writes preserve sources and retained branch snapshots", async () => {
  await compileAndRun(`
entry const sliced = func (count: U32) => return do:
  let source = @array.generate count (func i => return i)
  let values = @array.slice source 0 count
  for i in 0 .. count:
    values[i] := self + 1
  break #[source[0], source[count - 1], values[0], values[count - 1]]
entry const branched = func (count: U32) => return do:
  let values = @array.fill count 0
  for i in 0 .. count:
    if i % 2 == 0:
      values[i] := i + 1
    else:
      values[i] := i + 3
  break values
entry const retained = func (flag: Bool) => return do:
  let values = #[10, 20]
  let previous = values
  if flag:
    values[0] := 1
  else:
    values[0] := 3
  break #[previous[0], previous[1], values[0], values[1]]
entry const nested_slice = func (value: U32) => return do:
  let inner = #[value]
  let source = #[inner, inner]
  let values = @array.slice source 0 2
  values[0][0] := value + 1
  break #[inner[0], source[0][0], source[1][0], values[0][0], values[1][0]]
`, (guest) => {
    for (const count of [1, 32, 4096, 20020]) {
      equal([...guest.call("sliced", count) as Uint32Array].join(","), `0,${count - 1},1,${count}`);
      const values = guest.call("branched", count) as Uint32Array;
      for (let i = 0; i < count; i++) equal(values[i], i + (i % 2 === 0 ? 1 : 3));
    }
    equal([...guest.call("retained", true) as Uint32Array].join(","), "10,20,1,20");
    equal([...guest.call("retained", false) as Uint32Array].join(","), "10,20,3,20");
    equal([...guest.call("nested_slice", 9) as Uint32Array].join(","), "9,9,9,10,9");
  });
});
