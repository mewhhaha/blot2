import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("checked scalar ranges keep source bounds, early exits and visible writes", async () => {
  await compileAndRun(
    `
func half (values: Array U32): U32 => return values.length / 2
io scan (values: Array U32): U32 => do:
  let sum = 0
  for i in 0..values.length:
    sum := self + values[i]
  return sum
io suffix (values: Array U32): U32 => do:
  let sum = 0
  for i in 3..@array.length values:
    sum := self + values[i]
  return sum
io prefix (values: Array U32): U32 => do:
  let sum = 0
  for i in 0..(half values):
    sum := self + values[i]
  return sum
io stop (values: Array U32): U32 => do:
  let sum = 0
  for i in 0..values.length:
    if values[i] == 7:
      break
    sum := self + values[i]
  return sum
io replace (values: own Array U32): U32 => do:
  let sum = 0
  for i in 0..values.length:
    values[i] := values[i] + 1
    sum := self + values[i]
  return sum
io next (values: Array U32): U32 => do:
  let sum = 0
  for i in 0..values.length:
    sum := self + values[i + 1]
  return sum
`,
    (guest) => {
      for (const words of [[], [2], [1, 2, 7, 9], [0xffffffff, 4]]) {
        const input = Uint32Array.from(words);
        const sum = (items: number[]) =>
          items.reduce((a, b) => (a + b) >>> 0, 0);
        assert.equal(guest.call("scan", input), sum(words));
        assert.equal(guest.call("suffix", input), sum(words.slice(3)));
        assert.equal(
          guest.call("prefix", input),
          sum(words.slice(0, words.length >>> 1)),
        );
        let stop = words.indexOf(7);
        if (stop < 0) stop = words.length;
        assert.equal(guest.call("stop", input), sum(words.slice(0, stop)));
        assert.equal(
          guest.call("replace", input),
          (sum(words) + words.length) >>> 0,
        );
        if (words.length) {
          assert.throws(
            () => guest.call("next", input),
            WebAssembly.RuntimeError,
          );
        } else {
          assert.equal(guest.call("next", input), 0);
        }
        assert.equal(guest.call("scan", input), sum(words));
      }
    },
  );
});

Deno.test("an array length member supplied by a prelude keeps its own semantics", async () => {
  const prelude = await Deno.readTextFile(
    new URL("../../std/prelude.sq", import.meta.url),
  );
  const standard =
    "func Array.length (values: #[a]): U32 => @array.length values";
  assert.ok(prelude.includes(standard));
  const file = await Deno.makeTempFile({ suffix: ".sq" });
  try {
    await Deno.writeTextFile(
      file,
      prelude.replace(
        standard,
        standard.replace("@array.length values", "(@array.length values) / 2"),
      ),
    );
    await compileAndRun(
      `
io scan (values: Array U32): U32 => do:
  let sum = 0
  for i in 0..values.length:
    sum := self + values[i]
  return sum
`,
      (guest) =>
        assert.equal(guest.call("scan", Uint32Array.of(1, 2, 4, 8)), 3),
      { prelude: file },
    );
  } finally {
    await Deno.remove(file);
  }
});
