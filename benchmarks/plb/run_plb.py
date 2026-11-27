#!/usr/bin/env python3
"""Run and chart the Programming-Language-Benchmarks (PLB) suite for Blot vs
official unmodified PLB Go, Rust, C, and C++ reference programs.

Measures single-process CPU time (ru_utime + ru_stime), wall time, and exact
per-child peak RSS via benchmarks/goose-suite/measure_proc.c, verifying exact
output against official PLB *_out files and cross-checking full benchmark inputs
against official Go/Rust outputs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
BLOT_DIR = HERE / "blot"
PLB_ROOT = REPO / "build" / "upstream-benches" / "PLB"
PLB_ALGO = PLB_ROOT / "bench" / "algorithm"
WORK_DIR = REPO / "build" / "plb-work"
MEASURE_SRC = REPO / "benchmarks" / "goose-suite" / "measure_proc.c"

BLOTC = REPO / "compiler-goose" / "build" / "blotc-goose"
PRELUDE = REPO / "std" / "prelude.blot"
STD_ROOT = REPO / "std"

PROBLEMS = [
    {
        "name": "helloworld",
        "blot_file": "helloworld.blot",
        "blot_mode": "str",
        "unittests": [(["QwQ"], "QwQ_out"), (["T_T"], "T_T_out")],
        "bench_args": ["QwQ"],
        "bench_label": "arg = QwQ (process launch)",
        "refs": {"go": "1.go", "rust": "1.rs", "c": "1.c", "cpp": "1.cpp"},
        "reps": 15,
    },
    {
        "name": "nsieve",
        "blot_file": "nsieve.blot",
        "blot_mode": "int",
        "unittests": [(["4"], "4_out"), (["5"], "5_out")],
        "bench_args": ["12"],
        "bench_label": "n = 12 (up to 40,960,000)",
        "refs": {"go": "1.go", "rust": "1.rs", "c": "1.c", "cpp": "1.cpp"},
        "reps": 3,
    },
    {
        "name": "binarytrees",
        "blot_file": "binarytrees.blot",
        "blot_mode": "int",
        "unittests": [(["6"], "6_out"), (["10"], "10_out")],
        "bench_args": ["18"],
        "bench_label": "depth = 18",
        "refs": {"go": "1.go", "rust": "3.rs"},
        "reps": 3,
    },
    {
        "name": "merkletrees",
        "blot_file": "merkletrees.blot",
        "blot_mode": "int",
        "unittests": [(["9"], "9_out"), (["10"], "10_out")],
        "bench_args": ["17"],
        "bench_label": "depth = 17",
        "refs": {"go": "1.go", "rust": "1.rs"},
        "reps": 3,
    },
    {
        "name": "fannkuch-redux",
        "blot_file": "fannkuch_redux.blot",
        "blot_mode": "int",
        "unittests": [(["7"], "7_out"), (["10"], "10_out")],
        "bench_args": ["11"],
        "bench_label": "n = 11 (39,916,800 perms)",
        "refs": {"go": "1.go", "rust": "1.rs", "cpp": "1-im.cpp"},
        "reps": 3,
    },
    {
        "name": "fasta",
        "blot_file": "fasta.blot",
        "blot_mode": "fasta",
        "unittests": [(["1000"], "1000_out")],
        "bench_args": ["2500000"],
        "bench_label": "n = 2,500,000 (25.4 MB DNA)",
        "refs": {"go": "3.go", "rust": "1.rs"},
        "reps": 3,
    },
    {
        "name": "pidigits",
        "blot_file": "pidigits.blot",
        "blot_mode": "int",
        "unittests": [(["27"], "27_out"), (["30"], "30_out")],
        "bench_args": ["8000"],
        "bench_label": "8,000 digits of pi",
        "refs": {"go": "8.go"},
        "reps": 3,
    },
    {
        "name": "lru",
        "blot_file": "lru.blot",
        "blot_mode": "int",
        "unittests": [
            (["10", "1000"], "10_1000_out"),
            (["77", "7777"], "77_7777_out"),
            (["100", "10000"], "100_10000_out"),
        ],
        "bench_args": ["1000", "3000000"],
        "bench_label": "size = 1,000 · 3,000,000 ops",
        "refs": {"go": "3.go"},
        "reps": 3,
    },
    {
        "name": "coro-prime-sieve",
        "blot_file": "coro_prime_sieve.blot",
        "blot_mode": "int",
        "unittests": [(["100"], "100_out"), (["200"], "200_out")],
        "bench_args": ["4000"],
        "bench_label": "first 4,000 primes",
        "refs": {"go": "1.go"},
        "reps": 3,
    },
    {
        "name": "nbody",
        "blot_file": "nbody.blot",
        "blot_mode": "u8",
        "unittests": [(["1000"], "1000_out"), (["10000"], "10000_out")],
        "bench_args": ["5000000"],
        "bench_label": "5,000,000 steps (F64x2 SIMD)",
        "refs": {"go": "1.go", "rust": "1.rs", "c": "2.c", "cpp": "1.cpp"},
        "reps": 3,
    },
    {
        "name": "spectral-norm",
        "blot_file": "spectral_norm.blot",
        "blot_mode": "u8",
        "unittests": [(["100"], "100_out"), (["101"], "101_out")],
        "bench_args": ["4000"],
        "bench_label": "n = 4,000 (F64x2 SIMD)",
        "refs": {"go": "1.go", "rust": "2.rs", "c": "3.c"},
        "reps": 3,
    },
    {
        "name": "mandelbrot",
        "blot_file": "mandelbrot.blot",
        "blot_mode": "u8",
        "unittests": [(["200"], "200_out"), (["500"], "500_out")],
        "bench_args": ["5000"],
        "bench_label": "5,000 × 5,000 (4×F64x2 SIMD)",
        "refs": {"go": "1.go"},
        "reps": 3,
    },
    {
        "name": "json-serde",
        "blot_file": "json_serde.blot",
        "blot_mode": "json",
        "blot_flags": ["--transport-mb", "8"],
        "use_problem_cwd": True,
        "unittests": [(["sample", "10"], "sample_10_out"), (["canada", "3"], "canada_3_out")],
        "bench_args": ["canada", "15"],
        "bench_label": "canada.json × 15 (2.2 MiB)",
        "refs": {"go": "1.go"},
        "reps": 3,
    },
]

LANG_META = {
    "blot": ("Blot", "#0d7c66"),
    "c": ("C (-O3)", "#64748b"),
    "cpp": ("C++ (-O3)", "#334155"),
    "rust": ("Rust", "#c2592c"),
    "go": ("Go", "#2563eb"),
}


def resolve_wtime_aot() -> Path:
    for p in [
        REPO.parent / "wtime" / "tools" / "wtime-aot" / "target" / "release" / "wtime-aot",
        Path("/home/mewhhaha/src/wtime/tools/wtime-aot/target/release/wtime-aot"),
    ]:
        if p.exists():
            return p
    raise FileNotFoundError("wtime-aot binary not found")


def run_cmd(argv: list[str], cwd: Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
    merged_env = os.environ.copy()
    merged_env["PATH"] = f"{Path.home()}/.cargo/bin:{Path.home()}/.local/bin:{merged_env.get('PATH', '')}"
    if env:
        merged_env.update(env)
    p = subprocess.run(argv, cwd=cwd, env=merged_env, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"Command failed ({p.returncode}): {' '.join(argv)}\nSTDOUT:\n{p.stdout}\nSTDERR:\n{p.stderr}")
    return p


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def normalize_out(b: bytes) -> bytes:
    return b.replace(b"\r\n", b"\n").strip()


def measure_once(measure_bin: Path, argv: list[str], env: dict | None = None, capture_hash: bool = False, cwd: Path | None = None) -> tuple[float, float, int, str | None]:
    merged_env = os.environ.copy()
    merged_env["GOMAXPROCS"] = "1"
    merged_env["OMP_NUM_THREADS"] = "1"
    if env:
        merged_env.update(env)
    with tempfile.NamedTemporaryFile(delete=False) as tf:
        metrics_path = Path(tf.name)
    try:
        if capture_hash:
            p = subprocess.run([str(measure_bin), str(metrics_path), *argv], cwd=cwd, env=merged_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if p.returncode != 0:
                raise RuntimeError(f"Run failed ({p.returncode}): {' '.join(argv)}\nSTDERR: {p.stderr.decode(errors='replace')}")
            digest = hashlib.sha256(normalize_out(p.stdout)).hexdigest()
        else:
            p = subprocess.run([str(measure_bin), str(metrics_path), *argv], cwd=cwd, env=merged_env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            if p.returncode != 0:
                raise RuntimeError(f"Run failed ({p.returncode}): {' '.join(argv)}\nSTDERR: {p.stderr.decode(errors='replace')}")
            digest = None
        parts = metrics_path.read_text().strip().split()
        return float(parts[0]), float(parts[1]), int(parts[2]), digest
    finally:
        metrics_path.unlink(missing_ok=True)


def build_all(wtime: Path, selected: set[str] | None) -> tuple[Path, Path, dict[str, dict[str, dict]]]:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    measure_bin = WORK_DIR / "measure_proc"
    run_cmd(["clang", "-O2", str(MEASURE_SRC), "-o", str(measure_bin)])
    runner_bin = WORK_DIR / "blot_plb_runner"
    run_cmd(["clang", "-O2", str(HERE / "blot_plb_runner.c"), "-ldl", "-o", str(runner_bin)])

    bins: dict[str, dict[str, dict]] = {}
    for prob in PROBLEMS:
        name = prob["name"]
        if selected and name not in selected:
            continue
        bins[name] = {}

        # Blot
        bdir = WORK_DIR / "blot"
        bdir.mkdir(parents=True, exist_ok=True)
        wasm = bdir / f"{name}.wasm"
        so = bdir / f"{name}.so"
        t0 = time.perf_counter()
        extra_flags = prob.get("blot_flags", [])
        run_cmd([str(BLOTC), "build", str(BLOT_DIR / prob["blot_file"]), str(wasm), "--prelude", str(PRELUDE), "--std-root", str(STD_ROOT), *extra_flags])
        blotc_ms = (time.perf_counter() - t0) * 1000.0
        t1 = time.perf_counter()
        run_cmd([str(wtime), "--backend", "x64", "--target-cpu", "native", "--guard-pages", "--blot-cdylib", str(wasm), "-o", str(so)])
        aot_ms = (time.perf_counter() - t1) * 1000.0
        bins[name]["blot"] = {
            "argv": [str(runner_bin), prob["blot_mode"], str(so)],
            "compile_ms": round(blotc_ms + aot_ms, 2),
            "blotc_ms": round(blotc_ms, 2),
            "aot_ms": round(aot_ms, 2),
            "wasm_bytes": wasm.stat().st_size,
            "source": f"benchmarks/plb/blot/{prob['blot_file']}",
        }

        pdir = PLB_ALGO / name
        for lang, src_name in prob["refs"].items():
            src = pdir / src_name
            ldir = WORK_DIR / lang
            ldir.mkdir(parents=True, exist_ok=True)
            exe = ldir / name
            t0 = time.perf_counter()
            if lang == "go":
                run_cmd(["go", "build", "-o", str(exe), str(src)])
            elif lang == "rust":
                run_cmd(["rustc", "-O", "-C", "target-cpu=native", "-C", "lto=fat", "-C", "codegen-units=1", str(src), "-o", str(exe)])
            elif lang == "c":
                run_cmd(["clang", "-O3", "-fomit-frame-pointer", "-march=native", "-w", str(src), "-o", str(exe), "-lm"])
            elif lang == "cpp":
                run_cmd(["clang++", "-O3", "-std=c++20", "-fomit-frame-pointer", "-march=native", "-w", str(src), "-o", str(exe), "-pthread", "-lm"])
            bins[name][lang] = {
                "argv": [str(exe)],
                "compile_ms": round((time.perf_counter() - t0) * 1000.0, 2),
                "source": f"PLB/bench/algorithm/{name}/{src_name}",
            }
    return measure_bin, runner_bin, bins


def verify_unittests(bins: dict[str, dict[str, dict]], selected: set[str] | None) -> None:
    for prob in PROBLEMS:
        name = prob["name"]
        if selected and name not in selected:
            continue
        pdir = PLB_ALGO / name
        run_cwd = pdir if prob.get("use_problem_cwd") else None
        for args, out_file in prob["unittests"]:
            expected = normalize_out((pdir / out_file).read_bytes())
            for lang, info in bins[name].items():
                p = subprocess.run(
                    [*info["argv"], *args],
                    cwd=run_cwd,
                    env={**os.environ, "GOMAXPROCS": "1", "OMP_NUM_THREADS": "1"},
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                if p.returncode != 0:
                    raise RuntimeError(f"Unittest failed {name}/{lang} {args}: rc={p.returncode}\n{p.stderr.decode(errors='replace')}")
                actual = normalize_out(p.stdout)
                if actual != expected:
                    raise AssertionError(
                        f"OUTPUT MISMATCH {name}/{lang} args={args} vs {out_file}:\n"
                        f"EXPECTED ({len(expected)} B): {expected[:200]!r}\n"
                        f"ACTUAL   ({len(actual)} B): {actual[:200]!r}"
                    )
        print(f"  [ok] {name}: all {len(bins[name])} languages passed {len(prob['unittests'])} official unittest(s)")


def fmt_ms(v: float) -> str:
    if v >= 1000.0:
        return f"{v / 1000.0:.2f} s"
    if v >= 10.0:
        return f"{v:.1f} ms"
    return f"{v:.2f} ms"


def fmt_mib(b: int) -> str:
    return f"{b / (1024.0 * 1024.0):.1f} MiB"


def render_svg(data: dict, out_path: Path, metric: str) -> None:
    is_mem = metric == "memory"
    probs = [p for p in PROBLEMS if p["name"] in data["results"]]
    cols = 3
    rows = (len(probs) + cols - 1) // cols
    card_w, card_h = 440, 224
    gap_x, gap_y = 20, 20
    pad_x = 32
    header_h = 122
    footer_h = 46
    width = pad_x * 2 + cols * card_w + (cols - 1) * gap_x
    height = header_h + rows * card_h + (rows - 1) * gap_y + footer_h

    title = (
        "Programming-Language-Benchmarks (PLB): Peak Memory (RSS)"
        if is_mem
        else "Programming-Language-Benchmarks (PLB): Runtime (Blot vs Official Go, Rust, C &amp; C++)"
    )
    subtitle = (
        f"Exact per-process peak RSS (wait4 ru_maxrss) · single-threaded · {data['meta']['cpu']} · lower is better"
        if is_mem
        else f"Single-process CPU time (helloworld: median wall ms) · 100% verified official PLB outputs · {data['meta']['cpu']} · lower is better"
    )

    lines = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}">',
        "<style>",
        "  .bg { fill: #fafafa; }",
        "  .card { fill: #ffffff; stroke: #e2e8f0; stroke-width: 1; rx: 10; }",
        "  .title { font: 700 22px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #0f172a; }",
        "  .sub { font: 400 13px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #475569; }",
        "  .ctitle { font: 700 15px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #0f172a; }",
        "  .csub { font: 400 11.5px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #64748b; }",
        "  .lbl { font: 500 12.5px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #1e293b; }",
        "  .lbl-blot { font: 700 12.5px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #0d7c66; }",
        "  .val { font: 600 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #0f172a; }",
        "  .val-blot { font: 700 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #0d7c66; }",
        "  .badge-bg { fill: #f1f5f9; rx: 6; }",
        "  .badge-win { fill: #dcfce7; rx: 6; }",
        "  .badge-txt { font: 600 11px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #334155; }",
        "  .badge-win-txt { font: 700 11px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #166534; }",
        "  .track { fill: #f1f5f9; rx: 4; }",
        "  .leg { font: 500 12px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #334155; }",
        "  .foot { font: 400 11.5px -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; fill: #64748b; }",
        "</style>",
        f'<rect class="bg" width="{width}" height="{height}"/>',
        f'<text class="title" x="{pad_x}" y="40">{title}</text>',
        f'<text class="sub" x="{pad_x}" y="64">{subtitle}</text>',
    ]

    lx = pad_x
    for key in ["blot", "c", "cpp", "rust", "go"]:
        label, color = LANG_META[key]
        lines.append(f'<rect x="{lx}" y="82" width="13" height="13" rx="3" fill="{color}"/>')
        lines.append(f'<text class="leg" x="{lx + 19}" y="93">{label}</text>')
        lx += 19 + len(label) * 7.5 + 24

    for idx, prob in enumerate(probs):
        name = prob["name"]
        col = idx % cols
        row = idx // cols
        cx = pad_x + col * (card_w + gap_x)
        cy = header_h + row * (card_h + gap_y)
        lines.append(f'<rect class="card" x="{cx}" y="{cy}" width="{card_w}" height="{card_h}"/>')
        lines.append(f'<text class="ctitle" x="{cx + 16}" y="{cy + 26}">{name}</text>')
        lines.append(f'<text class="csub" x="{cx + 16}" y="{cy + 44}">{prob["bench_label"]}</text>')

        res = data["results"][name]
        items = []
        for lang, r in res.items():
            if is_mem:
                val = float(r["peak_rss_bytes"])
                txt = fmt_mib(r["peak_rss_bytes"])
            else:
                val = float(r["wall_ms"] if name == "helloworld" else r["cpu_ms"])
                txt = fmt_ms(val)
            items.append((lang, val, txt))
        items.sort(key=lambda x: x[1])

        # Badge comparing Blot vs Go (present on all 9)
        blot_val = next(v for l, v, _ in items if l == "blot")
        go_val = next((v for l, v, _ in items if l == "go"), None)
        if go_val and go_val > 0:
            ratio = blot_val / go_val
            if ratio < 1.0:
                badge = f"{go_val / blot_val:.2f}× faster than Go" if not is_mem else f"{go_val / blot_val:.1f}× less RAM vs Go"
                bcls, tcls = "badge-win", "badge-win-txt"
            else:
                badge = f"{ratio:.2f}× Go"
                bcls, tcls = "badge-bg", "badge-txt"
            bw = max(92, int(len(badge) * 6.4) + 16)
            bx = cx + card_w - bw - 14
            lines.append(f'<rect class="{bcls}" x="{bx}" y="{cy + 11}" width="{bw}" height="22"/>')
            lines.append(f'<text class="{tcls}" x="{bx + bw / 2}" y="{cy + 26}" text-anchor="middle">{badge}</text>')

        vmax = max(v for _, v, _ in items) or 1.0
        bar_x = cx + 92
        bar_max_w = 242
        y0 = cy + 62
        step = 30
        for i, (lang, val, txt) in enumerate(items):
            y = y0 + i * step
            label, color = LANG_META[lang]
            bw = max(4.0, (val / vmax) * bar_max_w)
            is_blot = lang == "blot"
            lines.append(f'<text class="{"lbl-blot" if is_blot else "lbl"}" x="{cx + 16}" y="{y + 14}">{label}</text>')
            lines.append(f'<rect class="track" x="{bar_x}" y="{y}" width="{bar_max_w}" height="20"/>')
            lines.append(f'<rect x="{bar_x}" y="{y}" width="{bw:.1f}" height="20" rx="4" fill="{color}"/>')
            lines.append(f'<text class="{"val-blot" if is_blot else "val"}" x="{bar_x + bw + 8:.1f}" y="{y + 14}">{txt}</text>')

    foot = (
        "Sorted fastest → slowest per problem. Official unmodified PLB Go, Rust, C, and C++ sources run single-threaded (GOMAXPROCS=1, OMP_NUM_THREADS=1)."
        if not is_mem
        else "Sorted lowest → highest peak RSS per problem. Measured via wait4(ru_maxrss) in a fresh child process."
    )
    lines.append(f'<text class="foot" x="{pad_x}" y="{height - 16}">{foot}</text>')
    lines.append("</svg>")
    out_path.write_text("\n".join(lines) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="Subset of problem names to run")
    ap.add_argument("--reps", type=int, default=None, help="Override repetitions per benchmark")
    ap.add_argument("--verify-only", action="store_true", help="Build and verify unittests only")
    ap.add_argument("--out-dir", type=Path, default=REPO / "benchmarks" / "evidence" / "measurements" / "2026-11-27-plb")
    args = ap.parse_args()

    selected = set(args.only) if args.only else None
    wtime = resolve_wtime_aot()
    print(f"Building PLB binaries ({len(selected) if selected else len(PROBLEMS)} problems)...")
    measure_bin, _, bins = build_all(wtime, selected)
    print("Verifying official PLB unittests...")
    verify_unittests(bins, selected)
    if args.verify_only:
        print("All official PLB unittests passed!")
        return

    results: dict[str, dict[str, dict]] = {}
    for prob in PROBLEMS:
        name = prob["name"]
        if selected and name not in selected:
            continue
        reps = args.reps if args.reps is not None else prob["reps"]
        bench_args = prob["bench_args"]
        run_cwd = (PLB_ALGO / name) if prob.get("use_problem_cwd") else None
        print(f"\nBenchmarking {name} ({' '.join(bench_args)}) x {reps}...")
        samples: dict[str, list[tuple[float, float, int]]] = {l: [] for l in bins[name]}
        hashes: dict[str, str] = {}
        langs = list(bins[name].keys())

        # Warmup + exact full-input hash cross-check
        for lang in langs:
            _, _, _, h = measure_once(measure_bin, [*bins[name][lang]["argv"], *bench_args], capture_hash=True, cwd=run_cwd)
            hashes[lang] = h or ""
        uniq_hashes = set(hashes.values())
        if len(uniq_hashes) != 1:
            raise AssertionError(f"Full-input SHA-256 mismatch on {name}: {hashes}")
        print(f"  [verified] full-input output SHA-256 = {next(iter(uniq_hashes))[:16]} across {langs}")

        # Interleaved timed repetitions
        for r in range(reps):
            order = langs if r % 2 == 0 else list(reversed(langs))
            for lang in order:
                wall_ms, cpu_ms, rss_b, _ = measure_once(measure_bin, [*bins[name][lang]["argv"], *bench_args], capture_hash=False, cwd=run_cwd)
                samples[lang].append((wall_ms, cpu_ms, rss_b))

        results[name] = {}
        for lang in langs:
            walls = [s[0] for s in samples[lang]]
            cpus = [s[1] for s in samples[lang]]
            rsss = [s[2] for s in samples[lang]]
            results[name][lang] = {
                "cpu_ms": round(min(cpus) if name != "helloworld" else statistics.median(cpus), 3),
                "cpu_median_ms": round(statistics.median(cpus), 3),
                "wall_ms": round(statistics.median(walls) if name == "helloworld" else min(walls), 3),
                "peak_rss_bytes": int(statistics.median(rsss)),
                "compile_ms": bins[name][lang]["compile_ms"],
                "source": bins[name][lang]["source"],
                "sha256": hashes[lang],
                "samples_cpu_ms": [round(x, 3) for x in cpus],
                "samples_wall_ms": [round(x, 3) for x in walls],
            }
            if lang == "blot":
                results[name][lang]["blotc_ms"] = bins[name][lang]["blotc_ms"]
                results[name][lang]["aot_ms"] = bins[name][lang]["aot_ms"]
                results[name][lang]["wasm_bytes"] = bins[name][lang]["wasm_bytes"]
            rinfo = results[name][lang]
            print(f"  {lang:5s}: cpu={fmt_ms(rinfo['cpu_ms']):>9s}  wall={fmt_ms(rinfo['wall_ms']):>9s}  rss={fmt_mib(rinfo['peak_rss_bytes']):>9s}")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    payload = {
        "meta": {
            "date": time.strftime("%Y-%m-%d"),
            "cpu": cpu_model(),
            "single_threaded": True,
            "problems": [p["name"] for p in PROBLEMS if p["name"] in results],
        },
        "results": results,
    }
    (args.out_dir / "results.json").write_text(json.dumps(payload, indent=2) + "\n")
    render_svg(payload, args.out_dir / "plb_runtime.svg", "runtime")
    render_svg(payload, args.out_dir / "plb_memory.svg", "memory")
    print(f"\nWrote {args.out_dir / 'results.json'}, plb_runtime.svg, and plb_memory.svg")


if __name__ == "__main__":
    main()
