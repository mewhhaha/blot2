#!/usr/bin/env python3
"""Check incoming-content copies without weakening real-owner lifetime errors."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "compiler-goose/tests/copied_argument_contents"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--stdlib", type=Path, default=ROOT.parent / "goose-to-wasm/build/source/stdlib")
    parser.add_argument("--output", type=Path, default=ROOT / "build/goose-port/copied-argument-controls")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    binaries = {name: path.resolve(strict=True) for name, path in
                [("baseline", args.baseline), ("candidate", args.candidate)]}
    stdlib = args.stdlib.resolve(strict=True)
    report = {"binaries": {name: {"path": str(path), "sha256": digest(path)}
                           for name, path in binaries.items()},
              "cases": {}, "passed": True, "scope": "Checker lifetime controls and three executed positives"}

    def run(name, command, expected):
        started = time.monotonic()
        try:
            result = subprocess.run(command, capture_output=True, timeout=8)
            status = result.returncode
            output = result.stdout + result.stderr
        except subprocess.TimeoutExpired as error:
            status = 124
            output = (error.stdout or b"") + (error.stderr or b"")
        log = args.output / (name + ".log")
        log.write_bytes(output)
        passed = status == expected["exit"]
        if expected["exit"]:
            passed = passed and b"error:" in output and expected["section"].encode() in output
        return {"command": command, "exit": status, "seconds": time.monotonic() - started,
                "log": str(log), "log_sha256": digest(log), "passed": passed}

    expectations = json.loads((FIXTURES / "expectations.json").read_text())
    for name, expected in expectations.items():
        source = FIXTURES / (name + ".goose")
        row = {"source_sha256": digest(source)}
        for variant, binary in binaries.items():
            command = [str(binary), "check", str(source), "--stdlib", str(stdlib)]
            row[variant] = run(name + "-" + variant, command, expected[variant])
        if expected.get("run"):
            command = [str(binaries["candidate"]), "run", str(source), "--stdlib", str(stdlib)]
            row["runtime"] = run(name + "-run", command, {"exit": 0})
        row["passed"] = all(value["passed"] for value in row.values() if isinstance(value, dict))
        report["passed"] = report["passed"] and row["passed"]
        report["cases"][name] = row
        print(name + ": " + str(row["passed"]), flush=True)
    (args.output / "evidence.json").write_text(json.dumps(report, indent=2) + "\n")
    if not report["passed"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
