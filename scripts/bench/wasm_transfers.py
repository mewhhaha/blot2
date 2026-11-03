#!/usr/bin/env python3
"""Inspect uninterrupted word-transfer runs in an already censused Wasm binary.

Uses wasm_size.py's decoder and a SHA-matched --census report. Counts static
encodings, not runtime work or removable bytes. Direct-call reachability is
reported only without tables, elements, or indirect/reference calls.
"""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import time

from wasm_size import Reader, instruction


def analyze(path, census):
    started = time.monotonic()
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != census["wasm_sha256"]:
        raise ValueError("census does not describe this binary")
    bodies, runs, roots = {}, [], set()
    counts, sizes = Counter(), Counter()
    identity_counts, identity_sizes = Counter(), Counter()
    unsupported = set()
    readback_count = readback_bytes = 0
    for section in census["sections"]:
        ident = section["id"]
        r = Reader(data, section["payload_offset"], section["payload_offset"] + section["payload_bytes"])
        if ident in (4, 9):
            unsupported.add("table or element section")
        elif ident == 7:
            for _ in range(r.leb()):
                r.string()
                kind, index = r.byte(), r.leb()
                if kind == 0:
                    roots.add(index)
        elif ident == 8:
            roots.add(r.leb())
        elif ident == 10:
            for ordinal in range(r.leb()):
                size = r.leb()
                start, end = r.pos, r.pos + size
                b = Reader(data, start, end)
                for _ in range(b.leb()):
                    b.leb()
                    b.value_type()
                index = census["imported_functions"] + ordinal
                calls, body_runs = set(), []
                pending = previous = run = None
                while b.pos < b.end:
                    offset = b.pos
                    name, length, operand = instruction(b)
                    if name in ("call", "return_call"):
                        calls.add(operand)
                    elif name in ("call_indirect", "return_call_indirect", "call_ref", "return_call_ref", "ref.func"):
                        unsupported.add(name)
                    if previous and previous[0] == "local.set" and name == "local.get" and previous[2] == operand:
                        readback_count += 1
                        readback_bytes += previous[1] + length
                    previous = name, length, operand
                    if pending and name in ("local.set", "global.set"):
                        source_name, source_length, source, source_offset = pending
                        kind = source_name + " -> " + name
                        if source_name == "i32.const":
                            kind = "i32.const 0 -> " + name
                        if run is None or run["kind"] != kind:
                            if run:
                                body_runs.append(run)
                            run = dict(kind=kind, function=index, offset=source_offset,
                                       pairs=0, bytes=0, first_source=source,
                                       first_target=operand, consecutive_targets=True,
                                       consecutive_sources=True)
                        if run["pairs"]:
                            run["consecutive_targets"] &= operand == run["last_target"] + 1
                            run["consecutive_sources"] &= source == run["last_source"] + 1
                        run["pairs"] += 1
                        run["bytes"] += source_length + length
                        run["last_source"], run["last_target"] = source, operand
                        counts[kind] += 1
                        sizes[kind] += source_length + length
                        if kind in ("local.get -> local.set", "global.get -> global.set") and source == operand:
                            identity_counts[kind] += 1
                            identity_sizes[kind] += source_length + length
                        pending = None
                    else:
                        next_pending = None
                        if name in ("local.get", "global.get") or (name == "i32.const" and operand == 0):
                            next_pending = name, length, operand, offset
                        if run and (pending is not None or next_pending is None):
                            body_runs.append(run)
                            run = None
                        pending = next_pending
                if run:
                    body_runs.append(run)
                bodies[index] = dict(bytes=size, calls=calls)
                runs.extend(body_runs)
                r.pos = end
    assert len(bodies) == census["functions"]
    reached, pending = set(), list(roots)
    while pending:
        index = pending.pop()
        if index in reached:
            continue
        reached.add(index)
        if index in bodies:
            pending.extend(bodies[index]["calls"])
    reachability = dict(supported=not unsupported, unsupported=sorted(unsupported), roots=sorted(roots))
    if not unsupported:
        unreachable = sorted(set(bodies) - reached)
        reachability.update(unreachable_functions=unreachable,
                            unreachable_body_bytes=sum(bodies[index]["bytes"] for index in unreachable))
    return dict(format=1, path=str(path), wasm_sha256=digest, wasm_bytes=len(data),
                elapsed_seconds=time.monotonic() - started,
                note="Static nonoverlapping adjacent get/set or zero/set runs. These are not proofs of removability.",
                direct_call_reachability=reachability,
                transfers=[dict(kind=kind, pairs=count, bytes=sizes[kind]) for kind, count in counts.most_common()],
                identity_transfers=[dict(kind=kind, pairs=count, bytes=identity_sizes[kind])
                                    for kind, count in identity_counts.most_common()],
                local_set_then_get_same_index=dict(count=readback_count, encoded_bytes=readback_bytes,
                                                  note="Overlaps transfer runs; replacing with tee depends on other IR metadata."),
                run_buckets={str(bound): dict(runs=sum(run["pairs"] >= bound for run in runs),
                                             pairs=sum(run["pairs"] for run in runs if run["pairs"] >= bound),
                                             bytes=sum(run["bytes"] for run in runs if run["pairs"] >= bound))
                             for bound in (1, 4, 16, 64, 256, 1024)},
                top_runs=sorted(runs, key=lambda run: -run["bytes"])[:30])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wasm", type=Path)
    parser.add_argument("--census", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = analyze(args.wasm, json.loads(args.census.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({key: result[key] for key in ("wasm_bytes", "elapsed_seconds", "run_buckets", "direct_call_reachability")}))


if __name__ == "__main__":
    main()
