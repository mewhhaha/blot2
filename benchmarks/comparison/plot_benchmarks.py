#!/usr/bin/env python3
"""Generate clean editorial SVG benchmark charts from recorded JSON evidence."""

from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_PATH = ROOT / "benchmarks/evidence/measurements/2026-11-24-rust-and-bevy-ecs.json"
OUT_DIR = ROOT / "benchmarks/evidence/measurements"

FONT = "'DejaVu Sans', system-ui, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"

# Editorial palette harmonized with existing Blot charts
BG_CANVAS = "#fafaf8"
BG_CARD = "#ffffff"
BORDER = "#e2e8f0"
TEXT_MAIN = "#0f172a"
TEXT_SUB = "#475569"
TEXT_MUTED = "#64748b"
GRID = "#f1f5f9"

C_BLOT = "#0f766e"        # Blot deep teal
C_BLOT_ALT = "#14b8a6"    # Blot lighter teal
C_SPARK = "#059669"       # Blot spark SIMD emerald
C_RUST_WASM = "#3b607e"   # Rust wasm32 slate blue
C_RUST_NAT = "#c2592b"    # Rust / Bevy native terracotta

PILL_WIN_BG = "#dcfce7"
PILL_WIN_FG = "#166534"
PILL_NEU_BG = "#f1f5f9"
PILL_NEU_FG = "#334155"
PILL_RUST_BG = "#ffedd5"
PILL_RUST_FG = "#9a3412"


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def svg_header(w: int, h: int, title: str) -> list[str]:
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(title)}">',
        f'  <title>{esc(title)}</title>',
        f'  <rect x="0.5" y="0.5" width="{w - 1}" height="{h - 1}" rx="12" fill="{BG_CANVAS}" stroke="{BORDER}"/>',
    ]


def text(x: float, y: float, s: str, size: float = 12, weight: str = "400", fill: str = TEXT_MAIN, anchor: str = "start") -> str:
    return (
        f'  <text x="{x:.1f}" y="{y:.1f}" font-family="{FONT}" '
        f'font-size="{size}" font-weight="{weight}" fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>'
    )


def pill(x: float, y: float, label: str, bg: str, fg: str, anchor: str = "start") -> str:
    pad_x = 8.0
    w = len(label) * 6.4 + pad_x * 2
    h = 20.0
    rx = x if anchor == "start" else x - w
    return (
        f'  <rect x="{rx:.1f}" y="{y - 14:.1f}" width="{w:.1f}" height="{h:.1f}" rx="10" fill="{bg}"/>\n'
        f'  <text x="{rx + w / 2:.1f}" y="{y:.1f}" font-family="{FONT}" font-size="10.5" font-weight="600" '
        f'fill="{fg}" text-anchor="middle">{esc(label)}</text>'
    )


def legend_item(x: float, y: float, color: str, label: str) -> tuple[str, float]:
    out = (
        f'  <rect x="{x:.1f}" y="{y - 10:.1f}" width="13" height="13" rx="3" fill="{color}"/>\n'
        f'  <text x="{x + 19:.1f}" y="{y + 1:.1f}" font-family="{FONT}" font-size="11.5" font-weight="500" fill="{TEXT_SUB}">{esc(label)}</text>'
    )
    width = 19 + len(label) * 6.8 + 22
    return out, x + width


def build_compile_and_size(data: dict) -> str:
    c = data["compile_speed_ms"]
    w, h = 920, 326
    els = svg_header(w, h, "Compile speed and WebAssembly output size: Blot vs Rust")

    els.append(text(28, 38, "Compile speed & WebAssembly output size", size=20, weight="700"))
    els.append(text(28, 60, "Cold builds on AMD Ryzen 7 7800X3D (median of 9 runs, lower is better)", size=12.5, fill=TEXT_SUB))

    # Left card: Compile speed
    lx, ly, lw, lh = 28, 80, 422, 196
    els.append(f'  <rect x="{lx}" y="{ly}" width="{lw}" height="{lh}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(lx + 16, ly + 26, "Cold compile time (ms)", size=13.5, weight="700"))
    compile_ratio = c["rust_wasm32_opt3_ms"] / c["blot_6_kernels_ms"]
    els.append(pill(lx + lw - 14, ly + 25, f"{compile_ratio:.1f}× faster vs rustc wasm32", PILL_WIN_BG, PILL_WIN_FG, anchor="end"))

    compile_rows = [
        ("Blot · 6 kernels", c["blot_6_kernels_ms"], C_BLOT),
        ("Blot · 9-mod Ink ECS", c["blot_ink_ecs_app_ms"], C_BLOT_ALT),
        ("Rust -O3 · native rlib", c["rust_native_opt3_ms"], C_RUST_NAT),
        ("Rust -O3 · wasm32", c["rust_wasm32_opt3_ms"], C_RUST_WASM),
    ]
    max_c = max(v for _, v, _ in compile_rows)
    bar_x = lx + 160
    bar_max_w = 182.0
    for idx, (label, val, color) in enumerate(compile_rows):
        ry = ly + 62 + idx * 33
        bw = max(4.0, (val / max_c) * bar_max_w)
        els.append(text(lx + 16, ry + 13, label, size=11.5, weight="500", fill=TEXT_MAIN))
        els.append(f'  <rect x="{bar_x:.1f}" y="{ry:.1f}" width="{bar_max_w:.1f}" height="18" rx="4" fill="{GRID}"/>')
        els.append(f'  <rect x="{bar_x:.1f}" y="{ry:.1f}" width="{bw:.1f}" height="18" rx="4" fill="{color}"/>')
        els.append(text(bar_x + bw + 8, ry + 13, f"{val:.1f} ms", size=11.5, weight="600", fill=TEXT_MAIN))

    # Right card: Binary size
    rx, ry0, rw, rh = 470, 80, 422, 196
    els.append(f'  <rect x="{rx}" y="{ry0}" width="{rw}" height="{rh}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(rx + 16, ry0 + 26, "Output .wasm size (KiB)", size=13.5, weight="700"))
    size_ratio = c["rust_wasm_bytes"] / c["blot_wasm_bytes"]
    els.append(pill(rx + rw - 14, ry0 + 25, f"{size_ratio:.0f}× smaller (6 kernels)", PILL_WIN_BG, PILL_WIN_FG, anchor="end"))

    blot_kib = c["blot_wasm_bytes"] / 1024.0
    ink_kib = c["ink_ecs_wasm_bytes"] / 1024.0
    rust_kib = c["rust_wasm_bytes"] / 1024.0
    size_rows = [
        ("Blot · 6 kernels", blot_kib, C_BLOT, f"{blot_kib:.1f} KiB"),
        ("Blot · 9-mod Ink ECS", ink_kib, C_BLOT_ALT, f"{ink_kib:.1f} KiB"),
        ("Rust -O3 · 6 kernels", rust_kib, C_RUST_WASM, f"{rust_kib:,.0f} KiB"),
    ]
    max_s = max(v for _, v, _, _ in size_rows)
    sbar_x = rx + 156
    sbar_max_w = 174.0
    for idx, (label, val, color, fmt) in enumerate(size_rows):
        ry = ry0 + 68 + idx * 40
        bw = max(4.0, (val / max_s) * sbar_max_w)
        els.append(text(rx + 16, ry + 14, label, size=11.5, weight="500", fill=TEXT_MAIN))
        els.append(f'  <rect x="{sbar_x:.1f}" y="{ry:.1f}" width="{sbar_max_w:.1f}" height="20" rx="4" fill="{GRID}"/>')
        els.append(f'  <rect x="{sbar_x:.1f}" y="{ry:.1f}" width="{bw:.1f}" height="20" rx="4" fill="{color}"/>')
        els.append(text(sbar_x + bw + 8, ry + 14, fmt, size=11.5, weight="600", fill=TEXT_MAIN))

    # Footer
    els.append(
        text(
            28,
            304,
            "Production scale: Gdev (307-module / 3.09 MB 3D game, 5,029 functions) compiles cold in 549.4 ms to 4.08 MB Wasm (pen check: 0.42 s).",
            size=11.2,
            fill=TEXT_MUTED,
        )
    )
    els.append("</svg>\n")
    return "\n".join(els)


def fmt_ms(v: float) -> str:
    if v < 0.1:
        return f"{v:.3f} ms"
    if v < 10.0:
        return f"{v:.2f} ms"
    return f"{v:.1f} ms"


def build_kernels_chart(data: dict) -> str:
    by_name = {row["name"]: row for row in data["kernels"]}
    specs = [
        ("particle_spark_simd", "65k particles × 32 · spark v128"),
        ("mandelbrot_f32", "256×256 scalar FP · 100 max iter"),
        ("merge_sort", "100k U32 · owned ping-pong buffers"),
        ("lcg_recurrence", "1,000,000 tight integer steps"),
        ("prime_sieve", "100k flags · bounds-checked writes"),
        ("matmul_64", "64×64 F32 · scalar triple loop"),
    ]

    w, h = 920, 492
    els = svg_header(w, h, "Blot vs Rust -O3 compute, memory, and auto-SIMD benchmarks")

    els.append(text(28, 38, "Blot vs Rust (-O3): Compute, memory & auto-SIMD", size=20, weight="700"))
    els.append(text(28, 60, "Median of 15 runs in ms (lower is better) · bit-exact checksum parity on every kernel · Ryzen 7 7800X3D", size=12.5, fill=TEXT_SUB))

    # Legend
    lx = 28.0
    for color, label in [
        (C_BLOT, "Blot (Wasmtime 49.0.7)"),
        (C_RUST_WASM, "Rust -O3 (wasm32, Wasmtime 49.0.7)"),
        (C_RUST_NAT, "Rust -O3 (Native x86_64)"),
    ]:
        snippet, lx = legend_item(lx, 86, color, label)
        els.append(snippet)

    card_w, card_h = 276, 162
    gap_x, gap_y = 18, 18
    start_x, start_y = 28, 108

    for idx, (name, sub) in enumerate(specs):
        row_data = by_name[name]
        col = idx % 3
        row = idx // 3
        cx = start_x + col * (card_w + gap_x)
        cy = start_y + row * (card_h + gap_y)

        els.append(f'  <rect x="{cx}" y="{cy}" width="{card_w}" height="{card_h}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els.append(text(cx + 14, cy + 24, name, size=13, weight="700"))
        els.append(text(cx + 14, cy + 40, sub, size=10.5, fill=TEXT_MUTED))

        bars = [
            ("Blot", row_data["blot_wasmtime_ms"], C_BLOT),
            ("Rust Wasm", row_data["rust_wasmtime_ms"], C_RUST_WASM),
            ("Rust Nat.", row_data["rust_native_ms"], C_RUST_NAT),
        ]
        vmax = max(v for _, v, _ in bars)
        bx = cx + 84
        bmax_w = 114.0
        for b_i, (blabel, bval, bcol) in enumerate(bars):
            by = cy + 54 + b_i * 25
            bw = max(3.5, (bval / vmax) * bmax_w)
            els.append(text(cx + 14, by + 12.5, blabel, size=10.8, weight="500", fill=TEXT_SUB))
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax_w:.1f}" height="16" rx="3.5" fill="{GRID}"/>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="16" rx="3.5" fill="{bcol}"/>')
            els.append(text(bx + bw + 6, by + 12.5, fmt_ms(bval), size=10.8, weight="600", fill=TEXT_MAIN))

        ratio_w = row_data["blot_vs_rust_wasm"]
        ratio_n = row_data["blot_vs_rust_native"]
        ratio_txt = f"Blot: {ratio_w:.2f}× Rust Wasm · {ratio_n:.2f}× native" if ratio_w < 10 else f"Blot: {ratio_w:.1f}× Rust Wasm · {ratio_n:.1f}× native"
        els.append(text(cx + 14, cy + card_h - 12, ratio_txt, size=10.2, weight="500", fill=TEXT_MUTED))

    els.append(
        text(
            28,
            h - 16,
            "Each subplot uses its own linear 0..max scale. Blot enforces canonical 0x7fc00000 quiet NaN and bounds checks; use spark #[...] for SIMD.",
            size=11.0,
            fill=TEXT_MUTED,
        )
    )
    els.append("</svg>\n")
    return "\n".join(els)


def build_ecs_chart(data: dict) -> str:
    by_name = {row["name"]: row for row in data["ecs"]}
    dense = by_name["dense_iter_10k_x100"]
    sparse = by_name["sparse_filtered_iter_500_of_10k_x100"]
    spawn = by_name["batch_spawn_10k"]
    churn = by_name["structural_churn_2000_tag_ops"]
    snap = by_name["world_snapshot_copy_10k"]

    w, h = 920, 580
    els = svg_header(w, h, "Ink ECS vs Bevy ECS 0.20.1 performance comparison")

    els.append(text(28, 38, "Ink ECS (Blot → Wasmtime) vs Bevy ECS 0.20.1 (Native Rust)", size=20, weight="700"))
    els.append(text(28, 60, "10,000-entity worlds · median of 15 runs (lower is better) · bit-exact checksum parity on dense, sparse & spawn", size=12.5, fill=TEXT_SUB))

    # Legend
    lx = 28.0
    ink_kib = data["compile_speed_ms"]["ink_ecs_wasm_bytes"] / 1024.0
    for color, label in [
        (C_SPARK, "Blot SoA + spark SIMD (Wasmtime)"),
        (C_BLOT, f"Ink ECS ({ink_kib:.1f} KiB Wasm, Wasmtime 49.0.7)"),
        (C_RUST_NAT, "Bevy ECS 0.20.1 (Native x86_64 Rust -O3)"),
    ]:
        snippet, lx = legend_item(lx, 86, color, label)
        els.append(snippet)

    # Top full-width card: Dense iteration (4 bars)
    tx, ty, tw, th = 28, 108, 864, 166
    els.append(f'  <rect x="{tx}" y="{ty}" width="{tw}" height="{th}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
    els.append(text(tx + 16, ty + 25, "Dense iteration: Pos += Vel (10,000 entities × 100 ticks)", size=13.5, weight="700"))
    ratio_spark = dense["bevy_native_ms"] / dense["ink_soa_spark_simd_ms"]
    els.append(pill(tx + tw - 14, ty + 24, f"Blot spark SoA {ratio_spark:.1f}× faster vs Bevy AoS", PILL_WIN_BG, PILL_WIN_FG, anchor="end"))

    dense_rows = [
        ("Blot SoA + spark SIMD", dense["ink_soa_spark_simd_ms"], C_SPARK),
        ("Bevy ECS (native AoS)", dense["bevy_native_ms"], C_RUST_NAT),
        ("Ink ECS (Pool direct)", dense["ink_pool_direct_ms"], C_BLOT),
        ("Ink ECS (cached query)", dense["ink_cached_query_ms"], C_BLOT),
    ]
    dmax = max(v for _, v, _ in dense_rows)
    dbx = tx + 196
    dbmax_w = 570.0
    for idx, (label, val, color) in enumerate(dense_rows):
        ry = ty + 44 + idx * 28
        bw = max(4.0, (val / dmax) * dbmax_w)
        els.append(text(tx + 16, ry + 13.5, label, size=11.5, weight="500", fill=TEXT_MAIN))
        els.append(f'  <rect x="{dbx:.1f}" y="{ry:.1f}" width="{dbmax_w:.1f}" height="18" rx="4" fill="{GRID}"/>')
        els.append(f'  <rect x="{dbx:.1f}" y="{ry:.1f}" width="{bw:.1f}" height="18" rx="4" fill="{color}"/>')
        els.append(text(dbx + bw + 9, ry + 13.5, f"{val:.2f} ms", size=11.5, weight="600", fill=TEXT_MAIN))

    # Bottom 2x2 grid: 4 workloads
    cards = [
        (
            "Structural tag churn (2,000 ops)",
            "Insert/remove Active tag on 10k world",
            f"Ink {churn['bevy_native_ms'] / churn['ink_ms']:.1f}× faster",
            PILL_WIN_BG,
            PILL_WIN_FG,
            [
                ("Ink ECS", churn["ink_ms"], C_BLOT, f"{churn['ink_ms'] * 1000:.1f} µs"),
                ("Bevy ECS", churn["bevy_native_ms"], C_RUST_NAT, f"{churn['bevy_native_ms'] * 1000:.1f} µs"),
            ],
        ),
        (
            "Full-world snapshot (10k entities)",
            "Clone all 5 pools / rebuild Bevy World",
            f"Ink {snap['bevy_native_world_rebuild_ms'] / snap['ink_ms']:.1f}× faster",
            PILL_WIN_BG,
            PILL_WIN_FG,
            [
                ("Ink ECS", snap["ink_ms"], C_BLOT, f"{snap['ink_ms'] * 1000:.1f} µs"),
                ("Bevy ECS", snap["bevy_native_world_rebuild_ms"], C_RUST_NAT, f"{snap['bevy_native_world_rebuild_ms'] * 1000:.1f} µs"),
            ],
        ),
        (
            "Sparse filtered query (5% × 100)",
            "With Active, Without Frozen (500 of 10k)",
            f"Bevy {sparse['ink_cached_query_ms'] / sparse['bevy_native_ms']:.1f}× faster",
            PILL_RUST_BG,
            PILL_RUST_FG,
            [
                ("Bevy ECS", sparse["bevy_native_ms"], C_RUST_NAT, f"{sparse['bevy_native_ms']:.3f} ms"),
                ("Ink ECS", sparse["ink_cached_query_ms"], C_BLOT, f"{sparse['ink_cached_query_ms']:.3f} ms"),
            ],
        ),
        (
            "Batch spawn (10,000 entities)",
            "Pos + Vel + 10% Active",
            f"Bevy {spawn['ink_ms'] / spawn['bevy_native_ms']:.1f}× faster",
            PILL_RUST_BG,
            PILL_RUST_FG,
            [
                ("Bevy ECS", spawn["bevy_native_ms"], C_RUST_NAT, f"{spawn['bevy_native_ms']:.3f} ms"),
                ("Ink ECS", spawn["ink_ms"], C_BLOT, f"{spawn['ink_ms']:.3f} ms"),
            ],
        ),
    ]

    cw, ch = 423, 114
    gap = 18
    by0 = 292
    for idx, (title, sub, badge, pbg, pfg, bars) in enumerate(cards):
        col = idx % 2
        row = idx // 2
        cx = 28 + col * (cw + gap)
        cy = by0 + row * (ch + gap)
        els.append(f'  <rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="8" fill="{BG_CARD}" stroke="{BORDER}"/>')
        els.append(text(cx + 14, cy + 24, title, size=12.6, weight="700"))
        els.append(text(cx + 14, cy + 40, sub, size=10.5, fill=TEXT_MUTED))
        els.append(pill(cx + cw - 12, cy + 23, badge, pbg, pfg, anchor="end"))

        vmax = max(v for _, v, _, _ in bars)
        bx = cx + 88
        bmax_w = 248.0
        for b_i, (blabel, bval, bcol, bfmt) in enumerate(bars):
            by = cy + 52 + b_i * 27
            bw = max(4.0, (bval / vmax) * bmax_w)
            els.append(text(cx + 14, by + 13.5, blabel, size=11.2, weight="500", fill=TEXT_MAIN))
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bmax_w:.1f}" height="18" rx="4" fill="{GRID}"/>')
            els.append(f'  <rect x="{bx:.1f}" y="{by:.1f}" width="{bw:.1f}" height="18" rx="4" fill="{bcol}"/>')
            els.append(text(bx + bw + 8, by + 13.5, bfmt, size=11.2, weight="600", fill=TEXT_MAIN))

    els.append(
        text(
            28,
            h - 18,
            "Archetype tables (Bevy) excel at AoS queries & batch spawn; entity-indexed owned columns (Ink) excel at tag churn, snapshots, and spark SoA.",
            size=10.9,
            fill=TEXT_MUTED,
        )
    )
    els.append("</svg>\n")
    return "\n".join(els)


def main() -> None:
    data = json.loads(DATA_PATH.read_text())
    outputs = {
        "2026-11-24-compile-and-size.svg": build_compile_and_size(data),
        "2026-11-24-blot-vs-rust-kernels.svg": build_kernels_chart(data),
        "2026-11-24-ink-vs-bevy-ecs.svg": build_ecs_chart(data),
    }
    for fname, content in outputs.items():
        path = OUT_DIR / fname
        path.write_text(content)
        print(f"wrote {path} ({len(content)} bytes)")


if __name__ == "__main__":
    main()
