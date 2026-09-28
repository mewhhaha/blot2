#!/usr/bin/env python3
"""Guard the measurement harness itself, independently of the compiler."""
import struct
from bench_frames import check_frames


def frame(*words):
    return struct.pack('<' + 'I' * (len(words) + 1), len(words), *words)


header = (0x424c4f54, 13)
greeting = frame(*header)
artifact = frame(*header, 2)
check_frames(greeting + artifact * 2, 2)
invalid = [b'', greeting + b'\x01', greeting + frame(*header),
           greeting + frame(*header, 0), greeting + frame(*header, 5),
           frame(header[0], 12) + artifact, greeting + frame(header[0], 12, 2),
           greeting + frame(0, 13, 2), greeting + artifact + b'x',
           greeting + struct.pack('<I', 16777217)]
for data in invalid:
    try:
        check_frames(data, 1)
    except ValueError:
        continue
    raise RuntimeError('measurement harness accepted invalid framing')
print(f'{len(invalid) + 1} measurement framing checks passed')
