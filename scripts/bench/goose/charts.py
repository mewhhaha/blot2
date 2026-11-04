"""Regenerate the README charts from pinned evidence; requires matplotlib."""

import json
import subprocess
from pathlib import Path

from matplotlib import rcParams
from matplotlib.figure import Figure

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "results/2026-11-04-shared-hills.json"
LABELS = {
    "fannkuch": "Fannkuch",
    "crc32": "CRC32",
    "custom_hash": "Custom hash",
    "sieve": "Sieve",
    "mandelbrot_f32": "Mandelbrot (F32)",
    "sort_merge": "Merge sort",
    "sort_quick": "Quicksort",
}
COLORS = {"blot": "#c94d3f", "goose": "#087f8c"}


def chart(rows, field, title, subtitle, filename, limit, ticks, series):
    figure = Figure(figsize=(10, 6.4))
    axes = figure.subplots()
    figure.subplots_adjust(left=0.23, right=0.90, top=0.79, bottom=0.14)
    figure.suptitle(title, x=0.04, y=0.97, ha="left", fontsize=19, weight="bold")
    figure.text(0.04, 0.88, subtitle, fontsize=10, color="#475569")
    step = 0.68 / len(series)
    for ordinal, (backend, label, color) in enumerate(series):
        offset = (ordinal - (len(series) - 1) / 2) * step
        values = []
        positions = []
        for index, case in enumerate(LABELS):
            cell = next(
                (
                    row[field]
                    for row in rows
                    if row["case"] == case and row["backend"] == backend
                ),
                None,
            )
            if cell is None:
                axes.text(
                    0,
                    index + offset,
                    "unsupported",
                    va="center",
                    color=color,
                    fontsize=9,
                )
                continue
            values.append(cell["median"])
            positions.append(index + offset)
        bars = axes.barh(
            positions,
            values,
            height=step * 0.82,
            color=color,
            label=label,
        )
        axes.bar_label(
            bars, labels=[f"{value:,.2f}" for value in values], padding=5, fontsize=10
        )
    axes.set_yticks(range(len(LABELS)), LABELS.values(), fontsize=11)
    axes.set_ylim(len(LABELS) - 0.45, -0.55)
    axes.set_xlim(0, limit)
    axes.set_xticks(ticks)
    axes.set_xlabel("Milliseconds · lower is better", labelpad=10, fontsize=10)
    axes.tick_params(axis="both", length=0, pad=9, labelcolor="#334155")
    axes.set_axisbelow(True)
    axes.grid(axis="x", color="#e2e8f0", linewidth=0.8)
    for spine in axes.spines.values():
        spine.set_visible(False)
    figure.legend(
        loc="upper right", bbox_to_anchor=(0.97, 0.98), ncol=len(series), frameon=False
    )
    figure.text(
        0.04,
        0.025,
        "2026-11-04 · shared-host medians · Blot vs Goose direct Wasm",
        fontsize=9,
        color="#64748b",
    )
    destination = HERE / "charts" / filename
    destination.parent.mkdir(exist_ok=True)
    figure.savefig(
        destination,
        facecolor="white",
        metadata={"Date": None, "Title": title, "Description": subtitle},
    )
    destination.write_text(
        "\n".join(line.rstrip() for line in destination.read_text().splitlines()) + "\n"
    )
    subprocess.run(["deno", "fmt", str(destination)], check=True)


def main():
    rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "blot-goose"})
    evidence = json.loads(EVIDENCE.read_text())
    builds = [row for row in evidence["build_summary"] if row["phase"] == "cold"]
    runtime = [
        row for row in evidence["runtime_summary"] if row["profile"] == "bounded"
    ]
    chart(
        builds,
        "wall_ms",
        "Cold compilation",
        "Five fresh uncached builds · seven supported adapted cases",
        "compilation.svg",
        150,
        [0, 25, 50, 75, 100, 125, 150],
        [("blot", "Blot", COLORS["blot"]), ("goose", "Goose", COLORS["goose"])],
    )
    chart(
        runtime,
        "kernel_ms",
        "Bounded Wasm runtime",
        "Five matched pairs · 400,000-element sorts · Mandelbrot F32 control",
        "runtime.svg",
        500,
        [0, 100, 200, 300, 400, 500],
        [
            ("blot", "Blot", COLORS["blot"]),
            ("goose", "Goose", COLORS["goose"]),
        ],
    )


if __name__ == "__main__":
    main()
