"""One fresh compiler process; JSON request on stdin, timings on stdout."""
import json
import resource
import subprocess
import sys
import time
from pathlib import Path

request = json.load(sys.stdin)
start = time.perf_counter_ns()
result = subprocess.run(request['command'], capture_output=True, cwd=request['cwd'])
elapsed = time.perf_counter_ns() - start
usage = resource.getrusage(resource.RUSAGE_CHILDREN)
Path(request['stdout']).write_bytes(result.stdout)
Path(request['stderr']).write_bytes(result.stderr)
print(json.dumps({'exit_code': result.returncode, 'wall_ms': elapsed / 1e6,
                  'cpu_ms': (usage.ru_utime + usage.ru_stime) * 1000,
                  'peak_rss_kib': usage.ru_maxrss}))
