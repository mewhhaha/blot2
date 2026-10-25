import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source =
  `type Row is data = #Row {a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32, i: U32}
type Vector is data = #Vector {x: F32, y: F32}
type Nested is data = #Nested {head: {value: Vector, stamp: U32}, tail: U32}
const row = fn index => #Row {a: index, b: 2, c: 3, d: 4, e: @u32.add index 7, f: 6, g: 7, h: 8, i: 9}
entry const array = fn (index: U32) => (@array.generate 513 row)[index].e
entry const list = fn (index: U32) => do:
  let cursor = @list.cursor (@list.generate 513 row)
  for step in 0..index:
    cursor := @cursor.advance cursor
  break (@cursor.value cursor).e
entry const snapshot = fn (index: U32) => do:
  let values = @array.generate 513 row
  let old = values
  values[index].e := 1000
  break @u32.add old[index].e values[index].e
entry const nested_bits = fn (value: F32) => do:
  let rows = @array.fill 2 (#Nested {head: {value: #Vector {x: value, y: 2.0}, stamp: 3}, tail: 4})
  break #[rows[1].head.value.x, rows[0].head.value.y]
entry const escaped = fn (value: F32) => do:
  let rows = @list.fill 2 (#Nested {head: {value: #Vector {x: value, y: 2.0}, stamp: 3}, tail: 4})
  let selected = (@cursor.value (@list.cursor rows)).head
  break #[selected.value.x, selected.value.y]
entry const checked_index = fn (divisor: U32) => (@array.fill 1 (#Row {a: 1, b: 2, c: 3, d: 4, e: 7, f: 6, g: 7, h: 8, i: 9}))[@u32.div 0 divisor].e
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`indexed numeric projections preserve bounds snapshots nested escapes and bits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-indexed-rows-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        for (
          const index of [0, 1, 26, 27, 31, 32, 33, 243, 244, 255, 256, 512]
        ) {
          assert.equal(guest.call("array", index), index + 7);
          assert.equal(guest.call("list", index), index + 7);
          assert.equal(guest.call("snapshot", index), index + 1007);
        }
        for (const entry of ["array", "list", "snapshot"]) {
          for (const index of entry === "list" ? [513] : [513, 0xffffffff]) {
            assert.throws(
              () => guest.call(entry, index),
              WebAssembly.RuntimeError,
            );
          }
          assert.equal(guest.call(entry, 1), entry === "snapshot" ? 1008 : 8);
        }
        assert.throws(
          () => guest.call("checked_index", 0),
          WebAssembly.RuntimeError,
        );
        assert.equal(guest.call("checked_index", 1), 7);
        for (const value of [-0, 0, 1.5, -1000, Infinity, -Infinity]) {
          const expected = Float32Array.of(value, 2);
          for (const entry of ["nested_bits", "escaped"]) {
            const actual = guest.call(entry, value) as Float32Array;
            assert.deepEqual(
              new Uint32Array(actual.buffer, actual.byteOffset, actual.length),
              new Uint32Array(expected.buffer),
            );
          }
        }
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
