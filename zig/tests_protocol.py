#!/usr/bin/env python3
"""Exercise the actual native process and its binary stream, not a mock backend."""
from pathlib import Path
import os
import random
import shlex
import struct
import subprocess
import unittest

BINARY = Path(__file__).resolve().parent / 'zig-out/bin/blotc-zig'
MAGIC, VERSION = 0x424C4F54, 13
# Optional CPU emulator prefix. CI uses QEMU without build-host extensions.
RUNNER = shlex.split(os.environ.get('BLOT_ZIG_RUNNER', ''))

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

def node(kind, field='', text='', children=()):
    return (kind, field, text, children)


def request(operation, root=None):
    """Encode the small field-labelled CSTs used at the native boundary."""
    strings, body = [], []

    def identity(text):
        if text not in strings:
            strings.append(text)
        return strings.index(text)

    def tree(value):
        kind, field, text, children = value
        body.extend([identity(kind), identity(field), identity(text), 0, 0, len(children)])
        for child in children:
            tree(child)

    tree(root or node('program'))
    if operation in (0, 1, 7):
        tree(node('program'))  # Empty prelude for stateless commands.
    dictionary = [len(strings)]
    for text in strings:
        dictionary.extend([len(text), *map(ord, text)])
    header = [MAGIC, VERSION, operation, 100, 0]
    if operation != 2:  # Open session has no constant-evaluation budget.
        header.extend([10000, 0])
    return frame(header + dictionary + body)


def answer_module():
    # Field-labelled semantic input equivalent to:
    # entry const answer = fn () => 42
    # Source parsing itself is covered by standalone.test.ts and the full suite.
    return node('program', children=[
        node('declaration', 'declarations', children=[
            node('value_declaration', 'value', children=[
                node('IDENT', 'modifier', 'entry'),
                node('const', 'kind', 'const'),
                node('IDENT', 'name', 'answer'),
                node('lambda', 'value', children=[
                    node('parameter', 'parameter'),
                    node('INTEGER', 'body', '42'),
                ]),
            ]),
        ]),
    ])


class ProtocolTests(unittest.TestCase):
    def run_compiler(self, payload=b'', *args):
        return subprocess.run([*RUNNER, str(BINARY), *args], input=payload,
                              capture_output=True, timeout=30 if RUNNER else 10)

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

    def test_valid_semantic_requests_recover_after_compile_diagnostics(self):
        # Compiling an empty module must reject no_entry, not crash. A following
        # valid analysis must still succeed, including in a multi-worker process.
        for threads in (1, 2, 4, 8):
            with self.subTest(threads=threads):
                result = self.run_compiler(
                    request(0) + request(7) + request(0),
                    '--threads', str(threads))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, b'')
                output = packets(result.stdout)
                self.assertEqual(len(output), 4)
                self.assertEqual(output[0], (MAGIC, VERSION))
                self.assertEqual(output[1], (MAGIC, VERSION, 1, 0, 0, 10000, 0))
                self.assertEqual(output[3], output[1])
                self.assertEqual(output[2][:3], (MAGIC, VERSION, 0))
                length = output[2][3]
                self.assertEqual(''.join(map(chr, output[2][4:4 + length])), 'no_entry')

    def test_emit_produces_identical_wasm_across_worker_counts(self):
        expected = None
        for threads in (1, 2, 4, 8):
            with self.subTest(threads=threads):
                result = self.run_compiler(request(7, answer_module()),
                                           '--threads', str(threads))
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stderr, b'')
                output = packets(result.stdout)
                self.assertEqual(len(output), 2)
                response = output[1]
                self.assertEqual(response[:3], (MAGIC, VERSION, 5))
                size = response[3]
                packed = struct.pack('<' + 'I' * (len(response) - 4), *response[4:])
                self.assertEqual(len(packed), (size + 3) // 4 * 4)
                self.assertEqual(packed[size:], b'\0' * (len(packed) - size))
                wasm = packed[:size]
                self.assertEqual(wasm[:8], b'\0asm\1\0\0\0')
                self.assertIn(b'answer', wasm)
                if expected is None:
                    expected = wasm
                self.assertEqual(wasm, expected)

    def test_seeded_packet_mutations_do_not_break_following_requests(self):
        rng = random.Random(20260928)
        encoded = request(7, answer_module())
        original = list(struct.unpack('<' + 'I' * (len(encoded) // 4), encoded))[1:]
        payload = bytearray()
        for _ in range(64):
            words = original.copy()
            for _ in range(rng.randrange(1, 4)):
                words[rng.randrange(len(words))] = rng.choice([
                    0, 1, 0xffff, 0x10000, 0xd800, 0x110000, 0xffffffff,
                    rng.randrange(200),
                ])
            payload.extend(frame(words))
            payload.extend(request(0))
        result = self.run_compiler(payload, '--threads', '4')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        output = packets(result.stdout)
        self.assertEqual(len(output), 129)
        # A mutation can remain valid; recovery must always return valid analysis.
        for response in output[2::2]:
            self.assertEqual(response, (MAGIC, VERSION, 1, 0, 0, 10000, 0))

    def test_retained_session_accepts_multiple_complete_requests(self):
        result = self.run_compiler(request(2) + request(3) * 3,
                                   '--threads', '4')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        output = packets(result.stdout)
        self.assertEqual(len(output), 5)
        self.assertEqual(output[1], (MAGIC, VERSION, 3))
        for response in output[2:]:
            self.assertEqual(response[:3], (MAGIC, VERSION, 4))
            # Eight Nat cache counters precede the inner analysis result.
            self.assertEqual(response[19:], (1, 0, 0, 10000, 0))

    def test_version_is_text_without_a_protocol_handshake(self):
        result = self.run_compiler(b'', '--version')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, b'blotc-zig 0.1.0 (protocol 13)\n')
        self.assertEqual(result.stderr, b'')

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
