#!/usr/bin/env python3
"""Seed gdev's start state with controlled settled-brick density.

Use only on an isolated gdev checkout. The unchanged game starts with no salt
stacks; each variant has the same 151 grid positions and 0, 1, 4, or 8 bricks
per stack. The original game.blot is read from that checkout's HEAD each time.
"""

import argparse
from pathlib import Path
import subprocess


def seeded(original: str, depth: int) -> str:
    if depth == 0:
        return original
    if original.count("  stacks: #[],") != 1:
        raise ValueError("expected exactly one empty starting salt stack list")
    if original.count('import * as app from "ink/app"') != 1:
        raise ValueError("expected exactly one app import")
    seeded = original.replace(
        'import * as app from "ink/app"',
        'import * as array from "std/array"\nimport * as app from "ink/app"',
        1,
    )
    seeded = seeded.replace(
        "  stacks: #[],",
        """  stacks: array.generate 151 (fn (index: U32) => #salt.Stack {
    x: 12.0 + U32.to_f32 (index % 13) * 1.5,
    z: -9.0 + U32.to_f32 (index / 13) * 1.5,
    count: DEPTH, turn: 0.0, lift: 0.0, fall: 0.0, jolt: 0.0,
  }),""".replace("DEPTH", str(depth)),
        1,
    )
    seeded = seeded.replace("  gathered: 0,", f"  gathered: {151 * depth},", 1)
    return seeded


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout", type=Path)
    parser.add_argument("bricks_per_stack", type=int, choices=(0, 1, 4, 8))
    args = parser.parse_args()
    game = args.checkout / "src/game.blot"
    original = subprocess.check_output(
        ["git", "-C", str(args.checkout), "show", "HEAD:src/game.blot"],
        text=True,
    )
    permitted = {seeded(original, depth) for depth in (0, 1, 4, 8)}
    if game.read_text() not in permitted:
        raise ValueError("game.blot has unrelated changes; preserve them in another checkout")
    temporary = game.with_suffix(".blot.issue16-tmp")
    temporary.write_text(seeded(original, args.bricks_per_stack))
    temporary.replace(game)


if __name__ == "__main__":
    main()
