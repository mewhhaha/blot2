"""Subprocess-level framing checks; no Bend installation is needed."""
import struct
import subprocess
import sys

exe = sys.argv[1]
magic, version = 1112297300, 13
handshake = struct.pack('<III', 2, magic, version)

def run(data, expected_code=0):
    result = subprocess.run([exe, '--threads', '1'], input=data, capture_output=True, timeout=10)
    assert result.returncode == expected_code, result.stderr.decode(errors='replace')
    assert result.stdout.startswith(handshake), result.stdout
    return result.stdout[len(handshake):]

assert run(b'') == b''
for data in (b'\x01', struct.pack('<I', 2)+b'\0'*4, struct.pack('<I', 16777217)):
    run(data, 1)
# Both complete malformed requests must get a diagnostic without killing the process.
reply = run(struct.pack('<II', 1, 12345)*2)
for _ in range(2):
    size, = struct.unpack_from('<I', reply)
    frame, reply = reply[4:4+size*4], reply[4+size*4:]
    assert len(frame) == size*4
    assert struct.unpack_from('<II', frame) == (magic, version)
assert not reply
print('6 native framing checks passed')
