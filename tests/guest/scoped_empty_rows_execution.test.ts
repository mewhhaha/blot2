import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const source = `
type Row is data = $Row {text: &[U32]}
type Plain is data = $Plain {amount: U32}
const append = func (rows: own Array Row) -> (text: &[U32]): Array Row => return do:
  @storage.push rows ($Row {text})
  return rows
const consume = func (row: Row): U32 => return row.text.at 0
io const empty = func (count: U32): U32 => return do:
  let rows: Array Row = #[]
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
io const seeded = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: Array Row = #[]
  if count > 0:
    @storage.push rows ($Row {text: &labels[0..1]})
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
io const joined = func (choose: U32): U32 => return do:
  let first: Array Row = #[]
  let second: Array Row = #[]
  let rows = if choose == 0 then first else second
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
io const mixed = func (choose: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let first: Array Row = #[]
  let second: Array Row = #[$Row {text: &labels[0..1]}]
  let rows = if choose == 0 then first else second
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
io const alias_write = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65]
  let rows: Array Row = #[]
  for index in 0 .. count:
    rows := append self (&labels[0..1])
  let total = 0
  for row in rows:
    for code in row.text:
      total := self + code
  return total
io const skipped = func (index_effect: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let labels: Array U32 = #[65]
  let rows: Array Row = #[]
  if false:
    use idx <- index_effect 0
    let row = rows[idx]
    return row.text.at 0
  @storage.push rows ($Row {text: &labels[0..1]})
  return rows[0].text.at 0
io const direct = func (index_effect: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let rows: Array Row = #[]
  use idx <- index_effect 0
  return rows[idx].text.at 0
io const pattern = func (index_effect: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let rows: Array Row = #[]
  use idx <- index_effect 0
  let $Row {text} = rows[idx]
  return text.at 0
io const argument = func (index_effect: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let rows: Array Row = #[]
  use idx <- index_effect 0
  return consume rows[idx]
io const record = func (index_effect: U32 -> U32 ! {Foreign}): U32 ! {Foreign} => return do:
  let rows: Array Row = #[]
  use idx <- index_effect 0
  let stored = {row: rows[idx]}
  return stored.row.text.at 0
io const array = func (index_effect: U32 -> U32 ! {Foreign}): Array U32 ! {Foreign} => return do:
  let rows: Array Row = #[]
  use idx <- index_effect 0
  return #[rows[idx].text.at 0]
io const copied = func (): U32 => return do:
  let rows: Array Row = #[]
  let copy = @storage.copy rows
  return copy.length
io const plain = func (count: U32): U32 => return do:
  let rows: Array Plain = #[]
  let total = 0
  for index in 0 .. count:
    if index > 0:
      total := self + rows[0].amount
    @storage.push rows ($Plain {amount: index + 1})
  return total
`;

Deno.test(`empty borrowed row traversal preserves zero-iteration flow and bounds traps`, async () => {
  const directory = await Deno.makeTempDir({ prefix: "blot-empty-rows-" });
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(entry, source);
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
  });
  try {
    const result = await compiler.build();
    assert(result.success, JSON.stringify(result));
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      const call = (name: string, value: unknown) =>
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
        let effects = 0;
        let currentIndex = 0;
        const indexEffect = guest.capability({
          parameter: "U32",
          result: "U32",
          call: () => {
            effects++;
            return currentIndex;
          },
        });
        assert.equal(await call("skipped", indexEffect), 65);
        assert.equal(await call("copied", null), 0);
        assert.equal(effects, 0);
        for (
          const name of ["direct", "pattern", "argument", "record", "array"]
        ) {
          for (const index of [0, 1, 0xFFFFFFFF]) {
            currentIndex = index;
            let trapped = false;
            try {
              await call(name, indexEffect);
            } catch (error) {
              assert(error instanceof WebAssembly.RuntimeError);
              trapped = true;
            }
            assert(trapped);
          }
        }
        assert.equal(effects, 15);
        assert.equal(await call("seeded", 1), 65);
        assert.equal(await call("empty", 0), 0);
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
