import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

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
  values[index] := $Pair {x: 100, y: 200}
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
for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`numeric variants preserve active arms lists static values and snapshots (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-numeric-variants-",
    });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const invoke = (count: number) => {
        (raw["blot:ownership_enter"] as CallableFunction)();
        const value = (raw.mixed as CallableFunction)(count);
        (raw["blot:ownership_leave"] as CallableFunction)(0);
        return value;
      };
      invoke(0);
      const retired = () =>
        Number((raw["blot:rc_destroyed"] as WebAssembly.Global).value) >>> 0;
      const before = retired();
      invoke(2000);
      assert.equal(
        retired() - before,
        1,
        "mixed row generation and scalar matching allocate only the output Array",
      );
      const emptyBefore = retired();
      (raw["blot:ownership_enter"] as CallableFunction)();
      assert.equal((raw.absent_escape as CallableFunction)(2000), 2000);
      (raw["blot:ownership_leave"] as CallableFunction)(0);
      assert(
        retired() - emptyBefore <= 3,
        `empty variants remain immortal when materialized through an escaping producer: ${
          retired() - emptyBefore
        } retirements (two Arrays and one captured callback)`,
      );
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
          assert.equal(guest.call("saved", i), read(i) + 300);
          assert.equal(guest.call("conversions", i), read(i + 80));
          assert.equal(guest.call("callback", i), read(i));
        }
        for (const seed of [0, 1, 73]) {
          assert.equal(guest.call("anonymous", seed), seed * 1000);
        }
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
}

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`tagged numeric rows preserve optional and selected-reader allocation budgets (${codegenTier})`, async () => {
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry: new URL(
        "../../benchmarks/runtime-boundaries/main.blot",
        import.meta.url,
      ),
      prelude: new URL("../../std/prelude.blot", import.meta.url),
      stdRoot: new URL("../../std", import.meta.url),
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build();
      assert(built.success, JSON.stringify(built));
      const raw =
        new WebAssembly.Instance(new WebAssembly.Module(built.bytes)).exports;
      const retired = () =>
        Number((raw["blot:rc_destroyed"] as WebAssembly.Global).value) >>> 0;
      for (const count of [0, 1, 2, 32, 2000]) {
        const before = retired();
        (raw["blot:ownership_enter"] as CallableFunction)();
        assert.equal(
          (raw.optional_generate as CallableFunction)(count),
          count * (count + 1) / 2,
        );
        (raw["blot:ownership_leave"] as CallableFunction)(0);
        assert.equal(
          retired() - before,
          1,
          "only final Array storage is retired",
        );
      }
      // Reconstructing an unguarded row must still initialize its own local
      // before publishing aliases, so existing selected-reader SROA survives.
      for (const steps of [2, 100, 101]) {
        const before = retired();
        (raw["blot:ownership_enter"] as CallableFunction)();
        assert.equal(
          (raw.selected as CallableFunction)(steps),
          2_001_000 * steps,
        );
        (raw["blot:ownership_leave"] as CallableFunction)(0);
        if (codegenTier === "optimized") assert.equal(retired() - before, 1);
        assert.equal(
          Number((raw["blot:rc_roots"] as WebAssembly.Global).value),
          0,
        );
        assert.equal(
          Number((raw["blot:rc_leases"] as WebAssembly.Global).value),
          0,
        );
      }
    } finally {
      await compiler.dispose();
    }
  });
}
