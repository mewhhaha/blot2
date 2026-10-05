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
