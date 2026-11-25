import {
  deepStrictEqual,
  notStrictEqual,
  ok,
  strictEqual,
} from "node:assert/strict";
import { instantiateGuest } from "../../host/guest.ts";
import { runCli } from "../../host/cli.ts";
import {
  createZigProjectCompiler,
  type ZigProjectCompilerOptions,
} from "../../host/zig_project_client.ts";

const executable = Deno.args[0] ??
  new URL("../../compiler-goose/build/blotc-goose", import.meta.url).pathname;
const prelude = new URL("../../std/prelude.blot", import.meta.url).pathname;
const stdRoot = new URL("../../std", import.meta.url).pathname;

function asWords(value: unknown): number[] {
  const view = value as Float32Array | Uint32Array;
  return Array.from(
    new Uint32Array(view.buffer, view.byteOffset, view.length),
  );
}

function hasByteSeq(bytes: Uint8Array, seq: readonly number[]): boolean {
  outer: for (let i = 0; i + seq.length <= bytes.length; i++) {
    for (let j = 0; j < seq.length; j++) {
      if (bytes[i + j] !== seq[j]) continue outer;
    }
    return true;
  }
  return false;
}

async function withModule(
  prefix: string,
  src: string,
  extra: Partial<ZigProjectCompilerOptions>,
  fn: (
    guest: Awaited<ReturnType<typeof instantiateGuest>>,
    bytes: Uint8Array,
    identity: string,
  ) => void,
) {
  const dir = await Deno.makeTempDir({ prefix });
  const entry = `${dir}/main.blot`;
  try {
    await Deno.writeTextFile(entry, src);
    const compiler = await createZigProjectCompiler({
      executable,
      entry,
      prelude,
      stdRoot,
      ...extra,
    });
    try {
      const built = await compiler.build();
      ok(built.success, JSON.stringify(built));
      const guest = await instantiateGuest(built.bytes);
      try {
        fn(guest, built.bytes, compiler.compilerIdentity);
      } finally {
        guest.dispose();
      }
    } finally {
      await compiler.dispose();
    }
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
}

Deno.test("Default MVP self-tail-call-to-loop TCO: 200k recursion, parallel swaps, owned arrays, fork/effect safety", async () => {
  const src = `type Pair is data = $Pair { a: U32, b: U32 }

func sum_tail (n: U32) -> (acc: U32): U32 =>
  if n == 0:
    return acc
  return sum_tail (n - 1) (acc + n)

// Parallel parameter swap: a and b swap every iteration; sequential overwrite would corrupt!
func swap_tail (n: U32) -> (a: U32) -> (b: U32): U32 =>
  if n == 0:
    return a * 1000 + b
  return swap_tail (n - 1) b (a + 1)

// Multi-word record parameter swap at deep recursion
func pair_tail (n: U32) -> (p: Pair): U32 =>
  case p of
    $Pair { a, b } =>
      if n == 0:
        return a * 10000 + b
      return pair_tail (n - 1) ($Pair { a: b, b: a + 1 })

// Read-only array threaded through 50,000 self-tail calls
func sum_arr_tail (n: U32) -> (arr: #[U32]) -> (acc: U32): U32 =>
  if n == 0:
    return acc
  let idx = n & 3
  return sum_arr_tail (n - 1) arr (acc + arr[idx])

// Tail call inside fork must NOT jump past fork teardown (tco_inhibit safety)
func fork_in_body (n: U32): U32 =>
  let a = #[10]
  let inner = fork a:
    a[0] := 99
    if n > 0:
      return fork_in_body (n - 1)
    return 1
  return a[0] + inner

entry func run_sum (n: U32): U32 =>
  return sum_tail n 0

entry func run_swap (n: U32): U32 =>
  return swap_tail n 10 20

entry func run_pair (n: U32): U32 =>
  return pair_tail n ($Pair { a: 3, b: 7 })

entry func run_arr_sum (n: U32): U32 =>
  let a = #[1, 2, 3, 4]
  return sum_arr_tail n a 0

entry func run_fork_check (n: U32): U32 =>
  return fork_in_body n
`;
  await withModule("blot-self-tco-", src, {}, (guest) => {
    // 200,000 deep recursion runs in O(1) stack via MVP loop/br (zero Wasm 3.0 opcodes)
    const n = 200_000;
    const expectedSum = ((BigInt(n) * BigInt(n + 1)) / 2n) & 0xffffffffn;
    strictEqual(guest.call("run_sum", n), Number(expectedSum));

    // Parallel swap verification across odd/even & large depths
    for (const k of [0, 1, 2, 3, 7, 100, 100_001]) {
      let a = 10;
      let b = 20;
      for (let i = 0; i < k; i++) {
        const nextA = b;
        const nextB = (a + 1) >>> 0;
        a = nextA;
        b = nextB;
      }
      strictEqual(
        guest.call("run_swap", k),
        (Math.imul(a, 1000) + b) >>> 0,
        `run_swap(${k})`,
      );
    }

    // Multi-word record swap
    {
      let a = 3;
      let b = 7;
      for (let i = 0; i < 100_001; i++) {
        const na = b;
        const nb = (a + 1) >>> 0;
        a = na;
        b = nb;
      }
      strictEqual(
        guest.call("run_pair", 100_001),
        (Math.imul(a, 10000) + b) >>> 0,
      );
    }

    // Array parameter threaded through 50,000 tail calls: 12,500 * (1+2+3+4) = 125,000
    strictEqual(guest.call("run_arr_sum", 50_000), 125_000);

    // Fork rollback preserved when self-call appears inside `fork`:
    // n=0 => 10 + 1 = 11; n=1 => 10 + 11 = 21; n=5 => 5*10 + 11 = 61
    strictEqual(guest.call("run_fork_check", 0), 11);
    strictEqual(guest.call("run_fork_check", 1), 21);
    strictEqual(guest.call("run_fork_check", 5), 61);
  });
});

Deno.test("Opt-in Wasm 3.0 --tail-calls: mutual recursion at 200k depth via return_call (0x12) + identity isolation", async () => {
  const src = `func step_a (n: U32) -> (acc: U32): U32 =>
  if n == 0:
    return acc
  return step_b (n - 1) (acc + 1)

func step_b (n: U32) -> (acc: U32): U32 =>
  if n == 0:
    return acc + 100
  return step_c (n - 1) (acc + 2)

func step_c (n: U32) -> (acc: U32): U32 =>
  if n == 0:
    return acc + 1000
  return step_a (n - 1) (acc + 3)

entry func mutual_run (n: U32): U32 =>
  return step_a n 0
`;
  let defaultId = "";
  let tailId = "";
  await withModule("blot-tc-def-", src, {}, (guest, _bytes, id) => {
    defaultId = id;
    // Small depth works without --tail-calls, while 200k mutual calls overflow stack (proving no return_call in default mode)
    strictEqual(guest.call("mutual_run", 30), 60);
    let overflowed = false;
    try {
      guest.call("mutual_run", 200_000);
    } catch {
      overflowed = true;
    }
    ok(
      overflowed,
      "Default build must not emit return_call for mutual recursion",
    );
  });
  await withModule(
    "blot-tc-on-",
    src,
    { tailCalls: true },
    (guest, _bytes, id) => {
      tailId = id;
      notStrictEqual(
        tailId,
        defaultId,
        "--tail-calls must change compilerIdentity",
      );
      // 200,000 mutual tail calls: 66666 full cycles of (1+2+3=6) + 2 steps (a->b->c: +1+2) + c base (+1000)
      const n = 200_000;
      let acc = 0;
      let state = 0;
      for (let rem = n; rem > 0; rem--) {
        if (state === 0) {
          acc = (acc + 1) >>> 0;
          state = 1;
        } else if (state === 1) {
          acc = (acc + 2) >>> 0;
          state = 2;
        } else {
          acc = (acc + 3) >>> 0;
          state = 0;
        }
      }
      if (state === 1) acc = (acc + 100) >>> 0;
      else if (state === 2) acc = (acc + 1000) >>> 0;
      strictEqual(guest.call("mutual_run", n), acc);
      strictEqual(guest.call("mutual_run", 0), 0);
      strictEqual(guest.call("mutual_run", 1), 101);
      strictEqual(guest.call("mutual_run", 2), 1003);
      strictEqual(guest.call("mutual_run", 3), 6);
    },
  );
});

Deno.test("Opt-in Wasm 3.0 --relaxed-simd / --wasm3: f32x4.relaxed_madd & nmadd in spark, matmul & escape SIMD", async () => {
  const src = `import * as simd from "std/simd"

func f32_bits (x: F32): U32 =>
  let (b, _, _, _) = simd.f32_bits (x, 0.0, 0.0, 0.0)
  return b

// 1. spark FMA: both relaxed_madd (a*b + c, c + a*b) and relaxed_nmadd (c - a*b) + NaN canonicalization
entry func spark_fma (n: U32): #[U32] =>
  let a = @array.fill n 0.0
  let b = @array.fill n 0.0
  let c = @array.fill n 0.0
  let zero = U32.to_f32 (n & 0)
  let inf = 1.0 / zero
  for i in 0 .. n:
    let f = U32.to_f32 ((i & 7) + 1)
    a[i] := if i == 3 then inf else f * 0.5
    b[i] := if i == 3 then 0.0 else 0.25
    c[i] := 10.0 + f
  let r1 = spark #[a[i] * b[i] + c[i] | i <- 0 .. n]
  let r2 = spark #[c[i] - a[i] * b[i] | i <- 0 .. n]
  let out = @array.fill (n * 2) 0
  for i in 0 .. n:
    out[i] := f32_bits r1[i]
    out[n + i] := f32_bits r2[i]
  return out

// 2. matmul FMA across 4x8 (6B-1), 2x16 (5C), and 1x16 (4C)
entry func matmul_fma (packed: U32): #[U32] =>
  let rows = packed & 63
  let inner = (packed >> 6) & 63
  let cols = (packed >> 12) & 63
  let a = @array.fill (rows * inner) 0.0
  let b = @array.fill (inner * cols) 0.0
  let c = @array.fill (rows * cols) 0.0
  for i in 0 .. (rows * inner):
    a[i] := U32.to_f32 ((i % 4) + 1) * 0.25
  for i in 0 .. (inner * cols):
    b[i] := U32.to_f32 ((i % 3) + 1) * 0.5
  for i in 0 .. rows:
    let ra = i * inner
    let rc = i * cols
    for k in 0 .. inner:
      let aik = a[ra + k]
      let rb = k * cols
      for j in 0 .. cols:
        c[rc + j] := self + aik * b[rb + j]
  let out = @array.fill (rows * cols) 0
  for i in 0 .. (rows * cols):
    out[i] := f32_bits c[i]
  return out

// 3. Escape-time SIMD (2.0 * zr * zi + ci -> relaxed_madd)
entry func escape_fma (size: U32): U32 =>
  let inv = 1.0 / U32.to_f32 size
  let total: U32 = 0
  for py in 0 .. size:
    let ci = U32.to_f32 py * inv * 2.4 - 1.2
    for px in 0 .. size:
      let cr = U32.to_f32 px * inv * 2.4 - 1.8
      let zr: F32 = 0.0
      let zi: F32 = 0.0
      let it: U32 = 0
      for ever:
        if it >= 32:
          break
        let zr2 = zr * zr
        let zi2 = zi * zi
        if zr2 + zi2 > 4.0:
          break
        let nzi = 2.0 * zr * zi + ci
        zr := zr2 - zi2 + cr
        zi := nzi
        it := self + 1
      total := self + it
  return total
`;
  const RELAXED_MADD = [0xfd, 0x85, 0x02];
  const RELAXED_NMADD = [0xfd, 0x86, 0x02];
  let defaultId = "";
  let defaultSpark: number[] = [];
  let defaultMatmuls: number[][] = [];

  await withModule("blot-rs-def-", src, {}, (guest, bytes, id) => {
    defaultId = id;
    ok(
      !hasByteSeq(bytes, RELAXED_MADD),
      "Default build must NOT emit f32x4.relaxed_madd",
    );
    ok(
      !hasByteSeq(bytes, RELAXED_NMADD),
      "Default build must NOT emit f32x4.relaxed_nmadd",
    );
    defaultSpark = asWords(guest.call("spark_fma", 17));
    defaultMatmuls = [
      [1, 5, 16],
      [2, 5, 16],
      [4, 5, 16],
      [8, 6, 16],
    ].map(([r, k, c]) =>
      asWords(guest.call("matmul_fma", ((c << 12) | (k << 6) | r) >>> 0))
    );
  });

  await withModule(
    "blot-rs-on-",
    src,
    { wasm3: true },
    (guest, bytes, id) => {
      notStrictEqual(
        id,
        defaultId,
        "--wasm3 must change compilerIdentity",
      );
      ok(
        hasByteSeq(bytes, RELAXED_MADD),
        "Expected f32x4.relaxed_madd (0xfd 0x85 0x02) under --wasm3",
      );
      ok(
        hasByteSeq(bytes, RELAXED_NMADD),
        "Expected f32x4.relaxed_nmadd (0xfd 0x86 0x02) under --wasm3",
      );

      // Dyadic rationals (powers of 2) are exact in both strict IEEE and FMA!
      const gotSpark = asWords(guest.call("spark_fma", 17));
      deepStrictEqual(gotSpark, defaultSpark);
      // Verify Inf * 0.0 + c still canonicalizes to 0x7fc00000 in both r1 and r2!
      strictEqual(gotSpark[3], 0x7fc00000);
      strictEqual(gotSpark[17 + 3], 0x7fc00000);

      // Dyadic matmul shapes match bit-exact across 1x16 (4C), 2x16 (5C), 4x8 & 8x16 (6B-1)
      const shapes: Array<[number, number, number]> = [
        [1, 5, 16],
        [2, 5, 16],
        [4, 5, 16],
        [8, 6, 16],
      ];
      for (let i = 0; i < shapes.length; i++) {
        const [r, k, c] = shapes[i];
        const got = asWords(
          guest.call("matmul_fma", ((c << 12) | (k << 6) | r) >>> 0),
        );
        deepStrictEqual(got, defaultMatmuls[i], `matmul_fma ${r}x${k}x${c}`);
      }

      // Escape-time SIMD runs cleanly under --wasm3 (small FMA drift allowed vs strict)
      const esc = guest.call("escape_fma", 32) as number;
      ok(esc > 5000 && esc < 20000, `escape_fma(32) = ${esc}`);
    },
  );

  // Verify host CLI (`runCli`) passes --relaxed-simd / --wasm3 end-to-end
  const dir = await Deno.makeTempDir({ prefix: "blot-cli-wasm3-" });
  try {
    const entry = `${dir}/main.blot`;
    const out = `${dir}/out.wasm`;
    await Deno.writeTextFile(entry, src);
    const code = await runCli(executable, [
      "build",
      entry,
      out,
      "--prelude",
      prelude,
      "--std-root",
      stdRoot,
      "--relaxed-simd",
    ]);
    strictEqual(code, 0, "CLI build --relaxed-simd should succeed");
    const bytes = await Deno.readFile(out);
    ok(
      hasByteSeq(bytes, RELAXED_MADD),
      "CLI build --relaxed-simd should emit relaxed_madd",
    );
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
});
