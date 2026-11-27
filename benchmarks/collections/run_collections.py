#!/usr/bin/env python3
"""Cross-language Collection Families benchmark suite (Suite 8).

Compares Squid's three one-symbol collection families:
  - #[T]  (Array T)  — contiguous flat indexable array
  - %[T]  (Packed T) — non-indexable dense sequential array (SoA / split-stream)
  - ~[T]  (Seq T)    — Design H reversible generative SIMD-RRB sequence
executed via wtime-aot 0.1.11 (--backend x64 --target-cpu native --guard-pages
--blot-cdylib), against bit-exact C++20 (clang++ -O3 -march=native: std::vector,
std::deque, manual SoA / split-stream) and Rust (rustc -O: Vec, VecDeque, manual
SoA / split-stream, and imbl::Vector persistent RRB-tree).

Verifies 100% bit-exact u32 checksum parity across every implementation, records
in-process median latency (CLOCK_MONOTONIC), Wasm linear memory, and exact
per-process peak RSS via benchmarks/goose-suite/measure_proc.c, writes
benchmarks/evidence/measurements/2026-11-27-collections/results.json, and renders
editorial SVG charts.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import platform
import shutil
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SQUIDC = ROOT / "compiler-goose/build/squidc-goose"
PRELUDE = ROOT / "std/prelude.sq"
STD_ROOT = ROOT / "std"
MEASURE_SRC = ROOT / "benchmarks/goose-suite/measure_proc.c"
WORK_DIR = ROOT / "build/collections-work"
OUT_DIR = ROOT / "benchmarks/evidence/measurements/2026-11-27-collections"

SQUID_RUNNER_C = r"""
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
        fprintf(stderr, "invalid result ptr %u (mem_len=%zu)\n", ptr, mem_len);
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
    if (!dl) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }
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

    if (samples <= 0) {
        printf("0.000000 %zu %" PRIu32 "\n", mem_bytes, checksum);
        dlclose(dl);
        return 0;
    }

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
            if (r != checksum) return 6;
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
    printf("%.6f %zu %" PRIu32 "\n", times[samples / 2], mem_bytes, checksum);
    free(times);
    dlclose(dl);
    return 0;
}
"""

BENCHMARKS = [
    {
        "id": "flat_scan",
        "title": "Flat U32 build + 10× sum",
        "subtitle": "N = 100,000 sequential push + 10× full scan",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
io run (n: U32): #[U32] =>
  let xs: #[U32] = Array.with_capacity n
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
""",
            "packed": """
io run (n: U32): #[U32] =>
  let xs: %[U32] = Packed.with_capacity n
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
""",
            "seq": """
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push (i * 3 + 1)
  let acc: U32 = 0
  for _ in 0..10:
    for x in xs:
      acc := self + x
  return #[acc]
""",
        },
        "cpp": ["vector", "deque"],
        "rust": ["vec", "deque", "imbl"],
    },
    {
        "id": "random_index",
        "title": "200k random lookups",
        "subtitle": "N = 100,000 scattered LCG indexing",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector", "deque"],
        "rust": ["vec", "deque", "imbl"],
    },
    {
        "id": "skewed_sum",
        "title": "Skewed 64B sum (20× scan)",
        "subtitle": "N = 100,000 · 99% $Tick / 1% 64B $Big",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "packed": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector", "manual_split"],
        "rust": ["vec", "manual_split", "imbl"],
    },
    {
        "id": "wide_soa",
        "title": "Wide 72B Record (80× 2-col scan)",
        "subtitle": "N = 100,000 · 10 fields, reads only id & hp",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
type Entity = { id: U32, hp: U32, x: F64, y: F64, z: F64, vx: F64, vy: F64, vz: F64, mass: F64, flags: U32 }

io run (n: U32): #[U32] =>
  let ps: #[Entity] = Array.with_capacity n
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
""",
            "packed": """
type Entity = { id: U32, hp: U32, x: F64, y: F64, z: F64, vx: F64, vy: F64, vz: F64, mass: F64, flags: U32 }

io run (n: U32): #[U32] =>
  let ps: %[Entity] = Packed.with_capacity n
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
""",
            "seq": """
type Entity = { id: U32, hp: U32, x: F64, y: F64, z: F64, vx: F64, vy: F64, vz: F64, mass: F64, flags: U32 }

io run (n: U32): #[U32] =>
  let ps: ~[Entity] = ~[]
  for i in 0..n:
    ps := ps.push { id: i, hp: i * 2 + 1, x: 1.0f64, y: 2.0f64, z: 3.0f64, vx: 4.0f64, vy: 5.0f64, vz: 6.0f64, mass: 7.0f64, flags: 1 }
  let acc: U32 = 0
  for _ in 0..80:
    for { id, hp } in ps:
      acc := self + id + hp
  return #[acc]
""",
        },
        "cpp": ["vector", "manual_soa"],
        "rust": ["vec", "manual_soa", "imbl"],
    },
    {
        "id": "reverse_ops",
        "title": "100× reverse + reverse_range",
        "subtitle": "N = 100,000 · O(1) lazy rev bit vs O(n)",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
io run (n: U32): #[U32] =>
  let xs = Seq.ramp 0 1 n
  let acc: U32 = 0
  for k in 0..100:
    xs := xs.reverse
    xs := xs.reverse_range (k * 100) (n - k * 100)
    acc := self + xs[0] + xs[n / 2] + xs[n - 1]
  return #[acc]
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
    {
        "id": "generative_1m",
        "title": "1M ramp + edit + 1k reads + slice",
        "subtitle": "N = 1,000,000 · O(1) generative leaf vs materialized",
        "n": 1_000_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
    {
        "id": "snapshot_cow",
        "title": "2,000× CoW snapshot + 1 edit",
        "subtitle": "N = 50,000 U32 base · persistent branching",
        "n": 50_000,
        "fresh": True,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
    {
        "id": "cursor_insert",
        "title": "2,000 cursor-local middle inserts",
        "subtitle": "N = 20,000 · FocusGap O(1) vs array shift",
        "n": 20_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
io run (n: U32): #[U32] =>
  let xs: ~[U32] = ~[]
  for i in 0..n:
    xs := xs.push i
  let mid = n / 2
  for k in 0..2000:
    xs := xs.insert (mid + k) (100000 + k)
  return #[xs[mid] + xs[mid + 1999] + xs[mid + 2000] + xs.length]
""",
        },
        "cpp": ["vector", "deque"],
        "rust": ["vec", "deque", "imbl"],
    },
    {
        "id": "front_deque",
        "title": "Front deque (5k push + 2.5k pop)",
        "subtitle": "push_front + pop_front on U32",
        "n": 5_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector", "deque"],
        "rust": ["vec", "deque", "imbl"],
    },
    {
        "id": "split_concat",
        "title": "500× split+concat rotations",
        "subtitle": "N = 50,000 · O(log_16 n) RRB split/concat",
        "n": 50_000,
        "fresh": True,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
    {
        "id": "frozen_span",
        "title": "500× frozen-array slice+reverse",
        "subtitle": "N = 100,000 · zero-copy Seq.from_frozen_array",
        "n": 100_000,
        "fresh": False,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
    {
        "id": "packed_sum_cow",
        "title": "1,000× CoW edit on 50k 64B sum",
        "subtitle": "N = 50,000 skewed sum · persistent packed leaves",
        "n": 50_000,
        "fresh": True,
        "squid": {
            "array": """
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
""",
            "seq": """
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
""",
        },
        "cpp": ["vector"],
        "rust": ["vec", "imbl"],
    },
]


def resolve_wtime_aot() -> Path:
    env = os.environ.get("WTIME_AOT_BIN")
    if env and Path(env).is_file():
        return Path(env)
    sib = ROOT.parent / "wtime/tools/wtime-aot/target/release/wtime-aot"
    if sib.is_file():
        return sib
    found = shutil.which("wtime-aot")
    if found:
        return Path(found)
    raise SystemExit("wtime-aot not found")


def run_cmd(argv: list[str], cwd: Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
    r = subprocess.run([str(a) for a in argv], cwd=cwd, env=env, capture_output=True, text=True, errors="replace")
    if r.returncode != 0:
        raise RuntimeError(f"command failed ({r.returncode}): {' '.join(str(a) for a in argv)}\n{r.stdout}\n{r.stderr}")
    return r


def measure_peak_rss(measure_bin: Path, argv: list[str]) -> int:
    with tempfile.NamedTemporaryFile(prefix="col_rss_", suffix=".txt", delete=False) as tf:
        mpath = Path(tf.name)
    try:
        run_cmd([str(measure_bin), str(mpath), *argv])
        parts = mpath.read_text().strip().split()
        return int(parts[2])
    finally:
        mpath.unlink(missing_ok=True)


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def git_rev(path: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(path), "rev-parse", "--short", "HEAD"], text=True).strip()
    except Exception:
        return "unknown"


def fmt_ms(ms: float) -> str:
    if ms < 1.0:
        return f"{ms * 1000.0:.1f} µs"
    if ms < 10.0:
        return f"{ms:.2f} ms"
    return f"{ms:.1f} ms"


def fmt_mem(b: int) -> str:
    if b >= 1024 * 1024:
        return f"{b / (1024 * 1024):.1f} MiB"
    return f"{b / 1024.0:.0f} KiB"


def render_charts(data: dict, out_dir: Path) -> None:
    FONT = "'DejaVu Sans', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
    BG_CANVAS, BG_CARD, BORDER = "#fafaf8", "#ffffff", "#e2e8f0"
    TEXT_MAIN, TEXT_SUB, TEXT_MUTED, GRID = "#0f172a", "#475569", "#64748b", "#f1f5f9"

    # Chart 1: Squid 3-way (#[T] vs %[T] vs ~[T]) on wtime-aot 0.1.11 (all 12 workloads, 3x4 grid)
    C_ARR = "#3b607e"
    C_PCK = "#059669"
    C_SEQ = "#0f766e"
    w, h = 1040, 748
    els = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="Squid 3-way Collection Families Benchmark">',
        "  <title>Squid Collection Families: #[T] vs %[T] vs ~[T] (wtime-aot x64)</title>",
        f'  <rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="12" fill="{BG_CANVAS}" stroke="{BORDER}"/>',
        f'  <text x="28" y="36" font-family="{FONT}" font-size="20" font-weight="700" fill="{TEXT_MAIN}">Squid Collection Families: #[T] vs %[T] vs ~[T]</text>',
        f'  <text x="28" y="57" font-family="{FONT}" font-size="11.8" fill="{TEXT_SUB}">Native wtime-aot {html.escape(data["meta"]["wtime_aot"])} (--guard-pages) · median of {data["meta"]["samples"]} runs · bit-exact checksums · lower is better</text>',
    ]
    lx = 28.0
    for col, lbl in [(C_ARR, "#[T] Array (contiguous flat)"), (C_PCK, "%[T] Packed (auto SoA / split-stream)"), (C_SEQ, "~[T] Seq (Design H SIMD-RRB + FocusGap)")]:
        els.append(f'  <rect x="{lx:.1f}" y="73" width="12" height="12" rx="3" fill="{col}"/>')
        els.append(f'  <text x="{lx + 17:.1f}" y="83" font-family="{FONT}" font-size="11.2" font-weight="500" fill="{TEXT_SUB}">{html.escape(lbl)}</text>')
        lx += 17 + len(lbl) * 6.3 + 22

    cw, ch, gx, gy = 316, 144, 18, 16
    for idx, b in enumerate(data["benchmarks"]):
        col_i, row_i = idx % 3, idx // 3
        cx = 28 + col_i * (cw + gx)
        cy = 100 + row_i * (ch + gy)
        els.append(f'  <rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els.append(f'  <text x="{cx + 12}" y="{cy + 21}" font-family="{FONT}" font-size="12.2" font-weight="700" fill="{TEXT_MAIN}">{html.escape(b["title"])}</text>')
        els.append(f'  <text x="{cx + 12}" y="{cy + 36}" font-family="{FONT}" font-size="9.8" fill="{TEXT_MUTED}">{html.escape(b["subtitle"])}</text>')

        bars = []
        sq = b["squid"]
        if "array" in sq:
            bars.append(("#[T]", sq["array"]["ms"], sq["array"]["mem_bytes"], C_ARR))
        if "packed" in sq:
            bars.append(("%[T]", sq["packed"]["ms"], sq["packed"]["mem_bytes"], C_PCK))
        if "seq" in sq:
            bars.append(("~[T]", sq["seq"]["ms"], sq["seq"]["mem_bytes"], C_SEQ))
        vmax = max(x[1] for x in bars)
        fastest = min(bars, key=lambda x: x[1])
        runner_up = sorted(bars, key=lambda x: x[1])[1]
        ratio = runner_up[1] / fastest[1]
        badge = f"{fastest[0]} {ratio:.1f}×" if ratio >= 1.15 else "tie"
        bw_p = len(badge) * 6.2 + 14
        els.append(f'  <rect x="{cx + cw - 10 - bw_p:.1f}" y="{cy + 7}" width="{bw_p:.1f}" height="18" rx="9" fill="#dcfce7"/>')
        els.append(f'  <text x="{cx + cw - 10 - bw_p / 2:.1f}" y="{cy + 19.5}" font-family="{FONT}" font-size="9.8" font-weight="600" fill="#166534" text-anchor="middle">{html.escape(badge)}</text>')

        bx, bmax = cx + 46, 150.0
        for bi, (lbl, ms, mem, color) in enumerate(bars):
            by = cy + 49 + bi * 28
            bw = max(3.5, (ms / vmax) * bmax)
            els.append(f'  <text x="{cx + 12}" y="{by + 13}" font-family="{FONT}" font-size="10.8" font-weight="700" fill="{color}">{html.escape(lbl)}</text>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax:.1f}" height="17" rx="3.5" fill="{GRID}"/>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="17" rx="3.5" fill="{color}"/>')
            els.append(f'  <text x="{bx + bw + 6:.1f}" y="{by + 12.5}" font-family="{FONT}" font-size="9.8" font-weight="600" fill="{TEXT_MAIN}">{html.escape(fmt_ms(ms))} ({html.escape(fmt_mem(mem))})</text>')

    els.append(f'  <text x="28" y="{h - 12}" font-family="{FONT}" font-size="10.2" fill="{TEXT_MUTED}">Memory shown in parentheses is committed Wasm linear memory after one fresh call. {html.escape(data["meta"]["cpu"])}.</text>')
    els.append("</svg>\n")
    (out_dir / "collections_3way.svg").write_text("\n".join(els), encoding="utf-8")

    # Chart 2: Cross-Language Comparison (Squid vs C++20 vs Rust Vec/VecDeque/SoA vs Rust imbl::Vector)
    # 8 flagship cards (2x4 grid)
    cross_specs = [
        ("flat_scan", "Flat U32 build + 10× sum (100k)", [
            ("Squid #[T]", "squid", "array", C_ARR),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("C++ vector", "cpp", "vector", "#334155"),
            ("Rust Vec", "rust", "vec", "#c2592b"),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
        ]),
        ("random_index", "200k random lookups (100k)", [
            ("Squid #[T]", "squid", "array", C_ARR),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("C++ vector", "cpp", "vector", "#334155"),
            ("Rust Vec", "rust", "vec", "#c2592b"),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
        ]),
        ("skewed_sum", "Skewed 64B sum (20× scan, 100k)", [
            ("Squid %[T]", "squid", "packed", C_PCK),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("C++ vector", "cpp", "vector", "#334155"),
            ("C++ split*", "cpp", "manual_split", "#64748b"),
            ("Rust Vec", "rust", "vec", "#c2592b"),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
        ]),
        ("wide_soa", "Wide 72B Record (80× 2-col, 100k)", [
            ("Squid %[T]", "squid", "packed", C_PCK),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("C++ AoS", "cpp", "vector", "#334155"),
            ("C++ SoA*", "cpp", "manual_soa", "#64748b"),
            ("Rust AoS", "rust", "vec", "#c2592b"),
            ("Rust SoA*", "rust", "manual_soa", "#ea580c"),
        ]),
        ("snapshot_cow", "2,000× CoW snapshot + 1 edit (50k)", [
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
            ("C++ vector", "cpp", "vector", "#334155"),
            ("Rust Vec", "rust", "vec", "#c2592b"),
        ]),
        ("cursor_insert", "2,000 cursor middle inserts (20k)", [
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
            ("C++ deque", "cpp", "deque", "#64748b"),
            ("Rust VecDeque", "rust", "deque", "#ea580c"),
            ("C++ vector", "cpp", "vector", "#334155"),
        ]),
        ("front_deque", "Front deque: 5k push + 2.5k pop", [
            ("C++ deque", "cpp", "deque", "#64748b"),
            ("Rust VecDeque", "rust", "deque", "#ea580c"),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("Rust imbl", "rust", "imbl", "#9333ea"),
            ("C++ vector", "cpp", "vector", "#334155"),
        ]),
        ("split_concat", "500× split+concat rotations (50k)", [
            ("Rust imbl", "rust", "imbl", "#9333ea"),
            ("Squid ~[T]", "squid", "seq", C_SEQ),
            ("C++ vector", "cpp", "vector", "#334155"),
            ("Rust Vec", "rust", "vec", "#c2592b"),
        ]),
    ]

    by_id = {b["id"]: b for b in data["benchmarks"]}
    w2, h2 = 1040, 880
    els2 = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w2}" height="{h2}" viewBox="0 0 {w2} {h2}" role="img" aria-label="Collections Cross-Language Benchmark: Squid vs C++20 and Rust">',
        "  <title>Collections Cross-Language Benchmark: Squid vs C++20 and Rust</title>",
        f'  <rect x="0.5" y="0.5" width="{w2 - 1}" height="{h2 - 1}" rx="12" fill="{BG_CANVAS}" stroke="{BORDER}"/>',
        f'  <text x="28" y="36" font-family="{FONT}" font-size="20" font-weight="700" fill="{TEXT_MAIN}">Collections Suite: Squid vs C++20 (-O3 native) &amp; Rust (Vec / VecDeque / imbl)</text>',
        f'  <text x="28" y="57" font-family="{FONT}" font-size="11.6" fill="{TEXT_SUB}">Median in-process latency (lower is better) · 100% bit-exact checksum parity · {html.escape(data["meta"]["cpu"])}</text>',
    ]
    cw2, ch2, gx2, gy2 = 482, 180, 20, 16
    for idx, (bid, title, items) in enumerate(cross_specs):
        col_i, row_i = idx % 2, idx // 2
        cx = 28 + col_i * (cw2 + gx2)
        cy = 78 + row_i * (ch2 + gy2)
        b = by_id[bid]
        els2.append(f'  <rect x="{cx}" y="{cy}" width="{cw2}" height="{ch2}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els2.append(f'  <text x="{cx + 14}" y="{cy + 22}" font-family="{FONT}" font-size="12.8" font-weight="700" fill="{TEXT_MAIN}">{html.escape(title)}</text>')

        rows = []
        for lbl, grp, var, col in items:
            ms = b[grp][var]["ms"]
            rows.append((lbl, ms, col, grp == "squid"))
        rows.sort(key=lambda r: r[1])
        vmax = max(r[1] for r in rows)
        bx, bmax = cx + 114, 276.0
        row_step = 23 if len(rows) >= 6 else 27
        for ri, (lbl, ms, col, is_sq) in enumerate(rows):
            by = cy + 34 + ri * row_step
            bw = max(3.5, (ms / vmax) * bmax)
            els2.append(f'  <text x="{cx + 14}" y="{by + 13}" font-family="{FONT}" font-size="10.5" font-weight="{"700" if is_sq else "500"}" fill="{col if is_sq else TEXT_MAIN}">{html.escape(lbl)}</text>')
            els2.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax:.1f}" height="16" rx="3.5" fill="{GRID}"/>')
            els2.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="16" rx="3.5" fill="{col}"/>')
            els2.append(f'  <text x="{bx + bw + 7:.1f}" y="{by + 12.5}" font-family="{FONT}" font-size="10.4" font-weight="{"700" if is_sq else "600"}" fill="{TEXT_MAIN}">{html.escape(fmt_ms(ms))}</text>')

    els2.append(f'  <text x="28" y="{h2 - 12}" font-family="{FONT}" font-size="10.2" fill="{TEXT_MUTED}">Sorted fastest → slowest per card. *C++/Rust split &amp; SoA are hand-written multi-vector structures; Squid %[T]/~[T] generate them from a single type symbol.</text>')
    els2.append("</svg>\n")
    (out_dir / "collections_cross_lang.svg").write_text("\n".join(els2), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--samples", type=int, default=11)
    ap.add_argument("--warmup", type=int, default=3)
    args = ap.parse_args()

    wtime = resolve_wtime_aot()
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Build helpers: measure_proc, squid runner, C++20 binary, Rust (+ imbl) binary
    print("Building runners & reference binaries...", flush=True)
    measure_bin = WORK_DIR / "measure_proc"
    run_cmd(["clang", "-O2", str(MEASURE_SRC), "-o", str(measure_bin)])

    squid_runner_c = WORK_DIR / "squid_col_runner.c"
    squid_runner_c.write_text(SQUID_RUNNER_C)
    squid_runner = WORK_DIR / "squid_col_runner"
    run_cmd(["clang", "-O2", str(squid_runner_c), "-ldl", "-o", str(squid_runner)])

    cpp_bin = WORK_DIR / "cpp_collections"
    run_cmd(["clang++", "-std=c++20", "-O3", "-march=native", str(HERE / "cpp_collections.cpp"), "-o", str(cpp_bin)])

    rust_target = WORK_DIR / "rust-target"
    env = dict(os.environ, CARGO_TARGET_DIR=str(rust_target))
    run_cmd(["cargo", "build", "--release", "--manifest-path", str(HERE / "Cargo.toml")], env=env)
    rust_bin = rust_target / "release/rust_collections"

    results = []
    for b in BENCHMARKS:
        bid = b["id"]
        n = b["n"]
        fresh = "1" if b["fresh"] else "0"
        print(f"\n=== {bid}: {b['title']} (N={n:,}) ===", flush=True)
        row: dict = {
            "id": bid,
            "title": b["title"],
            "subtitle": b["subtitle"],
            "n": n,
            "squid": {},
            "cpp": {},
            "rust": {},
        }
        expected_chk: int | None = None

        # Squid variants
        for var, src in b["squid"].items():
            sq = WORK_DIR / f"{bid}_{var}.sq"
            wa = WORK_DIR / f"{bid}_{var}.wasm"
            so = WORK_DIR / f"{bid}_{var}.so"
            sq.write_text(src)
            t0 = time.perf_counter()
            run_cmd([str(SQUIDC), "build", str(sq), str(wa), "--prelude", str(PRELUDE), "--std-root", str(STD_ROOT)])
            squidc_ms = (time.perf_counter() - t0) * 1000.0
            t1 = time.perf_counter()
            run_cmd([str(wtime), str(wa), "-o", str(so), "--backend", "x64", "--target-cpu", "native", "--guard-pages", "--blot-cdylib"])
            aot_ms = (time.perf_counter() - t1) * 1000.0

            r = run_cmd([str(squid_runner), str(so), str(n), str(args.warmup), str(args.samples), fresh])
            ms_s, mem_s, chk_s = r.stdout.strip().split()
            ms, mem, chk = float(ms_s), int(mem_s), int(chk_s)
            rss = measure_peak_rss(measure_bin, [str(squid_runner), str(so), str(n), "0", "0", "0"])
            if expected_chk is None:
                expected_chk = chk
            else:
                assert chk == expected_chk, f"Checksum mismatch on {bid} squid/{var}: {chk} vs {expected_chk}"
            row["squid"][var] = {
                "ms": round(ms, 5),
                "mem_bytes": mem,
                "rss_bytes": rss,
                "checksum": chk,
                "wasm_bytes": wa.stat().st_size,
                "squidc_ms": round(squidc_ms, 2),
                "aot_ms": round(aot_ms, 2),
            }
            print(f"  squid/{var:7s}: {fmt_ms(ms):>10s}  wasm_mem={fmt_mem(mem):>8s}  rss={fmt_mem(rss):>8s}  chk={chk}", flush=True)

        # C++ variants
        for var in b["cpp"]:
            r = run_cmd([str(cpp_bin), bid, var, str(n), str(args.warmup), str(args.samples)])
            ms_s, chk_s = r.stdout.strip().split()
            ms, chk = float(ms_s), int(chk_s)
            rss = measure_peak_rss(measure_bin, [str(cpp_bin), bid, var, str(n), "0", "1"])
            assert chk == expected_chk, f"Checksum mismatch on {bid} cpp/{var}: {chk} vs {expected_chk}"
            row["cpp"][var] = {"ms": round(ms, 5), "rss_bytes": rss, "checksum": chk}
            print(f"  cpp/{var:12s}: {fmt_ms(ms):>10s}  rss={fmt_mem(rss):>8s}  chk={chk}", flush=True)

        # Rust variants
        for var in b["rust"]:
            r = run_cmd([str(rust_bin), bid, var, str(n), str(args.warmup), str(args.samples)])
            ms_s, chk_s = r.stdout.strip().split()
            ms, chk = float(ms_s), int(chk_s)
            rss = measure_peak_rss(measure_bin, [str(rust_bin), bid, var, str(n), "0", "1"])
            assert chk == expected_chk, f"Checksum mismatch on {bid} rust/{var}: {chk} vs {expected_chk}"
            row["rust"][var] = {"ms": round(ms, 5), "rss_bytes": rss, "checksum": chk}
            print(f"  rust/{var:11s}: {fmt_ms(ms):>10s}  rss={fmt_mem(rss):>8s}  chk={chk}", flush=True)

        results.append(row)

    wtime_ver = "0.1.11"
    wt_toml = ROOT.parent / "wtime/tools/wtime-aot/Cargo.toml"
    if wt_toml.is_file():
        for ln in wt_toml.read_text().splitlines():
            if ln.strip().startswith("version = "):
                wtime_ver = ln.split('"')[1]
                break
    clang_ver = subprocess.check_output(["clang++", "--version"], text=True).splitlines()[0]
    rust_ver = subprocess.check_output(["rustc", "--version"], text=True).strip()
    out = {
        "meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "cpu": cpu_model(),
            "os": f"{platform.system()} {platform.release()} ({platform.machine()})",
            "squid_commit": git_rev(ROOT),
            "wtime_aot": f"{wtime_ver} ({git_rev(ROOT.parent / 'wtime')})",
            "clang": clang_ver,
            "rust": rust_ver,
            "imbl": "6",
            "samples": args.samples,
            "warmup": args.warmup,
        },
        "benchmarks": results,
    }
    (OUT_DIR / "results.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    render_charts(out, OUT_DIR)
    print(f"\nWrote {OUT_DIR / 'results.json'}, collections_3way.svg, collections_cross_lang.svg")


if __name__ == "__main__":
    main()
