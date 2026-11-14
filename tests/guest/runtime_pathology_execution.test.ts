import { strict as assert } from "node:assert";
import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("two large records share their child across loop iterations", async () => {
  await compileAndRun(`
entry const memory = func () : Array U32 => return #[]
entry const fold = func (count: U32) => return do:
  let sum = 0
  for value in 0..count:
    let child = { a: value, b: value, c: value, d: value, e: value, f: value,
      g: value, h: value, i: value, j: value, k: value, l: value,
      m: value, n: value, o: value, p: value, q: value, r: value + 1 }
    let left = { child: child, a: value, b: value, c: value, d: value, e: value,
      f: value, g: value, h: value, i: value, j: value, k: value,
      l: value, m: value, n: value, o: value, p: value, q: value }
    let right = { child: child, a: value, b: value, c: value, d: value, e: value,
      f: value, g: value, h: value, i: value, j: value, k: value,
      l: value, m: value, n: value, o: value, p: value, q: value + 2 }
    if value % 2 == 0:
      let alias = left.child
      sum := self + alias.a + right.child.r + left.q + right.q
    else:
      sum := self + right.child.a + left.child.r + left.q + right.q
  break sum
`, guest => {
    for (const count of [0, 1, 2, 100000, 100000]) {
      equal(guest.call("fold", count), (2 * count * count + count) >>> 0);
    }
  });
});

Deno.test("record ownership crosses ordinary factories, borrowed calls and branches in finite loops", async () => {
  await compileAndRun(`
const make = func value => return { a: value, b: value, c: value, d: value, e: value, f: value,
  g: value, h: value, i: value, j: value, k: value, l: value,
  m: value, n: value, o: value, p: value, q: value, r: value + 1 }
const read = func record => return record.a + record.b + record.c + record.d + record.e + record.f +
  record.g + record.h + record.i + record.j + record.k + record.l + record.m + record.n +
  record.o + record.p + record.q + record.r
entry const storage_probe = func (value: U32) => return #[value]
entry const fold = func (count: U32) => return do:
  let sum = 0
  for value in 0..count:
    let record = make value
    if value % 2 == 0:
      sum := self + read record
    else:
      sum := self + read record + 1
  break sum
`, guest => {
    for (const count of [0, 1, 2, 100000, 100000]) {
      equal(guest.call("fold", count), (9 * count * (count - 1) + count + Math.floor(count / 2)) >>> 0);
    }
  });
});

Deno.test("large local records keep their fields through aliased reads", async () => {
  await compileAndRun(`
entry const storage_probe = func (value: U32) => return #[value]
entry const fold = func (count: U32) => return do:
  let sum = 0
  for value in 0..count:
    let record = { a: value, b: value, c: value, d: value, e: value, f: value,
      g: value, h: value, i: value, j: value, k: value, l: value,
      m: value, n: value, o: value, p: value, q: value, r: value + 1 }
    let alias = record
    sum := self + alias.a + record.r
  break sum
`, guest => {
    for (let repetition = 0; repetition < 5; repetition++) {
      equal(guest.call("fold", 100000), (100000 * 100000) >>> 0);
    }
  });
});

async function replacements(count: number) {
  await compileAndRun(
    `
import * as array from "../../std/array"
const replace = array.replace
entry const wrapped = func (count: U32) => return do:
  let values = array.fill count 0
  for i in 0..count:
    values := replace i (i + 1) values
  break values
entry const direct = func (count: U32) => return do:
  let values = array.fill count 0.0
  for i in 0..count:
    values := @array.set values i (F32.from i)
  break values
entry const snapshots = func () => return do:
  let original = #[1, 2, 3]
  let values = original
  let saved = func () => return values[0]
  values := replace 0 99 values
  break #[original[0], saved (), values[0]]
entry const nested = func () => return do:
  let original = #[#[1], #[2]]
  let changed = replace 0 99 original[0]
  break #[original[0][0], changed[0]]
`,
    (guest) => {
      assert.deepEqual(
        guest.call("wrapped", count),
        Uint32Array.from({ length: count }, (_, i) => i + 1),
      );
      assert.deepEqual(
        guest.call("direct", count),
        Float32Array.from({ length: count }, (_, i) => i),
      );
      assert.deepEqual(
        guest.call("snapshots", null),
        new Uint32Array([1, 1, 99]),
      );
      assert.deepEqual(guest.call("nested", null), new Uint32Array([1, 99]));
    },
  );
}

Deno.test("direct and wrapped array replacement retain earlier versions", async () => {
  await replacements(513);
});

// Direct backend gap: `values := @array.set values i v` copies every iteration and keeps each copy until the export returns, so 2,049 replacements trap ("unreachable") (tasks/DELETE_SCOPED.md, known limits).
Deno.test.ignore("direct and wrapped array replacement use linear storage", async () => {
  await replacements(2049);
});

Deno.test("array replacement evaluates written arguments before bounds checks and preserves iterator borrows", async () => {
  await compileAndRun(
    `
import * as array from "../../std/array"
entry const order = func (host: U32 -> U32 ! {Foreign}) => return
  array.replace (host 0) (host 1) (do:
    use value <- host 2
    break #[value])
entry const bounds = func (host: U32 -> U32 ! {Foreign}) => return do:
  let values = #[1]
  use changed <- array.replace 1 (host 42) values
  break changed
entry const borrowed = func () => return do:
  let values = #[1, 2, 3]
  let sum = 0
  for item in values:
    sum := sum + item
    values := array.replace 2 99 values
  break #[sum, values[2]]
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
      assert.deepEqual(guest.call("order", host), new Uint32Array([1]));
      assert.deepEqual(calls, [0, 1, 2]);
      calls.length = 0;
      assert.throws(() => guest.call("bounds", host));
      assert.deepEqual(calls, [42]);
      assert.deepEqual(guest.call("borrowed", null), new Uint32Array([6, 99]));
    },
  );
});

async function stagedAppends(count: number) {
  await compileAndRun(
    `
import * as array from "../../std/array"
const build = func (count: U32) : Array U32 => return do:
  let packed: Array U32 = #[]
  for i in 0..count:
    packed := array.push i self
  break packed
const grown = build ${count}
entry const ends = grown[${count - 1}]
const selected = array.filter_map (func x => return if x % 2 == 0 then $Some x else $Nothing) (array.generate 4097 identity)
entry const selected_last = selected[2048]
`,
    (guest) => {
      equal(guest.read("ends"), count - 1);
      equal(guest.read("selected_last"), 4096);
    },
  );
}

Deno.test("staged appends and comprehensions preserve immutable versions", async () => {
  await stagedAppends(1025);
});

// Direct backend gap: an `array.push` loop copies every iteration and keeps each copy until the export returns, so 8,193 appends trap ("unreachable") (tasks/DELETE_SCOPED.md, known limits).
Deno.test.ignore("staged appends preserve immutable versions within bounded storage", async () => {
  await stagedAppends(8193);
});

Deno.test("Result iteration stops on errors and allows distinct state result and error types without loop scaffolding", async () => {
  await compileAndRun(
    `
entry const run = func (count: U32) => return Result.unwrap_or 0 (Result.iterate 0 (func i => return
  $Ok (if i < count then $Continue (i + 1) else $Done i)))
entry const stop = func (host: U32 -> Bool ! {Foreign}) => return do:
  use outcome <- Result.iterate 0 (func i => return do:
    use failed <- host i
    if failed:
      break $Err i
    if i == 10:
      break $Ok ($Done #[42.0])
    break $Ok ($Continue (i + 1)))
  break case outcome of
    $Ok value => value[0]
    $Err error => F32.from error
const keep = func host => return func candidate => return case candidate of
  $Ok value => do:
    use observed <- host value
    break $Ok value
  $Err error => $Err error
entry const prefix = func (host: U32 -> Bool ! {Foreign}) => return do:
  use candidate <- keep host ($Ok 7)
  break Result.unwrap_or 0 candidate
`,
    (guest) => {
      equal(guest.call("run", 100000), 100000);
      assert(guest.memoryBytes() <= 128 * 1024);
      const calls: number[] = [];
      const host = guest.capability({
        parameter: "U32",
        result: "Bool",
        call(value) {
          calls.push(value as number);
          return value === 3;
        },
      });
      equal(guest.call("stop", host), 3);
      assert.deepEqual(calls, [0, 1, 2, 3]);
      calls.length = 0;
      equal(guest.call("prefix", host), 7);
      assert.deepEqual(calls, [7]);
      const failing = guest.capability({
        parameter: "U32",
        result: "Bool",
        call() {
          throw new Error("prefix effect");
        },
      });
      assert.throws(() => guest.call("prefix", failing));
      equal(guest.call("prefix", host), 7);
    },
  );
});
