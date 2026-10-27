"""Render verified data as Gnorp-inspired vertical charts; requires matplotlib.

Original vector artwork is decorative; bar silhouettes retain exact data heights.
"""
from pathlib import Path
import hashlib
import json
import os
import tempfile

os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "blot-matplotlib"))
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.offsetbox import AnnotationBbox, DrawingArea
from matplotlib.patches import Patch, Rectangle
from matplotlib.ticker import FuncFormatter

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "results/main-comparison"
OUT = ROOT / "charts"
MANIFEST = json.loads((DATA / "manifest.json").read_text())
RUNTIME = [
    ("recurrence", "Integer\n1,024 steps"), ("affine_loop", "F32\n128 steps"),
    ("generic_recurrence", "Generic integer\n1,024 steps"),
    ("generic_affine", "Generic F32\n128 steps"),
    ("generic_pair", "Generic pair\n1,024 steps"),
]
COMPILE = [
    ("independent", "Independent\nfunctions"), ("calls", "Shared\ncallee"),
    ("chains", "Call chain\n(127)"), ("diamonds", "Diamonds"),
    ("generics", "Generic\ncalls"), ("closures", "Captured\nclosures"),
    ("modules", "Imported\nmodules"), ("proofs", "Guarded\narithmetic"),
    ("domains", "Static\ndomains"),
]
BG, PANEL, GRID = "#171E29", "#202A38", "#344152"
TEXT, MUTED = "#F5F0DB", "#B7C2CA"
GOLD, MINT, MONO = "#F6BE5A", "#80DBBC", "DejaVu Sans Mono"
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 12,
    "svg.fonttype": "none", "svg.hashsalt": "blot-quarry-v1",
    "figure.facecolor": BG, "axes.facecolor": PANEL,
    "text.color": TEXT, "axes.labelcolor": MUTED,
    "xtick.color": TEXT, "ytick.color": MUTED,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.spines.left": False, "axes.spines.bottom": False,
})


def rows(name):
    source = DATA / (name + ".json")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == MANIFEST["files"][source.name]
    return {row["family"]: row for row in json.loads(source.read_text())["comparisons"]}


def hauler(color, scale=1.4):
    """Original pixel creature drawn in points, outside the data rectangle."""
    pixels = ["   hhh    ", "  hhhhh   ", "  wwwww   ", " wwwweww  ",
              " wwwwwww  ", "  wwwww   ", "  ww ww   ", "  dd dd   "]
    palette = {"h": color, "w": TEXT, "e": BG, "d": MUTED}
    drawing = DrawingArea(14 * scale, 11 * scale, clip=False)
    for row, line in enumerate(pixels):
        for col, token in enumerate(line):
            if token in palette:
                drawing.add_artist(Rectangle((col * scale, (8-row) * scale), scale, scale,
                                             facecolor=palette[token], edgecolor="none"))
    for x, y in [(10, 2), (11, 2), (12, 2), (11, 3), (12, 3), (12, 4)]:
        drawing.add_artist(Rectangle((x*scale, y*scale), scale, scale,
                                     facecolor=color, edgecolor="none"))
    return drawing


def quarry_mark(fig):
    rock = DrawingArea(78, 56, clip=False)
    for x, y, w, h, color in [
        (7, 6, 64, 9, "#465667"), (1, 15, 72, 20, "#5C6C7D"),
        (11, 35, 53, 9, "#6A7D8D"), (23, 44, 28, 6, "#80919E"),
        (14, 25, 17, 6, "#81909A"), (42, 14, 21, 5, "#43505E"),
        (32, 32, 5, 10, "#354252"), (37, 27, 12, 5, "#354252"),
    ]:
        rock.add_artist(Rectangle((x, y), w, h, facecolor=color, edgecolor="none"))
    fig.add_artist(AnnotationBbox(rock, (0.91, 0.91), xycoords=fig.transFigure, frameon=False))
    for x, color in [(0.86, GOLD), (0.965, MINT)]:
        fig.add_artist(AnnotationBbox(hauler(color, 2.2), (x, 0.88),
                                     xycoords=fig.transFigure, frameon=False))


def heading(fig, chapter, title, subtitle, direction):
    fig.text(0.055, 0.952, f"THE BENCHMARK QUARRY  /  {chapter}",
             fontfamily=MONO, fontsize=11, color=MINT, fontweight="bold")
    fig.text(0.055, 0.89, title, fontsize=28, fontweight="bold")
    fig.text(0.055, 0.845, subtitle, fontsize=12.5, color=MUTED)
    fig.legend(handles=[Patch(facecolor=GOLD, label="Zig · old compiler on main"),
                        Patch(facecolor=MINT, label="Goose · new K1 compiler")],
               loc="upper left", bbox_to_anchor=(0.05, 0.817), frameon=False,
               ncols=2, labelcolor=TEXT, fontsize=12, handlelength=1.2, columnspacing=2)
    fig.text(0.95, 0.785, direction, ha="right", fontfamily=MONO, fontsize=11,
             color=MINT, fontweight="bold")
    quarry_mark(fig)


def scaffold(ax, labels, ceiling, ticks, ylabel):
    ax.set_ylim(0, ceiling)
    ax.set_xlim(-0.65, len(labels) - 0.35)
    ax.set_yticks(ticks)
    ax.set_xticks(range(len(labels)), labels)
    ax.tick_params(axis="x", length=0, pad=24, labelsize=10.5)
    ax.tick_params(axis="y", length=0, pad=8, labelsize=10)
    ax.set_ylabel(ylabel, labelpad=10, fontsize=11)
    ax.yaxis.grid(True, color=GRID, linewidth=0.7)
    ax.set_axisbelow(True)
    ax.axhline(0, color=MUTED, linewidth=2, zorder=5)


def stack(ax, x, height, color, quantum, width=0.31):
    ax.bar(x, height, width=width, color=color, zorder=3)
    # Brick seams do not round or extend the exact top of the solid silhouette.
    for row in range(1, int(height / quantum) + 1):
        y = row * quantum
        if y < height:
            ax.plot([x-width/2, x+width/2], [y, y], color=PANEL, alpha=0.36,
                    linewidth=0.8, zorder=4, solid_capstyle="butt")
            offset = width * (0.14 if row % 2 else -0.14)
            ax.plot([x+offset, x+offset], [y-quantum, y], color=PANEL,
                    alpha=0.27, linewidth=0.8, zorder=4, solid_capstyle="butt")
    ax.add_artist(AnnotationBbox(hauler(color), (x, 0), xybox=(0, -10),
                                xycoords="data", boxcoords="offset points", frameon=False,
                                annotation_clip=False, zorder=6))


def whisker(ax, x, mid, low, high):
    assert 0 < low <= mid <= high
    ax.errorbar(x, mid, yerr=[[mid-low], [high-mid]], fmt="none", ecolor=TEXT,
                elinewidth=1.1, capsize=3, capthick=1.1, zorder=7)


def footer(fig, line1, line2, line3):
    for y, line in [(0.125, line1), (0.082, line2), (0.04, line3)]:
        fig.text(0.055, y, line, fontsize=10.5 if y > 0.04 else 9.5, color=MUTED)


def save(fig, name, title, description):
    OUT.mkdir(exist_ok=True)
    meta = {"Title": title, "Description": description}
    svg = OUT / (name + ".svg")
    fig.savefig(svg, metadata={**meta, "Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    fig.savefig(OUT / (name + ".png"), dpi=160, metadata=meta)
    plt.close(fig)


def runtime():
    fig, axes = plt.subplots(1, 2, figsize=(15, 8.8), sharey=True)
    fig.subplots_adjust(left=0.075, right=0.97, top=0.66, bottom=0.26, wspace=0.12)
    for ax, name, title in zip(axes, ["default", "optimizing"],
                              ["01  DEFAULT V8", "02  OPTIMIZING-ONLY V8"]):
        data = rows(name)
        scaffold(ax, [label for _, label in RUNTIME], 1.48, [0, 0.5, 1],
                 "Relative work per second" if name == "default" else "")
        ax.yaxis.set_major_formatter(FuncFormatter(lambda v, _: f"{v:.1f}×"))
        ax.axhline(1, color=GOLD, linestyle=(0, (3, 4)), alpha=0.5, linewidth=1, zorder=2)
        ax.set_title(title, loc="left", fontfamily=MONO, fontsize=12, pad=18,
                     color=TEXT, fontweight="bold")
        for i, (key, _) in enumerate(RUNTIME):
            ratio = data[key]["runtime_ns_per_call"]["paired_candidate_over_baseline"]
            # Five positive pairs: reciprocal(median time ratio) = median speed ratio.
            mid, low, high = 1/ratio["median"], 1/ratio["max"], 1/ratio["min"]
            assert high < 1.3
            stack(ax, i-0.18, 1, GOLD, 0.1)
            stack(ax, i+0.18, mid, MINT, 0.1)
            whisker(ax, i+0.18, mid, low, high)
            ax.text(i-0.18, 1.035, "1.00", ha="center", va="bottom",
                    color=GOLD, fontfamily=MONO, fontsize=9.5)
            ax.text(i+0.18, high+0.035, f"{mid:.2f}", ha="center", va="bottom",
                    color=MINT, fontfamily=MONO, fontsize=9.5, fontweight="bold")
    heading(fig, "01 / RUNTIME", "Same job. How much can they haul?",
            "Relative throughput for each benchmark · Zig on main = 1.00× in each engine", "TALLER = FASTER")
    footer(fig,
           "Shard stacks = work per second, relative to Zig. 0.25× means one quarter of Zig's throughput.",
           "Five paired samples · mint whiskers show the full paired range, not confidence intervals · Zig is the fixed reference",
           "20k warmup + 20k timed calls · fresh engines · required ownership hooks included · main default / K1 --opt=off · 2026-10-27")
    save(fig, "main-runtime-comparison", "Zig main versus Goose K1: runtime throughput",
         "Vertical bars with original Gnorp-inspired shard-haulers. Taller means faster. "
         "Main is 1.00x. Median paired K1/main throughput: integer 1.04/1.06, F32 1.10/0.92, "
         "generic integer 0.83/0.88, generic F32 0.28/0.24, generic pair 0.16/0.15 in default/optimizing-only V8. "
         "Whiskers show all five paired ratios, not confidence intervals. Synthetic kernels, not gdev.")


def compilation():
    data = rows("compile") | rows("compile-chains")
    fig, ax = plt.subplots(figsize=(15, 8.8))
    fig.subplots_adjust(left=0.075, right=0.97, top=0.70, bottom=0.26)
    scaffold(ax, [label for _, label in COMPILE], 31, [0, 5, 10, 15, 20, 25, 30], "Compile time (ms)")
    for i, (key, _) in enumerate(COMPILE):
        for who, offset, color in [("baseline", -0.18, GOLD), ("candidate", 0.18, MINT)]:
            timing = data[key]["wall_ms"][who]
            mid, low, high = (timing[k] for k in ["median", "min", "max"])
            assert high < 28
            stack(ax, i+offset, mid, color, 1.0)
            whisker(ax, i+offset, mid, low, high)
            ax.text(i+offset, high+0.55, f"{mid:.2f}", ha="center", va="bottom",
                    color=color, fontfamily=MONO, fontsize=9.5, fontweight="bold")
    heading(fig, "02 / COMPILE", "How long until the quarry opens?",
            "Fresh program compilation · native release compilers · actual elapsed milliseconds", "SHORTER = QUICKER")
    footer(fig,
           "Shard stacks = time spent compiling. Values are medians; whiskers show all five observations, not confidence intervals.",
           "128 functions/callers, except 127-depth chain · includes process startup and publication · no retained session",
           "Zig main 1e39b5d / Goose K1 e2ceba0 · main default / K1 --opt=off · host placement and cache uncontrolled · 2026-10-27")
    save(fig, "main-compile-comparison", "Zig main versus Goose K1: fresh compile time",
         "Vertical gold and mint shard stacks show actual median milliseconds and observed ranges. "
         "Shorter is quicker. Call chains: Zig 8.65ms, Goose 5.23ms. Guarded arithmetic: 22.27/24.90ms. "
         "Static domains: 7.71/13.03ms. Synthetic program builds, not compiler executable rebuilds or gdev.")


if __name__ == "__main__":
    runtime()
    compilation()
    print("Rendered vertical quarry charts from verified archived measurements; no benchmarks rerun.")
