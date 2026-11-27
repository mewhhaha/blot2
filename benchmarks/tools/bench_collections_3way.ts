// Three-way compiled-Wasm benchmark comparing Squid's three collection families:
//   #[T]  (Array T)  — contiguous flat indexable array
//   %[T]  (Packed T) — non-indexable dense sequential array (split-stream sums, SoA records)
//   ~[T]  (Seq T)    — Design H reversible generative SIMD-RRB sequence with focus gap & packed leaves
//
// Usage:
//   deno run -A benchmarks/tools/bench_collections_3way.ts [--compiler <path>] [--samples <n>]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

let compilerPath = resolve(
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname,
);
let samples = 11;
let warmup = 3;
for (let i = 0; i < Deno.args.length; i++) {
  if (Deno.args[i] === "--compiler" && Deno.args[i + 1]) {
    compilerPath = resolve(Deno.args[++i]);
  } else if (Deno.args[i] === "--samples" && Deno.args[i + 1]) {
    samples = Number(Deno.args[++i]);
  } else if (Deno.args[i] === "--warmup" && Deno.args[i + 1]) {
    warmup = Number(Deno.args[++i]);
  }
}

const prelude = new URL("../../std/prelude.sq", import.meta.url);
const stdRoot = new URL("../../std", import.meta.url);

const median = (xs: number[]) => {
  const s = xs.toSorted((a, b) => a - b);
  return s[Math.floor(s.length / 2)];
};

interface VariantResult {
  ms: number;
  memBytes: number;
  checksum: number;
  wasmBytes: number;
}

async function compileModule(source: string): Promise<Uint8Array> {
  const dir = await Deno.makeTempDir({ prefix: "squid-bench3-" });
  const entry = `${dir}/main.sq`;
  const compiler = await createZigProjectCompiler({
    executable: compilerPath,
    entry,
    prelude,
    stdRoot,
  });
  try {
    const built = await compiler.build({ sources: { [entry]: source } });
    assert(built.success, JSON.stringify(built));
    assert(WebAssembly.validate(built.bytes), "Invalid Wasm bytes");
    return built.bytes;
  } finally {
    await compiler.close();
    await Deno.remove(dir, { recursive: true });
  }
}

async function measureVariant(
  bytes: Uint8Array,
  exportName: string,
  arg: number | null,
  opts: { freshPerSample?: boolean } = {},
): Promise<VariantResult> {
  const freshPerSample = opts.freshPerSample ?? false;
  // Returning #[acc] ensures squid:memory is exported so guest.memoryBytes()
  // reports exact committed Wasm linear memory after one fresh invocation.
  const memGuest = await instantiateGuest(bytes);
  let checksum = 0;
  let memBytes = 0;
  try {
    const out = memGuest.call(exportName, arg) as Uint32Array;
    checksum = out[0];
    memBytes = memGuest.memoryBytes();
  } finally {
    memGuest.dispose();
  }

  const times: number[] = [];
  if (freshPerSample) {
    for (let i = 0; i < warmup + samples; i++) {
      const g = await instantiateGuest(bytes);
      try {
        const t0 = performance.now();
        const r = (g.call(exportName, arg) as Uint32Array)[0];
        const dt = performance.now() - t0;
        assert.equal(r, checksum);
        if (i >= warmup) times.push(dt);
      } finally {
        g.dispose();
      }
    }
  } else {
    const g = await instantiateGuest(bytes);
    try {
      for (let i = 0; i < warmup; i++) {
        assert.equal((g.call(exportName, arg) as Uint32Array)[0], checksum);
      }
      for (let i = 0; i < samples; i++) {
        const t0 = performance.now();
        const r = (g.call(exportName, arg) as Uint32Array)[0];
        const dt = performance.now() - t0;
        assert.equal(r, checksum);
        times.push(dt);
      }
    } finally {
      g.dispose();
    }
  }

  return {
    ms: median(times),
    memBytes,
    checksum,
    wasmBytes: bytes.length,
  };
}

interface BenchmarkDef {
  id: string;
  label: string;
  arg: number | null;
  freshPerSample?: boolean;
  arraySource?: string;
  packedSource?: string;
  seqSource?: string;
}

const benchmarks: BenchmarkDef[] = [
  // 1. Flat U32 sequential build + 10x scan (N = 100,000)
  {
    id: "flat_scan",
    label: "1. Flat U32 build + 10× for-sum (N=100k)",
    arg: 100_000,
    arraySource: `
io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
`,
    packedSource: `
io run (n: U32): #[U32] =>
  let xs: %[U32] = Packed.with_capacity n
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
`,
  },

  // 2. Flat U32 scattered random indexing (N = 100,000, 200,000 lookups)
  {
    id: "random_index",
    label: "2. Flat U32 200k random lookups (N=100k)",
    arg: 100_000,
    arraySource: `
io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push (i * 7 + 3)
  let acc: U32 = 0
  let seed: U32 = 1234567
  for _ in 0..200_000:
    seed := self * 1664525 + 1013904223
    let idx = seed % n
    acc := self + xs[idx]
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push (i * 7 + 3)
  let acc: U32 = 0
  let seed: U32 = 1234567
  for _ in 0..200_000:
    seed := self * 1664525 + 1013904223
    let idx = seed % n
    acc := self + xs[idx]
  return #[acc]
`,
  },

  // 3. Skewed Sum Stream (N = 100,000: 99% $Tick, 1% 64B $Big, build + 20x tag-heavy scan)
  {
    id: "skewed_sum",
    label: "3. Skewed Sum 99% $Tick / 1% 64B $Big + 20× scan (N=100k)",
    arg: 100_000,
    arraySource: `
type BigEvent is data =
  | $Tick
  | $Big { a: U64, b: U64, c: U64, d: U64, e: U64, f: U64, g: U64, h: U64 }

io run (n: U32): #[U32] =>
  let evs: #[BigEvent] = Array.with_capacity n
  for i in 0..n:
    if i % 100 == 0:
      let v = i.to_u64
      evs := evs.push ($Big { a: v, b: 1u64, c: 2u64, d: 3u64, e: 4u64, f: 5u64, g: 6u64, h: v + 7u64 })
    else:
      evs := evs.push $Tick
  let acc: U32 = 0
  for _ in 0..20:
    for ev in evs:
      case ev of
        $Tick =>
          acc := self + 1
        $Big { a, h } =>
          acc := self + a.to_u32 + h.to_u32
  return #[acc]
`,
    packedSource: `
type BigEvent is data =
  | $Tick
  | $Big { a: U64, b: U64, c: U64, d: U64, e: U64, f: U64, g: U64, h: U64 }

io run (n: U32): #[U32] =>
  let evs: %[BigEvent] = Packed.with_capacity n
  for i in 0..n:
    if i % 100 == 0:
      let v = i.to_u64
      evs := evs.push ($Big { a: v, b: 1u64, c: 2u64, d: 3u64, e: 4u64, f: 5u64, g: 6u64, h: v + 7u64 })
    else:
      evs := evs.push $Tick
  let acc: U32 = 0
  for _ in 0..20:
    for ev in evs:
      case ev of
        $Tick =>
          acc := self + 1
        $Big { a, h } =>
          acc := self + a.to_u32 + h.to_u32
  return #[acc]
`,
    seqSource: `
type BigEvent is data =
  | $Tick
  | $Big { a: U64, b: U64, c: U64, d: U64, e: U64, f: U64, g: U64, h: U64 }

io run (n: U32): #[U32] =>
  let evs: ~[BigEvent] = ~[]
  for i in 0..n:
    if i % 100 == 0:
      let v = i.to_u64
      evs := evs.push ($Big { a: v, b: 1u64, c: 2u64, d: 3u64, e: 4u64, f: 5u64, g: 6u64, h: v + 7u64 })
    else:
      evs := evs.push $Tick
  let acc: U32 = 0
  for _ in 0..20:
    for ev in evs:
      case ev of
        $Tick =>
          acc := self + 1
        $Big { a, h } =>
          acc := self + a.to_u32 + h.to_u32
  return #[acc]
`,
  },

  // 4. Wide 10-field Entity SoA (N = 100,000, 64B AoS row, build + 80x scan touching only 2/10 fields)
  {
    id: "wide_soa",
    label: "4. Wide 10-field Record (64B) 80× touched-2-col scan (N=100k)",
    arg: 100_000,
    arraySource: `
type Entity = {
  id: U32,
  hp: U32,
  x: F64,
  y: F64,
  z: F64,
  vx: F64,
  vy: F64,
  vz: F64,
  mass: F64,
  flags: U32,
}

io run (n: U32): #[U32] =>
  let ps: #[Entity] = Array.with_capacity n
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
`,
    packedSource: `
type Entity = {
  id: U32,
  hp: U32,
  x: F64,
  y: F64,
  z: F64,
  vx: F64,
  vy: F64,
  vz: F64,
  mass: F64,
  flags: U32,
}

io run (n: U32): #[U32] =>
  let ps: %[Entity] = Packed.with_capacity n
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
`,
    seqSource: `
type Entity = {
  id: U32,
  hp: U32,
  x: F64,
  y: F64,
  z: F64,
  vx: F64,
  vy: F64,
  vz: F64,
  mass: F64,
  flags: U32,
}

io run (n: U32): #[U32] =>
  let ps: ~[Entity] = ~[]
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
`,
  },

  // 5. Reverse & reverse_range (N = 100,000, 100 whole reverses + 100 range reverses)
  {
    id: "reverse_ops",
    label: "5. 100× reverse + 100× reverse_range (N=100k)",
    arg: 100_000,
    arraySource: `
func arr_rev_range (xs: own #[U32]) -> (start: U32) -> (end: U32): #[U32] =>
  let i = start
  let j = end - 1
  for ever:
    if i >= j:
      break
    let tmp = xs[i]
    xs[i] := xs[j]
    xs[j] := tmp
    i := self + 1
    j := self - 1
  return xs

io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push i
  let acc: U32 = 0
  for k in 0..100:
    xs := arr_rev_range xs 0 n
    xs := arr_rev_range xs (k * 100) (n - k * 100)
    acc := self + xs[0] + xs[n / 2] + xs[n - 1]
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs = Seq.ramp 0 1 n
  let acc: U32 = 0
  for k in 0..100:
    xs := xs.reverse
    xs := xs.reverse_range (k * 100) (n - k * 100)
    acc := self + xs[0] + xs[n / 2] + xs[n - 1]
  return #[acc]
`,
  },

  // 6. Generative 1M arithmetic ramp + slice + 1k lookups + middle edit
  {
    id: "generative_1m",
    label: "6. Generative 1M ramp + slice + 1k reads + edit",
    arg: 1_000_000,
    arraySource: `
io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push (10 + i * 3)
  xs[n / 2] := 999999
  let acc: U32 = 0
  let seed: U32 = 42
  for _ in 0..1000:
    seed := self * 1664525 + 1013904223
    acc := self + xs[seed % n]
  for j in 500_000..500_100:
    acc := self + xs[j]
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs = Seq.ramp 10 3 n
  xs[n / 2] := 999999
  let acc: U32 = 0
  let seed: U32 = 42
  for _ in 0..1000:
    seed := self * 1664525 + 1013904223
    acc := self + xs[seed % n]
  let sub = xs.slice 500_000 500_100
  for x in sub:
    acc := self + x
  return #[acc]
`,
  },

  // 7. Snapshot CoW branching (2,000 versions copied from frozen 50,000-element base + 1 edit each)
  {
    id: "snapshot_cow",
    label: "7. 2,000× snapshot copy + 1 edit from 50k base",
    arg: 50_000,
    freshPerSample: true,
    arraySource: `
io run (n: U32): #[U32] =>
  let base: #[U32] = Array.with_capacity n
  for i in 0..n:
    base := base.push i
  let frz = freeze base
  let acc: U32 = 0
  for v in 0..2000:
    let snap = copy frz
    let idx = (v * 97) % n
    snap[idx] := v + 1000
    acc := self + snap[idx] + snap[(idx + 1) % n]
  return #[acc]
`,
    packedSource: `
io run (n: U32): #[U32] =>
  let base: %[U32] = Packed.with_capacity n
  for i in 0..n:
    base := base.push i
  let frz = freeze base
  let acc: U32 = 0
  for v in 0..2000:
    let snap = copy frz
    snap := snap.push (v + 1000)
    acc := self + snap.length
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let base: ~[U32] = ~[]
  for i in 0..n:
    base := base.push i
  let frz = freeze base
  let acc: U32 = 0
  for v in 0..2000:
    let snap = copy frz
    let idx = (v * 97) % n
    snap[idx] := v + 1000
    acc := self + snap[idx] + snap[(idx + 1) % n]
  return #[acc]
`,
  },

  // 8. Cursor-local middle inserts (2,000 consecutive inserts at midpoint of 20k)
  {
    id: "cursor_insert",
    label: "8. 2,000 cursor-local middle inserts (N=20k)",
    arg: 20_000,
    arraySource: `
func arr_insert (xs: own #[U32]) -> (idx: U32) -> (val: U32): #[U32] =>
  let n = xs.length
  xs := xs.push val
  let i = n
  for ever:
    if i <= idx:
      break
    xs[i] := xs[i - 1]
    i := self - 1
  xs[idx] := val
  return xs

io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity (n + 2000)
  for i in 0..n:
    xs := xs.push i
  let mid = n / 2
  for k in 0..2000:
    xs := arr_insert xs (mid + k) (100000 + k)
  return #[xs[mid] + xs[mid + 1999] + xs[mid + 2000] + xs.length]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push i
  let mid = n / 2
  for k in 0..2000:
    xs := xs.insert (mid + k) (100000 + k)
  return #[xs[mid] + xs[mid + 1999] + xs[mid + 2000] + xs.length]
`,
  },

  // 9. Front deque (5,000 push_front + 2,500 pop_front)
  {
    id: "front_deque",
    label: "9. Front deque: 5,000 push_front + 2,500 pop_front",
    arg: 5_000,
    arraySource: `
func arr_push_front (xs: own #[U32]) -> (val: U32): #[U32] =>
  let n = xs.length
  xs := xs.push val
  let i = n
  for ever:
    if i == 0:
      break
    xs[i] := xs[i - 1]
    i := self - 1
  xs[0] := val
  return xs

func arr_pop_front (xs: own #[U32]): (#[U32], U32) =>
  let out = xs[0]
  let n = xs.length
  for i in 1..n:
    xs[i - 1] := xs[i]
  let (xs2, _) = xs.pop
  return (xs2, out)

io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := arr_push_front xs i
  let acc: U32 = 0
  for _ in 0..(n / 2):
    let (next_xs, v) = arr_pop_front xs
    xs := next_xs
    acc := self + v
  return #[acc + xs.length]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push_front i
  let acc: U32 = 0
  for _ in 0..(n / 2):
    let (next_xs, v) = xs.pop_front
    xs := next_xs
    acc := self + v
  return #[acc + xs.length]
`,
  },

  // 10. Split + Concat rotations (500 rotations on N = 50,000)
  {
    id: "split_concat",
    label: "10. 500× split+concat rotations (N=50k)",
    arg: 50_000,
    freshPerSample: true,
    arraySource: `
io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push i
  let seed: U32 = 987654
  for _ in 0..500:
    seed := self * 1664525 + 1013904223
    let cut = seed % n
    let out: #[U32] = Array.with_capacity n
    out := out.extend_view (&xs[cut..n])
    out := out.extend_view (&xs[0..cut])
    xs := out
  return #[xs[0] + xs[n / 2] + xs[n - 1]]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push i
  let seed: U32 = 987654
  for _ in 0..500:
    seed := self * 1664525 + 1013904223
    let cut = seed % n
    let (l, r) = xs.split cut
    xs := r.concat l
  return #[xs[0] + xs[n / 2] + xs[n - 1]]
`,
  },
];

function fmtMs(r?: VariantResult): string {
  if (!r) return "N/A";
  if (r.ms < 1) return `${(r.ms * 1000).toFixed(1)} µs`;
  return `${r.ms.toFixed(2)} ms`;
}

function fmtMem(r?: VariantResult): string {
  if (!r) return "—";
  if (r.memBytes >= 1024 * 1024) {
    return `${(r.memBytes / (1024 * 1024)).toFixed(2)} MiB`;
  }
  return `${(r.memBytes / 1024).toFixed(0)} KiB`;
}

console.log(`Compiler: ${compilerPath}`);
console.log(`Samples: ${samples} (warmup: ${warmup})\n`);

interface Row {
  id: string;
  label: string;
  arr?: VariantResult;
  packed?: VariantResult;
  seq?: VariantResult;
}

const rows: Row[] = [];
for (const b of benchmarks) {
  const row: Row = { id: b.id, label: b.label };
  if (b.arraySource) {
    const bytes = await compileModule(b.arraySource);
    row.arr = await measureVariant(bytes, "run", b.arg, {
      freshPerSample: b.freshPerSample,
    });
  }
  if (b.packedSource) {
    const bytes = await compileModule(b.packedSource);
    row.packed = await measureVariant(bytes, "run", b.arg, {
      freshPerSample: b.freshPerSample,
    });
  }
  if (b.seqSource) {
    const bytes = await compileModule(b.seqSource);
    row.seq = await measureVariant(bytes, "run", b.arg, {
      freshPerSample: b.freshPerSample,
    });
  }
  if (row.arr && row.seq) {
    assert.equal(
      row.arr.checksum,
      row.seq.checksum,
      `Checksum mismatch on ${b.id} (#[] vs ~[]): ${row.arr.checksum} vs ${row.seq.checksum}`,
    );
  }
  if (row.arr && row.packed && b.id !== "snapshot_cow") {
    assert.equal(
      row.arr.checksum,
      row.packed.checksum,
      `Checksum mismatch on ${b.id} (#[] vs %[]): ${row.arr.checksum} vs ${row.packed.checksum}`,
    );
  }
  rows.push(row);
  console.log(
    `${b.label}\n  #[T]: ${fmtMs(row.arr)} (${fmtMem(row.arr)})  |  %[T]: ${
      fmtMs(row.packed)
    } (${fmtMem(row.packed)})  |  ~[T]: ${fmtMs(row.seq)} (${fmtMem(row.seq)})`,
  );
}

console.log("\n=== MARKDOWN SUMMARY TABLE ===");
console.log(
  "| Benchmark | `#[T]` (`Array`) | `%[T]` (`Packed`) | `~[T]` (`Seq`, Design H) | Winner |",
);
console.log("| --- | ---: | ---: | ---: | --- |");
for (const r of rows) {
  const candidates: [string, VariantResult][] = [];
  if (r.arr) candidates.push(["`#[T]`", r.arr]);
  if (r.packed && r.id !== "snapshot_cow") {
    candidates.push(["`%[T]`", r.packed]);
  }
  if (r.seq) candidates.push(["`~[T]`", r.seq]);
  candidates.sort((a, b) => a[1].ms - b[1].ms);
  const fastest = candidates[0];
  const runnerUp = candidates[1];
  const speedup = runnerUp
    ? `${(runnerUp[1].ms / fastest[1].ms).toFixed(1)}×`
    : "";
  console.log(
    `| ${r.label} | ${fmtMs(r.arr)} (${fmtMem(r.arr)}) | ${fmtMs(r.packed)} (${
      fmtMem(r.packed)
    }) | ${fmtMs(r.seq)} (${fmtMem(r.seq)}) | ${
      fastest[0]
    } (${speedup} faster) |`,
  );
}
