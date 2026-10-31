import { strict as assert } from "node:assert";
import { createZigProjectCompiler } from "../../compiler/zig_project_client.ts";
import { instantiateGuest } from "../../compiler/guest.ts";

const executable = Deno.args[0] ??
  new URL("../zig-out/bin/blotc", import.meta.url).pathname;
const source = `
import * as simd from "std/simd"
const shuffled = simd.f32_shuffle
entry const floating = func (values: Array F32): Array U32 => return do:
  let input = &values[0..8]
  let left = (input[0], input[1], input[2], input[3])
  let right = (input[4], input[5], input[6], input[7])
  let (a, b, c, d) = simd.f32_bits (shuffled (0, 5, 2, 7) left right)
  let (e, f, g, h) = simd.f32_bits (shuffled (4, 1, 6, 3) left right)
  let (i, j, k, l) = simd.f32_bits (simd.f32_swizzle (3, 2, 1, 0) left)
  let (m, n, o, p) = simd.f32_bits (simd.f32_broadcast 0 left)
  let (q, r, s, t) = simd.f32_bits (simd.f32_broadcast 3 left)
  return #[a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, s, t]
entry const integers = func (values: Array U32): Array U32 => return do:
  let input = &values[0..8]
  let left = (input[0], input[1], input[2], input[3])
  let right = (input[4], input[5], input[6], input[7])
  let (a, b, c, d) = simd.u32_shuffle (7, 0, 5, 2) left right
  let (e, f, g, h) = simd.u32_swizzle (3, 2, 1, 0) left
  let (i, j, k, l) = simd.u32_broadcast 3 left
  return #[a, b, c, d, e, f, g, h, i, j, k, l]
`;

for (const codegenTier of ["development", "optimized"] as const) {
  Deno.test(`scoped standard SIMD wrappers retain literal selectors and exact lane bits (${codegenTier})`, async () => {
    const directory = await Deno.makeTempDir({ prefix: "blot-scoped-simd-" });
    const entry = `${directory}/main.blot`;
    await Deno.writeTextFile(entry, source);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude: new URL("../../std/prelude.blot", import.meta.url).pathname,
      stdRoot: new URL("../../std/", import.meta.url).pathname,
      codegenTier,
      cacheDirectory: false,
    });
    try {
      const result = await compiler.build();
      assert(result.success, JSON.stringify(result));
      for (const asynchronous of [false, true]) {
        const guest = await instantiateGuest(result.bytes, { asynchronous });
        const call = (
          name: string,
          values: Float32Array<ArrayBuffer> | Uint32Array<ArrayBuffer>,
        ) =>
          asynchronous
            ? guest.callAsync(name, values)
            : guest.call(name, values);
        try {
          for (
            const bits of [
              [
                0x80000000,
                0x7FC01234,
                0x3F800000,
                0xFF800000,
                0,
                0xFFC05678,
                0x7F800000,
                0x40800000,
              ],
              [0, 0x80000000, 1, 0xFFFFFFFF, 7, 8, 9, 10],
            ]
          ) {
            const words = Uint32Array.from(bits);
            const floating = new Float32Array(words.buffer);
            assert.deepEqual(
              await call("floating", floating),
              Uint32Array.from([
                bits[0],
                bits[5],
                bits[2],
                bits[7],
                bits[4],
                bits[1],
                bits[6],
                bits[3],
                bits[3],
                bits[2],
                bits[1],
                bits[0],
                ...Array(4).fill(bits[0]),
                ...Array(4).fill(bits[3]),
              ]),
            );
            assert.deepEqual(
              await call("integers", words),
              Uint32Array.from([
                bits[7],
                bits[0],
                bits[5],
                bits[2],
                bits[3],
                bits[2],
                bits[1],
                bits[0],
                ...Array(4).fill(bits[3]),
              ]),
            );
          }
        } finally {
          guest.dispose();
        }
      }
      for (
        const selection of [
          "simd.u32_shuffle (0, 8, 2, 7) lanes lanes",
          "simd.u32_swizzle (0, 4, 2, 3) lanes",
          "simd.u32_broadcast 4 lanes",
          "simd.u32_broadcast input lanes",
        ]
      ) {
        const rejected = await compiler.build({
          sources: {
            [entry]: `${source}
entry const invalid = func (input: U32): Array U32 => return do:
  let lanes = (input, 2, 3, 4)
  let (a, b, c, d) = ${selection}
  return #[a, b, c, d]
`,
          },
        });
        assert(!rejected.success);
        assert.equal(rejected.diagnostics[0].code, "simd_lane_literal");
        assert.equal("bytes" in rejected, false);
      }
      const recovered = await compiler.build();
      assert(recovered.success, JSON.stringify(recovered));
      assert.deepEqual(recovered.bytes, result.bytes);
    } finally {
      await compiler.dispose();
      await Deno.remove(directory, { recursive: true });
    }
  });
}
