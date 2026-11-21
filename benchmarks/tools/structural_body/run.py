"""Time independent first-time structural edits and verify each complete image."""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
import os
from pathlib import Path
import platform
import select
import signal
from statistics import median
import subprocess
import sys
import tempfile

here = Path(__file__).resolve().parent
root = here.parents[2]
work = root / "build/structural-body"
sys.path.insert(0, str(here.parent))
from wasm_size import Reader

# A guard regression fails the run even when the edited image has matching bytes.
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


def execute(base, jobs, dataset, oracles, record):
    # Complete the checkpoint before disclosing any edited path or byte offset.
    with tempfile.TemporaryDirectory(dir=work) as temp:
        folder = Path(temp)
        env = {k: v for k, v in os.environ.items() if not k.startswith("BLOT_")}
        env.update(BLOT_BASE=str(dataset / base), BLOT_SAVE=temp)
        if not record:
            env["BLOT_CONTROL"] = "1"
        read_fd, write_fd = os.pipe()
        env["BLOT_READY_FD"] = str(write_fd)
        with os.fdopen(read_fd, "rb") as ready, os.fdopen(write_fd,"wb") as sender, subprocess.Popen(
            [work / "probe"], env=env, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, start_new_session=True, pass_fds=(write_fd,),
        ) as proc:
            sender.close()
            try:
                if not select.select([ready], [], [], 15)[0]:
                    raise TimeoutError("waiting for generator checkpoint")
                if ready.read(1) != b"!":
                    out, err = proc.communicate(timeout=3)
                    raise RuntimeError((base, out, err))
                assert (folder / "1.wasm").read_bytes() == oracles[base]
                requests = []
                for index, (case, first) in enumerate(jobs):
                    dest = folder / str(index)
                    dest.mkdir()
                    fields = [str(dataset / case["to"]), str(dest), str(case["unit"]),
                              str(case["point"]), str(int(first))]
                    if any("\n" in value for value in fields):
                        raise ValueError("newline in benchmark path")
                    requests.extend(fields)
                payload = "".join(value + "\n" for value in requests)
                out, err = proc.communicate(payload, timeout=15 * (1 + len(jobs)))
                if proc.returncode:
                    raise RuntimeError((base, out, err))
            finally:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()

        setup = defaultdict(list)
        stats = setup
        samples = []
        for line in out.splitlines():
            key, value = line.split()
            if key == "JOB":
                assert int(value) == len(samples)
                stats = defaultdict(list)
                samples.append(stats)
            else:
                stats[int(key)].append(int(value))
        rows = []
        for i, ((case, first), stats) in enumerate(zip(jobs, samples, strict=True)):
            dest = folder / str(i)
            reason = stats[14][0]
            assert (dest / "3.wasm").read_bytes() == oracles[case["to"]]
            candidate = dest / "2.wasm"
            if reason == 0:
                assert candidate.read_bytes() == oracles[case["to"]]
            else:
                assert not candidate.exists()
            rows.append(dict(name=case["name"], old=base, new=case["to"], referenceFirst=first,
                             outcome=reasons[reason], code=reason, compareNs=stats[18][0],
                             replayNs=stats[2][0], fullNs=stats[8][0], decodeNs=stats[27][0],
                             forkToDecisionNs=next(iter(stats[30]), None), emitted=sum(stats[4]),
                             changedUnits=stats[11], importOnly=stats[19],
                             addedKeys=list(zip(stats[20], stats[21], stats[22], strict=True))))
        checkpoint = dict(base=base, traced=record, edits=len(jobs), buildNs=setup[26][0],
                          namedEntries=setup[23][0], lookups=setup[24][0],
                          traceStorageBytes=setup[25][0])
        return rows, checkpoint


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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rounds", type=int, default=8)
    args = parser.parse_args()
    if args.rounds < 1:
        parser.error("--rounds must be positive")
    manifest = json.loads((work / "capture.json").read_text())
    build = json.loads((work / "build-identity.json").read_text())
    assert sha((work / "probe").read_bytes()) == build["probe"]
    assert manifest["captureSha256"] == build["capture.so"]
    dataset = work / manifest["dataset"]
    trials = manifest["trials"]
    assert len(trials) == 2 * len(expected)
    names = {trial["from"] for trial in trials} | {trial["to"] for trial in trials}
    for name in names:
        packets = hashlib.sha256()
        for unit in range(1, 294):
            data = (dataset / name / f"{unit}-2.bin").read_bytes()
            packets.update(hashlib.sha256(data).digest())
        assert packets.hexdigest() == manifest["packetSets"][name], name
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
    checkpoints = []
    for run in range(args.rounds):
        order = list(enumerate(trials))
        if run % 2:
            order.reverse()
        groups = defaultdict(list)
        for i, case in order:
            groups[case["from"]].append((case, (run + i) % 2 == 0))
        for base, jobs in groups.items():
            modes = [True]
            if base == "base":
                modes = [False, True]
                if run % 2:
                    modes.reverse()
            for record in modes:
                selected = []
                if record:
                    selected = jobs
                observations, startup = execute(base, selected, dataset, oracles, record)
                checkpoints.append(dict(round=run, **startup))
                for row in observations:
                    assert row["code"] == expected_by_pair[row["old"], row["new"]], row
                    rows.append(dict(round=run, **row))
        print(f"Round {run + 1}/{args.rounds} verified", flush=True)

    summary = {}
    for case in trials:
        a, b = case["from"], case["to"]
        sample = [r for r in rows if r["old"] == a and r["new"] == b]
        screen = [r["compareNs"] + r["replayNs"] for r in sample]
        ready = [r["forkToDecisionNs"] for r in sample if r["forkToDecisionNs"] is not None]
        ready_ms = None
        if ready:
            ready_ms = median(ready) / 1e6
        summary[f"{a} to {b}"] = dict(outcome=sample[0]["outcome"],
                                      fullMs=median(r["fullNs"] for r in sample)/1e6,
                                      screenAndAttemptMs=median(screen)/1e6,
                                      screenMs=median(r["compareNs"] for r in sample)/1e6,
                                      forkToDecisionMs=ready_ms,
                                      reemitAndAssembleMs=median(r["replayNs"] for r in sample)/1e6)
    assert sha((work / "probe").read_bytes()) == build["probe"]
    identity = dict(captureCompilerSha256=manifest["compilerSha256"], pins=manifest["pins"],
                    packetSets=manifest["packetSets"], captureToolSha256=manifest["captureToolSha256"],
                    probeBuild=build, host=platform.machine(), runnerSha256=sha(Path(__file__).read_bytes()))
    base_setup = [c for c in checkpoints if c["base"]=="base"]
    measured = [c for c in base_setup if c["traced"]]
    control = [c for c in base_setup if not c["traced"]]
    costs = [a["buildNs"] - b["buildNs"] for a,b in zip(measured,control,strict=True)]
    for key in ("namedEntries","lookups","traceStorageBytes"):
        assert len({c[key] for c in measured})==1
    setup = dict(tracedMs=median(c["buildNs"] for c in measured)/1e6,
                 controlMs=median(c["buildNs"] for c in control)/1e6,
                 pairedOverheadMs=median(costs)/1e6,
                 **{key: measured[0][key] for key in ("namedEntries","lookups","traceStorageBytes")})
    report = dict(rounds=args.rounds, identity=identity, setup=setup,
                  byteChecks=len(checkpoints) + len(rows) + sum(r["code"]==0 for r in rows),
                  images={name: dict(bytes=len(data), sha256=sha(data)) for name,data in sorted(oracles.items())},
                  bodyChanges=comparisons, median=summary)
    (work/"summary.json").write_text(json.dumps(report, indent=2)+"\n")
    (work/"runs.json.gz").write_bytes(gzip.compress(json.dumps(dict(edits=rows,checkpoints=checkpoints),separators=(",",":")).encode(),mtime=0))
    print(json.dumps(summary,indent=2))


if __name__ == "__main__":
    main()
