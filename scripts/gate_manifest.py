"""Pin the complete gate inputs and reject concurrent source changes."""
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from datetime import datetime, timezone

root = Path(__file__).resolve().parent.parent
out = root / "test-results"
out.mkdir(exist_ok=True)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def inputs():
    files = [root / "blot.goose", root / "test.goose", root / "AGENTS.md", root / "docs/guide.md"]
    for folder in ["src", "tests", "scripts", "host", "examples", "migration", "docs/spec"]:
        files.extend(p for p in (root / folder).rglob("*") if p.is_file() and p.suffix in {".goose", ".h", ".c", ".ts", ".py", ".sh", ".blot", ".json", ".md"})
    files.extend(root / "editor" / name for name in ["test.mjs", "blot.tmLanguage.json", "package.json", "package-lock.json"])
    return {str(path.relative_to(root)): digest(path) for path in sorted(set(files))}
def command(*argv):
    r = subprocess.run(argv, cwd=root, capture_output=True, text=True, check=True)
    return (r.stdout + r.stderr).strip()
path = out / "gate-inputs.json"
if sys.argv[1] == "--start":
    record = {"started": datetime.now(timezone.utc).isoformat(), "status": "running", "inputs": inputs(),
              "base_commit": command("git", "rev-parse", "HEAD"), "branch": command("git", "branch", "--show-current"),
              "platform": platform.platform(), "goose": command(os.environ["GOOSE"], "version"),
              "clang": command(os.environ.get("CC", "clang"), "--version"), "deno": command("deno", "--version"),
              "compiler_mode": sys.argv[2] if len(sys.argv) > 2 else "debug"}
    path.write_text(json.dumps(record, indent=2) + "\n")
    # A failed or interrupted rerun must not leave an older pass looking current.
    (out / "qualification.json").write_text(json.dumps(record, indent=2) + "\n")
elif sys.argv[1] == "--finish":
    record = json.loads(path.read_text())
    current = inputs()
    if record["inputs"] != current:
        changed = [p for p in set(current) | set(record["inputs"]) if current.get(p) != record["inputs"].get(p)]
        raise SystemExit("gate inputs changed during execution; rerun: " + ", ".join(sorted(changed)))
    record.update({"status": "passed", "finished": datetime.now(timezone.utc).isoformat(),
                   "compiler_sha256": digest(root / "build/blot"),
                   "input_manifest_sha256": hashlib.sha256(json.dumps(current, sort_keys=True).encode()).hexdigest(),
                   "evidence": {name: digest(out / name) for name in ["native.log", "goose-native-diagnostics.log", "editor.log", "deno.log", "arena-faults.json", "session-arena-faults.json"]}})
    (out / "qualification.json").write_text(json.dumps(record, indent=2) + "\n")
    print("qualified frozen inputs:", record["input_manifest_sha256"], "compiler:", record["compiler_sha256"])
else:
    raise SystemExit("expected --start or --finish")
