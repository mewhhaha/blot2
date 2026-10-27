"""Render the published paired runtime comparisons without rerunning benchmarks.

Requires matplotlib. Run: MPLCONFIGDIR=/tmp/blot-matplotlib python3 benchmarks/plot_runtime.py
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
from matplotlib.patches import Patch
from matplotlib.ticker import PercentFormatter

ROOT = Path(__file__).resolve().parent
DATA = ROOT / "results/runtime"
OUT = ROOT / "charts"
ORDER = [
    ("generic_recurrence", "Generic integer loop\n1,024 steps"),
    ("generic_affine", "Generic F32 loop\n128 steps"),
    ("generic_pair", "Generic 8-byte pair\n1,024 steps"),
    ("recurrence", "Integer loop\n1,024 steps"),
    ("affine_loop", "F32 loop\n128 steps"),
]
manifest = json.loads((DATA / "manifest.json").read_text())
plt.rcParams.update({
    "font.family": "DejaVu Sans", "font.size": 12,
    "svg.fonttype": "none", "svg.hashsalt": "blot-runtime-comparison-v1",
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.spines.left": False, "axes.spines.bottom": False,
})
fig, axes = plt.subplots(1, 2, figsize=(12, 7.3), sharey=True)
fig.patch.set_facecolor("#ffffff")
fig.subplots_adjust(left=0.235, right=0.975, top=0.72, bottom=0.22, wspace=0.10)
y = list(range(4, -1, -1))
for ax, name, title in zip(axes, ["default", "optimizing"],
                          ["Default V8", "Optimizing-only V8 · control"]):
    source = DATA / (name + ".json")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == manifest["files"][source.name]
    rows = {row["family"]: row for row in json.loads(source.read_text())["comparisons"]}
    ratios = [rows[key]["runtime_ns_per_call"]["paired_candidate_over_baseline"] for key, _ in ORDER]
    medians = [r["median"] * 100 for r in ratios]
    low = [r["min"] * 100 for r in ratios]
    high = [r["max"] * 100 for r in ratios]
    assert all(0 <= a <= b <= c <= 130 for a, b, c in zip(low, medians, high))
    ax.set_facecolor("#ffffff")
    ax.barh(y, [100] * 5, height=0.56, color="#E2E8F0", zorder=2)
    ax.barh(y, medians, height=0.34, color="#087E8B", zorder=3)
    ax.errorbar(medians, y, xerr=([b-a for a,b in zip(low,medians)],
                                 [c-b for b,c in zip(medians,high)]),
                fmt="none", ecolor="#183844", elinewidth=1.3, capsize=3, zorder=4)
    for row, value in zip(y, medians):
        ax.text(2.5, row, f"{value:.1f}%", ha="left", va="center",
                color="white", fontsize=11, fontweight="bold", zorder=5)
    ax.axvline(100, color="#75889B", linestyle=(0, (3, 3)), linewidth=1.1, zorder=1)
    ax.axhline(1.5, color="#E2E8F0", linewidth=0.9, zorder=1)
    ax.set_xlim(0, 130)
    ax.set_ylim(-0.6, 4.6)
    ax.set_xticks([0, 25, 50, 75, 100, 125])
    ax.xaxis.set_major_formatter(PercentFormatter(xmax=100, decimals=0))
    ax.tick_params(axis="both", length=0, labelcolor="#40546A", pad=8)
    ax.xaxis.grid(True, color="#EEF2F6", linewidth=0.8)
    ax.set_axisbelow(True)
    ax.set_title(title, loc="left", fontsize=14, fontweight="bold", pad=21, color="#14283D")
    ax.set_yticks(y, [label for _, label in ORDER], fontsize=12, color="#203B50")
fig.text(0.05, 0.945, "Runtime before and after", fontsize=25, fontweight="bold", color="#14283D")
fig.text(0.05, 0.89, "Previous compiler = 100% for each kernel and engine. Lower is better.",
         fontsize=13, color="#40546A")
fig.legend(handles=[Patch(facecolor="#E2E8F0", label="Previous K1"),
                    Patch(facecolor="#087E8B", label="Updated K1")],
           loc="upper left", bbox_to_anchor=(0.045, 0.855), frameon=False, ncols=2, fontsize=12)
fig.text(0.05, 0.12, "Bars: median paired runtime ratio. Whiskers: full observed range across five pairs (not confidence intervals).",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.075, "Fresh engine process per artifact · both compilers --opt=off · 20,000 warmup + 20,000 timed calls",
         fontsize=10.5, color="#40546A")
fig.text(0.05, 0.035, "Before 900ede2 → after e2ceba0 · measured kernels, not whole applications · data: benchmarks/results/runtime/",
         fontsize=10, color="#60758A")
OUT.mkdir(exist_ok=True)
metadata = {"Title": "Blot K1 runtime before and after", "Description":
    "Paired runtime as a percentage of the previous K1, separately for default and optimizing-only V8. "
    "Generic integer: 22.0% and 20.6%; generic F32: 81.3% and 84.7%. "
    "Ordinary and eight-byte aggregate controls remain approximately unchanged. "
    "Whiskers show all five pairs, not confidence intervals."}
fig.savefig(OUT / "runtime-comparison.svg", metadata={**metadata, "Date": None})
svg = OUT / "runtime-comparison.svg"
svg.write_text("\n".join(line.rstrip() for line in svg.read_text().splitlines()) + "\n")
fig.savefig(OUT / "runtime-comparison.png", dpi=160, metadata=metadata)
plt.close(fig)
print("Rendered SVG and PNG from verified archived measurements.")
