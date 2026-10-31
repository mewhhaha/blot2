import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
type Row is data = $Row {text: &[U32]}
const size = func collections: U32 => return do:
  let total = 0
  for item in collections.rows:
    let row: Row = item
    let text_length: U32 = row.text.length
    total := self + text_length
  return total
const effects: GrowArray U32 = #[0]
const tick = func (value: U32): U32 => return do:
  @storage.write (@storage.at effects 0) (effects[0] + 1)
  return value
entry const empty = func (count: U32): U32 => return do:
  let rows: ResizeArray Row = #[]
  return size {rows: &rows[0..rows.length]}
entry const populated = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65, 66]
  let rows: ResizeArray Row = #[]
  if count > 0:
    rows.push ($Row {text: &labels[0..2]})
  return size {rows: &rows[0..rows.length]}
entry const joined = func (count: U32): U32 => return do:
  let labels: Array U32 = #[65, 66]
  let first: ResizeArray Row = #[]
  let second: ResizeArray Row = #[$Row {text: &labels[0..2]}]
  let selected = if count == 0 then first else second
  return size {rows: &selected[0..selected.length]}
entry const fallback_return = func (value: U32): U32 => return do:
  let absent: Maybe Row = $Nothing
  let $Some row = absent else:
    return tick value
  return row.text.at 0
entry const fallback_break = func (count: U32): U32 => return do:
  for index in 0 .. count:
    let absent: Maybe Row = $Nothing
    let $Some row = absent else:
      tick index
      break
    return row.text.at 0
  return 42
entry const fallback_continue = func (count: U32): U32 => return do:
  for index in 0 .. count:
    let absent: Maybe Row = $Nothing
    let $Some row = absent else:
      tick index
      continue
    return row.text.at 0
  return 42
entry const evaluated = func (value: U32): U32 => return do:
  let needle = tick value
  let absent: Maybe U32 = $Nothing
  let ($Some item, ^needle) = (absent, tick value) else:
    return tick 99
  return item
entry const dynamic = func (value: U32): U32 => return do:
  let candidate: Maybe U32 = if value == 0 then $Nothing else $Some (tick value)
  let $Some item = candidate else:
    return tick 99
  return item
entry const effect_count = func (): U32 => return effects[0]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`refutable bindings preserve iterator and exiting fallback control flow (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-pattern-fallback-",
    });
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
      assert(
        result.success,
        !result.success ? JSON.stringify(result.diagnostics) : "",
      );
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = (name: string, value: number | null) =>
          asynchronous ? guest.callAsync(name, value) : guest.call(name, value);
        let effects = 0;
        try {
          for (const count of [0, 1, 4]) {
            assert.equal(await call("empty", count), 0);
            assert.equal(await call("populated", count), count === 0 ? 0 : 2);
            assert.equal(await call("joined", count), count === 0 ? 0 : 2);
            assert.equal(await call("fallback_break", count), 42);
            effects += count === 0 ? 0 : 1;
            assert.equal(await call("fallback_continue", count), 42);
            effects += count;
            assert.equal(await call("effect_count", null), effects);
          }
          for (const value of [0, 1, 42, 0xFFFFFFFF]) {
            assert.equal(await call("fallback_return", value), value);
            effects++;
            assert.equal(await call("evaluated", value), 99);
            effects += 3;
            assert.equal(
              await call("dynamic", value),
              value === 0 ? 99 : value,
            );
            effects++;
            assert.equal(await call("effect_count", null), effects);
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
}
