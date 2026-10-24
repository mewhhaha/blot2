"""Linux x86-64 perf groups for all idle compiler threads and future threads.

Usage: python3 process_pmu.py PID
JSON line protocol on stdin: start, stop, quit. Attach while the compiler is
idle. Existing threads must remain unchanged during attachment. Each existing
thread receives three two-event groups; future threads inherit exactly once.
Counters cover user space only. Read individual members because inherited
PERF_FORMAT_GROUP reads are unsupported. Raw counts and scheduling times remain
reported; scaled counts are estimates, never a cache-level diagnosis.
See https://man7.org/linux/man-pages/man2/perf_event_open.2.html
"""
import ctypes
import fcntl
import json
import os
from pathlib import Path
import platform
import struct
import sys

assert platform.system() == 'Linux' and platform.machine() == 'x86_64'
pid = int(sys.argv[1])
class Attr(ctypes.Structure):
    _fields_ = [('type', ctypes.c_uint), ('size', ctypes.c_uint), ('config', ctypes.c_ulonglong),
                ('sample_period', ctypes.c_ulonglong), ('sample_type', ctypes.c_ulonglong),
                ('read_format', ctypes.c_ulonglong), ('flags', ctypes.c_ulonglong),
                ('rest', ctypes.c_byte * 72)]
libc = ctypes.CDLL(None, use_errno=True)
groups, descriptors = [], []
before = None

def threads():
    return sorted(int(p.name) for p in Path(f'/proc/{pid}/task').iterdir())
def read(fd):
    data = os.read(fd, 24)
    if len(data) != 24:
        raise RuntimeError('Counter was not scheduled or returned a partial record')
    return struct.unpack('QQQ', data)
def reply(value):
    print(json.dumps(value), flush=True)
try:
    attached = threads()
    for tid in attached:
        for events in [[('cycles', 0), ('instructions', 1)], [('branches', 4), ('branch_misses', 5)], [('cache_references', 2), ('cache_misses', 3)]]:
            leader = -1
            for name, config in events:
                attr = Attr()
                attr.size = ctypes.sizeof(attr)
                attr.config = config
                attr.read_format = 3  # TOTAL_TIME_ENABLED | TOTAL_TIME_RUNNING
                # INHERIT_THREAD excludes child processes. The compiler's
                # existing threads each get their own inherited root group.
                attr.flags = (int(leader == -1) | (1 << 1) | (1 << 5) | (1 << 6) | (1 << 35))
                fd = libc.syscall(298, ctypes.byref(attr), tid, -1, leader, 8)  # CLOEXEC
                if fd < 0:
                    raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()))
                descriptors.append((tid, name, fd))
                if leader == -1:
                    leader = fd
                    groups.append(fd)
    if attached != threads():
        raise RuntimeError('Threads changed during attachment; retry while compiler is idle')
    reply({'ready': True, 'pid': pid, 'threads_at_attach': attached,
           'scope': 'all threads at attach plus inherited future threads; user-space only',
           'events': 'generic hardware events, three two-event groups per existing thread',
           'read_format': 'individual inherited counters with enabled/running time',
           'affinity_at_attach': {str(tid): sorted(os.sched_getaffinity(tid)) for tid in attached}})
    for command in sys.stdin:
        command = command.strip()
        if command == 'start':
            if before is not None:
                raise RuntimeError('Already measuring')
            before = {fd: read(fd) for _, _, fd in descriptors}
            for leader in groups:
                fcntl.ioctl(leader, 0x2400, 1)  # ENABLE | GROUP
            reply({'started': True})
        elif command == 'stop':
            if before is None:
                raise RuntimeError('Not measuring')
            for leader in groups:
                fcntl.ioctl(leader, 0x2401, 1)  # DISABLE | GROUP
            rows = []
            for tid, name, fd in descriptors:
                value, enabled, running = (a-b for a, b in zip(read(fd), before[fd]))
                if min(value, enabled, running) < 0 or running > enabled:
                    raise RuntimeError('Invalid inherited counter delta')
                rows.append({'root_tid': tid, 'event': name, 'raw': value, 'time_enabled_ns': enabled,
                             'time_running_ns': running, 'running_ratio': running/enabled if enabled else None,
                             'scaled': value*enabled/running if running else None})
            reply({'threads_at_stop': threads(), 'counters': rows})
            before = None
        elif command == 'quit':
            break
        else:
            raise RuntimeError('Expected start, stop or quit')
finally:
    for _, _, fd in descriptors:
        os.close(fd)
