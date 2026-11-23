import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("owner reservations preserve lengths and borrows of neighboring pools", async () => {
  await compileAndRun(
    `
entry const answer = func (overflow: Bool): Array U32 => return do:
  let large: GrowArray U32 = #[41]
  let small: ResizeArray U32 = #[1, 2, 3]
  @storage.reserve large 300001
  @storage.reserve large 1
  @storage.reserve small 0
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
      // A reservation imposes no logical-length limit, so pushing past a zero
      // request grows the pool.
      assert.deepEqual(Array.from(guest.call("answer", true) as Uint32Array), [
        300047,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", false) as Uint32Array), [
        300045,
      ]);
    },
  );
});

Deno.test("owner reservation counts require literal provenance", async () => {
  await compileExpectedFailure(
    `
entry const invalid = func (count: U32) => return do:
  let rows: GrowArray U32 = #[]
  @storage.reserve rows count
  return rows.length
`,
    "literal_required",
  );
});

// Direct backend: storage_unsupported for a reservation beyond Wasm32 memory; it returns 0 instead (tasks/DELETE_SCOPED.md).
Deno.test.ignore("owner reservation counts require checked Wasm32 sizes", async () => {
  await compileExpectedFailure(
    `
entry const invalid = func () => return do:
  let rows: GrowArray U32 = #[]
  @storage.reserve rows 4294967295
  return rows.length
`,
    "storage_unsupported",
    "Array capacity exceeds the Wasm32 storage plan",
  );
});

Deno.test("fixed application literals remain independent", async () => {
  const names = Array.from({ length: 12 }, (_, index) => `slot_${index}`);
  const declarations = names.map((name, index) =>
    index === 0
      ? `const ${name}: GrowArray U32 = #[${index}]`
      : `const ${name}: Array U32 = #[${index}]`
  ).join("\n");
  await compileAndRun(
    `${declarations}
entry const answer = func (): Array U32 => return do:
  @storage.push slot_0 1
  return #[slot_0.length - 1 + ${names.slice(1).map((name) => `${name}[0]`).join(" + ")}]
`,
    (guest) => {
      assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
        67,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
        68,
      ]);
    },
  );
});
