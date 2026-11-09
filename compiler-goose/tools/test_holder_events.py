#!/usr/bin/env python3
"""Compare source-extracted holder/store-slot methods; no compiler rebuild."""
import argparse
import json
from pathlib import Path
from test_checker_tools import block, command, digest, source_root

ROOT = Path(__file__).resolve().parents[2]
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--baseline-source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--cxx', default='/usr/bin/clang++')
    a = p.parse_args()
    a.source, a.baseline_source = source_root(a.source), source_root(a.baseline_source)
    a.output = a.output.resolve(); a.output.mkdir(parents=True, exist_ok=True)
    src, old = a.source / 'src', a.baseline_source / 'src'
    prefix = ''.join('#include "' + str(src / n) + '"\n' for n in (
        'includes.h','utils.h','direct_input_trace.h','small_vector.h','flat_map.h',
        'lexer_cache.h','lexer.h','ast.h','type_queries.h'))
    prefix += 'using namespace goose;\n'
    (a.output / 'holder-prefix.h').write_text(prefix)
    # The first scan and all preconditions must remain byte-identical.
    marker = '    // What was stored may also be a reference to a slot holding references,'
    before = (old / 'typecheck_builtins.h').read_text()
    after = (src / 'typecheck_builtins.h').read_text()
    start = 'inline bool TypeCheck::HolderMayPointInto('
    assert before[before.index(start):before.index(marker)] == after[after.index(start):after.index(marker)]
    methods = ''
    h = (src / 'typecheck.h').read_text()
    for head in ('    static void IndexStoreEventId(', '    void IndexStoreEvent(',
                 '    void AppendStoreEventLog(', '    void ReplaceStoreEventLog('):
        methods += block(h, head) + '\n'
    methods += '    template<typename F> ' + block(h, 'bool AnyHolderStoreEvent(') + '\n'
    for root, raw in ((src, False), (old, True)):
        text = (root / 'typecheck_builtins.h').read_text()
        # Both overloads are extracted individually from the exact source.
        first = text.index('inline bool TypeCheck::HolderMayPointInto(')
        second = text.index('inline bool TypeCheck::HolderMayPointInto(', first+1)
        parts = [block(text[first:], 'inline bool TypeCheck::HolderMayPointInto('),
                 block(text[second:], 'inline bool TypeCheck::HolderMayPointInto('),
                 block(text, 'inline TypeExpr *TypeCheck::StoredSlotMayPointInto(')]
        for part in parts:
            part = part.replace('TypeCheck::', '').replace('TypeExpr **via)', 'TypeExpr **via = nullptr)')
            if raw:
                part = part.replace('HolderMayPointInto', 'RawHolderMayPointInto').replace('StoredSlotMayPointInto', 'RawStoredSlotMayPointInto')
            methods += part + '\n'
    (a.output / 'holder-methods.h').write_text(methods)
    results = {}
    for mode, flags in (('debug', []), ('release', ['-DNDEBUG'])):
        binary = a.output / mode
        built = command(a, 'compile-'+mode, [a.cxx, '-std=gnu++20', '-O2', *flags,
            '-Wno-unused-parameter', '-I'+str(a.output), ROOT/'compiler-goose/tests/checker_tools/holder_events.cpp', '-o', binary], 30)
        run = command(a, mode, [binary], 30)
        results[mode] = {'compile': built, 'run': run, 'binary_sha256': digest(binary)}
    receipt = {'scope':'actual AST, append/replace/index and holder/store-slot methods; controlled type/depth/liveness query leaves',
        'methods_sha256': digest(a.output/'holder-methods.h'),
        'fixture_sha256': digest(ROOT/'compiler-goose/tests/checker_tools/holder_events.cpp'),
        'sources': {str(root): {n:digest(root/n) for n in ('ast.h','typecheck.h','type_queries.h','typecheck_builtins.h')} for root in (src,old)}, 'results':results}
    (a.output/'receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({k:v['run']['stdout'].strip() for k,v in results.items()}))
if __name__ == '__main__': main()
