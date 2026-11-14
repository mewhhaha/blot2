#!/usr/bin/env python3
"""Build plain upstream Goose (github.com/aardappel/goose), unpatched.

Clones or reuses build/goose-upstream, checks out the pinned commit (or
--commit), builds it with CMake, and prints the compiler and its standard
library as JSON for build.py's --goose and --stdlib.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
UPSTREAM = "https://github.com/aardappel/goose"
# Upstream master on 14 November 2026.
COMMIT = "d92c4315"


def run(command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", default=COMMIT, help=f"upstream commit (default {COMMIT})")
    parser.add_argument("--checkout", type=Path, default=ROOT / "build/goose-upstream")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--cxx", default="clang++")
    parser.add_argument("--jobs", type=int, default=8)
    args = parser.parse_args()
    checkout = args.checkout.resolve()
    if not (checkout / ".git").exists():
        run(["git", "clone", "-q", UPSTREAM, str(checkout)])
    if subprocess.run(["git", "cat-file", "-e", args.commit + "^{commit}"], cwd=checkout).returncode != 0:
        run(["git", "fetch", "-q", UPSTREAM], cwd=checkout)
    dirty = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"], cwd=checkout,
                           capture_output=True, text=True, check=True).stdout
    if dirty:
        raise SystemExit(f"{checkout} has local changes; upstream Goose must be unpatched")
    run(["git", "checkout", "-q", args.commit], cwd=checkout)
    build = checkout / "build"
    run(["cmake", "-B", str(build), "-DCMAKE_BUILD_TYPE=Release",
         f"-DCMAKE_C_COMPILER={args.cc}", f"-DCMAKE_CXX_COMPILER={args.cxx}"], cwd=checkout)
    run(["cmake", "--build", str(build), "--config", "Release", "-j", str(args.jobs)], cwd=checkout)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=checkout, capture_output=True,
                          text=True, check=True).stdout.strip()
    print(json.dumps({"goose": str(build / "goose"), "stdlib": str(checkout / "stdlib"),
                      "commit": head}))


if __name__ == "__main__":
    main()
