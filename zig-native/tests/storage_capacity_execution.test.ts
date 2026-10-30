import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("owner reservations preserve lengths and borrows without enlarging neighboring pools", async () => {
  await compileAndRun(
    `
entry const answer = func (overflow: Bool): Array U32 => return do:
  let large: GrowArray U32 = #[41]
  let small: ResizeArray U32 = #[1, 2, 3]
  let alias = large
  let first = &large[0..1]
  @storage.reserve alias 300001
  @storage.reserve large 1
  @storage.reserve small 0
  for index in 0 .. 300000:
    @storage.push large index
  if overflow:
    @storage.push small 4
    @storage.push small 5
  return #[large.length + first[0] + small.length]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const memory = new WebAssembly.Instance(module)
        .exports["blot:memory"] as WebAssembly.Memory;
      assert(memory.buffer.byteLength < 5 * 1024 * 1024);
      assert.deepEqual(Array.from(guest.call("answer", false) as Uint32Array), [
        300045,
      ]);
      assert.throws(() => guest.call("answer", true), WebAssembly.RuntimeError);
      assert.deepEqual(Array.from(guest.call("answer", false) as Uint32Array), [
        300045,
      ]);
    },
  );
});

Deno.test("owner reservation counts require literal provenance and checked Wasm32 sizes", async () => {
  await compileExpectedFailure(
    `
entry const invalid = func (count: U32) => return do:
  let rows: GrowArray U32 = #[]
  @storage.reserve rows count
  return rows.length
`,
    "literal_required",
  );
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

Deno.test("fixed application literals reserve their actual extent and remain independent", async () => {
  const names = Array.from({ length: 12 }, (_, index) => `slot_${index}`);
  const declarations = names.map((name, index) =>
    `const ${name}: Array U32 = #[${index}]`
  ).join("\n");
  await compileAndRun(
    `${declarations}
entry const answer = func (): Array U32 => return do:
  let current = slot_0
  current[0] := current[0] + 1
  return #[${names.map((name) => `${name}[0]`).join(" + ")}]
`,
    (guest, bytes) => {
      const module = new WebAssembly.Module(bytes);
      const memory = new WebAssembly.Instance(module)
        .exports["blot:memory"] as WebAssembly.Memory;
      // One temporary region and transport, rather than twelve default 1 MiB
      // persistent lanes for twelve single-word state cells.
      assert(memory.buffer.byteLength < 4 * 1024 * 1024);
      assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
        67,
      ]);
      assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
        68,
      ]);
    },
  );
});
