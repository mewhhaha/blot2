"""Time independent first-time structural edits and verify each complete image."""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
from statistics import median
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[2]
work = root / "build/structural-body"
sys.path.insert(0, str(here.parent))
from wasm_size import Reader

# Each direction has a distinct initial compiler state. A guard regression must
# fail the run even if it happens to emit the same bytes for this fixture.
expected = {
    "timing": (0, 0), "input": (0, 0), "helper": (0, 0),
    "render": (4, 4), "edge": (4, 7), "stage": (6, 6),
}
reasons = {
    0: "accepted", 1: "missing instance", 2: "obligation", 3: "emit error",
    4: "layout", 5: "diagnostic", 6: "compile-time reader", 7: "lookup order",
    8: "another module changed", 9: "inferred result",
}


def sections_and_bodies(image):
    assert image[:8] == b"\0asm\x01\0\0\0"
    reader = Reader(image, start=8)
    sections = defaultdict(list)
    bodies = []
    while reader.pos < reader.end:
        tag = reader.byte()
        size = reader.leb()
        start = reader.pos
        reader.skip(size)
        section = image[start:reader.pos]
        if tag != 10:
            sections[tag].append(section)
            continue
        code = Reader(section)
        for _ in range(code.leb()):
            size = code.leb()
            start = code.pos
            code.skip(size)
            bodies.append(section[start:code.pos])
        assert code.pos == code.end
    return sections, bodies


def execute(case, dataset, oracles, first):
    with tempfile.TemporaryDirectory(dir=work) as output:
        directory = Path(output)
        env = dict(os.environ, BLOT_BASE=str(dataset / case["from"]),
                   BLOT_EDIT=str(dataset / case["to"]), BLOT_EDIT_UNIT=str(case["unit"]),
                   BLOT_EDIT_POINT=str(case["point"]), BLOT_SAVE=output)
        env.pop("BLOT_REFERENCE_FIRST", None)
        if first:
            env["BLOT_REFERENCE_FIRST"] = "1"
        proc = subprocess.run([work / "probe"], env=env, capture_output=True,
                              text=True, timeout=15)
        if proc.returncode:
            raise RuntimeError((case, proc.returncode, proc.stderr, proc.stdout))
        stats = defaultdict(list)
        for line in proc.stdout.splitlines():
            key, value = map(int, line.split())
            stats[key].append(value)
        reason = stats[14][0]
        assert (directory / "1.wasm").read_bytes() == oracles[case["from"]]
        assert (directory / "3.wasm").read_bytes() == oracles[case["to"]]
        candidate = directory / "2.wasm"
        if reason == 0:
            assert candidate.read_bytes() == oracles[case["to"]]
        else:
            assert not candidate.exists()
        return dict(outcome=reasons[reason], code=reason, compareNs=stats[18][0],
                    replayNs=stats[2][0], fullNs=stats[8][0], emitted=sum(stats[4]),
                    changedUnits=stats[11], importOnly=stats[19],
                    addedKeys=list(zip(stats[20], stats[21], stats[22], strict=True)))


def image_changes(old, new):
    old_sections, a = sections_and_bodies(old)
    new_sections, b = sections_and_bodies(new)
    changes = [i for i, (left, right) in enumerate(zip(a, b)) if left != right]
    result = dict(oldCount=len(a), newCount=len(b), changedAtSharedOrdinals=len(changes),
                  otherChangedSections=sorted(tag for tag in old_sections.keys() | new_sections.keys()
                                              if old_sections[tag] != new_sections[tag]))
    if len(changes) <= 5:
        result["bodySizes"] = [[i, len(a[i]), len(b[i])] for i in changes]
    return result


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(checkout, *args):
    return subprocess.check_output(["git", "-C", checkout, *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=8)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    manifest = json.loads((work / "capture.json").read_text())
    dataset = work / manifest["dataset"]
    trials = manifest["trials"]
    assert len(trials) == 2 * len(expected)
    names = {trial["from"] for trial in trials} | {trial["to"] for trial in trials}
    oracles = {name: (dataset / name / "main.wasm").read_bytes() for name in names}
    comparisons = {}
    expected_by_pair = {}
    for forward, reverse in zip(trials[::2], trials[1::2], strict=True):
        a, b, name = forward["from"], forward["to"], forward["name"]
        assert (reverse["from"], reverse["to"], reverse["name"]) == (b, a, name)
        comparisons[name] = image_changes(oracles[a], oracles[b])
        expected_by_pair[a, b], expected_by_pair[b, a] = expected[name]
    assert comparisons.keys() == expected.keys()

    rows = []
    for run in range(args.rounds):
        order = list(enumerate(trials))
        if run % 2:
            order.reverse()
        for i, case in order:
            first = (run + i) % 2 == 0
            a, b = case["from"], case["to"]
            row = execute(case, dataset, oracles, first)
            assert row["code"] == expected_by_pair[a, b], (case, row)
            rows.append(dict(round=run, name=case["name"], old=a, new=b,
                             referenceFirst=first, **row))
        print(f"Round {run + 1}/{args.rounds} verified", flush=True)

    summary = {}
    for case in trials:
        a, b = case["from"], case["to"]
        sample = [r for r in rows if r["old"] == a and r["new"] == b]
        screen = [r["compareNs"] + r["replayNs"] for r in sample]
        summary[f"{a} to {b}"] = dict(outcome=sample[0]["outcome"],
                                      fullMs=median(r["fullNs"] for r in sample)/1e6,
                                      screenAndAttemptMs=median(screen)/1e6,
                                      screenMs=median(r["compareNs"] for r in sample)/1e6,
                                      reemitAndAssembleMs=median(r["replayNs"] for r in sample)/1e6)
    identity = dict(compilerSha256=manifest["compilerSha256"], probeSha256=sha((work/"probe").read_bytes()),
                    compilerSourceTree=git(root, "rev-parse", "HEAD:compiler-goose"),
                    stdTree=git(root, "rev-parse", "HEAD:std"),
                    gdev=git(root.parent/"gdev", "rev-parse", "HEAD"), ink=git(root.parent/"ink", "rev-parse", "HEAD"),
                    host=platform.machine(), clang=subprocess.check_output(["clang","--version"],text=True).splitlines()[0])
    report = dict(rounds=args.rounds, identity=identity, byteChecks=len(rows)*2 + sum(r["code"]==0 for r in rows),
                  images={name: dict(bytes=len(data), sha256=sha(data)) for name,data in sorted(oracles.items())},
                  bodyChanges=comparisons, median=summary)
    (work/"summary.json").write_text(json.dumps(report, indent=2)+"\n")
    (work/"runs.json.gz").write_bytes(gzip.compress(json.dumps(rows,separators=(",",":")).encode(),mtime=0))
    print(json.dumps(summary,indent=2))


if __name__ == "__main__":
    main()
