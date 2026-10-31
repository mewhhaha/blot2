import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type Row is data = $Row {text: &[U32]}
type Plain is data = $Plain {amount: U32}
const effects: GrowArray U32 = #[0]
const index_effect = func (index: U32): U32 => return do:
  @storage.write (@storage.at effects 0) (effects[0] + 1)
  return index
const append = func (rows: ResizeArray Row) -> (text: &[U32]) => return rows.push ($Row {text})
const consume = func (row: Row): U32 => return row.text.at 0
entry const empty = func (count: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
entry const seeded = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: ResizeArray Row = #[]
  if count > 0:
    rows.push ($Row {text: &labels[0..1]})
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
entry const joined = func (choose: U32): U32 => return do:
  let first: ResizeArray Row = #[]
  let second: ResizeArray Row = #[]
  let rows = if choose == 0 then first else second
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
entry const mixed = func (choose: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let first: ResizeArray Row = #[]
  let second: ResizeArray Row = #[$Row {text: &labels[0..1]}]
  let rows = if choose == 0 then first else second
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
entry const alias_write = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: ResizeArray Row = #[]
  let alias = rows
  for index in 0 .. count:
    append alias (&labels[0..1])
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
entry const skipped = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: ResizeArray Row = #[]
  if count > 0:
    let row = rows[index_effect 0]
    return row.text.at 0
  rows.push ($Row {text: &labels[0..1]})
  return rows[0].text.at 0
entry const direct = func (index: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  return rows[index_effect index].text.at 0
entry const effect_count = func (): U32 => return effects[0]
entry const pattern = func (index: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  let $Row {text} = rows[index_effect index]
  return text.at 0
entry const argument = func (index: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  return consume rows[index_effect index]
entry const record = func (index: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  let stored = {row: rows[index_effect index]}
  return stored.row.text.at 0
entry const array = func (index: U32): Array U32 => return do:
  let rows: ResizeArray Row = #[]
  return #[rows[index_effect index].text.at 0]
entry const copied = func (): U32 => return do:
  let rows: ResizeArray Row = #[]
  let copy = @storage.copy rows
  return copy.length
entry const plain = func (count: U32): U32 => return do:
  let rows: ResizeArray Plain = #[]
  let total = 0
  for index in 0 .. count:
    if index > 0:
      total := self + rows[0].amount
    rows.push ($Plain {amount: index + 1})
  return total
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`empty borrowed row traversal preserves zero-iteration flow and bounds traps (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-empty-rows-" });
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const result = await compiler.build();
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = (name: string, value: number | null) =>
          asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
        try {
          for (const count of [0, 1, 4]) {
            assert.equal(await call("empty", count), 0);
            assert.equal(await call("seeded", count), count === 0 ? 0 : 65);
            assert.equal(await call("joined", count), 0);
            assert.equal(await call("mixed", count), count === 0 ? 0 : 65);
            assert.equal(await call("alias_write", count), count * 65);
            assert.equal(await call("plain", count), Math.max(0, count - 1));
          }
          assert.equal(await call("skipped", 0), 65);
          assert.equal(await call("copied", null), 0);
          assert.equal(await call("effect_count", null), 0);
          for (
            const name of ["direct", "pattern", "argument", "record", "array"]
          ) {
            for (const index of [0, 1, 0xFFFFFFFF]) {
              let trapped = false;
              try {
                await call(name, index);
              } catch (error) {
                assert(error instanceof WebAssembly.RuntimeError);
                trapped = true;
              }
              assert(trapped);
            }
          }
          assert.equal(await call("effect_count", null), 15);
          assert.equal(await call("seeded", 1), 65);
          assert.equal(await call("empty", 0), 0);
        } finally {
          guest.dispose();
        }
      }
      for (const exit of ["", "    continue\n"]) {
        const rejected = await compiler.build({
          sources: {
            [entry]: `${source}
entry const late = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: ResizeArray Row = #[]
  let total = 0
  for index in 0 .. count:
    if index > 0:
      for row in rows:
        for code in row.text:
          total := self + code
    append rows (&labels[0..1])
${exit}  return total
`,
          },
        });
        assert(!rejected.success);
        assert.equal(rejected.diagnostics[0].code, "storage_escape");
        assert.equal(
          rejected.diagnostics[0].message,
          "A loop cannot widen stored variants or borrowed roots after reading them; write the complete shape before its first read",
        );
        assert.equal("bytes" in rejected, false);
      }
      const recovered = await compiler.build();
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, result.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
