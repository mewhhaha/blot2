#!/usr/bin/env python3
"""Exercise the actual native process and its binary stream, not a mock backend."""
from pathlib import Path
import struct
import subprocess
import unittest

BINARY = Path(__file__).resolve().parent / 'zig-out/bin/blotc-zig'
MAGIC, VERSION = 0x424C4F54, 13

def frame(words):
    return struct.pack('<' + 'I' * (len(words) + 1), len(words), *words)

def packets(data):
    result = []
    while data:
        if len(data) < 4:
            raise AssertionError('truncated response prefix')
        count, = struct.unpack_from('<I', data)
        size = 4 + count * 4
        if len(data) < size:
            raise AssertionError('truncated response body')
        result.append(struct.unpack_from('<' + 'I' * count, data, 4))
        data = data[size:]
    return result

class ProtocolTests(unittest.TestCase):
    def run_compiler(self, payload=b'', *args):
        return subprocess.run([str(BINARY), *args], input=payload,
                              capture_output=True, timeout=10)

    def test_clean_eof_and_handshake(self):
        result = self.run_compiler()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(packets(result.stdout), [(MAGIC, VERSION)])
        self.assertEqual(result.stderr, b'')

    def test_bad_requests_do_not_corrupt_following_responses(self):
        requests = [[], [MAGIC], [MAGIC, VERSION], [MAGIC, VERSION, 999],
                    [MAGIC, VERSION, 0], [0, VERSION, 0], [MAGIC, 99, 0]]
        result = self.run_compiler(b''.join(map(frame, requests)))
        self.assertEqual(result.returncode, 0, result.stderr)
        output = packets(result.stdout)
        self.assertEqual(len(output), len(requests) + 1)
        self.assertEqual(output[0], (MAGIC, VERSION))
        for response in output[1:]:
            self.assertEqual(response[:3], (MAGIC, VERSION, 0))
        self.assertEqual(result.stderr, b'')

    def test_truncated_frames_fail_instead_of_hanging(self):
        for payload in [b'\x01', struct.pack('<I', 2) + b'\x01\x02']:
            with self.subTest(payload=payload):
                result = self.run_compiler(payload)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(b'native protocol: truncated frame', result.stderr)

    def test_oversized_frames_fail_before_allocating_the_body(self):
        result = self.run_compiler(struct.pack('<I', 16 * 1024 * 1024 + 1))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'native protocol: frame exceeds 16777216 words', result.stderr)

    def test_options_validate_values(self):
        for args in [('--threads', '0'), ('--threads', '65'), ('--threads',), ('--unknown',)]:
            with self.subTest(args=args):
                result = self.run_compiler(b'', *args)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b'')
        result = self.run_compiler(b'', '--threads', '4', '--inherit-priority')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(packets(result.stdout), [(MAGIC, VERSION)])

if __name__ == '__main__':
    unittest.main()
