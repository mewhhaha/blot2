import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const source = `entry const copied = func (input: U32): Array U32 => return do:
  let rows: Array U32 = #[input, 7, 9]
  for index in 1 .. 3:
    rows[index] := rows[@u32.sub index 1]
  rows[1] := @u32.add self 5
  return rows
entry const self_value = func (input: U32): U32 => return do:
  let rows: Array U32 = #[@u32.add input 9]
  rows[0] := @u32.add self 5
  return rows[0]
entry const floats = func (input: F32): Array F32 => return do:
  let (negative_zero, nan, _, _) = @simd.u32x4.from_bits (0x80000000, 0x7fc01234, 0, 0)
  let rows: Array F32 = #[input, 0.0, 0.0, negative_zero, nan]
  rows[1] := rows[3]
  rows[2] := rows[4]
  return rows
entry const booleans = func (input: Bool): Bool => return do:
  let rows: Array Bool = #[input, false, true]
  rows[1] := rows[2]
  rows[1] := self and true
  if rows[0]:
    if rows[1]:
      return false
    return true
  return rows[1]
const target: Array U32 = #[9]
entry const rhs_trap = func (denominator: U32): U32 => return do:
  let rows = target
  rows[0] := @u32.div 42 denominator
  return rows[0]
entry const read = func (): U32 => return target[0]
entry const destination_first = func (index: U32): U32 => return do:
  let rows = target
  rows[index] := @u32.div 42 (@u32.sub index 1)
  return rows[0]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scalar replacements preserve aliases self bits and destination-before-RHS traps (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({
      prefix: "blot-scalar-replacements-",
    });
    const entry = `${directory}/main.blot`;
    const stdRoot = new URL("../../std", import.meta.url).pathname;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      stdRoot,
      prelude: `${stdRoot}/prelude.blot`,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({ sources: { [entry]: source } });
      assert(built.success, JSON.stringify(built));
      const counters = built.stats.workCounters as Record<string, number>;
      assert(
        counters.scoped_scalar_old_loads_avoided > 0,
        JSON.stringify(counters),
      );
      assert.equal(counters.scoped_merge_loops, 0);
      assert.equal(counters.scoped_bulk_copies, 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        const call = async (name: string, input: unknown = null) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          for (const input of [0, 7, 0xffffffff]) {
            assert.deepEqual(
              await call("copied", input),
              new Uint32Array([input, (input + 5) >>> 0, input]),
            );
            assert.equal(await call("self_value", input), (input + 14) >>> 0);
          }
          const floats = await call("floats", 1.25) as Float32Array;
          assert.equal(floats[0], 1.25);
          assert(Object.is(floats[1], -0));
          assert.equal(
            new Uint32Array(floats.buffer, floats.byteOffset, floats.length)[2],
            0x7fc01234,
          );
          assert.equal(await call("booleans", true), false);
          assert.equal(await call("booleans", false), true);
          await assert.rejects(
            () => call("rhs_trap", 0),
            WebAssembly.RuntimeError,
          );
          assert.equal(await call("read"), 9);
          await assert.rejects(() => call("destination_first", 1), {
            name: "RuntimeError",
            message: /unreachable/,
          });
          assert.equal(await call("read"), 9);
          assert.equal(await call("rhs_trap", 2), 21);
          assert.equal(await call("read"), 21);
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
