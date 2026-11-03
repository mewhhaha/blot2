"""Regenerate the README charts from pinned evidence; requires matplotlib."""

import json
from pathlib import Path

from matplotlib import rcParams
from matplotlib.figure import Figure

HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "results/2026-11-03.json"
LABELS = {"fannkuch": "Fannkuch", "crc32": "CRC32", "custom_hash": "Custom hash"}
COLORS = {"blot": "#c94d3f", "goose": "#087f8c"}


def chart(rows, field, title, subtitle, filename, limit, ticks):
    figure = Figure(figsize=(10, 4.2))
    axes = figure.subplots()
    figure.subplots_adjust(left=0.18, right=0.90, top=0.74, bottom=0.18)
    figure.suptitle(title, x=0.04, y=0.97, ha="left", fontsize=19, weight="bold")
    figure.text(0.04, 0.84, subtitle, fontsize=10, color="#475569")
    for backend, offset in [("blot", -0.17), ("goose", 0.17)]:
        values = [
            next(
                row[field]["median"]
                for row in rows
                if row["case"] == case and row["backend"] == backend
            )
            for case in LABELS
        ]
        bars = axes.barh(
            [index + offset for index in range(len(LABELS))],
            values,
            height=0.28,
            color=COLORS[backend],
            label=backend.capitalize(),
        )
        axes.bar_label(
            bars, labels=[f"{value:,.2f}" for value in values], padding=5, fontsize=10
        )
    axes.set_yticks(range(len(LABELS)), LABELS.values(), fontsize=11)
    axes.set_ylim(2.55, -0.55)
    axes.set_xlim(0, limit)
    axes.set_xticks(ticks)
    axes.set_xlabel("Milliseconds · lower is better", labelpad=10, fontsize=10)
    axes.tick_params(axis="both", length=0, pad=9, labelcolor="#334155")
    axes.set_axisbelow(True)
    axes.grid(axis="x", color="#e2e8f0", linewidth=0.8)
    for spine in axes.spines.values():
        spine.set_visible(False)
    figure.legend(loc="upper right", bbox_to_anchor=(0.97, 0.98), ncol=2, frameon=False)
    figure.text(
        0.04,
        0.025,
        "2026-11-03 · shared-host medians · Blot vs Goose direct Wasm",
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


def main():
    rcParams.update({"svg.fonttype": "none", "svg.hashsalt": "blot-goose"})
    evidence = json.loads(EVIDENCE.read_text())
    builds = [
        row for row in evidence["compilation"]["summary"] if row["phase"] == "cold"
    ]
    runtime = [
        row for row in evidence["runtime"]["summary"] if row["profile"] == "bounded"
    ]
    chart(
        builds,
        "wall_ms",
        "Cold compilation",
        "Five fresh uncached builds per cell · ordinary compiler settings",
        "compilation.svg",
        110,
        [0, 25, 50, 75, 100],
    )
    chart(
        runtime,
        "kernel_ms",
        "Bounded Wasm runtime",
        "Five checked pairs in the same V8 · production input sizes, fewer repetitions",
        "runtime.svg",
        6000,
        [0, 1500, 3000, 4500, 6000],
    )


if __name__ == "__main__":
    main()
