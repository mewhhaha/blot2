"""Turn every store the compiler can prove unique into an update, and check.

Usage: python3 scripts/integration/harvest_stores.py PROJECT_DIR ENTRY... [--compiler EXE] [--jobs N]

For each ENTRY (checked from PROJECT_DIR with its pen.json) the compiler
reports the stores whose place is provably the function's own
(BLOT_REPORT_STORES); each becomes `place := value`. Then the entries are
checked again: an update the compiler would turn back into a store
(`"kind":"store"`, an `aliased_update`) goes back to `=`, until none is
left. Only sites in PROJECT_DIR proposed during this run are rewritten. The
report lists the successful conversions and any remaining diagnostics.
"""
import argparse
import collections
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
parser.add_argument("project", type=Path)
parser.add_argument("entries", nargs="+")
parser.add_argument("--compiler", type=Path, default=Path(__file__).resolve().parents[2] / "compiler-goose/build/blotc-goose-dev")
parser.add_argument("--jobs", type=int, default=4)
args = parser.parse_args()
project = args.project.resolve()
compiler = args.compiler.resolve()

def run(entry, report):
    env = os.environ.copy()
    env.pop("BLOT_REPORT_STORES", None)
    if report:
        env["BLOT_REPORT_STORES"] = "1"
    command = [compiler, "migrate-stores", entry, "--project", "pen.json", "--dry-run", "--inference-budget", "20000000"]
    process = subprocess.run(command, cwd=project, capture_output=True, text=True, env=env)
    proven, aliased, errors = set(), set(), set()
    finished = False
    for line in process.stdout.splitlines():
        record = json.loads(line)
        kind = record["kind"]
        if kind == "migrate-stores":
            finished = True
        elif kind == "store":
            aliased.add((Path(record["filename"]).resolve(), record["start"]))
        elif kind == "diagnostic":
            code = record["code"]
            if code == "unchecked" and record["stage"] == "lower":
                proven.add((Path(record["filename"]).resolve(), record["start"]))
            elif code != "dependency_failed":
                errors.add((entry, code))
    if not finished:
        raise RuntimeError(f"{entry}: incomplete compiler run ({process.returncode}) {process.stderr}")
    return proven, aliased, errors

def sweep(report):
    proven, aliased, errors = set(), set(), set()
    with ThreadPoolExecutor(args.jobs) as pool:
        for found, shared, diagnostics in pool.map(lambda entry: run(entry, report), args.entries):
            proven.update(found)
            aliased.update(shared)
            errors.update(diagnostics)
    return proven, aliased, errors

def operator(src,start,want):
    """Offset of the statement's `=` (want b'=') or of the `:` of its `:=` (want b':=')."""
    nesting=0; at=start
    while at+1<len(src):
        b=src[at:at+1]
        if b in b'([{': nesting+=1
        elif b in b')]}':
            if nesting>0: nesting-=1
        elif b==b'"':
            at+=1
            while at<len(src) and src[at:at+1]!=b'"':
                if src[at:at+1]==b'\\': at+=1
                at+=1
        elif b==b'\n':
            if nesting==0: return -1
        elif nesting==0 and want==b':=' and src[at:at+2]==b':=': return at
        elif nesting==0 and want==b'=' and b==b'=':
            prev=src[at-1:at]; nxt=src[at+1:at+2]
            if prev not in b':=<>!' and nxt not in b'=>': return at
        at+=1
    return -1
proven, _, baseline_errors = sweep(True)
proposals = collections.defaultdict(set)
for path, start in proven:
    if path.is_relative_to(project):
        proposals[path].add(start)

# Rebuild from original byte offsets so rejected updates can be retracted
# individually even after earlier edits shifted the compiler's offsets.
original = {}
active = {}
for path, starts in proposals.items():
    source = path.read_bytes()
    sites = {operator(source, start, b'=') for start in starts}
    sites.discard(-1)
    if sites:
        original[path] = source
        active[path] = sorted(sites)

def edited(path):
    source = original[path]
    pieces = []
    previous = 0
    for at in active[path]:
        pieces.extend((source[previous:at], b':'))
        previous = at
    pieces.append(source[previous:])
    return b''.join(pieces)

published = {}
def publish(path, content):
    if path.read_bytes() != published.get(path, original[path]):
        raise RuntimeError(f"{path} changed during the migration")
    path.write_bytes(content)
    published[path] = content

made = sum(map(len, active.values()))
errors = baseline_errors
try:
    for path in active:
        publish(path, edited(path))
    while any(active.values()):
        _, aliased, errors = sweep(False)
        rejected = collections.defaultdict(set)
        for path, start in aliased:
            if path in active:
                rejected[path].add(operator(published[path], start, b':='))
        changed = False
        for path, locations in rejected.items():
            retained = [at for i, at in enumerate(active[path]) if at + i not in locations]
            if retained != active[path]:
                active[path] = retained
                publish(path, edited(path))
                changed = True
        if not changed:
            break
except BaseException:
    for path, content in published.items():
        if path.read_bytes() == content:
            path.write_bytes(original[path])
    raise
kept = sum(map(len, active.values()))
if not kept:
    errors = baseline_errors
print(f"{kept} stores became updates ({made} tried, {made-kept} put back)")
for entry, code in sorted(errors):
    print("  diagnostic after:", entry, code)
