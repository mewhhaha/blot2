// Three-way compiled-Wasm benchmark comparing Squid's three collection families:
//   #[T]  (Array T)  — contiguous flat indexable array
//   %[T]  (Packed T) — non-indexable dense sequential array (split-stream sums, SoA records)
//   ~[T]  (Seq T)    — Design H reversible generative SIMD-RRB sequence with focus gap & packed leaves
//
// Usage:
//   deno run -A benchmarks/tools/bench_collections_3way.ts [--compiler <path>] [--samples <n>] [--warmup <n>] [--wtime-aot [path]]
import { strict as assert } from "node:assert";
import { resolve } from "node:path";
import { instantiateGuest } from "../../host/guest.ts";
import { createZigProjectCompiler } from "../../host/zig_project_client.ts";

let compilerPath = resolve(
  new URL("../../compiler-goose/build/squidc-goose", import.meta.url).pathname,
);
let wtimeAotPath: string | null = null;
const defaultWtimeAotPath = resolve(
  new URL(
    "../../../wtime/tools/wtime-aot/target/release/wtime-aot",
    import.meta.url,
  ).pathname,
);
let samples = 11;
let warmup = 3;
for (let i = 0; i < Deno.args.length; i++) {
  if (Deno.args[i] === "--compiler" && Deno.args[i + 1]) {
    compilerPath = resolve(Deno.args[++i]);
  } else if (Deno.args[i] === "--wtime-aot") {
    if (Deno.args[i + 1] && !Deno.args[i + 1].startsWith("--")) {
      wtimeAotPath = resolve(Deno.args[++i]);
    } else {
      wtimeAotPath = defaultWtimeAotPath;
    }
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

const WTIME_RUNNER_C = `
#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef void *(*fn_new)(void *, const void *, uint64_t, uint8_t *);
typedef void (*fn_drop)(void *);
typedef int32_t (*fn_call_export)(void *, const uint8_t *, size_t, uint64_t, uint64_t *, uint8_t *);
typedef int32_t (*fn_call_finish)(void *, int32_t *, uint8_t *);
typedef void (*fn_mem_data)(void *, uint8_t **, size_t *);

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec * 1e-6;
}

static int cmp_double(const void *a, const void *b) {
    double da = *(const double *)a;
    double db = *(const double *)b;
    return (da > db) - (da < db);
}

static uint32_t read_u32_first(fn_mem_data mem_fn, void *h, uint64_t res, size_t *out_mem) {
    uint8_t *mem = NULL;
    size_t mem_len = 0;
    mem_fn(h, &mem, &mem_len);
    if (out_mem) *out_mem = mem_len;
    uint32_t ptr = (uint32_t)res;
    if (!mem || (size_t)ptr + 8 > mem_len) {
        fprintf(stderr, "invalid result ptr %u (mem_len=%zu)\\n", ptr, mem_len);
        exit(5);
    }
    uint32_t val = 0;
    memcpy(&val, mem + ptr + 4, 4);
    return val;
}

int main(int argc, char **argv) {
    if (argc < 6) return 2;
    const char *so_path = argv[1];
    uint64_t arg = (uint64_t)strtoull(argv[2], NULL, 10);
    int warmup = atoi(argv[3]);
    int samples = atoi(argv[4]);
    int fresh = atoi(argv[5]);
    void *dl = dlopen(so_path, RTLD_NOW | RTLD_LOCAL);
    if (!dl) { fprintf(stderr, "dlopen: %s\\n", dlerror()); return 2; }
    fn_new f_new = (fn_new)dlsym(dl, "blot_aot_new");
    fn_drop f_drop = (fn_drop)dlsym(dl, "blot_aot_drop");
    fn_call_export f_call = (fn_call_export)dlsym(dl, "blot_aot_call_export");
    fn_call_finish f_fin = (fn_call_finish)dlsym(dl, "blot_aot_call_finish_invocation");
    fn_mem_data f_mem = (fn_mem_data)dlsym(dl, "blot_aot_mem_data");
    if (!f_new || !f_drop || !f_call || !f_mem) return 2;

    uint8_t trap = 0;
    uint64_t res = 0;
    size_t mem_bytes = 0;
    void *h0 = f_new(NULL, NULL, 0, &trap);
    if (!h0) return 3;
    if (f_call(h0, (const uint8_t *)"run", 3, arg, &res, &trap) != 0) return 4;
    uint32_t checksum = read_u32_first(f_mem, h0, res, &mem_bytes);
    if (f_fin) { int32_t fin = 0; f_fin(h0, &fin, &trap); }
    f_drop(h0);

    double *times = (double *)malloc(sizeof(double) * (size_t)samples);
    if (fresh) {
        for (int i = 0; i < warmup + samples; i++) {
            void *h = f_new(NULL, NULL, 0, &trap);
            if (!h) return 3;
            double t0 = now_ms();
            int32_t rc = f_call(h, (const uint8_t *)"run", 3, arg, &res, &trap);
            double dt = now_ms() - t0;
            if (rc != 0) return 4;
            uint32_t r = read_u32_first(f_mem, h, res, NULL);
            if (r != checksum) { fprintf(stderr, "checksum mismatch\\n"); return 6; }
            if (f_fin) { int32_t fin = 0; f_fin(h, &fin, &trap); }
            f_drop(h);
            if (i >= warmup) times[i - warmup] = dt;
        }
    } else {
        void *h = f_new(NULL, NULL, 0, &trap);
        if (!h) return 3;
        for (int i = 0; i < warmup; i++) {
            if (f_call(h, (const uint8_t *)"run", 3, arg, &res, &trap) != 0) return 4;
            if (read_u32_first(f_mem, h, res, NULL) != checksum) return 6;
            if (f_fin) { int32_t fin = 0; f_fin(h, &fin, &trap); }
        }
        for (int i = 0; i < samples; i++) {
            double t0 = now_ms();
            int32_t rc = f_call(h, (const uint8_t *)"run", 3, arg, &res, &trap);
            double dt = now_ms() - t0;
            if (rc != 0) return 4;
            if (read_u32_first(f_mem, h, res, NULL) != checksum) return 6;
            if (f_fin) { int32_t fin = 0; f_fin(h, &fin, &trap); }
            times[i] = dt;
        }
        f_drop(h);
    }
    qsort(times, (size_t)samples, sizeof(double), cmp_double);
    double med = times[samples / 2];
    printf("%.6f %zu %" PRIu32 "\\n", med, mem_bytes, checksum);
    free(times);
    dlclose(dl);
    return 0;
}
`;

let wtimeWorkDir: string | null = null;
let wtimeRunnerBin: string | null = null;

async function ensureWtimeRunner(): Promise<string> {
  if (wtimeRunnerBin) return wtimeRunnerBin;
  wtimeWorkDir = await Deno.makeTempDir({ prefix: "squid-bench3-wtime-" });
  const cPath = `${wtimeWorkDir}/runner.c`;
  const binPath = `${wtimeWorkDir}/runner`;
  await Deno.writeTextFile(cPath, WTIME_RUNNER_C);
  const cc = await new Deno.Command("cc", {
    args: ["-O2", cPath, "-ldl", "-o", binPath],
  }).output();
  assert(
    cc.success,
    `Failed to compile native wtime runner: ${
      new TextDecoder().decode(cc.stderr)
    }`,
  );
  wtimeRunnerBin = binPath;
  return binPath;
}

async function measureVariantWtimeAot(
  bytes: Uint8Array,
  arg: number | null,
  opts: { freshPerSample?: boolean } = {},
): Promise<VariantResult> {
  assert(wtimeAotPath, "wtimeAotPath not set");
  const runner = await ensureWtimeRunner();
  const dir = await Deno.makeTempDir({ prefix: "squid-bench3-so-" });
  try {
    const wasmPath = `${dir}/mod.wasm`;
    const soPath = `${dir}/mod.so`;
    await Deno.writeFile(wasmPath, bytes);
    const aot = await new Deno.Command(wtimeAotPath, {
      args: [
        wasmPath,
        "-o",
        soPath,
        "--backend",
        "x64",
        "--target-cpu",
        "native",
        "--guard-pages",
        "--blot-cdylib",
      ],
    }).output();
    assert(
      aot.success,
      `wtime-aot failed: ${new TextDecoder().decode(aot.stderr)}`,
    );
    const run = await new Deno.Command(runner, {
      args: [
        soPath,
        String(arg ?? 0),
        String(warmup),
        String(samples),
        opts.freshPerSample ? "1" : "0",
      ],
    }).output();
    assert(
      run.success,
      `wtime runner failed (${run.code}): ${
        new TextDecoder().decode(run.stderr)
      }`,
    );
    const [msStr, memStr, chkStr] = new TextDecoder()
      .decode(run.stdout)
      .trim()
      .split(/\s+/);
    return {
      ms: Number(msStr),
      memBytes: Number(memStr),
      checksum: Number(chkStr),
      wasmBytes: bytes.length,
    };
  } finally {
    await Deno.remove(dir, { recursive: true });
  }
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

  // 4. Wide 10-field Entity SoA (N = 100,000, 72B AoS row, build + 80x scan touching only 2/10 fields)
  {
    id: "wide_soa",
    label: "4. Wide 10-field Record (72B) 80× touched-2-col scan (N=100k)",
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

  // 7. Snapshot CoW branching (2,000 versions copied from frozen 50,000-element base + 1 indexed edit each)
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

  // 11. Zero-copy frozen span: wrap *#[U32] (100k) -> 500x slice + reverse + 100-elem sum
  {
    id: "frozen_span",
    label: "11. Frozen 100k array: 500× slice + reverse + 100-elem sum",
    arg: 100_000,
    arraySource: `
io run (n: U32): #[U32] =>
  let base: #[U32] = Array.with_capacity n
  for i in 0..n:
    base := base.push (i * 5 + 7)
  let frz = freeze base
  let acc: U32 = 0
  let seed: U32 = 314159
  for _ in 0..500:
    seed := self * 1664525 + 1013904223
    let start = seed % (n - 20_000)
    let len: U32 = 20_000
    let sub: #[U32] = Array.with_capacity len
    for j in 0..len:
      sub := sub.push frz[start + len - 1 - j]
    for j in 0..100:
      acc := self + sub[j]
  return #[acc]
`,
    seqSource: `
io run (n: U32): #[U32] =>
  let base: #[U32] = Array.with_capacity n
  for i in 0..n:
    base := base.push (i * 5 + 7)
  let frz = freeze base
  let span = Seq.from_frozen_array frz
  let acc: U32 = 0
  let seed: U32 = 314159
  for _ in 0..500:
    seed := self * 1664525 + 1013904223
    let start = seed % (n - 20_000)
    let sub = (span.slice start (start + 20_000)).reverse
    let head = sub.slice 0 100
    for x in head:
      acc := self + x
  return #[acc]
`,
  },

  // 12. Persistent CoW branching on skewed 64B sum (1,000 versions from 50k base + 1 edit each)
  {
    id: "packed_sum_cow",
    label: "12. 1,000× CoW snapshot + 1 edit on 50k skewed 64B sum",
    arg: 50_000,
    freshPerSample: true,
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
  let frz = freeze evs
  let acc: U32 = 0
  for v in 0..1000:
    let snap = copy frz
    let idx = (v * 97) % n
    let vv = v.to_u64
    snap[idx] := $Big { a: vv, b: 0u64, c: 0u64, d: 0u64, e: 0u64, f: 0u64, g: 0u64, h: vv + 1u64 }
    case snap[idx] of
      $Tick =>
        acc := self + 1
      $Big { a, h } =>
        acc := self + a.to_u32 + h.to_u32
    case snap[(idx + 1) % n] of
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
  let frz = freeze evs
  let acc: U32 = 0
  for v in 0..1000:
    let snap = copy frz
    let idx = (v * 97) % n
    let vv = v.to_u64
    snap[idx] := $Big { a: vv, b: 0u64, c: 0u64, d: 0u64, e: 0u64, f: 0u64, g: 0u64, h: vv + 1u64 }
    case snap[idx] of
      $Tick =>
        acc := self + 1
      $Big { a, h } =>
        acc := self + a.to_u32 + h.to_u32
    case snap[(idx + 1) % n] of
      $Tick =>
        acc := self + 1
      $Big { a, h } =>
        acc := self + a.to_u32 + h.to_u32
  return #[acc]
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
console.log(
  `Runtime: ${wtimeAotPath ? `wtime-aot (${wtimeAotPath})` : "Deno/V8"}`,
);
console.log(`Samples: ${samples} (warmup: ${warmup})\n`);

async function runMeasure(
  bytes: Uint8Array,
  exportName: string,
  arg: number | null,
  opts: { freshPerSample?: boolean } = {},
): Promise<VariantResult> {
  if (wtimeAotPath) {
    return await measureVariantWtimeAot(bytes, arg, opts);
  }
  return await measureVariant(bytes, exportName, arg, opts);
}

interface Row {
  id: string;
  label: string;
  arr?: VariantResult;
  packed?: VariantResult;
  seq?: VariantResult;
}

const rows: Row[] = [];
try {
  for (const b of benchmarks) {
    const row: Row = { id: b.id, label: b.label };
    if (b.arraySource) {
      const bytes = await compileModule(b.arraySource);
      row.arr = await runMeasure(bytes, "run", b.arg, {
        freshPerSample: b.freshPerSample,
      });
    }
    if (b.packedSource) {
      const bytes = await compileModule(b.packedSource);
      row.packed = await runMeasure(bytes, "run", b.arg, {
        freshPerSample: b.freshPerSample,
      });
    }
    if (b.seqSource) {
      const bytes = await compileModule(b.seqSource);
      row.seq = await runMeasure(bytes, "run", b.arg, {
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
      } (${fmtMem(row.packed)})  |  ~[T]: ${fmtMs(row.seq)} (${
        fmtMem(row.seq)
      })`,
    );
  }
} finally {
  if (wtimeWorkDir) {
    await Deno.remove(wtimeWorkDir, { recursive: true });
  }
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
