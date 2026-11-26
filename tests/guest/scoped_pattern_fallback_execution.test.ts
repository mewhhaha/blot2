import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const source = `
type Row is data = $Row {text: &[U32]}
const size = func collections: U32 => return do:
  let total = 0
  for item in collections.rows:
    let row: Row = item
    let text_length: U32 = row.text.length
    total := self + text_length
  return total
io const empty = func (count: U32): U32 => return do:
  let rows: Array Row = #[]
  return size {rows: &rows[0..rows.length]}
io const populated = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65, 66]
  let rows: Array Row = #[]
  if count > 0:
    @storage.push rows ($Row {text: &labels[0..2]})
  return size {rows: &rows[0..rows.length]}
io const joined = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65, 66]
  let first: Array Row = #[]
  let second: Array Row = #[$Row {text: &labels[0..2]}]
  let selected = if count == 0 then first else second
  return size {rows: &selected[0..selected.length]}
io const fallback_return = func (value: U32): Array U32 => return do:
  let ticks: Array U32 = #[]
  let absent: Maybe Row = $Nothing
  let $Some row = absent else:
    @storage.push ticks 1
    return #[value, @storage.length ticks]
  return #[row.text.at 0, @storage.length ticks]
io const fallback_break = func (count: U32): Array U32 => return do:
  let ticks: Array U32 = #[]
  for index in 0 .. count:
    let absent: Maybe Row = $Nothing
    let $Some row = absent else:
      @storage.push ticks 1
      break
    return #[row.text.at 0, @storage.length ticks]
  return #[42, @storage.length ticks]
io const fallback_continue = func (count: U32): Array U32 => return do:
  let ticks: Array U32 = #[]
  for index in 0 .. count:
    let absent: Maybe Row = $Nothing
    let $Some row = absent else:
      @storage.push ticks 1
      continue
    return #[row.text.at 0, @storage.length ticks]
  return #[42, @storage.length ticks]
io const evaluated = func (value: U32): Array U32 => return do:
  let ticks: Array U32 = #[]
  @storage.push ticks 1
  let needle = value
  let absent: Maybe U32 = $Nothing
  let second = do:
    @storage.push ticks 1
    break value
  let ($Some item, ^needle) = (absent, second) else:
    @storage.push ticks 1
    return #[99, @storage.length ticks]
  return #[item, @storage.length ticks]
io const dynamic = func (value: U32): Array U32 => return do:
  let ticks: Array U32 = #[]
  let candidate: Maybe U32 = if value == 0 then $Nothing else do:
    @storage.push ticks 1
    break $Some value
  let $Some item = candidate else:
    @storage.push ticks 1
    return #[99, @storage.length ticks]
  return #[item, @storage.length ticks]
`;

Deno.test(`refutable bindings preserve iterator and exiting fallback control flow`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-pattern-fallback-",
  });
  const entry = `${directory}/main.blot`;
  await Deno.writeTextFile(entry, source);
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
  });
  try {
    const result = await compiler.build();
    assert(
      result.success,
      !result.success ? JSON.stringify(result.diagnostics) : "",
    );
    for (const asynchronous of [false, true]) {
      const guest = await instantiateGuest(result.bytes, { asynchronous });
      const call = (name: string, value: number | null) =>
        asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
      try {
        for (const count of [0, 1, 4]) {
          assert.equal(await call("empty", count), 0);
          assert.equal(await call("populated", count), count === 0 ? 0 : 2);
          assert.equal(await call("joined", count), count === 0 ? 0 : 2);
          assert.deepEqual(
            await call("fallback_break", count),
            Uint32Array.of(42, count === 0 ? 0 : 1),
          );
          assert.deepEqual(
            await call("fallback_continue", count),
            Uint32Array.of(42, count),
          );
        }
        for (const value of [0, 1, 42, 0xFFFFFFFF]) {
          assert.deepEqual(
            await call("fallback_return", value),
            Uint32Array.of(value, 1),
          );
          assert.deepEqual(
            await call("evaluated", value),
            Uint32Array.of(99, 3),
          );
          assert.deepEqual(
            await call("dynamic", value),
            Uint32Array.of(value === 0 ? 99 : value, 1),
          );
        }
      } finally {
        guest.dispose();
      }
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
