"""Show a compact main-build result and the first failing source location."""
import json
from pathlib import Path
import sys

log = Path(sys.argv[1])
if not log.read_text().strip():
    raise SystemExit("still running")
result = json.loads(log.read_text().splitlines()[-1])
print(json.dumps({key: value for key, value in result.items() if key != "stats"}, indent=2))
for diagnostic in result.get("diagnostics", []):
    source = Path(diagnostic["filename"]).read_bytes()
    start, end = diagnostic["start"], diagnostic["end"]
    line = source[:start].count(b"\n") + 1
    print("SPAN", repr(source[start:end]), "LINE", line)
    lines = source.decode().splitlines()
    for index in range(max(0, line - 8), min(len(lines), line + 9)):
        print(f"{index + 1}: {lines[index]}")
trace = Path(result["evidence"]) / "compiler-stderr.log"
if trace.exists():
    lines = trace.read_text().splitlines()
    print("TRACE\n" + "\n".join(lines[:18]))
    for line in lines[18:]:
        if line.startswith(("SOURCE_WORK_FINAL", "JUMP_OWNER", "NUM_")):
            print(line)
