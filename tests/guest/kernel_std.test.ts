import { compileAndRun, equal } from "./compile_helpers.ts";

Deno.test("std/kernel exposes represented Kernel handles, exact 16-bit lane packing, and FNV-1a 64-bit hashes", async () => {
  await compileAndRun(
    `import * as kernel from "std/kernel"

func prep (ctx: #[F32]) => #[ctx[0]]
func run_a (ctx: #[F32]) -> (x: U32): U32 => x + F32.to_u32 ctx[0]
func run_b (ctx: #[F32]) -> (x: U32): U32 => x * 2 + F32.to_u32 ctx[0]

entry kernel ka: Kernel [#[F32], U32, U32] = { prepare: prep, run: run_a }
entry kernel kb: Kernel [#[F32], U32, U32] = { prepare: prep, run: run_b }

entry func check_handles (flag: U32): #[U32] =>
  let selected = if flag == 0 then ka else kb
  let kid = kernel.id selected
  let bh = kernel.binding_hash selected
  let ch = kernel.ctx_hash selected
  let ih = kernel.io_hash selected
  return #[kid, bh.lo, bh.hi, ch.lo, ch.hi, ih.lo, ih.hi]

entry func check_pack_u32 (v: U32): U32 =>
  let (lo, hi) = kernel.pack_u32 v
  return case kernel.unpack_u32 lo hi of
    $Some out => out
    $Nothing => 0

entry func check_pack_hash (pair: #[U32]): #[U32] =>
  let h = $kernel.Hash64 { lo: pair[0], hi: pair[1] }
  let (w0, w1, w2, w3) = kernel.pack_hash h
  return case kernel.unpack_hash w0 w1 w2 w3 of
    $Some out => #[out.lo, out.hi]
    $Nothing => #[0, 0]

entry func check_fnv_f32 (xs: #[F32]): #[U32] =>
  let h = kernel.fnv1a64_f32s (&xs[0..xs.length])
  return #[h.lo, h.hi]
`,
    async (guest) => {
      const metaA = guest.call("check_handles", 0) as Uint32Array;
      const metaB = guest.call("check_handles", 1) as Uint32Array;
      equal(metaA[0], 0);
      equal(metaB[0], 1);
      // Distinct bodies -> distinct binding_hash, identical ctx_hash and io_hash!
      equal(metaA[1] === metaB[1] && metaA[2] === metaB[2], false);
      equal(metaA[3], metaB[3]);
      equal(metaA[4], metaB[4]);
      equal(metaA[5], metaB[5]);
      equal(metaA[6], metaB[6]);

      for (const v of [0, 1, 65535, 65536, 16_777_215, 16_777_216, 0xdeadbeef, 0xffffffff]) {
        equal(guest.call("check_pack_u32", v), v);
      }
      const unpacked = guest.call("check_pack_hash", Uint32Array.of(0x84222325, 0xcbf29ce4)) as Uint32Array;
      equal(unpacked[0], 0x84222325);
      equal(unpacked[1], 0xcbf29ce4);

      // Compare std/kernel.fnv1a64_f32s against BigInt FNV-1a 64-bit reference over IEEE-754 LE bytes.
      const vals = new Float32Array([0.0, -0.0, 1.0, 2.0, -42.5, 16_777_216.0]);
      const bytes = new Uint8Array(vals.buffer);
      let ref = 0xcbf29ce484222325n;
      const prime = 0x00000100000001b3n;
      const mask64 = 0xffffffffffffffffn;
      for (const b of bytes) {
        ref = ((ref ^ BigInt(b)) * prime) & mask64;
      }
      const got = guest.call("check_fnv_f32", vals) as Uint32Array;
      equal(got[0], Number(ref & 0xffffffffn));
      equal(got[1], Number((ref >> 32n) & 0xffffffffn));
    },
    { stdRoot: new URL("../../std", import.meta.url).pathname },
  );
});
