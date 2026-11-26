#!/usr/bin/env python3
"""Cross-language benchmark harness mirroring Goose's 16-benchmark suite with Blot added.

Compiles and runs Goose (clang -O2), C++ idiomatic & expert (clang++ -O2),
Rust (rustc -O -C codegen-units=1), and Blot (blotc-goose + wtime-aot x64-v3
via standalone native blot_runner) on the same machine, verifying byte-for-byte
identical checksum output across every implementation and measuring:
  - whole-process wall time (best of `--reps` after 2 discarded warmups)
  - exact per-process peak RSS via `os.wait4` (`ru_maxrss`, NOT cumulative)
  - cold compile time (ms) and output binary size (bytes)

Usage:
  python3 benchmarks/goose-suite/run_suite.py --sizes medium --reps 3
  python3 benchmarks/goose-suite/run_suite.py --only sum,push,particles,blur --sizes small --reps 1
"""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUITE_DIR = Path(__file__).resolve().parent
BLOT_SRC_DIR = SUITE_DIR / "blot"
GOOSE_BENCH_DIR = ROOT / "build/goose-port/upstream-d5ae5bb/source/bench"
GOOSE_EXE_DEFAULT = ROOT / "build/goose-port/upstream-d5ae5bb/build-precision/goose"
BLOTC_DEFAULT = ROOT / "compiler-goose/build/blotc-goose"
STD_ROOT = ROOT / "std"
PRELUDE_PATH = STD_ROOT / "prelude.blot"
WORK_DIR = ROOT / "build/goose-suite-work"
OUT_JSON_DEFAULT = ROOT / "benchmarks/evidence/measurements/2026-11-26-goose-suite/results.json"

STACK_RESERVE = "GS_STACK_RESERVE=2147483648ull"
SIZE_NAMES = ["small", "medium", "large"]

GOOSE_N_RE = re.compile(r"^(\s*let\s+\w+\s*=\s*)(\d+)(\s*;.*//\s*BENCH_N.*)$")
RUST_N_RE = re.compile(r"^(\s*const\s+\w+\s*:\s*\w+\s*=\s*)(\d+)(\s*;.*//\s*BENCH_N.*)$")
BLOT_N_RE = re.compile(r"^(\s*const\s+BENCH_N\s*:\s*U32\s*=\s*)(\d+)(\s*//\s*BENCH_N.*)$")

BENCHMARKS = [
    dict(
        name="sum",
        what="Build a flat 32-bit array, then scan it 8 times.",
        param="N",
        sizes=[1_000_000, 16_000_000, 128_000_000],
        blot=[dict(label="blot grow array", file="sum.blot")],
        goose=[dict(label="goose grow-only array", file="sum.goose")],
        cpp=[
            dict(label="cpp vector", file="sum.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp vector+reserve", file="sum.cpp", variant=1, tier="expert"),
        ],
        rust=[dict(label="rust Vec, collect", file="sum.rs")],
    ),
    dict(
        name="push",
        what="Push N records while keeping links/indices to every 64th one.",
        param="N",
        sizes=[1_000_000, 16_000_000, 64_000_000],
        blot=[dict(label="blot array+reserve, indices", file="push.blot")],
        goose=[dict(label="goose array, typed references", file="push.goose")],
        cpp=[
            dict(label="cpp vector, indices", file="push.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp vector+reserve, indices", file="push.cpp", variant=1, tier="expert"),
        ],
        rust=[dict(label="rust Vec+reserve, indices", file="push.rs")],
    ),
    dict(
        name="strlist",
        what="Split a text into N words, store them, scan 4 times.",
        param="N",
        sizes=[200_000, 2_000_000, 8_000_000],
        blot=[dict(label="blot packed bytes + offsets", file="strlist.blot")],
        goose=[dict(label="goose inline strings, owned", file="strlist.goose")],
        cpp=[
            dict(label="cpp vector<string>", file="strlist.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp flat offsets", file="strlist.cpp", variant=2, tier="expert"),
        ],
        rust=[
            dict(label="rust Vec<String>", file="strlist_owned.rs"),
            dict(label="rust Vec<&str>", file="strlist_borrowed.rs"),
        ],
    ),
    dict(
        name="records",
        what="Build a log of N variant records, aggregate 4 times.",
        param="N",
        sizes=[500_000, 4_000_000, 16_000_000],
        blot=[dict(label="blot packed records + text pool", file="records.blot")],
        goose=[dict(label="goose variable enum", file="records_var.goose")],
        cpp=[
            dict(label="cpp variant + string", file="records.cpp", variant=1, tier="idiomatic"),
            dict(label="cpp variant + buffer", file="records.cpp", variant=2, tier="expert"),
        ],
        rust=[dict(label="rust enum + String", file="records.rs")],
    ),
    dict(
        name="tree",
        what="Build a complete binary tree of depth D, sum it 8 times.",
        param="depth",
        sizes=[16, 20, 24],
        blot=[dict(label="blot arena + indices", file="tree.blot")],
        goose=[dict(label="goose pool + typed relative refs", file="tree.goose")],
        cpp=[
            dict(label="cpp unique_ptr", file="tree.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp arena + indices", file="tree.cpp", variant=2, tier="expert"),
        ],
        rust=[
            dict(label="rust Box nodes", file="tree_box.rs"),
            dict(label="rust arena + indices", file="tree_arena.rs"),
        ],
    ),
    dict(
        name="interp",
        what="Build an expression tree of depth D, evaluate it 8 times.",
        param="depth",
        sizes=[16, 20, 24],
        blot=[dict(label="blot arena + tag dispatch", file="interp.blot")],
        goose=[dict(label="goose case functions + relative refs", file="interp.goose")],
        cpp=[
            dict(label="cpp virtual + unique_ptr", file="interp.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp tagged union + arena", file="interp.cpp", variant=2, tier="expert"),
        ],
        rust=[
            dict(label="rust enum + Box", file="interp_box.rs"),
            dict(label="rust enum + arena indices", file="interp_arena.rs"),
        ],
    ),
    dict(
        name="graph",
        what="Build CSR adjacency for V vertices / 8V edges, BFS from 4 sources.",
        param="V",
        sizes=[100_000, 500_000, 2_000_000],
        blot=[dict(label="blot CSR two-pass", file="graph.blot")],
        goose=[dict(label="goose CSR two-pass", file="graph_csr.goose")],
        cpp=[
            dict(label="cpp vector<vector>", file="graph.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp CSR two-pass", file="graph.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust Vec<Vec>", file="graph_nested.rs"),
            dict(label="rust CSR two-pass", file="graph_csr.rs"),
        ],
    ),
    dict(
        name="words",
        what="Count word frequencies over a text of N words.",
        param="N",
        sizes=[500_000, 4_000_000, 16_000_000],
        blot=[dict(label="blot packed bytes + open addressing", file="words.blot")],
        goose=[dict(label="goose slices + open addressing", file="words.goose")],
        cpp=[
            dict(label="cpp unordered_map<string>", file="words.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp open addressing", file="words.cpp", variant=2, tier="expert"),
        ],
        rust=[
            dict(label="rust HashMap<&str>", file="words_hashmap.rs"),
            dict(label="rust open addressing", file="words_open.rs"),
        ],
    ),
    dict(
        name="particles",
        what="Integrate N particles for 200 steps of exact binary32 vector math.",
        param="N",
        sizes=[100_000, 1_000_000, 4_000_000],
        blot=[dict(label="blot SoA, 4-wide SIMD", file="particles.blot")],
        goose=[dict(label="goose AoS, per component", file="particles_scalar.goose")],
        cpp=[
            dict(label="cpp AoS, elementwise", file="particles.cpp", variant=2, tier="idiomatic"),
            dict(label="cpp AoS, per component", file="particles.cpp", variant=0, tier="expert"),
        ],
        rust=[dict(label="rust AoS, per component", file="particles_scalar.rs")],
    ),
    dict(
        name="sexp",
        what="Generate N s-expression forms, parse into a tree, walk 4 times.",
        param="N",
        sizes=[20_000, 100_000, 300_000],
        blot=[dict(label="blot 8B arena + packed text", file="sexp.blot")],
        goose=[dict(label="goose pool + refs, inline text", file="sexp.goose")],
        cpp=[
            dict(label="cpp unique_ptr + string", file="sexp.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp arena + string_view", file="sexp.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust enum + Box + String", file="sexp_box.rs"),
            dict(label="rust arena + &str", file="sexp_arena.rs"),
        ],
    ),
    dict(
        name="lru",
        what="LRU cache of capacity N/8 under N skewed lookups & invalidations.",
        param="N",
        sizes=[2_000_000, 8_000_000, 32_000_000],
        blot=[dict(label="blot open addressing + arena", file="lru.blot")],
        goose=[dict(label="goose reusable pool + pool-relative refs", file="lru.goose")],
        cpp=[
            dict(label="cpp list + unordered_map", file="lru.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp arena + open addressing", file="lru.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust HashMap + arena", file="lru_hashmap.rs"),
            dict(label="rust open addressing + arena", file="lru_open.rs"),
        ],
    ),
    dict(
        name="scene",
        what="Build a depth-D scene graph, animate & update transforms for 16 frames.",
        param="depth",
        sizes=[12, 14, 16],
        blot=[dict(label="blot arena + inline transforms", file="scene.blot")],
        goose=[dict(label="goose pool + inline child refs", file="scene.goose")],
        cpp=[
            dict(label="cpp unique_ptr children", file="scene.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp arena + child indices", file="scene.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust Box children", file="scene_box.rs"),
            dict(label="rust arena + child indices", file="scene_arena.rs"),
        ],
    ),
    dict(
        name="calc",
        what="Generate, parse and evaluate N arithmetic expressions (1/3 malformed).",
        param="N",
        sizes=[100_000, 400_000, 1_600_000],
        blot=[dict(label="blot arena + error codes", file="calc.blot")],
        goose=[dict(label="goose local pool + return from", file="calc.goose")],
        cpp=[
            dict(label="cpp unique_ptr + exceptions", file="calc.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp arena + error codes", file="calc.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust Box + Result", file="calc_box.rs"),
            dict(label="rust arena + Result", file="calc_arena.rs"),
        ],
    ),
    dict(
        name="bintrees",
        what="Benchmarks Game binary-trees: build, check & discard trees up to depth D.",
        param="depth",
        sizes=[15, 17, 19],
        blot=[dict(label="blot arena per tree", file="bintrees.blot")],
        goose=[dict(label="goose local pool per tree", file="bintrees.goose")],
        cpp=[
            dict(label="cpp new/delete", file="bintrees.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp vector arena", file="bintrees.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust Box", file="bintrees_box.rs"),
            dict(label="rust Vec arena", file="bintrees_arena.rs"),
        ],
    ),
    dict(
        name="respond",
        what="Build & render N JSON responses with FNV-1a checksum.",
        param="N",
        sizes=[100_000, 400_000, 1_600_000],
        blot=[dict(label="blot streaming", file="respond.blot")],
        goose=[
            dict(label="goose inline DTO", file="respond.goose"),
            dict(label="goose streaming", file="respond_stream.goose"),
        ],
        cpp=[
            dict(label="cpp DTO + string", file="respond.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp streaming", file="respond.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust DTO + String", file="respond_dto.rs"),
            dict(label="rust streaming", file="respond_stream.rs"),
        ],
    ),
    dict(
        name="blur",
        what="16 passes of a 3x3 blur over a WxW 8-bit image.",
        param="W",
        sizes=[1024, 2048, 8192],
        blot=[dict(label="blot sliding 3-col, #[U8]", file="blur.blot")],
        goose=[dict(label="goose flat indexing", file="blur.goose")],
        cpp=[
            dict(label="cpp flat indexing", file="blur.cpp", variant=0, tier="idiomatic"),
            dict(label="cpp row pointers", file="blur.cpp", variant=1, tier="expert"),
        ],
        rust=[
            dict(label="rust flat indexing", file="blur_index.rs"),
            dict(label="rust row slices", file="blur_windows.rs"),
        ],
    ),
]


def resolve_wtime_aot() -> Path:
    env = os.environ.get("WTIME_AOT_BIN")
    if env and Path(env).is_file():
        return Path(env)
    sibling = ROOT.parent / "wtime/tools/wtime-aot/target/release/wtime-aot"
    if sibling.is_file():
        return sibling
    local = Path.home() / ".local/bin/wtime-aot"
    if local.is_file():
        return local
    found = shutil.which("wtime-aot")
    if found:
        return Path(found)
    raise SystemExit("wtime-aot not found")


def resolve_rustc() -> str:
    found = shutil.which("rustc")
    if found:
        return found
    cargo_bin = Path.home() / ".cargo/bin/rustc"
    if cargo_bin.is_file():
        return str(cargo_bin)
    raise SystemExit("rustc not found")


def write_sized(src: Path, dst: Path, n: int, pattern: re.Pattern[str]) -> None:
    lines = src.read_text(encoding="utf-8").splitlines()
    hit = False
    out = []
    for line in lines:
        if not hit:
            m = pattern.match(line)
            if m:
                out.append(f"{m.group(1)}{n}{m.group(3)}")
                hit = True
                continue
        out.append(line)
    if not hit:
        raise RuntimeError(f"no BENCH_N marker in {src}")
    dst.write_text("\n".join(out) + "\n", encoding="utf-8")


_MEASURE_BIN: Path | None = None


def build_measure_proc(work_dir: Path) -> Path:
    exe = work_dir / "measure_proc"
    cmd = ["clang", "-O2", str(SUITE_DIR / "measure_proc.c"), "-o", str(exe)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"failed building measure_proc:\n{r.stderr}")
    return exe


def run_measured(argv: list[str], cwd: Path | None = None) -> dict:
    """Run one child process via minimal posix_spawn wrapper for exact wall_ms, cpu_ms, and per-child peak RSS."""
    assert _MEASURE_BIN is not None
    metrics = WORK_DIR / f"metrics_{os.getpid()}.txt"
    r = subprocess.run(
        [str(_MEASURE_BIN), str(metrics), *argv],
        capture_output=True,
        cwd=str(cwd) if cwd else None,
    )
    wall_ms = 0.0
    cpu_ms = 0.0
    peak_bytes = 0
    if metrics.exists():
        parts = metrics.read_text(encoding="utf-8").strip().split()
        if len(parts) == 3:
            wall_ms = float(parts[0])
            cpu_ms = float(parts[1])
            peak_bytes = int(parts[2])
        metrics.unlink(missing_ok=True)
    return {
        "code": r.returncode,
        "wall_ms": wall_ms,
        "cpu_ms": cpu_ms,
        "ms": cpu_ms if cpu_ms > 0.0 else wall_ms,
        "peak_bytes": peak_bytes,
        "out": r.stdout.decode("utf-8", errors="replace").replace("\r\n", "\n"),
        "err": r.stderr.decode("utf-8", errors="replace").replace("\r\n", "\n"),
    }


def measure_cmd(argv: list[str], reps: int, warmups: int = 2) -> dict:
    for _ in range(warmups):
        r = run_measured(argv)
        if r["code"] != 0:
            return {"ok": False, "error": f"exit {r['code']}: {r['err'].strip()}"}
    cpu_times = []
    wall_times = []
    peak = 0
    out = ""
    for _ in range(reps):
        r = run_measured(argv)
        if r["code"] != 0:
            return {"ok": False, "error": f"exit {r['code']}: {r['err'].strip()}"}
        cpu_times.append(r["ms"])
        wall_times.append(r["wall_ms"])
        peak = max(peak, r["peak_bytes"])
        out = r["out"]
    cpu_times.sort()
    wall_times.sort()
    return {
        "ok": True,
        "ms": cpu_times[0],  # best user+sys CPU ms across reps (immune to host load preemption)
        "wall_ms": wall_times[0],
        "median_ms": cpu_times[len(cpu_times) // 2],
        "all_ms": [round(x, 3) for x in cpu_times],
        "all_wall_ms": [round(x, 3) for x in wall_times],
        "peak_bytes": peak,
        "peak_mb": round(peak / (1024 * 1024), 2),
        "out": out,
    }


def build_blot_runner(work_dir: Path) -> Path:
    runner = work_dir / "blot_runner"
    cmd = ["clang", "-O2", str(SUITE_DIR / "blot_runner.c"), "-ldl", "-o", str(runner)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"failed building blot_runner:\n{r.stderr}")
    return runner


def build_blot(
    blotc: Path,
    wtime_aot: Path,
    work_dir: Path,
    file: str,
    n: int,
    tag: str,
    wasm3: bool = False,
) -> dict:
    bdir = work_dir / "blot"
    bdir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(BLOT_SRC_DIR / "rng.blot", bdir / "rng.blot")
    src = bdir / f"{tag}.blot"
    wasm = bdir / f"{tag}.wasm"
    so = bdir / f"{tag}.so"
    write_sized(BLOT_SRC_DIR / file, src, n, BLOT_N_RE)

    t0 = time.perf_counter()
    cmd = [
        str(blotc),
        "build",
        str(src),
        str(wasm),
        "--prelude",
        str(PRELUDE_PATH),
        "--std-root",
        str(STD_ROOT),
    ]
    if wasm3:
        cmd.append("--wasm3")
    r = run_measured(cmd)
    blotc_ms = r["ms"]
    if r["code"] != 0:
        return {"ok": False, "error": f"blotc failed:\n{r['out']}\n{r['err']}"}

    r2 = run_measured(
        [
            str(wtime_aot),
            "--backend",
            "x64",
            "--target-cpu",
            "native",
            "--blot-cdylib",
            str(wasm),
            "-o",
            str(so),
        ],
    )
    aot_ms = r2["ms"]
    if r2["code"] != 0:
        return {"ok": False, "error": f"wtime-aot failed:\n{r2['out']}\n{r2['err']}"}

    return {
        "ok": True,
        "so": so,
        "wasm_bytes": wasm.stat().st_size,
        "so_bytes": so.stat().st_size,
        "blotc_ms": round(blotc_ms, 2),
        "aot_ms": round(aot_ms, 2),
        "compile_ms": round(blotc_ms + aot_ms, 2),
    }


def build_goose(goose_exe: Path, work_dir: Path, file: str, n: int, tag: str) -> dict:
    gdir = work_dir / "goose"
    gdir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(GOOSE_BENCH_DIR / "goose/rng.goose", gdir / "rng.goose")
    src = gdir / f"{tag}.goose"
    cfile = gdir / f"{tag}.c"
    exe = gdir / tag
    write_sized(GOOSE_BENCH_DIR / "goose" / file, src, n, GOOSE_N_RE)

    r = run_measured([str(goose_exe), "-O2", "--standalone", "-o", str(cfile), str(src)])
    if r["code"] != 0:
        return {"ok": False, "error": f"goose failed:\n{r['out']}\n{r['err']}"}
    r2 = run_measured(
        ["clang", "-O2", "-w", f"-D{STACK_RESERVE}", str(cfile), "-o", str(exe), "-lm", "-pthread"]
    )
    compile_ms = r["ms"] + r2["ms"]
    if r2["code"] != 0:
        return {"ok": False, "error": f"clang goose C failed:\n{r2['err']}"}
    return {"ok": True, "exe": exe, "compile_ms": round(compile_ms, 2), "bin_bytes": exe.stat().st_size}


def build_cpp(work_dir: Path, file: str, variant: int, n: int, tag: str) -> dict:
    cdir = work_dir / "cpp"
    cdir.mkdir(parents=True, exist_ok=True)
    exe = cdir / tag
    r = run_measured(
        [
            "clang++",
            "-O2",
            "-std=c++20",
            "-w",
            f"-DBENCH_N={n}",
            f"-DVARIANT={variant}",
            str(GOOSE_BENCH_DIR / "cpp" / file),
            "-o",
            str(exe),
            "-lm",
            "-pthread",
        ]
    )
    compile_ms = r["ms"]
    if r["code"] != 0:
        return {"ok": False, "error": f"clang++ failed:\n{r['err']}"}
    return {"ok": True, "exe": exe, "compile_ms": round(compile_ms, 2), "bin_bytes": exe.stat().st_size}


def build_rust(rustc: str, work_dir: Path, file: str, n: int, tag: str) -> dict:
    rdir = work_dir / "rust"
    rdir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(GOOSE_BENCH_DIR / "rust/bench.rs", rdir / "bench.rs")
    src = rdir / f"{tag}.rs"
    exe = rdir / tag
    write_sized(GOOSE_BENCH_DIR / "rust" / file, src, n, RUST_N_RE)
    r = run_measured([rustc, "-O", "-C", "codegen-units=1", "-o", str(exe), str(src)])
    compile_ms = r["ms"]
    if r["code"] != 0:
        return {"ok": False, "error": f"rustc failed:\n{r['err']}"}
    return {"ok": True, "exe": exe, "compile_ms": round(compile_ms, 2), "bin_bytes": exe.stat().st_size}


def geomean(xs: list[float]) -> float | None:
    vals = [x for x in xs if x and x > 0]
    if not vals:
        return None
    return math.exp(sum(math.log(x) for x in vals) / len(vals))


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated benchmark names")
    ap.add_argument("--sizes", default="medium", help="comma-separated: small,medium,large")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--warmups", type=int, default=2)
    ap.add_argument("--langs", default="blot,goose,cpp,rust", help="comma-separated subset of languages")
    ap.add_argument("--out", default=str(OUT_JSON_DEFAULT))
    ap.add_argument("--merge", action="store_true", help="merge into existing output JSON")
    ap.add_argument("--wasm3", action="store_true")
    args = ap.parse_args()

    only = [s.strip() for s in args.only.split(",") if s.strip()]
    sizes = [s.strip() for s in args.sizes.split(",") if s.strip()]
    langs = {s.strip() for s in args.langs.split(",") if s.strip()}

    global _MEASURE_BIN
    wtime_aot = resolve_wtime_aot()
    rustc = resolve_rustc()
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    _MEASURE_BIN = build_measure_proc(WORK_DIR)
    blot_runner = build_blot_runner(WORK_DIR) if "blot" in langs else None

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if args.merge and out_path.exists():
        state = json.loads(out_path.read_text(encoding="utf-8"))
    else:
        state = {"benchmarks": {}}

    clang_ver = subprocess.run(["clang", "--version"], capture_output=True, text=True).stdout.splitlines()[0]
    rust_ver = subprocess.run([rustc, "--version"], capture_output=True, text=True).stdout.strip()
    state["meta"] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "cpu": cpu_model(),
        "os": f"{platform.system()} {platform.release()} ({platform.machine()})",
        "clang": clang_ver,
        "rust": rust_ver,
        "wtime_aot": str(wtime_aot),
        "blotc": str(BLOTC_DEFAULT),
        "goose": str(GOOSE_EXE_DEFAULT),
        "reps": args.reps,
        "warmups": args.warmups,
        "sizes": sizes,
    }

    selected = [b for b in BENCHMARKS if not only or b["name"] in only]
    if not selected:
        raise SystemExit(f"no benchmarks matched --only {args.only}")

    failures = []
    for b in selected:
        bname = b["name"]
        bentry = state["benchmarks"].setdefault(
            bname,
            {"what": b["what"], "param": b["param"], "sizes": {}},
        )
        for si, sname in enumerate(SIZE_NAMES):
            if sname not in sizes:
                continue
            n = b["sizes"][si]
            sentry = bentry["sizes"].setdefault(sname, {"n": n, "rows": {}})
            sentry["n"] = n
            expected_out: str | None = None
            print(f"\n=== {bname} ({sname}: {b['param']}={n:,}) ===", flush=True)

            impls = []
            if "blot" in langs:
                for it in b["blot"]:
                    impls.append(("blot", it))
            if "goose" in langs:
                for it in b["goose"]:
                    impls.append(("goose", it))
            if "cpp" in langs:
                for it in b["cpp"]:
                    impls.append(("cpp", it))
            if "rust" in langs:
                for it in b["rust"]:
                    impls.append(("rust", it))

            for kind, it in impls:
                label = it["label"]
                slug = re.sub(r"[^A-Za-z0-9]+", "_", f"{bname}_{sname}_{label}").strip("_")
                if kind == "blot":
                    bsrc = BLOT_SRC_DIR / it["file"]
                    if not bsrc.exists():
                        print(f"  [SKIP] {label:38s} (missing {it['file']})", flush=True)
                        continue
                    built = build_blot(BLOTC_DEFAULT, wtime_aot, WORK_DIR, it["file"], n, slug, wasm3=args.wasm3)
                    argv = [str(blot_runner), str(built["so"])] if built["ok"] else []
                elif kind == "goose":
                    built = build_goose(GOOSE_EXE_DEFAULT, WORK_DIR, it["file"], n, slug)
                    argv = [str(built["exe"])] if built["ok"] else []
                elif kind == "cpp":
                    built = build_cpp(WORK_DIR, it["file"], it["variant"], n, slug)
                    argv = [str(built["exe"])] if built["ok"] else []
                else:
                    built = build_rust(rustc, WORK_DIR, it["file"], n, slug)
                    argv = [str(built["exe"])] if built["ok"] else []

                if not built["ok"]:
                    print(f"  [BUILD FAIL] {label:32s} {built['error'][:160]}", flush=True)
                    failures.append(f"{bname}/{sname}/{label}: build failed")
                    sentry["rows"][label] = {"kind": kind, "tier": it.get("tier"), "ok": False, "error": built["error"]}
                    continue

                res = measure_cmd(argv, args.reps, args.warmups)
                if not res["ok"]:
                    print(f"  [RUN FAIL]   {label:32s} {res['error'][:160]}", flush=True)
                    failures.append(f"{bname}/{sname}/{label}: run failed: {res['error']}")
                    sentry["rows"][label] = {"kind": kind, "tier": it.get("tier"), "ok": False, "error": res["error"]}
                    continue

                checksum_ok = True
                if expected_out is None:
                    expected_out = res["out"]
                elif res["out"] != expected_out:
                    checksum_ok = False
                    failures.append(
                        f"{bname}/{sname}/{label}: CHECKSUM MISMATCH\n  expected={expected_out.splitlines()}\n  got     ={res['out'].splitlines()}"
                    )

                status = "OK" if checksum_ok else "CHECKSUM MISMATCH"
                extra = f"compile={built['compile_ms']:.0f}ms"
                if kind == "blot":
                    extra = f"blotc={built['blotc_ms']:.0f}ms aot={built['aot_ms']:.0f}ms wasm={built['wasm_bytes']//1024}KiB"
                print(
                    f"  [{status:^6s}] {label:38s} {res['ms']:8.2f} ms  {res['peak_mb']:6.1f} MiB  ({extra})",
                    flush=True,
                )
                row_data = {
                    "kind": kind,
                    "tier": it.get("tier"),
                    "ok": checksum_ok,
                    "ms": round(res["ms"], 3),
                    "wall_ms": round(res["wall_ms"], 3),
                    "median_ms": round(res["median_ms"], 3),
                    "all_ms": res["all_ms"],
                    "all_wall_ms": res["all_wall_ms"],
                    "peak_bytes": res["peak_bytes"],
                    "peak_mb": res["peak_mb"],
                    "compile_ms": built["compile_ms"],
                    "stdout": res["out"].splitlines(),
                }
                if kind == "blot":
                    row_data["blotc_ms"] = built["blotc_ms"]
                    row_data["aot_ms"] = built["aot_ms"]
                    row_data["wasm_bytes"] = built["wasm_bytes"]
                sentry["rows"][label] = row_data

    out_path.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    print(f"\nWrote {out_path}")
    if failures:
        print("\nFAILURES:")
        for f in failures:
            print(" -", f)
        sys.exit(1)


if __name__ == "__main__":
    main()
