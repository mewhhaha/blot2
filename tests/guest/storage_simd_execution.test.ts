import { strict as assert } from "node:assert";
import { compileAndRun, compileExpectedFailure } from "./compile_helpers.ts";

Deno.test("data stack SIMD preserves masks lane selection and exact floating bits", async () => {
  await compileAndRun(`
const broadcast = func values -> lane => return @simd.u32x4.broadcast values lane
entry const answer = func () => return do:
  let owner: GrowArray U32 = #[]
  let floats = @simd.u32x4.from_bits (0x80000000, 0x7FC00000, 0x3F800000, 0x40800000)
  let limits = (0.0, 3.0, 2.0, 4.0)
  let mask = @simd.f32x4.lt floats limits
  let selected = @simd.f32x4.select mask (floats, limits)
  let (a, b, c, d) = @simd.f32x4.bits selected
  let (e, f, g, h) = @simd.f32x4.bits (@simd.f32x4.min floats limits)
  let (i, j, k, l) = @simd.u32x4.shuffle (7, 0, 5, 2) ((1, 2, 3, 4), (5, 6, 7, 8))
  let (m, n, o, p) = @simd.u32x4.swizzle (3, 2, 1, 0) (10, 20, 30, 40)
  let (q, _, _, _) = broadcast (10, 20, 30, 40) 0
  let (_, _, _, r) = broadcast (10, 20, 30, 40) 3
  let signed = @simd.u32x4.to_f32_signed (0xFFFFFFFF, 0x80000000, 0, 42)
  let (s, t, u, v) = @simd.f32x4.to_u32_signed signed
  let any = @simd.u32x4.any_true mask
  let all = @simd.u32x4.all_true mask
  return #[a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,if any then 1 else 0,if all then 1 else 0]
`, guest => {
    assert.deepEqual(Array.from(guest.call("answer", null) as Uint32Array), [
      0, 0x40400000, 0x3F800000, 0x40800000,
      0, 0x40400000, 0x3F800000, 0x40800000,
      8, 1, 6, 3, 40, 30, 20, 10, 10, 40,
      0xFFFFFFFF, 0x80000000, 0, 42, 1, 0,
    ]);
  });
});

Deno.test("data stack SIMD stores validate the whole span before changing persistent lanes", async () => {
  await compileAndRun(`
const words = #[11,22,33,44,55,66]
entry const write = func (index: U32) => return do:
  let owner: GrowArray U32 = #[]
  let changed = @simd.store words index (9,8,7,6)
  return changed[0]
entry const read = func () => return do:
  let (a,b,c,d) = @simd.load words 1
  return #[words[0],a,b,c,d,words[5]]
`, guest => {
    assert.throws(() => guest.call("write", 3), WebAssembly.RuntimeError);
    assert.deepEqual(Array.from(guest.call("read", null) as Uint32Array), [11,22,33,44,55,66]);
    assert.throws(() => guest.call("write", 0xFFFFFFFF), WebAssembly.RuntimeError);
    assert.equal(guest.call("write", 1), 11);
    assert.deepEqual(Array.from(guest.call("read", null) as Uint32Array), [11,9,8,7,6,66]);
  });
});

Deno.test("scalar references cannot supply stale or fabricated SIMD literal selectors", async () => {
  for (const selector of ["lane", "@storage.load place"]) {
    await compileExpectedFailure(`
const broadcast = func values -> selector => return @simd.u32x4.broadcast values selector
entry const answer = func () => return do:
  let lane = 0
  let place = @storage.ref lane
  @storage.write place 3
  let (chosen, _, _, _) = broadcast (10,20,30,40) (${selector})
  return chosen
`, "simd_lane_literal");
  }
});
