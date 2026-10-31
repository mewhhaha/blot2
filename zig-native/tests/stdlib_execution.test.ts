import { strict as assert } from "node:assert";
import { createCompiler, instantiateGuest } from "../../mod.ts";
import {
  compileAndRun,
  compileExpectedFailure,
  equal,
} from "./compile_helpers.ts";

Deno.test("array scans and compaction preserve order, wrap, snapshots and linear runtime storage", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
entry const scan = func (values: Array U32) => return array.prefix_sums values
entry const filter = func (values: Array U32) => return array.filter (func x => return x % 2 == 0) values
entry const filter_map = func (values: Array U32) => return
  array.filter_map (func x => return if x % 2 == 0 then $Some (x + 1) else $Nothing) values
entry const indices = func (values: Array U32) => return array.indices (array.map (func x => return x % 2 == 0) values)
entry const concat = func (values: Array U32) => return array.concat values values
entry const flatten = func (values: Array U32) => return array.flatten
  #[{start: 0, count: 0}, {start: 0, count: values.length}, {start: values.length, count: 0},
    {start: 0, count: values.length}, {start: values.length, count: 0}] values
entry const push = func (values: Array U32) => return array.push 42 values
entry const staged = (array.prefix_sums (array.generate 1025 identity))[1024]
entry const staged_filter = (array.filter_map (func x => return if x == 1 then $Nothing else $Some x) #[1, 42])[0]
entry const snapshots = func () => return do:
  let input = #[1, 2, 3]
  let scan = array.prefix_sums input
  scan[0] := 99
  let filtered = array.filter (func x => return true) input
  filtered[0] := 7
  break #[input[0], scan[0], filtered[0]]
`,
    (guest) => {
      equal(guest.read("staged"), 524800);
      equal(guest.read("staged_filter"), 42);
      assert.deepEqual(
        guest.call("snapshots", null),
        new Uint32Array([1, 99, 7]),
      );
      for (const count of [0, 1, 2, 3, 31, 32, 33, 255, 256, 257, 8193]) {
        const input = Uint32Array.from(
          { length: count },
          (_, i) => i % 3 === 0 ? 0xFFFFFFFF : i,
        );
        const values = [...input];
        let total = 0;
        const expected = input.map((value) => total = (total + value) >>> 0);
        assert.deepEqual(guest.call("scan", input), expected);
        assert.deepEqual(
          guest.call("filter", input),
          input.filter((x) => x % 2 === 0),
        );
        assert.deepEqual(
          guest.call("filter_map", input),
          input.filter((x) => x % 2 === 0).map((x) => x + 1),
        );
        assert.deepEqual(
          guest.call("indices", input),
          Uint32Array.from(values.flatMap((x, i) => x % 2 === 0 ? [i] : [])),
        );
        for (const entry of ["concat", "flatten"]) {
          assert.deepEqual(
            guest.call(entry, input),
            Uint32Array.from([...input, ...input]),
          );
        }
        assert.deepEqual(
          guest.call("push", input),
          Uint32Array.from([...input, 42]),
        );
        assert.deepEqual([...input], values);
      }
      assert(
        guest.memoryBytes() <= 2 * 1024 * 1024,
        `Compaction copied growing outputs: ${guest.memoryBytes()}`,
      );
    },
  );
});

Deno.test("list folds sequence effects and list predicates stop at the first deciding element", async () => {
  await compileAndRun(
    `
import * as list from "../../std/list"
entry const fold = func (host: U32 -> U32 ! {Foreign}) => return
  list.fold_left (func total => return func value => return do:
    use amount <- host value
    break total + amount) 0 [1, 2, 3]
entry const any = func (host: U32 -> Bool ! {Foreign}) => return list.any host [1, 2, 3]
entry const all = func (host: U32 -> Bool ! {Foreign}) => return list.all host [1, 2, 3]
entry const empty_any = func (host: U32 -> Bool ! {Foreign}) => return list.any host []
entry const empty_all = func (host: U32 -> Bool ! {Foreign}) => return list.all host []
entry const filter = func (host: U32 -> Bool ! {Foreign}) => return Array.from_list (list.filter host [1, 2, 3])
`,
    (guest) => {
      const calls: number[] = [];
      const reducer = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return (value as number) * 10;
        },
      });
      equal(guest.call("fold", reducer), 60);
      assert.deepEqual(calls, [1, 2, 3]);
      for (
        const [entry, accept, result] of [
          ["any", true, true],
          ["all", false, false],
          ["empty_any", true, false],
          ["empty_all", false, true],
        ] as const
      ) {
        calls.length = 0;
        const predicate = guest.capability({
          parameter: "U32",
          result: "Bool",
          call(value) {
            calls.push(value as number);
            return value === 2 ? accept : !accept;
          },
        });
        equal(guest.call(entry, predicate), result);
        assert.deepEqual(calls, entry.startsWith("empty") ? [] : [1, 2]);
      }
      calls.length = 0;
      const predicate = guest.capability({
        parameter: "U32",
        result: "Bool",
        call(value) {
          calls.push(value as number);
          return value !== 2;
        },
      });
      assert.deepEqual(
        guest.call("filter", predicate),
        new Uint32Array([1, 3]),
      );
      assert.deepEqual(calls, [1, 2, 3]);
    },
  );
});

Deno.test("array filtering and collection mapping keep their pure callback contract", async () => {
  for (
    const [module, member, values] of [
      ["array", "filter", "#[1, 2]"],
      ["array", "map", "#[1, 2]"],
      ["list", "map", "[1, 2]"],
    ] as const
  ) {
    await compileExpectedFailure(
      `
import * as collection from "../../std/${module}"
entry const run = func (host: U32 -> Bool ! {Foreign}) => return
  (collection.${member} host ${values}).length
`,
      "effect_mismatch",
    );
  }
});

Deno.test("pattern branches preserve aliased list versions while appending", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return do:
  let values: List U32 = []
  let prior: List U32 = []
  for i in 0..count:
    let before = values
    let candidate = if i % 2 == 0 then $Some i else $Nothing
    if let $Some value = candidate:
      values := [...self, value]
    else:
      values := [i, ...self]
    prior := before
  break Array.from_list prior
`,
    (guest) => {
      let current: number[] = [], previous: number[] = [];
      for (let count = 0; count < 40; count++) {
        assert.deepEqual(guest.call("run", count), Uint32Array.from(previous));
        previous = current;
        current = count % 2 === 0 ? [...current, count] : [count, ...current];
      }
    },
  );
});

Deno.test("list append and prepend wrappers retain linear construction through aliases", async () => {
  await compileAndRun(
    `
import * as list from "../../std/list"
const alias = list.append
const prepend = func item => return func items => return @list.prepend items item
entry const appended = func (count: U32) => return do:
  let values: List U32 = []
  for index in 0..count:
    values := alias index values
  break Array.from_list values
entry const prepended = func (count: U32) => return do:
  let values: List F32 = []
  for index in 0..count:
    values := prepend (F32.from index) values
  break Array.from_list values
`,
    (guest) => {
      const count = 8193;
      assert.deepEqual(
        guest.call("appended", count),
        Uint32Array.from({ length: count }, (_, i) => i),
      );
      assert.deepEqual(
        guest.call("prepended", count),
        Float32Array.from({ length: count }, (_, i) => count - 1 - i),
      );
      assert(
        guest.memoryBytes() <= 2 * 1024 * 1024,
        `Wrappers copied growing lists: ${guest.memoryBytes()}`,
      );
    },
  );
});

Deno.test("collection wrapper elimination preserves argument effects and shared captured versions", async () => {
  await compileAndRun(
    `
import * as list from "../../std/list"
entry const order = func (host: U32 -> U32 ! {Foreign}) => return Array.from_list (list.append (host 1) (do:
  use initial <- host 2
  break [initial]))
entry const shared = func () => return do:
  let original = [1, 2]
  let appended = list.append 3 original
  break #[original.length, appended.length, (Array.from_list original)[1]]
entry const captured = func (count: U32) => return do:
  let callbacks: List (Unit -> U32) = []
  for index in 0..count:
    callbacks := list.append (func () => return callbacks.length) callbacks
  break #[callback () | callback <- callbacks]
`,
    (guest) => {
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "U32",
        call(value) {
          calls.push(value as number);
          return value;
        },
      });
      assert.deepEqual(guest.call("order", host), new Uint32Array([2, 1]));
      assert.deepEqual(calls, [1, 2]);
      assert.deepEqual(guest.call("shared", null), new Uint32Array([2, 3, 2]));
      assert.deepEqual(
        guest.call("captured", 20),
        Uint32Array.from({ length: 20 }, (_, i) => i),
      );
    },
  );
});

Deno.test("retained collection wrapper bodies invalidate after append becomes prepend", async () => {
  const directory = await Deno.makeTempDir();
  const entry = `${directory}/main.blot`, library = `${directory}/lib.blot`;
  const options = {
    entry,
    executable: Deno.args[0] ??
      new URL("../zig-out/bin/blotc", import.meta.url),
  };
  const compiler = await createCompiler(options);
  const declarations =
    `const append = func item => return func items => return @list.append items item
const build = func (count: U32) => return do:
  let values: List U32 = []
  for index in 0..count:
    values := append index values
  break Array.from_list values
`;
  try {
    for (
      const [source, offset, reversed] of [
        [declarations, 0, false],
        [declarations, 1, false],
        [declarations, 2, false],
        [declarations.replace("@list.append", "@list.prepend"), 0, true],
        [declarations, 0, false],
      ] as const
    ) {
      const sources = {
        [entry]:
          `import * as lib from "./lib"\nentry const run = func (count: U32) => return lib.build (count + ${offset})\n`,
        [library]: source,
      };
      const result = await compiler.build({ sources });
      assert(result.success, JSON.stringify(result));
      const guest = await instantiateGuest(result.bytes);
      try {
        assert.deepEqual(
          guest.call("run", 3),
          Uint32Array.from(
            { length: 3 + offset },
            (_, i) => reversed ? 2 + offset - i : i,
          ),
        );
      } finally {
        guest.dispose();
      }
      const fresh = await createCompiler(options);
      try {
        const rebuilt = await fresh.build({ sources });
        assert(rebuilt.success, JSON.stringify(rebuilt));
        assert.deepEqual(result.bytes, rebuilt.bytes);
      } finally {
        await fresh.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});

Deno.test("Maybe and Result deferred fallbacks skip work on success and run on failure", async () => {
  await compileAndRun(
    `
entry const some = Maybe.unwrap_or_else (@panic "unused fallback") ($Some 42)
entry const ok = Result.unwrap_or_else (@panic "unused fallback") ($Ok 42)
entry const nothing = Maybe.unwrap_or_else 42 $Nothing
entry const error = Result.unwrap_or_else 42 ($Err false)
entry const success = func (host: Unit -> U32 ! {Foreign}) => return
  Result.unwrap_or_else (host ()) ($Ok 42)
entry const failure = func (host: Unit -> U32 ! {Foreign}) => return
  Result.unwrap_or_else (host ()) ($Err false)
`,
    (guest) => {
      for (const name of ["some", "ok", "nothing", "error"]) {
        equal(
          guest.read(name),
          42,
        );
      }
      let calls = 0;
      const host = guest.capability({
        parameter: "Unit",
        result: "U32",
        call() {
          calls++;
          return 21;
        },
      });
      equal(guest.call("success", host), 42);
      equal(calls, 0);
      equal(guest.call("failure", host), 21);
      equal(calls, 1);
    },
  );
});

Deno.test("F32 trig boundaries and vector interpolation retain scalar arithmetic", async () => {
  await compileAndRun(
    `
import { Vec2, Vec3 } from "../../std/vector"
entry const trig = func (value: F32) => return do:
  let (s, c) = sin_cos value
  break #[sin value, cos value, tan value, s, c]
entry const vector = func (values: Array F32) => return do:
  let a = $Vec3 { x: values[0], y: values[1], z: values[2] }
  let b = $Vec3 { x: values[3], y: values[4], z: values[5] }
  let v = lerp a b values[6]
  let w = lerp ($Vec2 { x: a.x, y: a.y }) ($Vec2 { x: b.x, y: b.y }) values[6]
  break #[v.x, v.y, v.z, w.x, w.y]
entry const zero = func () => return do:
  let v = ($Vec3 { x: 0.0, y: 0.0, z: 0.0 }).normalized
  break #[v.x, v.y, v.z]
`,
    (guest) => {
      for (
        const value of [
          -8192,
          -1000,
          -Math.PI,
          -1,
          0,
          1,
          Math.PI / 2,
          Math.PI,
          1000,
          8192,
        ]
      ) {
        const x = Math.fround(value);
        const actual = guest.call("trig", x) as Float32Array;
        assert(Math.abs(actual[0] - Math.sin(x)) < 0.00002);
        assert(Math.abs(actual[1] - Math.cos(x)) < 0.00002);
        equal(actual[0], actual[3]);
        equal(actual[1], actual[4]);
        equal(actual[2], Math.fround(actual[0] / actual[1]));
      }
      for (const value of [8193, -8193, Infinity, -Infinity, NaN]) {
        assert(
          [...(guest.call("trig", value) as Float32Array)].every(Number.isNaN),
        );
      }
      const f = Math.fround;
      for (const weight of [-1, 0, 0.125, 1, 2]) {
        const input = new Float32Array([
          1.1,
          -2.2,
          10000,
          7.3,
          4.4,
          -0.001,
          weight,
        ]);
        const expected = [0, 1, 2].map((i) =>
          f(input[i] + f(f(input[i + 3] - input[i]) * input[6]))
        );
        assert.deepEqual(
          guest.call("vector", input),
          Float32Array.from([...expected, expected[0], expected[1]]),
        );
      }
      assert.deepEqual(guest.call("zero", null), new Float32Array(3));
    },
  );
});
