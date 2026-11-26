#!/usr/bin/env python3
"""Generate clean editorial SVG bar charts for the 16-benchmark Goose suite + Blot.

Reads `benchmarks/evidence/measurements/2026-11-26-goose-suite/results.json`
and writes publication-ready SVG bar charts into the same directory:
  - summary_overview.svg      (geomean runtime, peak RSS, compile speed + 16-bench Blot vs idiomatic C++)
  - runtime_part1.svg         (wall-clock ms, benchmarks 1-8)
  - runtime_part2.svg         (wall-clock ms, benchmarks 9-16)
  - memory_part1.svg          (exact per-process peak RSS MiB, benchmarks 1-8)
  - memory_part2.svg          (exact per-process peak RSS MiB, benchmarks 9-16)
  - compile_and_size.svg      (cold compile ms across all 16 + Blot .wasm sizes)
"""

from __future__ import annotations

import html
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DIR = ROOT / "benchmarks/evidence/measurements/2026-11-26-goose-suite"

FONT = "'DejaVu Sans', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

# Editorial palette harmonized with benchmarks/comparison/plot_benchmarks.py
BG_CANVAS = "#fafaf8"
BG_CARD = "#ffffff"
BORDER = "#e2e8f0"
TEXT_MAIN = "#0f172a"
TEXT_SUB = "#475569"
TEXT_MUTED = "#64748b"
GRID = "#f1f5f9"
AXIS = "#cbd5e1"

C_BLOT = "#0f766e"       # Blot deep teal
C_BLOT_AOT = "#2dd4bf"   # Blot wtime-aot light teal (stacked compile bar)
C_GOOSE = "#2563eb"      # Goose cobalt blue
C_RUST_EXP = "#c2592b"   # Rust expert / arena terracotta
C_RUST_ID = "#e69f73"    # Rust idiomatic warm sand
C_CPP_EXP = "#334155"    # C++ expert deep slate
C_CPP_ID = "#94a3b8"     # C++ idiomatic silver slate

PILL_WIN_BG = "#dcfce7"
PILL_WIN_FG = "#166534"
PILL_NEU_BG = "#f1f5f9"
PILL_NEU_FG = "#334155"
PILL_WARN_BG = "#ffedd5"
PILL_WARN_FG = "#9a3412"

BENCH_ORDER = [
    "sum", "push", "strlist", "records", "tree", "interp", "graph", "words",
    "particles", "sexp", "lru", "scene", "calc", "bintrees", "respond", "blur",
]

SHORT_LABELS = {
    # Blot
    "blot grow array": "Blot",
    "blot array+reserve, indices": "Blot",
    "blot packed bytes + offsets": "Blot",
    "blot packed records + text pool": "Blot",
    "blot arena + indices": "Blot",
    "blot arena + tag dispatch": "Blot",
    "blot CSR two-pass": "Blot",
    "blot packed bytes + open addressing": "Blot",
    "blot AoS, per component": "Blot",
    "blot 8B arena + packed text": "Blot",
    "blot open addressing + arena": "Blot",
    "blot arena + inline transforms": "Blot",
    "blot arena + error codes": "Blot",
    "blot arena per tree": "Blot",
    "blot streaming": "Blot",
    "blot sliding 3-col": "Blot",
    # Goose
    "goose grow-only array": "Goose",
    "goose array, typed references": "Goose",
    "goose inline strings, owned": "Goose",
    "goose variable enum": "Goose",
    "goose pool + typed relative refs": "Goose",
    "goose case functions + relative refs": "Goose",
    "goose CSR two-pass": "Goose",
    "goose slices + open addressing": "Goose",
    "goose AoS, per component": "Goose",
    "goose pool + refs, inline text": "Goose",
    "goose reusable pool + pool-relative refs": "Goose",
    "goose pool + inline child refs": "Goose",
    "goose local pool + return from": "Goose",
    "goose local pool per tree": "Goose",
    "goose inline DTO": "Goose (DTO)",
    "goose streaming": "Goose (stream)",
    "goose flat indexing": "Goose",
    # C++
    "cpp vector": "C++ (vector)",
    "cpp vector+reserve": "C++ (vec+res)",
    "cpp vector, indices": "C++ (vector)",
    "cpp vector+reserve, indices": "C++ (vec+res)",
    "cpp vector<string>": "C++ (vec<str>)",
    "cpp flat offsets": "C++ (offsets)",
    "cpp variant + string": "C++ (var+str)",
    "cpp variant + buffer": "C++ (var+buf)",
    "cpp unique_ptr": "C++ (uniq_ptr)",
    "cpp arena + indices": "C++ (arena)",
    "cpp virtual + unique_ptr": "C++ (virtual)",
    "cpp tagged union + arena": "C++ (arena)",
    "cpp vector<vector>": "C++ (vec<vec>)",
    "cpp CSR two-pass": "C++ (CSR)",
    "cpp unordered_map<string>": "C++ (umap)",
    "cpp open addressing": "C++ (open)",
    "cpp AoS, elementwise": "C++ (elemwise)",
    "cpp AoS, per component": "C++ (per-comp)",
    "cpp unique_ptr + string": "C++ (uniq_ptr)",
    "cpp arena + string_view": "C++ (arena)",
    "cpp list + unordered_map": "C++ (list+map)",
    "cpp arena + open addressing": "C++ (arena)",
    "cpp unique_ptr children": "C++ (uniq_ptr)",
    "cpp arena + child indices": "C++ (arena)",
    "cpp unique_ptr + exceptions": "C++ (except)",
    "cpp arena + error codes": "C++ (arena)",
    "cpp new/delete": "C++ (new/del)",
    "cpp vector arena": "C++ (arena)",
    "cpp DTO + string": "C++ (DTO)",
    "cpp streaming": "C++ (stream)",
    "cpp flat indexing": "C++ (flat)",
    "cpp row pointers": "C++ (row ptr)",
    # Rust
    "rust Vec, collect": "Rust (Vec)",
    "rust Vec+reserve, indices": "Rust (Vec+res)",
    "rust Vec<String>": "Rust (String)",
    "rust Vec<&str>": "Rust (&str)",
    "rust enum + String": "Rust (String)",
    "rust Box nodes": "Rust (Box)",
    "rust arena + indices": "Rust (arena)",
    "rust enum + Box": "Rust (Box)",
    "rust enum + arena indices": "Rust (arena)",
    "rust Vec<Vec>": "Rust (Vec<Vec>)",
    "rust CSR two-pass": "Rust (CSR)",
    "rust HashMap<&str>": "Rust (HashMap)",
    "rust open addressing": "Rust (open)",
    "rust AoS, per component": "Rust (AoS)",
    "rust enum + Box + String": "Rust (Box)",
    "rust arena + &str": "Rust (arena)",
    "rust HashMap + arena": "Rust (HashMap)",
    "rust open addressing + arena": "Rust (open)",
    "rust Box children": "Rust (Box)",
    "rust arena + child indices": "Rust (arena)",
    "rust Box + Result": "Rust (Box)",
    "rust arena + Result": "Rust (arena)",
    "rust Box": "Rust (Box)",
    "rust Vec arena": "Rust (arena)",
    "rust DTO + String": "Rust (DTO)",
    "rust streaming": "Rust (stream)",
    "rust flat indexing": "Rust (flat)",
    "rust row slices": "Rust (slices)",
}

RUST_IDIOMATIC_LABELS = {
    "rust Vec<String>",
    "rust Box nodes",
    "rust enum + Box",
    "rust Vec<Vec>",
    "rust HashMap<&str>",
    "rust enum + Box + String",
    "rust HashMap + arena",
    "rust Box children",
    "rust Box + Result",
    "rust Box",
    "rust DTO + String",
    "rust flat indexing",
}


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def svg_header(w: int, h: int, title: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">',
        f"  <title>{esc(title)}</title>",
        f'  <rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="12" fill="{BG_CANVAS}" stroke="{BORDER}"/>',
    ]


def text(
    x: float,
    y: float,
    s: str,
    size: float = 12,
    weight: str = "400",
    fill: str = TEXT_MAIN,
    anchor: str = "start",
) -> str:
    return (
        f'  <text x="{x:.1f}" y="{y:.1f}" font-family="{FONT}" '
        f'font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>'
    )


def pill(x: float, y: float, label: str, bg: str, fg: str, anchor: str = "start") -> str:
    pad_x = 8.0
    w = len(label) * 6.2 + pad_x * 2
    h = 20.0
    rx = x if anchor == "start" else x - w
    return (
        f'  <rect x="{rx:.1f}" y="{y - 14:.1f}" width="{w:.1f}" height="{h:.1f}" rx="10" fill="{bg}"/>\n'
        f'  <text x="{rx + w / 2:.1f}" y="{y:.1f}" font-family="{FONT}" font-size="10.2" font-weight="600" '
        f'fill="{fg}" text-anchor="middle">{esc(label)}</text>'
    )


def legend_row(x0: float, y: float, items: list[tuple[str, str]]) -> list[str]:
    out = []
    x = x0
    for color, label in items:
        out.append(f'  <rect x="{x:.1f}" y="{y - 9.5:.1f}" width="12" height="12" rx="3" fill="{color}"/>')
        out.append(text(x + 17, y + 0.5, label, size=11.0, weight="500", fill=TEXT_SUB))
        x += 17 + len(label) * 6.3 + 18
    return out


def geomean(vals: list[float]) -> float:
    pos = [v for v in vals if v > 0]
    return math.exp(sum(math.log(v) for v in pos) / len(pos))


def fmt_ms(v: float) -> str:
    if v >= 1000:
        return f"{v:,.0f} ms"
    if v >= 100:
        return f"{v:.0f} ms"
    if v >= 10:
        return f"{v:.1f} ms"
    return f"{v:.2f} ms"


def fmt_mb(v: float) -> str:
    if v >= 100:
        return f"{v:.0f} MiB"
    return f"{v:.1f} MiB"


def row_color(label: str, r: dict, rust_count: int) -> str:
    kind = r["kind"]
    if kind == "blot":
        return C_BLOT
    if kind == "goose":
        return C_GOOSE
    if kind == "cpp":
        return C_CPP_ID if r.get("tier") == "idiomatic" else C_CPP_EXP
    # rust
    if rust_count > 1 and label in RUST_IDIOMATIC_LABELS:
        return C_RUST_ID
    return C_RUST_EXP


def pick_tier_rows(rows: dict[str, dict]) -> dict[str, tuple[str, dict]]:
    """Extract canonical single representative per tier for summary geomeans."""
    blot_rows = [(k, v) for k, v in rows.items() if v["kind"] == "blot" and v.get("ok")]
    goose_rows = [(k, v) for k, v in rows.items() if v["kind"] == "goose" and v.get("ok")]
    cpp_exp = [(k, v) for k, v in rows.items() if v["kind"] == "cpp" and v.get("tier") == "expert" and v.get("ok")]
    cpp_id = [(k, v) for k, v in rows.items() if v["kind"] == "cpp" and v.get("tier") == "idiomatic" and v.get("ok")]
    rust_rows = [(k, v) for k, v in rows.items() if v["kind"] == "rust" and v.get("ok")]

    # When Goose has 2 rows (respond: inline DTO + streaming), pick streaming for fair apples-to-apples with Blot/C++ expert/Rust expert,
    # or fastest Goose row.
    goose_pick = min(goose_rows, key=lambda kv: kv[1]["ms"])
    rust_exp = rust_rows[-1]  # expert/arena row is listed second when 2 exist
    rust_id = rust_rows[0]    # idiomatic row is listed first (same as exp when 1 exists)
    return {
        "blot": blot_rows[0],
        "goose": goose_pick,
        "cpp_exp": cpp_exp[0],
        "cpp_id": cpp_id[0],
        "rust_exp": rust_exp,
        "rust_id": rust_id,
    }


def build_summary_overview(data: dict, size: str) -> str:
    benches = data["benchmarks"]
    tiers = ["blot", "goose", "rust_exp", "rust_id", "cpp_exp", "cpp_id"]
    time_ratios = {t: [] for t in tiers}
    mem_ratios = {t: [] for t in tiers}
    compile_ms = {"blot": [], "goose": [], "rust": [], "cpp": []}
    blot_vs_cpp_id = []  # (name, time_ratio, mem_ratio)

    for bname in BENCH_ORDER:
        rows = benches[bname]["sizes"][size]["rows"]
        picks = pick_tier_rows(rows)
        base_t = picks["cpp_exp"][1]["ms"]
        base_m = picks["cpp_exp"][1]["peak_mb"]
        for t in tiers:
            time_ratios[t].append(picks[t][1]["ms"] / base_t)
            mem_ratios[t].append(picks[t][1]["peak_mb"] / base_m)
        compile_ms["blot"].append(picks["blot"][1]["compile_ms"])
        compile_ms["goose"].append(picks["goose"][1]["compile_ms"])
        compile_ms["rust"].append(picks["rust_exp"][1]["compile_ms"])
        compile_ms["cpp"].append(picks["cpp_exp"][1]["compile_ms"])
        blot_vs_cpp_id.append((
            bname,
            picks["blot"][1]["ms"] / picks["cpp_id"][1]["ms"],
            picks["blot"][1]["peak_mb"] / picks["cpp_id"][1]["peak_mb"],
        ))

    w, h = 960, 770
    els = svg_header(w, h, "16-benchmark suite summary: Blot vs Goose, Rust, and C++")
    els.append(text(28, 36, "16-Benchmark Suite: Blot vs Goose, Rust & C++", size=20, weight="700"))
    meta = data["meta"]
    els.append(
        text(
            28,
            57,
            f"All 16 Goose-suite workloads ({size} size) · bit-exact checksum parity · {meta['cpu']} · lower is better",
            size=11.8,
            fill=TEXT_SUB,
        )
    )

    # Top row: 3 equal cards (width 290 each, gap 17 -> 28 + 290*3 + 17*2 + 28 = 960)
    card_w, card_h, gap = 290, 232, 17
    cy0 = 76

    # --- Card 1: Geomean Runtime ---
    cx1 = 28
    els.append(f'  <rect x="{cx1}" y="{cy0}" width="{card_w}" height="{card_h}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(cx1 + 14, cy0 + 24, "Geomean runtime", size=13.0, weight="700"))
    els.append(text(cx1 + 14, cy0 + 40, "Relative to C++ expert (1.00×)", size=10.2, fill=TEXT_MUTED))

    rt_bars = sorted(
        [
            ("Goose", geomean(time_ratios["goose"]), C_GOOSE, False),
            ("C++ expert", geomean(time_ratios["cpp_exp"]), C_CPP_EXP, False),
            ("Rust expert", geomean(time_ratios["rust_exp"]), C_RUST_EXP, False),
            ("Rust idiomatic", geomean(time_ratios["rust_id"]), C_RUST_ID, False),
            ("C++ idiomatic", geomean(time_ratios["cpp_id"]), C_CPP_ID, False),
            ("Blot (wtime-aot)", geomean(time_ratios["blot"]), C_BLOT, True),
        ],
        key=lambda x: x[1],
    )
    rmax = max(v for _, v, _, _ in rt_bars)
    bx, bmax = cx1 + 114, 114.0
    for i, (lbl, val, col, is_blot) in enumerate(rt_bars):
        by = cy0 + 54 + i * 27
        bw = max(4.0, (val / rmax) * bmax)
        els.append(text(cx1 + 14, by + 13, lbl, size=10.5, weight="700" if is_blot else "500", fill=C_BLOT if is_blot else TEXT_MAIN))
        els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax:.1f}" height="17" rx="3.5" fill="{GRID}"/>')
        els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="17" rx="3.5" fill="{col}"/>')
        els.append(text(bx + bw + 6, by + 13, f"{val:.2f}×", size=10.5, weight="700" if is_blot else "600", fill=C_BLOT if is_blot else TEXT_MAIN))

    # --- Card 2: Geomean Peak RSS ---
    cx2 = cx1 + card_w + gap
    els.append(f'  <rect x="{cx2}" y="{cy0}" width="{card_w}" height="{card_h}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(cx2 + 14, cy0 + 24, "Geomean peak memory", size=13.0, weight="700"))
    els.append(text(cx2 + 14, cy0 + 40, "Per-process RSS vs C++ expert (1.00×)", size=10.2, fill=TEXT_MUTED))

    mem_bars = sorted(
        [
            ("Goose", geomean(mem_ratios["goose"]), C_GOOSE, False),
            ("C++ expert", geomean(mem_ratios["cpp_exp"]), C_CPP_EXP, False),
            ("Rust expert", geomean(mem_ratios["rust_exp"]), C_RUST_EXP, False),
            ("Rust idiomatic", geomean(mem_ratios["rust_id"]), C_RUST_ID, False),
            ("C++ idiomatic", geomean(mem_ratios["cpp_id"]), C_CPP_ID, False),
            ("Blot (wtime-aot)", geomean(mem_ratios["blot"]), C_BLOT, True),
        ],
        key=lambda x: x[1],
    )
    mmax = max(v for _, v, _, _ in mem_bars)
    bx2, bmax2 = cx2 + 114, 114.0
    for i, (lbl, val, col, is_blot) in enumerate(mem_bars):
        by = cy0 + 54 + i * 27
        bw = max(4.0, (val / mmax) * bmax2)
        els.append(text(cx2 + 14, by + 13, lbl, size=10.5, weight="700" if is_blot else "500", fill=C_BLOT if is_blot else TEXT_MAIN))
        els.append(f'  <rect x="{bx2:.1f}" y="{by:.1f}" width="{bmax2:.1f}" height="17" rx="3.5" fill="{GRID}"/>')
        els.append(f'  <rect x="{bx2:.1f}" y="{by:.1f}" width="{bw:.1f}" height="17" rx="3.5" fill="{col}"/>')
        els.append(text(bx2 + bw + 6, by + 13, f"{val:.2f}×", size=10.5, weight="700" if is_blot else "600", fill=C_BLOT if is_blot else TEXT_MAIN))

    # --- Card 3: Geomean Cold Compile ---
    cx3 = cx2 + card_w + gap
    els.append(f'  <rect x="{cx3}" y="{cy0}" width="{card_w}" height="{card_h}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(cx3 + 14, cy0 + 24, "Geomean cold compile", size=13.0, weight="700"))
    gc_blot = geomean(compile_ms["blot"])
    gc_cpp = geomean(compile_ms["cpp"])
    els.append(pill(cx3 + card_w - 12, cy0 + 23, f"{gc_cpp / gc_blot:.1f}× vs C++", PILL_WIN_BG, PILL_WIN_FG, anchor="end"))
    els.append(text(cx3 + 14, cy0 + 40, "Full build to executable / native .so", size=10.2, fill=TEXT_MUTED))

    cmp_bars = sorted(
        [
            ("Blot (+AOT)", gc_blot, C_BLOT, True),
            ("Rust (-O)", geomean(compile_ms["rust"]), C_RUST_EXP, False),
            ("Goose (-O2)", geomean(compile_ms["goose"]), C_GOOSE, False),
            ("C++ (-O2)", gc_cpp, C_CPP_EXP, False),
        ],
        key=lambda x: x[1],
    )
    cmax = max(v for _, v, _, _ in cmp_bars)
    bx3, bmax3 = cx3 + 98, 122.0
    for i, (lbl, val, col, is_blot) in enumerate(cmp_bars):
        by = cy0 + 62 + i * 38
        bw = max(4.0, (val / cmax) * bmax3)
        els.append(text(cx3 + 14, by + 14, lbl, size=10.8, weight="700" if is_blot else "500", fill=C_BLOT if is_blot else TEXT_MAIN))
        els.append(f'  <rect x="{bx3:.1f}" y="{by:.1f}" width="{bmax3:.1f}" height="20" rx="3.5" fill="{GRID}"/>')
        els.append(f'  <rect x="{bx3:.1f}" y="{by:.1f}" width="{bw:.1f}" height="20" rx="3.5" fill="{col}"/>')
        els.append(text(bx3 + bw + 6, by + 14, f"{val:.0f} ms", size=10.5, weight="700" if is_blot else "600", fill=C_BLOT if is_blot else TEXT_MAIN))

    # --- Bottom full-width card: All 16 benchmarks Blot vs Idiomatic C++ (Peak RSS & Runtime) ---
    by_card = cy0 + card_h + 18
    bh_card = 408
    els.append(f'  <rect x="28" y="{by_card}" width="904" height="{bh_card}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(44, by_card + 24, "Blot vs Idiomatic C++ across all 16 benchmarks (log scale, < 1.0× = Blot wins)", size=13.0, weight="700"))

    mem_wins = sum(1 for _, _, mr in blot_vs_cpp_id if mr <= 1.0)
    rt_wins = sum(1 for _, tr, _ in blot_vs_cpp_id if tr <= 1.0)
    els.append(pill(918, by_card + 23, f"Memory: {mem_wins}/16 wins · Runtime: {rt_wins}/16 wins", PILL_NEU_BG, PILL_NEU_FG, anchor="end"))

    # Two side-by-side 16-row mini bar panels inside the bottom card: Left = Peak Memory ratio, Right = Runtime ratio
    panel_specs = [
        ("Peak RSS ratio (Blot / Idiomatic C++)", 44, 1, C_BLOT, "#94a3b8"),
        ("CPU runtime ratio (Blot / Idiomatic C++)", 494, 0, C_BLOT, "#d97706"),
    ]
    # Use log2 scale centered on 1.0× (range 0.125× .. 8.0× -> -3 .. +3)
    log_min, log_max = -3.0, 3.0
    for ptitle, px, idx_col, win_col, lose_col in panel_specs:
        els.append(text(px, by_card + 48, ptitle, size=11.0, weight="600", fill=TEXT_SUB))
        track_x = px + 76
        track_w = 304.0
        zero_x = track_x + ((0.0 - log_min) / (log_max - log_min)) * track_w

        # Reference grid ticks: 0.25x, 0.5x, 1x, 2x, 4x
        for tick_v, tick_lbl in [(0.25, "0.25×"), (0.5, "0.5×"), (1.0, "1.0×"), (2.0, "2×"), (4.0, "4×")]:
            tx = track_x + ((math.log2(tick_v) - log_min) / (log_max - log_min)) * track_w
            stroke = "#64748b" if tick_v == 1.0 else "#e2e8f0"
            sw = "1.4" if tick_v == 1.0 else "1"
            dash = "" if tick_v == 1.0 else ' stroke-dasharray="2,2"'
            els.append(f'  <line x1="{tx:.1f}" y1="{by_card + 56}" x2="{tx:.1f}" y2="{by_card + 382}" stroke="{stroke}" stroke-width="{sw}"{dash}/>')
            els.append(text(tx, by_card + 396, tick_lbl, size=9.5, weight="600" if tick_v == 1.0 else "400", fill=TEXT_MUTED, anchor="middle"))

        for row_i, (bname, tr, mr) in enumerate(blot_vs_cpp_id):
            val = tr if idx_col == 0 else mr
            ry = by_card + 62 + row_i * 20
            els.append(text(px, ry + 11.5, bname, size=10.3, weight="500", fill=TEXT_MAIN))
            lv = max(log_min, min(log_max, math.log2(val)))
            vx = track_x + ((lv - log_min) / (log_max - log_min)) * track_w
            bx_s = min(zero_x, vx)
            bw = max(2.5, abs(vx - zero_x))
            col = win_col if val <= 1.0 else lose_col
            els.append(f'  <rect x="{bx_s:.1f}" y="{ry + 1.5:.1f}" width="{bw:.1f}" height="12.5" rx="2.5" fill="{col}"/>')
            lbl_s = f"{val:.2f}×" if val < 10 else f"{val:.1f}×"
            if val <= 1.0:
                els.append(text(bx_s - 4, ry + 11.2, lbl_s, size=9.5, weight="600", fill=win_col, anchor="end"))
            else:
                els.append(text(bx_s + bw + 4, ry + 11.2, lbl_s, size=9.5, weight="500", fill=TEXT_SUB, anchor="start"))

    els.append(
        text(
            28,
            h - 14,
            "Best single-process CPU time (user+sys) of 3 runs after 2 warmups & exact per-process peak RSS via posix_spawn + wait4. All 16 outputs bit-identical.",
            size=10.2,
            fill=TEXT_MUTED,
        )
    )
    els.append("</svg>\n")
    return "\n".join(els)


def build_grid_page(
    data: dict,
    size: str,
    names: list[str],
    metric: str,  # "ms" or "peak_mb"
    title: str,
    subtitle: str,
) -> str:
    benches = data["benchmarks"]
    w = 960
    card_w, card_h = 442, 198
    gap_x, gap_y = 20, 16
    start_x, start_y = 28, 108
    rows_n = (len(names) + 1) // 2
    h = start_y + rows_n * card_h + (rows_n - 1) * gap_y + 38

    els = svg_header(w, h, title)
    els.append(text(28, 36, title, size=20, weight="700"))
    els.append(text(28, 57, subtitle, size=11.8, fill=TEXT_SUB))

    els.extend(
        legend_row(
            28,
            84,
            [
                (C_BLOT, "Blot (wtime-aot x64)"),
                (C_GOOSE, "Goose (clang -O2)"),
                (C_RUST_EXP, "Rust (expert / arena)"),
                (C_RUST_ID, "Rust (idiomatic)"),
                (C_CPP_EXP, "C++ (expert)"),
                (C_CPP_ID, "C++ (idiomatic)"),
            ],
        )
    )

    for idx, bname in enumerate(names):
        col = idx % 2
        row = idx // 2
        cx = start_x + col * (card_w + gap_x)
        cy = start_y + row * (card_h + gap_y)

        bdata = benches[bname]
        sdata = bdata["sizes"][size]
        rows_map = sdata["rows"]
        n_val = sdata["n"]
        param = bdata["param"]

        els.append(f'  <rect x="{cx}" y="{cy}" width="{card_w}" height="{card_h}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els.append(
            f'  <text x="{cx + 14:.1f}" y="{cy + 22:.1f}" font-family="{FONT}" font-size="13.5" font-weight="700" fill="{TEXT_MAIN}">'
            f'{esc(bname)}<tspan dx="8" font-size="10.6" font-weight="500" fill="{TEXT_MUTED}">{esc(param)} = {n_val:,}</tspan></text>'
        )

        rust_count = sum(1 for v in rows_map.values() if v["kind"] == "rust" and v.get("ok"))
        entries = []
        for lbl, r in rows_map.items():
            if not r.get("ok"):
                continue
            entries.append((
                SHORT_LABELS.get(lbl, lbl[:15]),
                r[metric],
                row_color(lbl, r, rust_count),
                r["kind"] == "blot",
            ))
        entries.sort(key=lambda e: e[1])

        # Badge showing Blot rank or win vs idiomatic C++
        picks = pick_tier_rows(rows_map)
        blot_v = picks["blot"][1][metric]
        cpp_id_v = picks["cpp_id"][1][metric]
        if blot_v <= cpp_id_v:
            badge = f"Blot {cpp_id_v / blot_v:.2f}× vs idiomatic C++"
            pbg, pfg = PILL_WIN_BG, PILL_WIN_FG
        else:
            badge = f"Blot {blot_v / cpp_id_v:.2f}× idiomatic C++"
            pbg, pfg = PILL_NEU_BG, PILL_NEU_FG
        els.append(pill(cx + card_w - 10, cy + 21, badge, pbg, pfg, anchor="end"))
        els.append(text(cx + 14, cy + 37, bdata["what"], size=9.8, fill=TEXT_MUTED))

        vmax = max(e[1] for e in entries)
        bx = cx + 114
        bmax_w = 248.0
        n_bars = len(entries)
        bar_step = 20.5 if n_bars >= 7 else (23.5 if n_bars == 6 else (27.5 if n_bars == 5 else 31.0))
        bar_h = 14.2 if n_bars >= 7 else (15.5 if n_bars == 6 else 17.0)
        y_first = cy + 48 + (4 if n_bars <= 5 else 0)

        for bi, (short_lbl, val, col_hex, is_blot) in enumerate(entries):
            by = y_first + bi * bar_step
            bw = max(3.5, (val / vmax) * bmax_w)
            els.append(
                text(
                    cx + 14,
                    by + bar_h - 3.0,
                    short_lbl,
                    size=10.3,
                    weight="700" if is_blot else "500",
                    fill=C_BLOT if is_blot else TEXT_MAIN,
                )
            )
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax_w:.1f}" height="{bar_h:.1f}" rx="3.5" fill="{GRID}"/>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="{bar_h:.1f}" rx="3.5" fill="{col_hex}"/>')
            val_txt = fmt_ms(val) if metric == "ms" else fmt_mb(val)
            els.append(
                text(
                    bx + bw + 6,
                    by + bar_h - 3.0,
                    val_txt,
                    size=10.2,
                    weight="700" if is_blot else "600",
                    fill=C_BLOT if is_blot else TEXT_MAIN,
                )
            )

    footer = (
        "Sorted fastest → slowest per benchmark (linear 0..max scale per card). Best single-process CPU time (user+sys) of 3 runs after 2 warmups."
        if metric == "ms"
        else "Sorted leanest → heaviest per benchmark (linear 0..max scale per card). Exact per-process peak RSS via posix_spawn + wait4."
    )
    els.append(text(28, h - 14, footer, size=10.2, fill=TEXT_MUTED))
    els.append("</svg>\n")
    return "\n".join(els)


def build_compile_and_size(data: dict, size: str) -> str:
    benches = data["benchmarks"]
    w, h = 960, 680
    els = svg_header(w, h, "Cold compile time across all 16 benchmarks and Blot Wasm output size")
    els.append(text(28, 36, "Cold Compile Time & Blot Wasm Binary Size (All 16 Benchmarks)", size=20, weight="700"))
    els.append(
        text(
            28,
            57,
            "Full clean build from source to native binary / wtime-aot .so (ms, lower is better) · Blot .wasm size in KiB",
            size=11.8,
            fill=TEXT_SUB,
        )
    )

    els.extend(
        legend_row(
            28,
            84,
            [
                (C_BLOT, "Blot (blotc-goose)"),
                (C_BLOT_AOT, "Blot (+ wtime-aot x64)"),
                (C_RUST_EXP, "Rust (rustc -O)"),
                (C_GOOSE, "Goose (goose + clang -O2)"),
                (C_CPP_EXP, "C++ (clang++ -O2)"),
            ],
        )
    )

    # Left card: 16 benchmarks grouped compile bars
    lx, ly, lw, lh = 28, 106, 636, 536
    els.append(f'  <rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(lx + 14, ly + 22, "Cold compile time per benchmark (ms)", size=12.8, weight="700"))

    rows_data = []
    max_cmp = 0.0
    for bname in BENCH_ORDER:
        picks = pick_tier_rows(benches[bname]["sizes"][size]["rows"])
        b_row = picks["blot"][1]
        g_ms = picks["goose"][1]["compile_ms"]
        r_ms = picks["rust_exp"][1]["compile_ms"]
        c_ms = picks["cpp_exp"][1]["compile_ms"]
        rows_data.append((bname, b_row["blotc_ms"], b_row["aot_ms"], r_ms, g_ms, c_ms, b_row["wasm_bytes"] / 1024.0))
        max_cmp = max(max_cmp, b_row["compile_ms"], g_ms, r_ms, c_ms)

    geomean_blot = geomean([r[1] + r[2] for r in rows_data])
    geomean_cpp = geomean([r[5] for r in rows_data])
    els.append(pill(lx + lw - 12, ly + 21, f"Blot geomean {geomean_blot:.0f} ms ({geomean_cpp / geomean_blot:.1f}× vs C++)", PILL_WIN_BG, PILL_WIN_FG, anchor="end"))

    bx = lx + 82
    bmax_w = 486.0
    row_step = 30.8
    for i, (bname, blotc_ms, aot_ms, r_ms, g_ms, c_ms, _) in enumerate(rows_data):
        ry = ly + 36 + i * row_step
        els.append(text(lx + 14, ry + 16, bname, size=10.8, weight="600", fill=TEXT_MAIN))
        # 4 slim bars per benchmark (height 5.2px each, 1.3px gap)
        # 1. Blot stacked (blotc + aot)
        bw_c = max(2.0, (blotc_ms / max_cmp) * bmax_w)
        bw_a = max(1.5, (aot_ms / max_cmp) * bmax_w)
        els.append(f'  <rect x="{bx:.1f}" y="{ry:.1f}" width="{bw_c:.1f}" height="5.5" rx="1.5" fill="{C_BLOT}"/>')
        els.append(f'  <rect x="{bx + bw_c:.1f}" y="{ry:.1f}" width="{bw_a:.1f}" height="5.5" rx="1.5" fill="{C_BLOT_AOT}"/>')
        els.append(text(bx + bw_c + bw_a + 5, ry + 5.5, f"{blotc_ms + aot_ms:.0f} ms", size=8.5, weight="700", fill=C_BLOT))

        # 2. Rust
        rw = max(2.0, (r_ms / max_cmp) * bmax_w)
        els.append(f'  <rect x="{bx:.1f}" y="{ry + 6.5:.1f}" width="{rw:.1f}" height="5.0" rx="1.5" fill="{C_RUST_EXP}"/>')

        # 3. Goose
        gw = max(2.0, (g_ms / max_cmp) * bmax_w)
        els.append(f'  <rect x="{bx:.1f}" y="{ry + 12.5:.1f}" width="{gw:.1f}" height="5.0" rx="1.5" fill="{C_GOOSE}"/>')

        # 4. C++
        cw = max(2.0, (c_ms / max_cmp) * bmax_w)
        els.append(f'  <rect x="{bx:.1f}" y="{ry + 18.5:.1f}" width="{cw:.1f}" height="5.0" rx="1.5" fill="{C_CPP_EXP}"/>')
        els.append(text(bx + max(rw, gw, cw) + 5, ry + 22.5, f"{c_ms:.0f} ms", size=8.5, weight="500", fill=TEXT_MUTED))

    # Right card: Blot .wasm output size across all 16 benchmarks
    rx, ry0, rw_card, rh_card = 682, 106, 250, 536
    els.append(f'  <rect x="{rx}" y="{ry0}" width="{rw_card}" height="{rh_card}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(rx + 14, ry0 + 22, "Blot .wasm output size", size=12.8, weight="700"))

    max_kib = max(r[6] for r in rows_data)
    sbx = rx + 76
    sbmax = 112.0
    for i, (bname, _, _, _, _, _, kib) in enumerate(rows_data):
        ry = ry0 + 38 + i * row_step
        bw = max(3.0, (kib / max_kib) * sbmax)
        els.append(text(rx + 14, ry + 13, bname, size=10.3, weight="500", fill=TEXT_MAIN))
        els.append(f'  <rect x="{sbx:.1f}" y="{ry + 2:.1f}" width="{sbmax:.1f}" height="14" rx="3" fill="{GRID}"/>')
        els.append(f'  <rect x="{sbx:.1f}" y="{ry + 2:.1f}" width="{bw:.1f}" height="14" rx="3" fill="{C_BLOT}"/>')
        els.append(text(sbx + bw + 5, ry + 12.5, f"{kib:.1f} KiB", size=9.6, weight="600", fill=TEXT_MAIN))

    min_kib = min(r[6] for r in rows_data)
    els.append(
        text(
            28,
            h - 14,
            f"Blot builds include full blotc-goose compilation + wtime-aot native x64 codegen. Every .wasm artifact is self-contained ({min_kib:.1f}–{max_kib:.1f} KiB).",
            size=10.2,
            fill=TEXT_MUTED,
        )
    )
    els.append("</svg>\n")
    return "\n".join(els)


def main() -> None:
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DIR
    size = sys.argv[2] if len(sys.argv) > 2 else "medium"
    data_path = out_dir / "results.json"
    data = json.loads(data_path.read_text(encoding="utf-8"))

    part1 = BENCH_ORDER[:8]
    part2 = BENCH_ORDER[8:]
    cpu = data["meta"]["cpu"]

    outputs = {
        "summary_overview.svg": build_summary_overview(data, size),
        "runtime_part1.svg": build_grid_page(
            data, size, part1, "ms",
            "Runtime: Benchmarks 1–8 (CPU ms, lower is better)",
            f"Medium size · best user+sys CPU ms of {data['meta']['reps']} runs ({data['meta']['warmups']} warmups) · bit-exact parity · {cpu}",
        ),
        "runtime_part2.svg": build_grid_page(
            data, size, part2, "ms",
            "Runtime: Benchmarks 9–16 (CPU ms, lower is better)",
            f"Medium size · best user+sys CPU ms of {data['meta']['reps']} runs ({data['meta']['warmups']} warmups) · bit-exact parity · {cpu}",
        ),
        "memory_part1.svg": build_grid_page(
            data, size, part1, "peak_mb",
            "Peak Process Memory: Benchmarks 1–8 (RSS MiB, lower is better)",
            f"Medium size · exact per-process peak RSS via posix_spawn + wait4 · {cpu}",
        ),
        "memory_part2.svg": build_grid_page(
            data, size, part2, "peak_mb",
            "Peak Process Memory: Benchmarks 9–16 (RSS MiB, lower is better)",
            f"Medium size · exact per-process peak RSS via posix_spawn + wait4 · {cpu}",
        ),
        "compile_and_size.svg": build_compile_and_size(data, size),
    }

    for fname, content in outputs.items():
        p = out_dir / fname
        p.write_text(content, encoding="utf-8")
        print(f"wrote {p} ({len(content):,} bytes)")


if __name__ == "__main__":
    main()
