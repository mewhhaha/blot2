#!/usr/bin/env python3
"""Migration invariants: lexical capture, supported surface and code shape."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / 'tools'))
from generate import Generator, Node, PRIMITIVES, free, bound, walk


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
