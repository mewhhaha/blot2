#!/usr/bin/env python3
"""Classify guest-suite failures on a -Ddirect-default=true compiler.

Usage: direct_guest_gap.py JUNIT.xml OUT.json

Run the suite first, e.g.
  deno test -A --parallel --junit-path=JUNIT.xml tests/guest tests/host -- \
    compiler/zig-out-direct/bin/blotc
Categories follow tasks/DELETE_SCOPED.md. Temporary: delete with the scoped
backend.
"""
import re,sys,json,collections,xml.etree.ElementTree as ET
t=ET.parse(sys.argv[1]).getroot()
DROP={
 'request handlers (B3)':['computation','request_loop'],
 'effect identities and reflection (B3)':['effect_scope','effect_reflection'],
 'monads and resolvers (B3)':['resolver_op'],
 'typed staging (C8)':['staging'],
 'polymorphic packages (C8)':['package_pack','package_unpack'],
 'usage contracts and resources (C8)':['usage_borrow','usage_read','usage_share','resource_acquire','resource_scope','resource_release'],
 'erased proofs (C8)':['proof_guard'],
 'type values and witnesses (C3/C4)':['type_constructor','type_same'],
 'language tasks (retired)':['task'],
}
PENDING={'traits redesign (C)':['contract_method']}
def classify(m):
    cats=[]
    forms=re.findall(r'(\w+) expressions are not supported yet',m)
    for g,fs in DROP.items():
        if any(f in fs for f in forms): cats.append('drop: '+g)
    for g,fs in PENDING.items():
        if any(f in fs for f in forms): cats.append('pending: '+g)
    if cats: return cats
    if re.search(r'Unknown (constant|function) export|exports no functions',m): return ['implement: constant exports']
    if re.search(r'Expected \w+, received storage_unsupported|Expected compilation to fail|evaluated to a falsy value:\s+assert\(!\w+\.success\)|- \'\w+\'.*storage_unsupported|storage_unsupported.*- \'',m): return ['diagnostic owned by scoped backend']
    if 'Direct backend' in m or 'storage_unsupported' in m:
        if re.search(r'(handle|effect_provider|state_provider|operation_value) expressions',m): return ['implement: providers and effect operations (B1)']
        if 'unresolved type variable' in m or 'leave open' in m or 'existential' in m or 'projection' in m: return ['implement: type inference gaps']
        if 'unbound local reference' in m or 'closure capture without a value' in m: return ['implement: unbound locals']
        if 'recursive data type' in m: return ['implement: recursive data types']
        if re.search(r'entry (results|parameters)',m): return ['implement: entry ABI forms']
        return ['implement: other forms']
    if re.search(r'scoped_\w+|workCounters|work_counters|checkpoint|nativeWorkSteps|graph_imports|"tier":"optimized"|runtime_optimization|optimized_bodies|Unable to export',m): return ['scoped internal']
    if re.search(r'RuntimeError|unreachable|signature mismatch|strictly (deep-)?equal|!==',m): return ['runtime mismatch']
    return ['other']
cases=collections.defaultdict(list); byfile=collections.defaultdict(collections.Counter)
total=0; passed=collections.Counter()
for suite in t.iter('testsuite'):
    f=suite.get('name').replace('./','')
    for c in suite.iter('testcase'):
        total+=1
        fail=c.find('failure')
        if fail is None: passed[f]+=1; continue
        m=(fail.get('message') or '')+'\n'+(fail.text or '')
        cat=classify(m)[0]
        cases[cat].append((f,c.get('name')))
        byfile[f][cat]+=1
summary={k:len(v) for k,v in cases.items()}
json.dump({'total':total,'passed':sum(passed.values()),'summary':summary,'files':{f:dict(c) for f,c in byfile.items()},'passed_by_file':passed},open(sys.argv[2],'w'),indent=1)
for k,v in sorted(summary.items(),key=lambda x:-x[1]): print(f'{v:5} {len({f for f,_ in cases[k]}):4} files  {k}')
