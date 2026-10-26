"""Replay the pinned runtime-boundaries results with Wasmtime's Python host.

Use the same baseline/candidate Wasm produced by runtime_boundaries.ts. Times
include three Python/Wasmtime function calls, ownership checks and the ownership
boundary per invocation.
"""
import argparse
import hashlib
import importlib.metadata
import json
import pathlib
import platform
import statistics
import time

import wasmtime

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=pathlib.Path)
parser.add_argument("--samples", type=int, default=31)
parser.add_argument("--batch", type=int, default=5)
args = parser.parse_args()
assert args.samples >= 3 and args.batch > 0
reference = json.loads((args.directory / "results.json").read_text())
assert reference["complete"]
engine = wasmtime.Engine()
guests = {}
for side in ["baseline", "candidate"]:
    data = (args.directory / f"{side}.wasm").read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    assert digest == next(b["wasm_sha256"] for b in reference["builds"] if b["side"] == side)
    store = wasmtime.Store(engine)
    module = wasmtime.Module(engine, data)
    guests[side] = (store, wasmtime.Instance(store, module, []).exports(store))


def invoke(side, name, argument, expected):
    store, exports = guests[side]
    exports["blot:ownership_enter"](store)
    outcome = 1
    try:
        result = exports[name](store, argument) & 0xFFFFFFFF
        assert result == (expected & 0xFFFFFFFF), (side, name, result, expected)
        outcome = 0
    finally:
        exports["blot:ownership_leave"](store, outcome)
    assert exports["blot:rc_roots"].value(store) == 0
    assert exports["blot:rc_leases"].value(store) == 0


report = dict(format=1, complete=False, engine="Wasmtime " + importlib.metadata.version("wasmtime"),
              host=platform.python_version(), scope=__doc__, samples=args.samples, batch=args.batch,
              builds=reference["builds"], rows=[])
destination = args.directory / "wasmtime.json"
for row in reference["rows"]:
    name, argument, expected = row["name"], row["argument"], row["expected"]
    measured = {}
    for side in guests:
        store, exports = guests[side]
        for _ in range(5):
            invoke(side, name, argument, expected)
        before = {key: exports["blot:" + key].value(store) for key in row[side]["counts"]}
        invoke(side, name, argument, expected)
        counts = {key: (exports["blot:" + key].value(store) - value) & 0xFFFFFFFF for key, value in before.items()}
        assert counts == row[side]["counts"], (side, name, counts, row[side]["counts"])
        measured[side] = dict(counts=counts, samples_ms=[])
    for sample in range(args.samples):
        for side in (["baseline", "candidate"] if sample % 2 == 0 else ["candidate", "baseline"]):
            start = time.perf_counter_ns()
            for _ in range(args.batch):
                invoke(side, name, argument, expected)
            measured[side]["samples_ms"].append((time.perf_counter_ns() - start) / 1e6 / args.batch)
    for side in guests:
        measured[side]["median_ms"] = statistics.median(measured[side]["samples_ms"])
    report["rows"].append(dict(name=name, argument=argument, expected=expected, **measured))
    destination.write_text(json.dumps(report, indent=2) + "\n")
    print(name, argument, *(round(measured[side]["median_ms"], 4) for side in guests), flush=True)
report["complete"] = True
destination.write_text(json.dumps(report, indent=2) + "\n")
