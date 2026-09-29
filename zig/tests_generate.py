#!/usr/bin/env python3
"""Migration invariants: lexical capture, supported surface and code shape."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tools'))
from generate import Generator, Node, PRIMITIVES, free, bound, walk
from partition import CODEGEN, GROUPS, select


def name(value):
    return Node('id', value)


class GenerationTests(unittest.TestCase):
    def test_parallel_rhs_capture_the_pre_binding_scope(self):
        batch = Node('parallel_bind', 2, [name('x'), name('y'), name('y'), name('x')])
        self.assertEqual(free(batch), {'x', 'y'})
        block = Node('block', children=[batch, Node('tuple', children=[name('x'), name('y')])])
        self.assertEqual(free(block), {'x', 'y'})

    def test_parallel_bindings_are_available_to_later_expressions(self):
        batch = Node('parallel_bind', 2, [name('x'), name('y'), name('left'), name('right')])
        block = Node('block', children=[batch, Node('tuple', children=[name('x'), name('y'), name('outside')])])
        self.assertEqual(free(block), {'left', 'right', 'outside'})

    def test_lambda_capture_excludes_its_parameter(self):
        lam = Node('lambda', 'x', [Node('tuple', children=[name('x'), name('outer')])])
        self.assertEqual(free(lam), {'outer'})

    def test_match_capture_respects_pattern_binders(self):
        match = Node('match', [([Node('ctor', 'Some', [name('x')])], Node('tuple', children=[name('x'), name('outer')]))], [name('input')])
        self.assertEqual(free(match), {'input', 'outer'})
        self.assertEqual(bound(Node('tuple', children=[name('x'), name('_')])), {'x'})

    def test_all_parallel_bindings_are_explicit_pure_semantic_batches(self):
        generator = Generator(Path(__file__).resolve().parent.parent)
        batches = [(m.name, node) for m in generator.mods.values() for f in m.functions
                   for node in walk(f.body) if node.kind == 'parallel_bind']
        self.assertTrue(batches)
        self.assertTrue(all(node.value in (2, 4, 8) for _, node in batches))
        self.assertNotIn('native_request', {module for module, _ in batches})
        self.assertNotIn('IO.read', PRIMITIVES)
        self.assertNotIn('IO.write', PRIMITIVES)

    def test_medium_recursive_dispatchers_are_outlined_before_debug_frames_grow(self):
        # This dispatcher was just below the former 1,000-node cutoff. Its
        # 50 KiB Debug frame overflowed on an ordinary 96-term expression.
        generator = Generator(Path(__file__).resolve().parent.parent)
        function = generator.functions['monomorph.expand']
        generator.mod = generator.mods[function.module]
        generator.current = 'monomorph.expand'
        generator.emit(function.body, {p: f'arg_{p}' for p in function.params}, None, None)
        self.assertGreater(generator.arms, 0)
        # The dispatcher hands off to the selected arm before evaluating it.
        self.assertNotIn('ctx.call(', '\n'.join(generator.lines))
        self.assertIn('return ctx.next(', '\n'.join(generator.lines))

    def test_differential_config_uses_the_same_package_registry(self):
        root = Path(__file__).resolve().parent.parent
        self.assertEqual((root / '.npmrc').read_text(), (root / 'zig/.npmrc').read_text())

    def test_compatibility_partition_preserves_every_file_and_worker_case(self):
        root = Path(__file__).resolve().parent.parent
        files = [p.relative_to(root).as_posix() for p in (root / 'compiler').glob('*.test.ts')]
        regular, patterns = [], []
        for group in GROUPS:
            selected, pattern = select(files, group)
            self.assertTrue(selected)
            if pattern:
                self.assertEqual(selected, [CODEGEN])
                patterns.append(pattern)
            else:
                regular.extend(selected)
        self.assertEqual(len(regular), len(set(regular)))
        self.assertEqual(set(regular), set(files) - {CODEGEN})
        import re
        for workers in (1, 2, 4, 8):
            name = f'native {workers}-thread codegen compiles only independent cache misses'
            self.assertEqual(sum(bool(re.fullmatch(pattern[1:-1], name)) for pattern in patterns), 1)
        self.assertEqual(len(patterns), 4)

    def test_compatibility_partition_rejects_invalid_or_incomplete_inventories(self):
        for files, group in [([], '0'), ([CODEGEN, CODEGEN], '0'), ([CODEGEN], 'codegen-16')]:
            with self.subTest(files=files, group=group), self.assertRaises(ValueError):
                select(files, group)

    def test_protocol_version_has_one_source_of_truth(self):
        import json
        import re
        root = Path(__file__).resolve().parent.parent
        generator = Generator(root)
        version = generator.protocol_version()
        manifest = json.loads((root / 'zig/src/generated/manifest.json').read_text())
        self.assertEqual(version, manifest['protocol_version'])
        self.assertIn(f'pub const version: u32 = {version};',
                      (root / 'zig/src/generated/protocol.zig').read_text())
        host = (root / 'compiler/native_protocol.ts').read_text()
        self.assertEqual(int(re.search(r'nativeProtocolVersion = (\d+)', host)[1]), version)

    def test_nonliteral_or_unrepresentable_protocol_version_is_rejected(self):
        from port import ParseError
        generator = Generator(Path(__file__).resolve().parent.parent)
        function = generator.functions['native_response.version']
        for body in [name('computed'), Node('block', children=[]),
                     Node('block', children=[Node('number', '4294967296')]),
                     Node('block', children=[Node('number', '14n')])]:
            with self.subTest(body=body), self.assertRaises(ParseError):
                function.body = body
                generator.protocol_version()

    def test_type_ir_oracles_are_transitively_independent(self):
        import re
        source = (Path(__file__).resolve().parent / 'src/generated/functions.zig').read_text()
        names = dict((int(i), n) for i, n in re.findall(r'&fun_(\d+), // ([^\n]+)', source))
        pieces = re.split(r'(?m)^fn fun_(\d+)\(', source)
        for i in range(1, len(pieces), 2):
            function = names[int(pieces[i])]
            body = pieces[i + 1].split('pub const table', 1)[0]
            oracle = '.$oracle_' in function
            if oracle:
                self.assertNotIn('native.', body, function)
            for target in re.findall(r'ctx\.(?:call|next|closure)\((\d+)', body):
                self.assertEqual(oracle, '.$oracle_' in names[int(target)],
                                 (function, names[int(target)]))

    def test_generated_semantics_are_native_and_have_bounded_arity(self):
        import json
        directory = Path(__file__).resolve().parent / 'src/generated'
        manifest = json.loads((directory / 'manifest.json').read_text())
        self.assertGreater(manifest['parallel_tasks'], 0)
        self.assertGreater(manifest['outlined_arms'], 0)
        self.assertGreater(len(manifest['sources']), 0)
        self.assertLessEqual(manifest['max_arity'], 64)
        source = (directory / 'functions.zig').read_text()
        self.assertIn('ctx.parallel(', source)
        self.assertIn('return ctx.next(', source)
        for foreign in ('@cImport', 'std.DynLib', 'std.process.Child'):
            self.assertNotIn(foreign, source)


if __name__ == '__main__':
    unittest.main()
