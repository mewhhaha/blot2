#!/usr/bin/env python3
"""Correctness gates for native algorithms; no timing assertions or benchmarks."""
import hashlib
import json
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

ZIG = "zig"
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'zig/tools'))
from generate import NATIVE_FUNCTIONS, NATIVE_MODULE_HASHES, native_functions
from tests_protocol import BINARY, MAGIC, VERSION, answer_module, frame, node, packets, request


def words(encoded):
    return list(struct.unpack('<' + 'I' * (len(encoded) // 4), encoded))[1:]


def diagnostic(packet):
    if packet[:3] != (MAGIC, VERSION, 0):
        raise AssertionError(('expected diagnostic', packet[:3]))
    values, at = [], 3
    for _ in range(3):
        count = packet[at]
        at += 1
        values.append(''.join(map(chr, packet[at:at + count])))
        at += count
    return tuple(values)


class OptimizationTests(unittest.TestCase):
    def run_compiler(self, payload, *args, **kwargs):
        result = subprocess.run([str(BINARY), *args], input=payload,
                                capture_output=True, timeout=30, **kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, b'')
        return packets(result.stdout)

    def test_native_manifest_matches_checked_source_hashes(self):
        modules = {name: SimpleNamespace(path=ROOT / 'compiler' / (name + '.bend'))
                   for name in NATIVE_MODULE_HASHES}
        enabled = native_functions(modules)
        manifest = json.loads((ROOT / 'zig/src/generated/manifest.json').read_text())
        self.assertEqual(sorted(enabled), manifest['native_functions'])
        self.assertLessEqual(set(enabled), set(NATIVE_FUNCTIONS))
        for name in enabled:
            module = name.split('.', 1)[0]
            self.assertEqual(hashlib.sha256(modules[module].path.read_bytes()).hexdigest(),
                             NATIVE_MODULE_HASHES[module])

    def test_changed_sources_disable_their_native_implementations(self):
        modules = {name: SimpleNamespace(path=ROOT / 'compiler' / (name + '.bend'))
                   for name in NATIVE_MODULE_HASHES}
        with tempfile.TemporaryDirectory() as directory:
            changed = Path(directory) / 'changed.bend'
            for name, module in modules.items():
                with self.subTest(module=name):
                    changed.write_bytes(module.path.read_bytes() + b'\n# changed algorithm\n')
                    patched = modules | {name: SimpleNamespace(path=changed)}
                    enabled = native_functions(patched)
                    self.assertFalse(any(fn.startswith(name + '.') for fn in enabled))
                    if name in ('model', 'nat_index', 'effect_rows'):
                        self.assertFalse(any(fn.startswith('types.') for fn in enabled))
                    if name in ('model', 'cst', 'native_response', 'native_io', 'native_session'):
                        self.assertNotIn('native_request.decode', enabled)

    def test_missing_modules_do_not_enable_native_algorithms(self):
        self.assertEqual(native_functions({}), {})

    def test_native_type_ir_has_no_compound_resolver_fallback(self):
        source = (ROOT / 'zig/src/generated/functions.zig').read_text()
        manifest = json.loads((ROOT / 'zig/src/generated/manifest.json').read_text())
        if 'native_request.decode' in manifest['native_functions']:
            self.assertIn('native.decode(ctx, args)', source)
        self.assertNotIn('fallback_types_resolve', source)
        self.assertNotIn('$source_resolve', source)
        self.assertIn('native.resolveType(ctx, ', source)
        self.assertIn('native.resolveTypes(ctx, ', source)
        self.assertIn('native.rewriteTypes(ctx, ', source)
        self.assertIn('native.renameTypes(ctx, ', source)
        self.assertIn('pub const oracle_types_resolve_work_reference:', source)

    def test_new_handwritten_zig_is_formatted(self):
        result = subprocess.run([ZIG, 'fmt', '--check', 'src/semantic.zig',
                                 'src/wire.zig', 'src/variables.zig', 'src/type_ir.zig', 'src/type_bridge.zig', 'src/type_ir_tests.zig'], cwd=ROOT / 'zig',
                                capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_decoder_keeps_unicode_error_precedence_and_word_offsets(self):
        prefix = [MAGIC, VERSION, 0, 100, 0, 10000, 0, 1, 2]
        output = self.run_compiler(frame(prefix + [0xd800]) + frame(prefix + [ord('a')]))
        self.assertEqual(diagnostic(output[1]), ('native_protocol', 'word:9',
                         'string contains an invalid Unicode scalar value'))
        self.assertEqual(diagnostic(output[2]), ('native_protocol', 'word:10',
                         'truncated request while reading dictionary string character'))

    def test_every_truncated_prefix_recovers_to_the_next_valid_request(self):
        encoded = words(request(7, answer_module()))
        payload = b''.join(frame(encoded[:n]) + request(0) for n in range(len(encoded)))
        for threads in (1, 4):
            output = self.run_compiler(payload, '--threads', str(threads))
            self.assertEqual(len(output), 1 + 2 * len(encoded))
            for response in output[1::2]:
                self.assertEqual(response[:3], (MAGIC, VERSION, 0))
            for response in output[2::2]:
                self.assertEqual(response, (MAGIC, VERSION, 1, 0, 0, 10000, 0))

    def test_native_decoding_does_not_use_one_stack_frame_per_cst_node(self):
        if sys.platform != 'linux':
            self.skipTest('Linux hard-stack-limit regression')
        import resource
        dictionary = [2, 7, *map(ord, 'program'), 0]
        branch = [0, 1, 1, 0, 0, 1]
        leaf = [0, 1, 1, 0, 0, 0]
        payload = frame([MAGIC, VERSION, 0, 100, 0, 10000, 0] + dictionary +
                        branch * 4096 + leaf + leaf)
        def small_stack():
            resource.setrlimit(resource.RLIMIT_STACK, (1024 * 1024, 1024 * 1024))
        output = self.run_compiler(payload, '--threads', '1', preexec_fn=small_stack)
        self.assertEqual(output[1], (MAGIC, VERSION, 1, 0, 0, 10000, 0))


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--compiler')
    parser.add_argument('--zig-exe', default='zig')
    options, remaining = parser.parse_known_args()
    if options.compiler:
        BINARY = Path(options.compiler).resolve()
    ZIG = options.zig_exe
    unittest.main(argv=[sys.argv[0], *remaining])
