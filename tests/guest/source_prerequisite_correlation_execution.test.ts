import { strict as assert } from "node:assert";
import { compileAndRun } from "./compile_helpers.ts";

Deno.test("pool projection prerequisites keep structural and nominal codec elements distinct", async () => {
  await compileAndRun(
    `
type Appearance is data = $Appearance {mesh: U32, material: U32}
type Stored is data = $Stored {start: U32, count: U32}
type Codec a is data = $Codec {encode: a -> Array U32}
type StoredCodec = {encode: Stored -> Array U32}
const appearance_codec = $Codec {encode: func (value: Appearance) => return #[value.mesh, value.material]}
const stored_codec = func (offset: Array U32): StoredCodec => return {
  encode: func (value: Stored) => return #[value.start + offset[0], value.count]}
const append_pool = func codec -> pool -> (destination: ResizeArray U32) => return do:
  let read: U32 -> Maybe a = pool.at
  let encode: a -> Array U32 = codec.encode
  for id in 0 .. pool.length:
    if let $Some value = read id:
      let encoded = encode value
      for word in encoded:
        destination.push word
const write_component = func codec -> pool -> destination => return
  append_pool codec pool destination
const write_stored = func access -> destination => return
  write_component (stored_codec access.offset) access.stored destination
const write = func access -> destination => return do:
  write_stored access destination
  write_component appearance_codec access.appearance destination
  write_stored access destination
entry const answer = func (offset: U32) => return do:
  let stored: ResizeArray (Maybe Stored) = #[$Some ($Stored {start: 7, count: 3}), $Nothing]
  let appearance: ResizeArray (Maybe Appearance) = #[$Nothing, $Some ($Appearance {mesh: 41, material: 19})]
  let offsets: Array U32 = #[offset]
  let output: ResizeArray U32 = #[]
  write {stored, appearance, offset: offsets} output
  return @storage.freeze output
`,
    (guest) => {
      assert.deepEqual(
        guest.call("answer", 100),
        new Uint32Array([107, 3, 41, 19, 107, 3]),
      );
      assert.deepEqual(
        guest.call("answer", 200),
        new Uint32Array([207, 3, 41, 19, 207, 3]),
      );
    },
  );
});
