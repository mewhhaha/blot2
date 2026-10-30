import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("record merge preserves owner roots and known callbacks with right wins", async () => {
  await compileAndRun(
    `
const overlay = func base -> replacement => return @record.merge base replacement
entry const answer = func () => return do:
  let original: Array U32 = #[11]
  let scratch: Array U32 = #[23]
  let order: Array U32 = #[0]
  let base = {owner: original, view: &original[0..1], retained: 7,
    operation: func (value: U32) => return value + 1}
  let left = func () => return do:
    order[0] := self * 10 + 1
    return base
  let right = func () => return do:
    order[0] := self * 10 + 2
    return {owner: scratch, view: &scratch[0..1], added: 9,
      operation: func (value: U32) => return value + 5}
  let merged = overlay (left ()) (right ())
  merged.owner[0] := 31
  return #[order[0], merged.retained, merged.added, merged.view[0],
    merged.operation 10, base.operation 10, base.owner[0], base.view[0], scratch[0]]
`,
    (guest) => {
      const expected = new Uint32Array([12, 7, 9, 31, 15, 11, 11, 11, 31]);
      assert.deepEqual(guest.call("answer", null), expected);
      assert.deepEqual(guest.call("answer", null), expected);
    },
  );
});

Deno.test("record merge cannot hide a borrowed scratch view escaping its scope", async () => {
  await compileExpectedFailure(
    `
entry const answer = func (): U32 => return do:
  let original: Array U32 = #[11]
  let base = {view: &original[0..1], retained: 7}
  let escaped = do:
    let scratch: Array U32 = #[23]
    break @record.merge base {view: &scratch[0..1], added: 9}
  return escaped.view[0]
`,
    "storage_escape",
  );
});
