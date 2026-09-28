#!/usr/bin/env python3
"""Run the fork/join stress suite with an explicit deadlock timeout."""
import subprocess
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: test_scheduler.py <stress-executable>")
subprocess.run([sys.argv[1]], check=True, timeout=60)
