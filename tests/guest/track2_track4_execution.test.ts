import {
  deepStrictEqual,
  ok,
  strictEqual,
  throws,
} from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";
import { instantiateGuest } from "../../host/guest.ts";

const executable = Deno.args[0] ??
  fileURLToPath(
    new URL("../../compiler-goose/build/blotc-goose", import.meta.url),
  );
const prelude = fileURLToPath(
  new URL("../../std/prelude.blot", import.meta.url),
);
const stdRoot = fileURLToPath(new URL("../../std", import.meta.url));

function hasByteSeq(bytes: Uint8Array, seq: number[]): boolean {
  outer: for (let i = 0; i <= bytes.length - seq.length; i++) {
    for (let j = 0; j < seq.length; j++) {
      if (bytes[i + j] !== seq[j]) continue outer;
    }
    return true;
  }
  return false;
}

function countByteSeq(bytes: Uint8Array, seq: number[]): number {
  let count = 0;
  outer: for (let i = 0; i <= bytes.length - seq.length; i++) {
    for (let j = 0; j < seq.length; j++) {
      if (bytes[i + j] !== seq[j]) continue outer;
    }
    count++;
  }
  return count;
}

function asWords(value: unknown): number[] {
  const view = value as Float32Array | Uint32Array;
  return Array.from(
    new Uint32Array(view.buffer, view.byteOffset, view.length),
  );
}

async function withModule(
  prefix: string,
  source: string,
  options: { relaxedSimd?: boolean; tailCalls?: boolean; wasm3?: boolean },
  run: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array,
  ) => void,
) {
  const dir = await Deno.makeTempDir({ prefix });
  const entry = `${dir}/main.blot`;
  await Deno.writeTextFile(entry, source);
  const compiler = await createZigProjectCompiler({
    executable,
    entry,
    prelude,
    stdRoot,
    ...options,
  });
  try {
    const built = await compiler.build();
    if (!built.success) {
      throw new Error(
        `Compile failed: ${JSON.stringify(built.diagnostics, null, 2)}`,
      );
    }
    const guest = await instantiateGuest(built.bytes);
    run(guest, built.bytes);
  } finally {
    await compiler.dispose();
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Wasm 3.0 extensions: return_call_indirect (0x13) on closure tail calls + relaxed min/max/trunc", async () => {
  const src = `
import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

func dispatch_loop (cb: U32 -> U32) -> (n: U32) -> (acc: U32): U32 =>
  if n == 0:
    return acc
  return cb (n - 1)

func step_fn (k: U32): U32 =>
  if k == 0:
    return 777
  return dispatch_loop step_fn k 0

#entry func test_indirect_tco (n: U32): U32 =>
  return dispatch_loop step_fn n 0

#entry func test_relaxed_ops (n: U32): Array U32 =>
  let a = @array.fill n 0.0
  let b = @array.fill n 0.0
  for i in 0 .. n:
    let fi = @u32.to_f32 i
    a[i] := fi * 0.5 + 1.0
    b[i] := 10.0 - fi * 0.25
  let lo = spark #[F32.min a[i] b[i] | i <- 0 .. n]
  let hi = spark #[F32.max a[i] b[i] | i <- 0 .. n]
  let tr = spark #[@f32.to_u32 (lo[i] + hi[i]) | i <- 0 .. n]
  let out = @array.fill (n * 3) 0
  for i in 0 .. n:
    out[i] := f32_bits lo[i]
    out[n + i] := f32_bits hi[i]
    out[n * 2 + i] := tr[i]
  return out
`;
  // 0x13 = OP_return_call_indirect
  // 0xfd 0x8d 0x02 = f32x4.relaxed_min (269)
  // 0xfd 0x8e 0x02 = f32x4.relaxed_max (270)
  // 0xfd 0x82 0x02 = i32x4.relaxed_trunc_f32x4_u (258)
  const RELAXED_MIN = [0xfd, 0x8d, 0x02];
  const RELAXED_MAX = [0xfd, 0x8e, 0x02];
  const RELAXED_TRUNC_U = [0xfd, 0x82, 0x02];

  let strictWords: number[] = [];
  await withModule("blot-w3ext-def-", src, {}, (guest, bytes) => {
    ok(!hasByteSeq(bytes, RELAXED_MIN), "default must not emit relaxed_min");
    ok(!hasByteSeq(bytes, RELAXED_MAX), "default must not emit relaxed_max");
    ok(
      !hasByteSeq(bytes, RELAXED_TRUNC_U),
      "default must not emit relaxed_trunc_u",
    );
    strictWords = asWords(guest.call("test_relaxed_ops", 19));
    strictEqual(guest.call("test_indirect_tco", 200), 777);
  });

  await withModule("blot-w3ext-on-", src, { wasm3: true }, (guest, bytes) => {
    ok(hasByteSeq(bytes, RELAXED_MIN), "expected f32x4.relaxed_min");
    ok(hasByteSeq(bytes, RELAXED_MAX), "expected f32x4.relaxed_max");
    ok(
      hasByteSeq(bytes, RELAXED_TRUNC_U),
      "expected i32x4.relaxed_trunc_f32x4_u",
    );
    // 100,000 mutual indirect closure tail calls would blow V8's stack without return_call_indirect!
    strictEqual(guest.call("test_indirect_tco", 100_000), 777);
    deepStrictEqual(asWords(guest.call("test_relaxed_ops", 19)), strictWords);
  });
});

Deno.test("Track 4A: #[n; T] dependent equal-length BCE eliminates redundant bounds checks outside loops", async () => {
  const src = `
func sum_three (a: #[n; U32]) -> (b: #[n; U32]) -> (c: #[n; U32]) -> (idx: U32): U32 =>
  if idx < a.length:
    return a[idx] + b[idx] + c[idx]
  return 0

func sum_post_trap (a: #[n; U32]) -> (b: #[n; U32]) -> (c: #[n; U32]) -> (idx: U32): U32 =>
  let x = a[idx]
  let y = b[idx]
  let z = c[idx]
  return x + y + z

#entry func test_guarded (idx: U32): U32 =>
  let a: #[4; U32] = #[10, 20, 30, 40]
  let b: #[4; U32] = #[1, 2, 3, 4]
  let c: #[4; U32] = #[100, 200, 300, 400]
  return sum_three a b c idx

#entry func test_post_trap (idx: U32): U32 =>
  let a: #[4; U32] = #[10, 20, 30, 40]
  let b: #[4; U32] = #[1, 2, 3, 4]
  let c: #[4; U32] = #[100, 200, 300, 400]
  return sum_post_trap a b c idx
`;
  await withModule("blot-sized-bce-", src, {}, (guest, bytes) => {
    strictEqual(guest.call("test_guarded", 0), 111);
    strictEqual(guest.call("test_guarded", 3), 444);
    strictEqual(guest.call("test_guarded", 4), 0);
    strictEqual(guest.call("test_post_trap", 2), 333);
    // Out-of-bounds still traps cleanly on the first check!
    throws(() => guest.call("test_post_trap", 4));
    // Sanity check the compiled binary stays compact (redundant traps removed).
    ok(bytes.length < 12000, `unexpectedly large wasm: ${bytes.length}`);
  });
});

Deno.test("Track 4B: Generalized AoS #[Vec2] & #[Vec4] record auto-SIMD (structural + nominal, AXPY, odd tails, NaN)", async () => {
  const src = `
import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

type Vec2 = { x: F32, y: F32 }
type Vec4 is data = $Vec4 { x: F32, y: F32, z: F32, w: F32 }

#entry func test_vec2_euler (n: U32): Array U32 =>
  let pos = @array.fill n { x: 0.0, y: 0.0 }
  let vel = @array.fill n { x: 0.0, y: 0.0 }
  for i in 0 .. n:
    let fi = @u32.to_f32 i
    pos[i] := { x: fi, y: fi * 2.0 }
    vel[i] := { x: 0.5, y: -0.25 }
  let dt = 0.5
  for i in 0 .. n:
    let p = pos[i]
    let v = vel[i]
    pos[i] := { x: p.x + v.x * dt, y: p.y + v.y * dt }
  let out = @array.fill (n * 2) 0
  for i in 0 .. n:
    out[i * 2] := f32_bits pos[i].x
    out[i * 2 + 1] := f32_bits pos[i].y
  return out

#entry func test_vec4_nominal (n: U32): Array U32 =>
  let pos = @array.fill n ($Vec4 { x: 0.0, y: 0.0, z: 0.0, w: 0.0 })
  let vel = @array.fill n ($Vec4 { x: 0.0, y: 0.0, z: 0.0, w: 0.0 })
  for i in 0 .. n:
    let fi = @u32.to_f32 i
    pos[i] := $Vec4 { x: fi, y: fi + 1.0, z: fi + 2.0, w: fi + 3.0 }
    vel[i] := $Vec4 { x: 1.0, y: 2.0, z: 3.0, w: 4.0 }
  let dt = 0.25
  for i in 0 .. n:
    let $Vec4 { x: px, y: py, z: pz, w: pw } = pos[i]
    let $Vec4 { x: vx, y: vy, z: vz, w: vw } = vel[i]
    pos[i] := $Vec4 { x: px + vx * dt, y: py + vy * dt, z: pz + vz * dt, w: pw + vw * dt }
  // Also test scaling with NaN canonicalization (Inf * 0.0 -> 0x7fc00000)
  if n > 0:
    pos[0] := $Vec4 { x: 1.0 / 0.0, y: 2.0, z: 3.0, w: 4.0 }
  let zero = 0.0
  for i in 0 .. n:
    let $Vec4 { x: px, y: py, z: pz, w: pw } = pos[i]
    pos[i] := $Vec4 { x: px * zero, y: py * zero, z: pz * zero, w: pw * zero }
  let out = @array.fill (n * 4) 0
  for i in 0 .. n:
    let $Vec4 { x, y, z, w } = pos[i]
    out[i * 4] := f32_bits x
    out[i * 4 + 1] := f32_bits y
    out[i * 4 + 2] := f32_bits z
    out[i * 4 + 3] := f32_bits w
  return out
`;
  const V128_STORE = [0xfd, 0x0b];
  await withModule("blot-aos-simd-", src, {}, (guest, bytes) => {
    // Must emit v128.store instructions for both Vec2 (4x + 1x) and Vec4 (4x + 1x)!
    ok(
      countByteSeq(bytes, V128_STORE) >= 10,
      `Expected >= 10 v128.store ops for AoS Vec2/Vec4 SIMD, got ${
        countByteSeq(bytes, V128_STORE)
      }`,
    );
    // Test Vec2 across sizes hitting 0, 1 (odd scalar tail), 2 (1x v128), 3 (1x + tail), 11 (4x + 1x + tail)
    for (const n of [0, 1, 2, 3, 7, 11, 25]) {
      const words = asWords(guest.call("test_vec2_euler", n));
      strictEqual(words.length, n * 2);
      const buf = new ArrayBuffer(4);
      const f32 = new Float32Array(buf);
      const u32 = new Uint32Array(buf);
      for (let i = 0; i < n; i++) {
        f32[0] = Math.fround(i + 0.5 * 0.5);
        strictEqual(words[i * 2], u32[0], `vec2 x mismatch at n=${n} i=${i}`);
        f32[0] = Math.fround(i * 2.0 + -0.25 * 0.5);
        strictEqual(
          words[i * 2 + 1],
          u32[0],
          `vec2 y mismatch at n=${n} i=${i}`,
        );
      }
    }
    // Test Vec4 nominal destructuring + scaling + exact canonical NaN (0x7fc00000)
    for (const n of [1, 3, 5, 13]) {
      const words = asWords(guest.call("test_vec4_nominal", n));
      strictEqual(words.length, n * 4);
      strictEqual(
        words[0],
        0x7fc00000,
        `expected canonical quiet NaN on Inf*0.0 at n=${n}`,
      );
      strictEqual(words[1], 0);
      strictEqual(words[2], 0);
      strictEqual(words[3], 0);
      for (let i = 4; i < n * 4; i++) {
        strictEqual(words[i], 0, `expected 0.0 at n=${n} lane=${i}`);
      }
    }
  });
});
