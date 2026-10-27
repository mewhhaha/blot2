"""Render the archived K1/main comparisons. Requires matplotlib; no new timings."""
from pathlib import Path
import hashlib
import json
import os
import tempfile

os.environ.setdefault("MPLCONFIGDIR", str(Path(tempfile.gettempdir()) / "blot-matplotlib"))
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from matplotlib.ticker import PercentFormatter

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "results/main-comparison"
OUT = ROOT / "charts"
MANIFEST = json.loads((DATA / "manifest.json").read_text())
RUNTIME = [
    ("generic_recurrence", "Generic integer loop\n1,024 steps"),
    ("generic_affine", "Generic F32 loop\n128 steps"),
    ("generic_pair", "Generic 8-byte pair\n1,024 steps"),
    ("recurrence", "Integer loop\n1,024 steps"),
    ("affine_loop", "F32 loop\n128 steps"),
]
COMPILE = [
    ("independent", "Independent functions"), ("calls", "Shared callee"),
    ("chains", "Call chain (127)"), ("diamonds", "Diamonds"),
    ("generics", "Generic calls"), ("closures", "Captured closures"),
    ("modules", "Imported modules"), ("proofs", "Guarded arithmetic"),
    ("domains", "Static domains"),
]
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 12,
    "svg.fonttype": "none", "svg.hashsalt": "blot-main-comparison-v1",
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.spines.left": False, "axes.spines.bottom": False,
})


def rows(name):
    source = DATA / (name + ".json")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == MANIFEST["files"][source.name]
    return {row["family"]: row for row in json.loads(source.read_text())["comparisons"]}


def panel(ax, data, order, metric, title, limit, ticks):
    y = list(range(len(order) - 1, -1, -1))
    ratios = [data[key][metric]["paired_candidate_over_baseline"] for key, _ in order]
    mid = [r["median"] * 100 for r in ratios]
    low, high = ([r[k] * 100 for r in ratios] for k in ("min", "max"))
    assert all(0 <= a <= b <= c < limit for a, b, c in zip(low, mid, high))
    ax.barh(y, [100] * len(y), height=0.60, color="#DEE6EF", zorder=2)
    ax.barh(y, mid, height=0.34, color="#087E8B", zorder=3)
    ax.errorbar(mid, y, xerr=([b-a for a,b in zip(low,mid)], [c-b for b,c in zip(mid,high)]),
                fmt="none", ecolor="#183844", elinewidth=1.3, capsize=3, zorder=4)
    for pos, value, hi in zip(y, mid, high):
        ax.text(hi + limit * 0.025, pos, f"{value / 100:.2f}×", va="center",
                fontsize=11, fontweight="bold", color="#183844")
    ax.axvline(100, color="#75889B", linestyle=(0, (3, 3)), linewidth=1.1, zorder=1)
    ax.set_xlim(0, limit)
    ax.set_ylim(-0.6, len(y) - 0.4)
    ax.set_xticks(ticks)
    ax.xaxis.set_major_formatter(PercentFormatter(xmax=100, decimals=0))
    ax.tick_params(axis="both", length=0, labelcolor="#40546A", pad=8)
    ax.xaxis.grid(True, color="#EEF2F6", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold", pad=21, color="#14283D")
    ax.set_yticks(y, [label for _, label in order], fontsize=12, color="#203B50")


def heading(fig, title, subtitle):
    fig.text(0.05, 0.945, title, fontsize=25, fontweight="bold", color="#14283D")
    fig.text(0.05, 0.89, subtitle, fontsize=13, color="#40546A")
    fig.legend(handles=[Patch(facecolor="#DEE6EF", label="main · 1e39b5d"),
                        Patch(facecolor="#087E8B", label="Goose K1 · current")],
               loc="upper left", bbox_to_anchor=(0.045, 0.855), frameon=False, ncols=2, fontsize=12)


def save(fig, name, title, description):
    OUT.mkdir(exist_ok=True)
    meta = {"Title": title, "Description": description}
    svg = OUT / (name + ".svg")
    fig.savefig(svg, metadata={**meta, "Date": None})
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
    fig.savefig(OUT / (name + ".png"), dpi=160, metadata=meta)
    plt.close(fig)


fig, axes = plt.subplots(1, 2, figsize=(12, 7.3), sharey=True)
fig.subplots_adjust(left=0.235, right=0.975, top=0.72, bottom=0.22, wspace=0.10)
for ax, name, title in zip(axes, ["default", "optimizing"],
                          ["Default V8", "Optimizing-only V8 · control"]):
    panel(ax, rows(name), RUNTIME, "runtime_ns_per_call", title, 800, [0, 100, 300, 500, 700])
    ax.axhline(1.5, color="#E2E8F0", linewidth=0.9, zorder=1)
heading(fig, "Runtime versus main", "main = 100% for each kernel and engine. Lower is better; above 100% is slower.")
fig.text(0.05, 0.12, "Bars: median paired runtime ratio. Whiskers: all five pairs, not confidence intervals.",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.075, "Fresh engines · 20,000 warmup + 20,000 timed calls · required export ownership hooks included",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.035, "main default pipeline / K1 --opt=off · equivalent loop kernels, not gdev · data: benchmarks/results/main-comparison/",
         fontsize=10, color="#60758A")
save(fig, "main-runtime-comparison", "Blot Goose K1 runtime versus main",
     "K1 generic integer loop takes 1.20/1.13 times main runtime, generic F32 3.61/4.24 times, "
     "and generic pair 6.40/6.55 times, in default/optimizing-only V8. Ordinary loops are near parity.")

data = rows("compile") | rows("compile-chains")
fig, ax = plt.subplots(figsize=(12, 8.7))
fig.subplots_adjust(left=0.25, right=0.95, top=0.74, bottom=0.20)
panel(ax, data, COMPILE, "wall_ms", "Fresh process compilation", 215, [0, 50, 100, 150, 200])
heading(fig, "Compile time versus main", "main = 100% for each family. Lower is better; above 100% is slower.")
fig.text(0.05, 0.12, "Bars: median paired wall-time ratio. Whiskers: all five pairs, not confidence intervals.",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.075, "128 functions/callers, except 127-depth chain · includes startup and publication · no retained session",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.035, "Native release binaries · main default pipeline / K1 --opt=off · synthetic corpus · host placement and cache uncontrolled",
         fontsize=10, color="#60758A")
save(fig, "main-compile-comparison", "Blot Goose K1 compile time versus main",
     "K1 is faster on measured call chains, closures, diamonds and generic calls; "
     "proof-heavy compilation takes 1.13 times main and static domains 1.71 times.")
print("Rendered runtime and compile SVG/PNG charts from verified archived measurements.")
