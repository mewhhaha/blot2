# Poor man's sampling profiler for blotc, run inside gdb:
#
#   gdb -batch -q -x scripts/bench/gdb_sampler.py
#
# scripts/bench/profile_compile.ts drives it; run that instead. Environment:
#   SAMPLE_CONTROL  directory for the handshake files below
#   SAMPLE_BINARY   the blotc whose symbols gdb loads (must have DWARF)
#   SAMPLE_OUT      JSON-lines output, one record per stop
#   SAMPLE_MIN_MS / SAMPLE_MAX_MS  random interval between stops (default 3-10)
#   SAMPLE_LIMIT    stop after this many samples (default unlimited)
#
# Handshake: the driver writes `pid`; this script attaches and writes
# `attached`; the driver writes `start` before the measured builds and `stop`
# after them. Each stop sends SIGUSR1 after a random delay (gdb keeps it from
# the program), then records every thread's stack including inlined frames.
# Threads blocked in the process's main function (joining the compile thread)
# are skipped.
import json
import os
import random
import subprocess
import time

import gdb

control = os.environ["SAMPLE_CONTROL"]
low = float(os.environ.get("SAMPLE_MIN_MS", "3")) / 1000
high = float(os.environ.get("SAMPLE_MAX_MS", "10")) / 1000
limit = int(os.environ.get("SAMPLE_LIMIT", "0")) or None


def flag(name):
    return os.path.exists(os.path.join(control, name))


def wait_for(name):
    while not flag(name):
        time.sleep(0.005)


def stack(thread):
    thread.switch()
    frame = gdb.newest_frame()
    frames = []
    while frame is not None and len(frames) < 4096:
        try:
            sal = frame.find_sal()
            frames.append([
                frame.name() or "??",
                sal.symtab.filename if sal.symtab else "",
                sal.line,
                frame.type() == gdb.INLINE_FRAME,
            ])
        except gdb.error:
            frames.append(["??", "", 0, False])
        try:
            frame = frame.older()
        except gdb.error:
            break
    return frames


wait_for("pid")
pid = int(open(os.path.join(control, "pid")).read())
for command in ("set pagination off", "set confirm off",
                "set debuginfod enabled off"):
    gdb.execute(command)
gdb.execute("file " + os.environ["SAMPLE_BINARY"])
gdb.execute("attach %d" % pid)
# `noprint` would imply `nostop`; continue() captures the message.
gdb.execute("handle SIGUSR1 nopass stop print")
open(os.path.join(control, "attached"), "w").write("1")
wait_for("start")
started = time.time()
taken = 0
def thread_cpu(tid):
    try:
        with open("/proc/%d/task/%d/schedstat" % (pid, tid)) as source:
            return int(source.read().split()[0])
    except FileNotFoundError:
        return None

previous_cpu = {t.ptid[1]: thread_cpu(t.ptid[1])
                for t in gdb.selected_inferior().threads()}
with open(os.environ["SAMPLE_OUT"], "a") as out:
    while not flag("stop") and (limit is None or taken < limit):
        delay = random.uniform(low, high)
        subprocess.Popen([
            "/bin/sh", "-c", "sleep %f; kill -USR1 %d 2>/dev/null" % (delay, pid)
        ])
        try:
            gdb.execute("continue", to_string=True)
        except gdb.error:
            break  # The process exited.
        if flag("stop"):
            break  # The measured builds finished while this stop was pending.
        try:
            stacks, tids, cpu_ns = [], [], []
            for thread in gdb.selected_inferior().threads():
                tid = thread.ptid[1]
                current = thread_cpu(tid)
                previous = previous_cpu.get(tid)
                previous_cpu[tid] = current
                frames = stack(thread)
                if any(f[0] == "main.main" for f in frames):
                    continue
                stacks.append(frames)
                tids.append(tid)
                cpu_ns.append(None if current is None or previous is None
                              else max(0, current - previous))
        except gdb.error:
            break
        out.write(json.dumps({"t": time.time() - started, "wall_ns": time.time_ns(),
                              "run": int(os.environ.get("SAMPLE_RUN", "0")), "frame_limit": 4096, "st": stacks,
                              "tid": tids, "cpu_ns": cpu_ns}) + "\n")
        out.flush()
        taken += 1
try:
    gdb.execute("detach")
except gdb.error:
    pass
open(os.path.join(control, "detached"), "w").write(str(taken))
gdb.execute("quit")
