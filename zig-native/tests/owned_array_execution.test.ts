import { compileAndRun, equal } from "./compile_helpers.ts";
Deno.test("exclusive fresh arrays update through nested loop carries", async () => {
  await compileAndRun(
    `
const fill = fn count => fn value => @array.fill count value
entry const build = fn (count: U32) -> Array U32 => do:
  let values = fill (@u32.mul count 2) 0
  for outer in 0 .. count:
    for inner in 0 .. 2:
      values[@u32.add (@u32.mul outer 2) inner] := outer
  return values
entry const floating = fn (count: U32) -> Array F32 => do:
  let values = @array.generate count (fn index => @u32.to_f32 index)
  for index in 0 .. count:
    values[index] := @f32.add self 0.5
  return values
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
const read = fn values => values[1]
const delay = fn ~value => value
entry const alias = fn () => do:
  let values = #[1, 2]
  let before = values
  values[1] := 9
  return @u32.add before[1] values[1]
entry const callback = fn () => do:
  let values = #[1, 2]
  let before = fn () => values[1]
  values[1] := 9
  return @u32.add (before ()) values[1]
entry const suspended = fn () => do:
  let values = #[1, 2]
  let before = delay values
  values[1] := 9
  return @u32.add (@array.get (@force before) 1) values[1]
entry const iterator = fn () => do:
  let values = #[1, 2]
  let sum = 0
  for value in values:
    values[1] := 9
    sum := @u32.add sum value
  return sum
entry const parameter = fn (values: Array U32) => do:
  values[1] := 9
  return values
entry const global = fn () => do:
  let values = stored
  values[1] := 9
  return @u32.add stored[1] values[1]
entry const retained = fn () => do:
  let values = #[1, 2]
  let state = #Cell values
  values[1] := 9
  let (#Cell before, _) = @state.run state (fn () => ())
  return @u32.add before[1] values[1]
entry const calls = fn () => do:
  let values = #[1, 2]
  let before = read values
  values[1] := 9
  return @u32.add before values[1]
entry const nested = fn () => do:
  let leaf = #[1]
  let values = @array.fill 2 leaf
  values[0][0] := 9
  return @u32.add values[0][0] values[1][0]
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
const get1 = fn index => fn values => values[index]
const total = fn (values: Array F32) => do:
  let sum = 0.0
  for value in values:
    sum := sum + value
  return sum
entry const inlined = fn (n: U32) -> F32 => do:
  let values = @array.generate n (fn i => @u32.to_f32 i)
  for i in 0..n:
    let x = get1 i values
    values[i] := x * 0.5 + 0.25
  return values[n - 1]
entry const called = fn (n: U32) -> F32 => do:
  let values = @array.fill n 1.0
  for i in 0..n:
    values[i] := total values / @u32.to_f32 n + 1.0
  return values[n - 1]
entry const generated = fn (n: U32) -> F32 => do:
  let values = @array.generate n (fn i => @u32.to_f32 i)
  let doubled = @array.generate n (fn i => values[i] * 2.0)
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  return values[n - 1]
entry const mapped = fn (n: U32) -> F32 => do:
  let values = @array.generate n (fn i => @u32.to_f32 i)
  let doubled = array.map (fn value => value * 2.0) values
  for i in 0..n:
    values[i] := values[i] + doubled[i]
  return values[n - 1]
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
        // Two arrays and the generator's environment; a copy adds one per i.
        const cases: [string, number, number][] = [
          ["inlined", (n - 1) * 0.5 + 0.25, 1],
          ["called", called(n), 1],
          ["generated", 3 * (n - 1), 3],
          ["mapped", 3 * (n - 1), 3],
        ];
        for (const [name, expected, allocations] of cases) {
          const observed = run(name, n);
          equal(observed.result, expected);
          equal(observed.destroyed, allocations);
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
const pass = fn values => values
const wrap = fn values => #Cell values
const pair = fn values => (values, 1)
const first = fn values => values[0]
const reader = fn values => fn index => values[index]
const left = fn a => fn b => a[0] + b[0]
entry const returned = fn (n: U32) => do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let before = pass values
    values[i] := 9
    sum := sum + before[i]
  return sum
entry const stored = fn (n: U32) => do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let #Cell before = wrap values
    values[i] := 9
    sum := sum + before[i]
  return sum
entry const paired = fn (n: U32) => do:
  let values = @array.fill n 1
  let sum = 0
  for i in 0..n:
    let (before, _) = pair values
    values[i] := 9
    sum := sum + before[i]
  return sum
entry const captured = fn (n: U32) => do:
  let values = @array.fill n 1
  let read = reader values
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + read i
  return sum
entry const kept = fn (n: U32) => do:
  let values = @array.fill n 1
  let read = fn index => values[index]
  let copied = @array.generate n read
  let sum = 0
  for i in 0..n:
    values[i] := 9
    sum := sum + read i + copied[i]
  return sum
entry const nested = fn (n: U32) => do:
  let values = @array.generate n (fn i => @array.fill 2 i)
  let sum = 0
  for i in 0..n:
    let inner = first values
    values[0][0] := 9
    sum := sum + inner[0]
  return sum
entry const ordered = fn (n: U32) => do:
  let values = @array.fill n 1
  return left values (@array.set values 0 9)
entry const indexed = fn (n: U32) => do:
  let values = @array.fill n 1
  return values[(@array.set values 0 5)[1] - 1]
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
        equal(run("nested", n).result, 9 * (n - 1));
        equal(run("ordered", n).result, 10);
        equal(run("indexed", n).result, 1);
      }
    },
  );
});
