import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const source =
  `const change = func (row: {a: U32, b: U32, c: U32, d: U32, e: U32, f: U32}) -> (_: U32) => return do:
  row.a := @u32.add self 1
  return row
const keep = func row -> (_: U32) => return row
const tick = func (audit: Array U32): U32 => return do:
  audit[0] := @u32.add self 1
  return audit[0]
const stop = func (value: U32): U32 => return do:
  use @panic "unused argument still traps"
  return value
const change_float = func (row: {a: F32, b: F32, c: F32, d: F32, e: F32, f: F32}) -> (_: U32) => return do:
  row.a := @f32.neg self
  return row
entry const answer = func (input: U32): Array U32 => return do:
  let audit: Array U32 = #[0]
  let before = {a: input, b: @u32.add input 2, c: @u32.add input 3, d: @u32.add input 4, e: @u32.add input 5, f: @u32.add input 6}
  let changed = change before (tick audit)
  let echoed = keep changed (tick audit)
  return #[before.a, echoed.a, echoed.b, echoed.c, echoed.d, echoed.e, echoed.f, audit[0]]
entry const trapped = func (input: U32): U32 => return do:
  let marker: Array U32 = #[input]
  let echoed = keep {a: marker[0], b: 2, c: 3, d: 4, e: 5, f: 6} (stop input)
  return echoed.a
entry const floating = func (bits: U32): Array U32 => return do:
  let audit: Array U32 = #[0]
  let (input, ignored_a, ignored_b, ignored_c) = @simd.u32x4.from_bits (bits,bits,bits,bits)
  let before = {a: input, b: input, c: input, d: input, e: input, f: input}
  let changed = change_float before (tick audit)
  let (a,b,c,d) = @simd.f32x4.bits (changed.a,changed.b,changed.c,changed.d)
  let (e,f,g,h) = @simd.f32x4.bits (changed.e,changed.f,before.a,before.b)
  return #[a,b,c,d,e,f,g,h,audit[0]]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`direct inputs retain aliased results eager arguments and F32 bits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-direct-input-" });
    const entry = `${directory}/main.blot`;
    const compiler = await createZigProjectCompiler({
      executable: Deno.args[0],
      entry,
      prelude: null,
      cacheDirectory: false,
      codegenTier,
    });
    try {
      const built = await compiler.build({
        sources: { [entry]: source },
        signal: AbortSignal.timeout(5000),
      });
      assert(built.success, JSON.stringify(built));
      const work = built.stats.workCounters as Record<string, number>;
      assert(work.scoped_direct_input_words_avoided > 0);
      assert(work.scoped_direct_argument_words_avoided > 0);
      assert(work.scoped_result_store_words_avoided > 0);
      assert(work.scoped_result_load_words_avoided > 0);
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(built.bytes, { asynchronous });
        const call = async (name: string, input: number) => {
          if (asynchronous) return await guest.callAsync(name, input);
          return guest.call(name, input);
        };
        try {
          for (const input of [0, 7, 0xffff_ffff, 0]) {
            assert.deepEqual(
              await call("answer", input),
              new Uint32Array([
                input,
                input + 1,
                input + 2,
                input + 3,
                input + 4,
                input + 5,
                input + 6,
                2,
              ]),
            );
          }
          for (
            const bits of [
              0,
              0x8000_0000,
              0x3fc0_0000,
              0xc050_0000,
              0x7f80_0000,
              0xff80_0000,
            ]
          ) {
            assert.deepEqual(
              await call("floating", bits),
              new Uint32Array([
                bits ^ 0x8000_0000,
                bits,
                bits,
                bits,
                bits,
                bits,
                bits,
                bits,
                1,
              ]),
            );
          }
          await assert.rejects(
            () => call("trapped", 7),
            WebAssembly.RuntimeError,
          );
          assert.deepEqual(
            await call("answer", 3),
            new Uint32Array([3, 4, 5, 6, 7, 8, 9, 2]),
          );
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
