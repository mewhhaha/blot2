#!/usr/bin/env python3
"""Build, verify, and run the bddicken/languages suite across Squid, Goose, C, C++, and Rust.

Reads official C, C++, Rust sources and levenshtein-words.txt from
`build/upstream-benches/bddicken-languages` (or $BDDICKEN), Goose sources from
`build/goose-port/upstream-d5ae5bb/source/bench/bddicken`, and Squid sources
from `benchmarks/bddicken/squid/`.

Outputs `benchmarks/evidence/measurements/2026-11-27-bddicken/results.json`
and generates `bddicken_chart.svg`.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SQUID_DIR = HERE / "squid"
GOOSE_BDD = ROOT / "build/goose-port/upstream-d5ae5bb/source/bench/bddicken"
GOOSE_EXE = ROOT / "build/goose-port/upstream-d5ae5bb/build-precision/goose"
GOOSE_STDLIB = ROOT / "build/goose-port/upstream-d5ae5bb/source-precision/stdlib"
SQUIDC = ROOT / "compiler-goose/build/squidc-goose"
STD_ROOT = ROOT / "std"
PRELUDE = STD_ROOT / "prelude.sq"
WORK_DIR = ROOT / "build/bddicken-work"
OUT_DIR = ROOT / "benchmarks/evidence/measurements/2026-11-27-bddicken"

BENCHES = ["fibonacci", "loops", "levenshtein", "hello-world"]
LANGS = ["squid", "goose", "c", "cpp", "rust"]


def resolve_bddicken() -> Path:
    env = os.environ.get("BDDICKEN")
    if env:
        return Path(env).resolve()
    cand = ROOT / "build/upstream-benches/bddicken-languages"
    if (cand / "languages.sh").exists():
        return cand
    raise SystemExit("bddicken/languages checkout not found at build/upstream-benches/bddicken-languages")


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


def check_result(bench: str, out: str) -> bool:
    if bench == "hello-world":
        return out.strip().lower() == "hello, world!"
    lines = [ln for ln in out.strip().splitlines() if ln.strip()]
    if not lines:
        return False
    fields = lines[0].split(",")
    if len(fields) != 6:
        return False
    r = fields[5].strip()
    if bench == "fibonacci":
        return r == "24157817"
    if bench == "loops":
        return r.isdigit() and 195000 <= int(r) <= 204999
    if bench == "levenshtein":
        return r == "554324"
    return False


def build_squid_runner() -> Path:
    runner = WORK_DIR / "squid_bddicken_runner"
    run_cmd(["clang", "-O2", str(HERE / "squid_bddicken_runner.c"), "-ldl", "-lm", "-o", str(runner)])
    return runner


def build_all(bdd: Path, wtime: Path) -> dict[str, dict[str, dict]]:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    runner = build_squid_runner()
    bins: dict[str, dict[str, dict]] = {}

    squid_map = {
        "fibonacci": "fibonacci.sq",
        "loops": "loops.sq",
        "levenshtein": "levenshtein.sq",
        "hello-world": "hello_world.sq",
    }

    for bench in BENCHES:
        bins[bench] = {}

        # Squid
        bdir = WORK_DIR / "squid"
        bdir.mkdir(parents=True, exist_ok=True)
        wasm = bdir / f"{bench}.wasm"
        so = bdir / f"{bench}.so"
        t0 = time.perf_counter()
        run_cmd([str(SQUIDC), "build", str(SQUID_DIR / squid_map[bench]), str(wasm), "--prelude", str(PRELUDE), "--std-root", str(STD_ROOT)])
        squidc_ms = (time.perf_counter() - t0) * 1000.0
        t1 = time.perf_counter()
        run_cmd([str(wtime), "--backend", "x64", "--target-cpu", "native", "--guard-pages", "--blot-cdylib", str(wasm), "-o", str(so)])
        aot_ms = (time.perf_counter() - t1) * 1000.0
        bins[bench]["squid"] = {
            "argv": [str(runner), bench, str(so)],
            "compile_ms": round(squidc_ms + aot_ms, 2),
            "squidc_ms": round(squidc_ms, 2),
            "aot_ms": round(aot_ms, 2),
            "wasm_bytes": wasm.stat().st_size,
        }

        # Goose (clang -O3 matching compare.py)
        gdir = WORK_DIR / "goose"
        gdir.mkdir(parents=True, exist_ok=True)
        cfile = gdir / f"{bench}.c"
        gexe = gdir / bench
        t0 = time.perf_counter()
        run_cmd([str(GOOSE_EXE), "-O2", "--stdlib", str(GOOSE_STDLIB), "--standalone", "-o", str(cfile), str(GOOSE_BDD / bench / "goose/run.goose")])
        run_cmd(["clang", "-O3", "-w", str(cfile), "-o", str(gexe), "-lm", "-pthread", "-ldl"])
        bins[bench]["goose"] = {"argv": [str(gexe)], "compile_ms": round((time.perf_counter() - t0) * 1000.0, 2)}

        # C (clang -O3 matching languages.sh / compare.py)
        cdir = WORK_DIR / "c"
        cdir.mkdir(parents=True, exist_ok=True)
        cexe = cdir / bench
        csrc_dir = bdd / bench / "c"
        files = [csrc_dir / "run.c"] if bench == "hello-world" else [bdd / "lib/c/benchmark.c"] + sorted(csrc_dir.glob("*.c"))
        t0 = time.perf_counter()
        run_cmd(["clang", "-O3", "-w", "-I", str(bdd / "lib/c"), *[str(f) for f in files], "-o", str(cexe), "-lm"])
        bins[bench]["c"] = {"argv": [str(cexe)], "compile_ms": round((time.perf_counter() - t0) * 1000.0, 2)}

        # C++ (clang++ -O3 -march=native -ffast-math matching languages.sh / compare.py)
        cppdir = WORK_DIR / "cpp"
        cppdir.mkdir(parents=True, exist_ok=True)
        cppexe = cppdir / bench
        t0 = time.perf_counter()
        run_cmd(["clang++", "-std=c++23", "-O3", "-ffast-math", "-march=native", "-w", "-I", str(bdd / "lib/cpp"), str(bdd / bench / "cpp/run.cpp"), "-o", str(cppexe)])
        bins[bench]["cpp"] = {"argv": [str(cppexe)], "compile_ms": round((time.perf_counter() - t0) * 1000.0, 2)}

        # Rust (cargo --release matching languages.sh / compare.py)
        rdir = WORK_DIR / "rust"
        rdir.mkdir(parents=True, exist_ok=True)
        rtarget = WORK_DIR / "rust-target" / bench
        rexe = rdir / bench
        env = dict(os.environ, CARGO_TARGET_DIR=str(rtarget))
        t0 = time.perf_counter()
        run_cmd(["cargo", "build", "--release", "--bin", "run", "--manifest-path", str(bdd / bench / "rust/Cargo.toml")], env=env)
        shutil.copy2(rtarget / "release/run", rexe)
        bins[bench]["rust"] = {"argv": [str(rexe)], "compile_ms": round((time.perf_counter() - t0) * 1000.0, 2)}

        print(f"built {bench:12s}: squid={bins[bench]['squid']['compile_ms']:.0f}ms goose={bins[bench]['goose']['compile_ms']:.0f}ms c={bins[bench]['c']['compile_ms']:.0f}ms cpp={bins[bench]['cpp']['compile_ms']:.0f}ms rust={bins[bench]['rust']['compile_ms']:.0f}ms", flush=True)
    return bins


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def render_svg(data: dict, out_path: Path) -> None:
    FONT = "'DejaVu Sans', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
    BG_CANVAS, BG_CARD, BORDER = "#fafaf8", "#ffffff", "#e2e8f0"
    TEXT_MAIN, TEXT_SUB, TEXT_MUTED, GRID = "#0f172a", "#475569", "#64748b", "#f1f5f9"
    COLORS = {
        "squid": "#0f766e",
        "goose": "#2563eb",
        "c": "#64748b",
        "cpp": "#334155",
        "rust": "#c2592b",
    }
    NAMES = {
        "squid": "Squid (wtime-aot)",
        "goose": "Goose (clang -O3)",
        "c": "C (clang -O3)",
        "cpp": "C++ (-O3 native)",
        "rust": "Rust (release)",
    }
    SUBS = {
        "fibonacci": "Naive recursion fib(37) = 24,157,817 · in-process mean ms",
        "loops": "10,000 × 10,000 modulo sum (u = 40) · in-process mean ms",
        "levenshtein": "Wagner-Fischer 2-row DP on 2,556 word pairs (sum = 554,324) · mean ms",
        "hello-world": "Whole-process launch + stdout print · median wall ms (100 runs)",
    }

    w, h = 960, 520
    els = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="bddicken/languages benchmarks: Squid vs Goose, C, C++, and Rust">',
        "  <title>bddicken/languages benchmarks: Squid vs Goose, C, C++, and Rust</title>",
        f'  <rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="12" fill="{BG_CANVAS}" stroke="{BORDER}"/>',
        f'  <text x="28" y="36" font-family="{FONT}" font-size="20" font-weight="700" fill="{TEXT_MAIN}">bddicken/languages Suite: Squid vs Goose, C, C++ &amp; Rust</text>',
        f'  <text x="28" y="57" font-family="{FONT}" font-size="11.8" fill="{TEXT_SUB}">Exact official C/C++/Rust sources &amp; inputs · verified outputs · {html.escape(data["meta"]["cpu"])} · lower is better</text>',
    ]

    # Legend
    lx = 28.0
    for lang in LANGS:
        lbl = NAMES[lang]
        els.append(f'  <rect x="{lx:.1f}" y="74.5" width="12" height="12" rx="3" fill="{COLORS[lang]}"/>')
        els.append(f'  <text x="{lx + 17:.1f}" y="84.5" font-family="{FONT}" font-size="11.0" font-weight="500" fill="{TEXT_SUB}">{html.escape(lbl)}</text>')
        lx += 17 + len(lbl) * 6.3 + 18

    cw, ch, gx, gy = 442, 184, 20, 18
    for idx, bench in enumerate(BENCHES):
        col, row = idx % 2, idx // 2
        cx = 28 + col * (cw + gx)
        cy = 104 + row * (ch + gy)
        els.append(f'  <rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els.append(f'  <text x="{cx + 14}" y="{cy + 23}" font-family="{FONT}" font-size="13.5" font-weight="700" fill="{TEXT_MAIN}">{html.escape(bench)}</text>')
        els.append(f'  <text x="{cx + 14}" y="{cy + 39}" font-family="{FONT}" font-size="10.0" fill="{TEXT_MUTED}">{html.escape(SUBS[bench])}</text>')

        brows = data["benchmarks"][bench]
        entries = [(lang, brows[lang]["best_mean_ms"]) for lang in LANGS if lang in brows]
        entries.sort(key=lambda kv: kv[1])
        vmax = max(v for _, v in entries)

        # Pill comparing Squid vs C
        squid_v = brows["squid"]["best_mean_ms"]
        c_v = brows["c"]["best_mean_ms"]
        if squid_v <= c_v:
            pill_lbl = f"Squid {c_v / squid_v:.2f}× vs C"
            pbg, pfg = "#dcfce7", "#166534"
        else:
            pill_lbl = f"Squid {squid_v / c_v:.2f}× C"
            pbg, pfg = "#f1f5f9", "#334155"
        pw = len(pill_lbl) * 6.2 + 16
        px = cx + cw - 10 - pw
        els.append(f'  <rect x="{px:.1f}" y="{cy + 8:.1f}" width="{pw:.1f}" height="20" rx="10" fill="{pbg}"/>')
        els.append(f'  <text x="{px + pw / 2:.1f}" y="{cy + 21.5:.1f}" font-family="{FONT}" font-size="10.2" font-weight="600" fill="{pfg}" text-anchor="middle">{html.escape(pill_lbl)}</text>')

        bx, bmax = cx + 118, 240.0
        for bi, (lang, val) in enumerate(entries):
            by = cy + 52 + bi * 25
            bw = max(3.5, (val / vmax) * bmax)
            is_b = lang == "squid"
            short = {"squid": "Squid", "goose": "Goose", "c": "C (-O3)", "cpp": "C++ (-O3)", "rust": "Rust"}[lang]
            els.append(f'  <text x="{cx + 14}" y="{by + 13.5:.1f}" font-family="{FONT}" font-size="10.6" font-weight="{"700" if is_b else "500"}" fill="{COLORS["squid"] if is_b else TEXT_MAIN}">{html.escape(short)}</text>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax:.1f}" height="17" rx="3.5" fill="{GRID}"/>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="17" rx="3.5" fill="{COLORS[lang]}"/>')
            vtxt = f"{val:.2f} ms" if val < 10 else f"{val:.1f} ms"
            els.append(f'  <text x="{bx + bw + 7:.1f}" y="{by + 13.5:.1f}" font-family="{FONT}" font-size="10.5" font-weight="{"700" if is_b else "600"}" fill="{COLORS["squid"] if is_b else TEXT_MAIN}">{html.escape(vtxt)}</text>')

    els.append(
        f'  <text x="28" y="{h - 14}" font-family="{FONT}" font-size="10.2" fill="{TEXT_MUTED}">'
        f'Sorted fastest → slowest per benchmark. Best mean across {data["meta"]["reps"]} interleaved {data["meta"]["run_ms"] // 1000}s runs (hello-world: median of {data["meta"]["hello_runs"]} process launches).</text>'
    )
    els.append("</svg>\n")
    out_path.write_text("\n".join(els), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-ms", type=int, default=2000)
    ap.add_argument("--warmup-ms", type=int, default=500)
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--hello-runs", type=int, default=100)
    args = ap.parse_args()

    bdd = resolve_bddicken()
    wtime = resolve_wtime_aot()
    bins = build_all(bdd, wtime)

    inputs = {
        "fibonacci": "37",
        "loops": "40",
        "levenshtein": str(bdd / "levenshtein/levenshtein-words.txt"),
        "hello-world": "",
    }

    # Check output correctness first
    print("\n=== Check outputs ===", flush=True)
    for bench in BENCHES:
        for lang in LANGS:
            argv = bins[bench][lang]["argv"]
            if bench == "hello-world":
                r = run_cmd(argv)
            else:
                r = run_cmd([*argv, "1", "0", inputs[bench]], cwd=bdd / bench)
            ok = check_result(bench, r.stdout)
            print(f"  [{'OK' if ok else 'FAIL':^4s}] {bench:12s} {lang:6s} {r.stdout.strip().splitlines()[0]}", flush=True)
            if not ok:
                raise SystemExit(f"check failed for {bench}/{lang}: {r.stdout!r}")

    # Interleaved benchmark reps
    raw: dict[str, dict[str, list[dict]]] = {b: {l: [] for l in LANGS} for b in BENCHES}
    for rep in range(args.reps):
        print(f"\n=== Rep {rep + 1}/{args.reps} ===", flush=True)
        for bench in BENCHES:
            for lang in LANGS:
                argv = bins[bench][lang]["argv"]
                if bench == "hello-world":
                    # Warmup 5 runs
                    for _ in range(5):
                        subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                    ts = []
                    for _ in range(args.hello_runs):
                        t0 = time.perf_counter()
                        subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
                        ts.append((time.perf_counter() - t0) * 1000.0)
                    rec = {"mean_ms": round(statistics.median(ts), 4), "min_ms": round(min(ts), 4), "runs": len(ts)}
                else:
                    r = run_cmd([*argv, str(args.run_ms), str(args.warmup_ms), inputs[bench]], cwd=bdd / bench)
                    fields = r.stdout.strip().splitlines()[0].split(",")
                    assert check_result(bench, r.stdout), f"bad output {bench}/{lang}: {r.stdout}"
                    rec = {
                        "mean_ms": round(float(fields[0]), 4),
                        "std_dev_ms": round(float(fields[1]), 4),
                        "min_ms": round(float(fields[2]), 4),
                        "max_ms": round(float(fields[3]), 4),
                        "runs": int(fields[4]),
                        "result": fields[5].strip(),
                    }
                raw[bench][lang].append(rec)
                print(f"  {bench:12s} {lang:6s} mean={rec['mean_ms']:8.3f} ms  min={rec['min_ms']:8.3f} ms  (runs={rec['runs']})", flush=True)

    clang_ver = subprocess.run(["clang", "--version"], capture_output=True, text=True).stdout.splitlines()[0]
    rust_ver = subprocess.run(["rustc", "--version"], capture_output=True, text=True).stdout.strip()
    squid_commit = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip() or "unknown"
    summary: dict[str, dict[str, dict]] = {}
    for bench in BENCHES:
        summary[bench] = {}
        for lang in LANGS:
            recs = raw[bench][lang]
            best = min(recs, key=lambda x: x["mean_ms"])
            entry = {
                "best_mean_ms": best["mean_ms"],
                "best_min_ms": min(x["min_ms"] for x in recs),
                "runs_per_rep": best["runs"],
                "compile_ms": bins[bench][lang]["compile_ms"],
                "reps": recs,
            }
            if lang == "squid":
                entry["squidc_ms"] = bins[bench]["squid"]["squidc_ms"]
                entry["aot_ms"] = bins[bench]["squid"]["aot_ms"]
                entry["wasm_bytes"] = bins[bench]["squid"]["wasm_bytes"]
            summary[bench][lang] = entry

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = {
        "meta": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "cpu": cpu_model(),
            "os": f"{platform.system()} {platform.release()} ({platform.machine()})",
            "clang": clang_ver,
            "rust": rust_ver,
            "squid_commit": squid_commit,
            "wtime_aot": f"{wtime} (--guard-pages)",
            "run_ms": args.run_ms,
            "warmup_ms": args.warmup_ms,
            "reps": args.reps,
            "hello_runs": args.hello_runs,
        },
        "benchmarks": summary,
    }
    (OUT_DIR / "results.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    render_svg(out, OUT_DIR / "bddicken_chart.svg")
    print(f"\nWrote {OUT_DIR / 'results.json'} and {OUT_DIR / 'bddicken_chart.svg'}")


if __name__ == "__main__":
    main()
