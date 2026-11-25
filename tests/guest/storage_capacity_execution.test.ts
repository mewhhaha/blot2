import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("dynamic array growth preserves lengths and borrows of neighboring pools", async () => {
  await compileAndRun(
    `
#entry const answer = func (overflow: Bool): Array U32 => return do:
  let large: Array U32 = #[41]
  let small: Array U32 = #[1, 2, 3]
  for index in 0 .. 300000:
    @storage.push large index
  if overflow:
    @storage.push small 4
    @storage.push small 5
  let first = &large[0..1]
  return #[large.length + first[0] + small.length]
`,
    (guest) => {
      assert.deepEqual(Array.from(guest.call("answer", false) as Uint32Array), [
        300045,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", true) as Uint32Array), [
        300047,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", false) as Uint32Array), [
        300045,
      ]);
    },
  );
});

Deno.test("retired @storage.reserve is rejected as unknown_intrinsic", async () => {
  await compileExpectedFailure(
    `
#entry const invalid = func (count: U32) => return do:
  let rows: Array U32 = #[]
  @storage.reserve rows count
  return rows.length
`,
    "unknown_intrinsic",
  );
});

Deno.test("fixed application literals remain independent", async () => {
  const names = Array.from({ length: 12 }, (_, index) => `slot_${index}`);
  const declarations = names.map((name, index) =>
    `const ${name}: Array U32 = #[${index}]`
  ).join("\n");
  await compileAndRun(
    `${declarations}
#entry const answer = func (extra: U32): Array U32 => return do:
  let local = @storage.copy slot_0
  for i in 0 .. extra:
    @storage.push local i
  return #[local.length - 1 + ${names.slice(1).map((name) => `${name}[0]`).join(" + ")}]
`,
    (guest) => {
      assert.deepEqual(Array.from(guest.call("answer", 1) as Uint32Array), [
        67,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", 2) as Uint32Array), [
        68,
      ]);
    },
  );
});
