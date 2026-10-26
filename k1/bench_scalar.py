#!/usr/bin/env python3
"""Compare process-level scalar fixture costs; this is not K1 qualification."""
import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import tempfile
import time
from pathlib import Path


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy", required=True, type=Path, help="Zig blotc executable")
    parser.add_argument("--k1", required=True, type=Path, help="experimental Goose fixture driver")
    parser.add_argument("--node", default="node", help="Node.js executable for Wasm witnesses")
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--warmup", type=int, default=2)
    args = parser.parse_args()
    if args.iterations < 1 or args.warmup < 0:
        parser.error("iterations must be positive and warmup nonnegative")
    legacy = args.legacy.resolve(strict=True)
    k1 = args.k1.resolve(strict=True)
    with tempfile.TemporaryDirectory(prefix="blot-k1-scalar-bench-") as directory:
        root = Path(directory)
        legacy_src, k1_src = root / "legacy.blot", root / "k1.blot"
        legacy_wasm, k1_wasm = root / "legacy.wasm", root / "k1.wasm"
        legacy_src.write_text("entry const id = fn (x: U32) -> U32 => x\n")
        k1_src.write_text("let id: U32 -> U32 = fn x => return x\n")
        commands = {
            "legacy": [str(legacy), "build", str(legacy_src), str(legacy_wasm), "--prelude", "none"],
            "k1_fixture": [str(k1), "fixture", str(k1_src)],
        }
        samples = {name: [] for name in commands}
        digests = {}
        environment = dict(os.environ, BLOT_CACHE_DIR="")
        for round_index in range(args.warmup + args.iterations):
            order = ("legacy", "k1_fixture") if round_index % 2 == 0 else ("k1_fixture", "legacy")
            for name in order:
                if name == "legacy":
                    legacy_wasm.unlink(missing_ok=True)
                start = time.perf_counter_ns()
                result = subprocess.run(commands[name], capture_output=True, check=False, env=environment)
                elapsed = time.perf_counter_ns() - start
                if result.returncode:
                    raise RuntimeError(f"{name} failed: {result.stderr.decode(errors='replace')}")
                if name == "legacy":
                    data = legacy_wasm.read_bytes()
                else:
                    try:
                        data = bytes.fromhex(result.stdout.decode("ascii"))
                    except (ValueError, UnicodeError) as error:
                        raise RuntimeError("K1 driver did not return hexadecimal Wasm") from error
                    k1_wasm.write_bytes(data)
                digest = sha256(data)
                if name in digests and digest != digests[name]:
                    raise RuntimeError(f"{name} emitted non-identical Wasm between runs")
                digests[name] = digest
                if round_index >= args.warmup:
                    samples[name].append(elapsed / 1_000_000)
        verify = r"""
const fs = require('fs');
(async () => {
  const legacy = (await WebAssembly.instantiate(fs.readFileSync(process.argv[1]))).instance.exports.id;
  const k1 = (await WebAssembly.instantiate(fs.readFileSync(process.argv[2]))).instance.exports.id;
  for (const value of [0, 1, 42, 0x7fffffff, 0xffffffff]) {
    if ((legacy(value) >>> 0) !== value || (k1(0, value) >>> 0) !== value)
      throw Error(`identity mismatch for ${value}`);
  }
})().catch(error => { console.error(error); process.exit(1); });
"""
        subprocess.run([args.node, "-e", verify, str(legacy_wasm), str(k1_wasm)], check=True)
        report = {
            "scope": "process wall time, identity scalar only; K1 is an unqualified private fixture",
            "caveat": "The legacy compiler writes Wasm and JSON; the K1 fixture prints hex. Pipelines and guarantees differ.",
            "platform": platform.platform(),
            "iterations": args.iterations,
            "warmup": args.warmup,
            "compiler_sha256": {"legacy": sha256(legacy.read_bytes()), "k1_fixture": sha256(k1.read_bytes())},
            "wasm_sha256": digests,
            "wasm_bytes": {"legacy": legacy_wasm.stat().st_size, "k1_fixture": k1_wasm.stat().st_size},
            "identity_witnesses": [0, 1, 42, 2147483647, 4294967295],
            "wall_ms": {name: {"median": statistics.median(values), "samples": values} for name, values in samples.items()},
        }
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
