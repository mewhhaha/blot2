"""One isolated child: retain raw output, wall/CPU time and peak process RSS."""
import json
import resource
import subprocess
import sys
import time
from pathlib import Path

request = json.load(sys.stdin)
started = time.perf_counter_ns()
result = subprocess.run(request["command"], cwd=request["cwd"], capture_output=True)
elapsed = time.perf_counter_ns() - started
usage = resource.getrusage(resource.RUSAGE_CHILDREN)
Path(request["stdout"]).write_bytes(result.stdout)
Path(request["stderr"]).write_bytes(result.stderr)
print(json.dumps({"exit_code": result.returncode, "wall_ms": elapsed / 1e6,
                  "cpu_ms": (usage.ru_utime + usage.ru_stime) * 1000,
                  "peak_rss_kib": usage.ru_maxrss}))
