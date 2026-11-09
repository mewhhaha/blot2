#!/usr/bin/env python3
"""Bind the focused reference closure laws to the actual selected checker methods."""
import argparse
import json
import os
from pathlib import Path
import build_goose_checker as builder
import test_checker_tools as checker

ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT/'compiler-goose/tests/checker_tools'

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--goose', type=Path, required=True)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--stdlib', type=Path, default=ROOT.parent/'goose-to-wasm/build/source/stdlib')
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--baseline-source', type=Path, required=True)
    p.add_argument('--cxx', default='/usr/bin/clang++')
    p.add_argument('--output', type=Path, default=ROOT/'build/goose-port/reference-closures/query-controls')
    args = p.parse_args(); args.output = args.output.resolve(); args.output.mkdir(parents=True, exist_ok=True)
    args.source = checker.source_root(args.source); args.baseline_source = checker.source_root(args.baseline_source)
    source = args.source/'src'; baseline = args.baseline_source/'src'
    assert checker.digest(source/'ast.h') == checker.digest(baseline/'ast.h')
    prefix = '#include <iostream>\n'
    for name in ('includes.h','utils.h','direct_input_trace.h','small_vector.h','flat_map.h',
                 'lexer_cache.h','lexer.h','ast.h','type_queries.h'):
        prefix += '#include '+json.dumps(str(source/name))+'\n'
    prefix += 'using namespace goose;\nstatic int passed;\nstatic void law(const char *,const function<void()> &f){f();++passed;}\n'
    prefix += '#include '+json.dumps(str(TESTS/'stability_laws.h'))+'\n'
    (args.output/'array-prefix.h').write_text(prefix)
    header = (source/'typecheck.h').read_text(); types = (source/'typecheck_types.h').read_text()
    builtins = (source/'typecheck_builtins.h').read_text(); methods = ''; bindings = {}
    for file,text,head in [('typecheck.h',header,'    static bool SameIndex('),
        ('typecheck.h',header,'    bool TypeEq('),('typecheck.h',header,'    bool TypeArgsEq('),
        ('typecheck_types.h',types,'inline TypeExpr *TypeCheck::LoadType('),
        ('typecheck_types.h',types,'inline bool TypeCheck::LoadedTypeEq('),
        ('typecheck_types.h',types,'inline bool TypeCheck::CanContain('),
        ('typecheck_types.h',types,'inline bool TypeCheck::CanContainWalk('),
        ('typecheck_builtins.h',builtins,'inline void TypeCheck::RefPointees('),
        ('typecheck_types.h',types,'inline void TypeCheck::ReachedThroughRefs('),
        ('typecheck_types.h',types,'inline bool TypeCheck::ReachesThroughRefs(')]:
        value = checker.block(text,head); bindings[head] = builder.json_digest({'body':value})
        if 'ReachedThroughRefs(' in head:value = value.replace('{','{\n++reach_walks;',1)
        methods += value.replace('TypeCheck::','')+'\n'
    old = checker.block((baseline/'typecheck_types.h').read_text(),'inline bool TypeCheck::ReachesThroughRefs(')
    methods += old.replace('TypeCheck::ReachesThroughRefs','BaselineReaches')+'\n'
    (args.output/'array-methods.h').write_text(methods)
    fixture = (TESTS/'array_gate.cpp').read_text().split('int main(){')[0]
    members = checker.block(header,'    struct ReferenceClosures {')+' referenceclosures;\n'
    members += '    CheckerTrace trace;\n'+checker.block(header,'    void TraceEngine(')+'\n'
    members += '    StructInst *GetStructInst(TypeExpr *t) { if(lazy)lazy(t); auto i=t->struc->inst; if(!i||i->failed)throw IncompleteFixture{}; return i; }\n'
    fixture = fixture.replace('    Ast ast;','    Ast ast;\n'+members,1)
    fixture += '#include '+json.dumps(str(TESTS/'reference_closures.cpp'))+'\n'
    (args.output/'probe.cpp').write_text(fixture)
    report = {'source108_sha256':builder.checked_source(args.source,None),
              'baseline_source108_sha256':builder.checked_source(args.baseline_source,None),
              'bindings':bindings,'fixture_sha256':checker.digest(TESTS/'reference_closures.cpp'),
              'adapter_sha256':checker.digest(TESTS/'array_gate.cpp'),'runs':[]}
    for name,extra in [('debug',[]),('release',['-DNDEBUG'])]:
        binary = args.output/name
        compile_result = checker.command(args,'compile-'+name,[args.cxx,'-std=gnu++20','-O2',*extra,
            '-I'+str(args.output),args.output/'probe.cpp','-o',binary],30)
        result = checker.command(args,name,[binary],30)
        assert json.loads(result['stdout'])['laws'] == 10
        report['runs'].append({'variant':name,'laws':10,'compile_seconds':compile_result['seconds'],
                              'run_seconds':result['seconds'],'binary_sha256':checker.digest(binary)})
    env = dict(os.environ)
    env.pop('GOOSE_DIAGNOSTIC_ROOTS', None); env.pop('GOOSE_CHECKER_PROFILE', None); env.pop('GOOSE_CHECKER_TRACE', None)
    cases = [args.stdlib.parent/'test'/name for name in (
        'lifetimes/store_reached_types.goose', 'lifetimes/store_inexact_roots.goose',
        'lifetimes/store_sources.goose', 'lifetimes/slice_ref_stores.goose',
        'typing/overloaded_function_values.goose')]
    cases += [TESTS/'array_gate.goose']; report['C_parity'] = []
    cfile = args.output/'same-path.c'
    for index,source in enumerate(cases):
        hashes = []
        for label,goose in [('baseline',args.baseline),('candidate',args.goose)]:
            checker.command(args,f'emit-{index}-{label}',[goose.resolve(),'--standalone',source,
                            '--stdlib',args.stdlib,'-o',cfile],30,env)
            hashes.append(checker.digest(cfile))
        assert hashes[0] == hashes[1]
        report['C_parity'].append({'source':str(source),'source_sha256':checker.digest(source),
                                  'C_sha256':hashes[0]})
    on = dict(env); on['GOOSE_CHECKER_TRACE'] = '1'
    trace = checker.command(args,'emit-trace',[args.goose.resolve(),'--standalone',cases[-1],
                            '--stdlib',args.stdlib,'-o',cfile],30,on)
    assert checker.digest(cfile) == report['C_parity'][-1]['C_sha256']
    assert 'GOOSE_CHECKER_TRACE event=begin stage=main root=main' in trace['stderr']
    assert 'GOOSE_CHECKER_TRACE event=end stage=main root=main' in trace['stderr']
    report['trace_C_identical'] = True
    report['candidate_sha256'] = checker.digest(args.goose)
    report['baseline_sha256'] = checker.digest(args.baseline)
    (args.output/'receipt.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'laws':10,'variants':2,'receipt':str(args.output/'receipt.json')}))

if __name__ == '__main__':main()
