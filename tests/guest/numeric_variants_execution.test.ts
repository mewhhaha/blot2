import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `type Choice is data = $Empty | $One U32 | $Pair {x: U32, y: U32}
const make = func (i: U32) : Choice => return if i % 3 == 0 then $Empty else if i % 3 == 1 then $One i else $Pair {x: i, y: i + 10}
const read = func (v: Choice) : U32 => return case v of
  $Empty => 0
  $One n => n
  $Pair (x, y) => x + y
entry const mixed = func (count: U32) => return do:
  let values = @array.generate count make
  let sum = 0
  for value in values:
    sum := self + read value
  break sum
entry const list = func (index: U32) => return do:
  let values = @list.generate 513 make
  let cursor = @list.cursor values
  for step in 0..index:
    cursor := @cursor.advance cursor
  break read (@cursor.value cursor)
entry const saved = func (index: U32) => return do:
  let values = @array.generate 513 make
  let old = values
  values[index] = $Pair {x: 100, y: 200}
  break read old[index] + read values[index]
entry const static_values = func (index: U32) => return do:
  let values = #[$Empty, $One 7, $Pair {x: 2, y: 3}]
  break read values[index]
entry const conversions = func (index: U32) => return do:
  let values = @array.generate 700 make
  let middle = @array.slice values 17 600
  let tree = @list.from_array middle
  let selected = @list.slice tree 63 513
  let copied = @array.from_list selected
  break read copied[index]
entry const callback = func (index: U32) => return do:
  let values = @array.generate 513 make
  let selected = values[index]
  let callbacks = #[func (ignored: U32) => return read selected]
  break callbacks[0] 0
type Nested is data = $Wrapped Choice | $Scalar U32
type FloatChoice is data = $NoFloat | $Float F32
entry const absent_escape = func (count: U32) => return do:
  let values = @array.generate count (func (i: U32) : Choice => return $Empty)
  let saved = values
  let copy = @array.generate count (func i => return saved[i])
  break copy.length
entry const anonymous = func (seed: U32) => return do:
  let values = @array.generate 2000 (func (i: U32) : Choice => return if i % 2 == 0 then $One seed else $Empty)
  let sum = 0
  for value in values:
    sum := self + read value
  break sum
entry const nested = func (count: U32) => return do:
  let values = @array.generate count (func (i: U32) : Nested => return if i % 2 == 0 then $Wrapped (if i % 4 == 0 then $Empty else $One i) else $Scalar i)
  let sum = 0
  for value in values:
    sum := self + case value of
      $Wrapped ($Empty) => 0
      $Wrapped ($One n) => n
      $Wrapped ($Pair (x, y)) => x + y
      $Scalar n => n
  break sum
entry const floating = func (seed: F32) => return do:
  let values = @array.generate 3 (func (i: U32) : FloatChoice => return if i == 1 then $NoFloat else $Float seed)
  let result = @array.fill 3 1.0
  for i in 0..3:
    result[i] := case values[i] of
      $NoFloat => 0.0
      $Float n => n
  break result
`;
Deno.test(`numeric variants preserve active arms lists static values and snapshots`, async () => {
  const directory = await Deno.makeTempDir({
    prefix: "blot-numeric-variants-",
  });
  const entry = `${directory}/main.blot`;
  const compiler = await createZigProjectCompiler({
    executable: Deno.args[0],
    entry,
    prelude: new URL("../../std/prelude.blot", import.meta.url),
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    const guest = await instantiateGuest(built.bytes);
    const read = (i: number) =>
      i % 3 === 0 ? 0 : i % 3 === 1 ? i : i * 2 + 10;
    try {
      for (
        const count of [0, 1, 2, 3, 80, 81, 82, 243, 244, 245, 513, 2000]
      ) {
        assert.equal(
          guest.call("mixed", count),
          Array.from({ length: count }, (_, i) => read(i)).reduce(
            (a, b) => a + b,
            0,
          ),
        );
      }
      for (const i of [0, 1, 2, 80, 81, 82, 243, 244, 245, 512]) {
        assert.equal(guest.call("list", i), read(i));
        // `old` aliases `values`, so both read the write (tasks/LANGUAGE_COHERENCE.md A7).
        assert.equal(guest.call("saved", i), 600);
        assert.equal(guest.call("conversions", i), read(i + 80));
        assert.equal(guest.call("callback", i), read(i));
      }
      for (const seed of [0, 1, 73]) {
        assert.equal(guest.call("anonymous", seed), seed * 1000);
      }
      assert.equal(guest.call("absent_escape", 2000), 2000);
      for (const count of [0, 1, 2, 3, 32, 513]) {
        assert.equal(
          guest.call("nested", count),
          Array.from({ length: count }, (_, i) => i % 4 === 0 ? 0 : i).reduce(
            (a, b) => a + b,
            0,
          ),
        );
      }
      for (const seed of [-0, 0, 1.5, Infinity, -Infinity, NaN]) {
        const actual = guest.call("floating", seed) as Float32Array;
        const expected = Float32Array.of(seed, 0, seed);
        assert.deepEqual(
          new Uint32Array(actual.buffer, actual.byteOffset, actual.length),
          new Uint32Array(expected.buffer),
        );
      }
      for (const [i, expected] of [0, 7, 5].entries()) {
        assert.equal(guest.call("static_values", i), expected);
      }
    } finally {
      guest.dispose();
    }
  } finally {
    await compiler.dispose();
    await Deno.remove(directory, { recursive: true });
  }
});
