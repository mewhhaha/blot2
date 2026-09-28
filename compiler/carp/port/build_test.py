#!/usr/bin/env python3
"""Hermetic build-cache tests with observable fake Carp/C toolchains.

These test dependency tracking and failure-safe publication, not language
semantics. The real native compiler and ownership runtime have separate suites.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

PORT = Path(__file__).resolve().parent
FAKE = r'''#!/usr/bin/env python3
import hashlib,json,os,pathlib,re,sys
args=sys.argv[1:]
if args==['--version']:
 print('clang fake version 1');raise SystemExit(0)
log=pathlib.Path(os.environ['BUILD_TEST_LOG'])
with log.open('a') as f:f.write(json.dumps([pathlib.Path(sys.argv[0]).name,*args])+'\n')
if pathlib.Path(sys.argv[0]).name=='carp':
 output=pathlib.Path(re.search(r'"output-directory" "([^"]+)"',args[args.index('--eval-postload')+1])[1]);output.mkdir(parents=True,exist_ok=True)
 data=pathlib.Path(args[-1]).read_bytes()
 (output/'main.c').write_bytes(b'generated '+data);raise SystemExit(0)
output=pathlib.Path(args[args.index('-o')+1])
inputs=[pathlib.Path(a).read_bytes() for a in args if a.endswith(('.c','.o')) and pathlib.Path(a).is_file()]
if any(b'COMPILE_ERROR' in data for data in inputs):raise SystemExit(2)
h=hashlib.sha256(b''.join(inputs)).hexdigest()
if '-c' in args:output.write_text(h)
else:
 bad=any(b'TEST_FAILURE' in data for data in inputs)
 output.write_text('#!/bin/sh\n# '+h+'\nexit '+('1' if bad else '0')+'\n');output.chmod(0o755)
'''

def main() -> None:
    checks = 0
    def check(value: bool, message: str) -> None:
        nonlocal checks
        if not value:raise AssertionError(message)
        checks += 1
    with tempfile.TemporaryDirectory(prefix='carp-build-test-') as tmp:
        root=Path(tmp);port=root/'compiler/carp/port';gen=port/'generated'
        gen.mkdir(parents=True);(port/'vendor').mkdir()
        for name in ['build.py','verify.py']:shutil.copy2(PORT/name,port/name)
        for name in ['generate.cjs','loops.cjs','vendor/acorn.cjs','runtime.c','runtime.h','runtime_test.c','scheduler.inc']:
            (port/name).write_text(name+'\n')
        for name in ['unit000.carp','unit001.carp','driver.carp','bindings.carp','tables.c','tables.h','calls.h','calls.inc']:
            (gen/name).write_text(name+'\n')
        (port/'reference.lock.json').write_text(json.dumps({'semanticSha256':'test-input','sourceCommit':'test-source'}))
        def manifest() -> None:
            sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
            (gen/'manifest.json').write_text(json.dumps({'inputSha256':'test-input','sourceCommit':'test-source',
                'generatorSha256':sha(port/'generate.cjs'),'loopsSha256':sha(port/'loops.cjs'),
                'vendorSha256':sha(port/'vendor/acorn.cjs'),
                'files':{p.name:sha(p) for p in gen.iterdir() if p.name!='manifest.json'}}))
        manifest()
        for name in ['carp','cc']:
            (root/name).write_text(FAKE);(root/name).chmod(0o755)
        env={**os.environ,'CARP_DIR':str(root),'CARP':str(root/'carp'),'CC':str(root/'cc'),
             'BUILD_TEST_LOG':str(root/'commands.log')}
        def build(mode: str='release', fail: bool=False, extra: tuple[str,...]=()) -> dict:
            r=subprocess.run([shutil.which('python3') or 'python3',str(port/'build.py'),mode,'--jobs','2',*extra],
                cwd=root,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=40)
            check((r.returncode!=0)==fail,r.stdout)
            return json.loads((root/'generated/carp-port'/mode/'build.json').read_text()) if not fail else {}
        def commands() -> list:
            return (root/'commands.log').read_text().splitlines()
        first=build();target=root/'generated/carp-port/blotc-carp-native'
        check(first['carp_units_generated']==3 and first['c_units_compiled']==5,'clean build stages')
        before=len(commands());mtime=target.stat().st_mtime_ns
        warm=build()
        check(len(commands())==before,'no-change build reran a compiler/linker')
        check(warm['runtime_tests_cached'] and warm['link_cached'] and not warm['published'],'cache flags')
        check(target.stat().st_mtime_ns==mtime,'no-change build replaced the public executable')
        debug=build('debug')
        check(debug['carp_units_generated']==0 and debug['c_units_compiled']==5,'mode switch must share Carp generation')
        build('release')
        changed=gen/'unit000.carp';changed.write_text('a real source edit\n');manifest()
        edit=build()
        check(edit['carp_units_generated']==1 and edit['c_units_compiled']==1,'one unit edit rebuilt unrelated units')
        runtime=port/'runtime.c';runtime.write_text('runtime edit\n')
        support=build()
        check(support['carp_units_generated']==0 and support['c_units_compiled']==1,'runtime edit rebuilt semantic units')
        healthy=target.read_bytes()
        (port/'runtime_test.c').write_text('TEST_FAILURE\n')
        build(fail=True)
        check(target.read_bytes()==healthy,'failed runtime check replaced public compiler')
        (port/'runtime_test.c').write_text('runtime_test.c\n');build()
        (gen/'unit001.carp').write_text('COMPILE_ERROR\n');manifest();healthy=target.read_bytes()
        build(fail=True)
        check(target.read_bytes()==healthy,'compile failure replaced public compiler')
        (gen/'unit001.carp').write_text('restored valid source\n');manifest();build()
        object_file=root/'generated/carp-port/release/unit000.o'
        object_file.write_bytes(b'corrupt object')
        corrupt=build()
        check(corrupt['c_units_compiled']==1,'corrupt object was silently reused')
        report=json.loads((root/'generated/carp-port/release/build.json').read_text())
        key=next(u['codegen_key'] for u in report['units'] if u['unit']=='unit001')
        (root/'generated/carp-port/codegen'/key/'main.c').write_text('corrupt C')
        repaired=build()
        check(repaired['carp_units_generated']==1,'corrupt generated C was silently reused')
        healthy=target.read_bytes();target.write_bytes(b'corrupt public binary')
        restored=build()
        check(restored['published'] and target.read_bytes()==healthy,'published binary was not repaired')
        before=len(commands());retest=build(extra=('--retest',))
        check(not retest['runtime_tests_cached'] and len(commands())==before,'--retest must execute checks without compiling')
        # Same --version output, different wrapper implementation: invalidate C.
        with (root/'cc').open('a') as f:f.write('\n# changed compiler wrapper\n')
        tool=build();check(tool['c_units_compiled']==5,'compiler wrapper bytes ignored')
        (gen/'driver.carp').write_text('modified without refreshing manifest\n')
        healthy=target.read_bytes();build(fail=True)
        check(target.read_bytes()==healthy,'manifest failure replaced public binary')
    print(f'Build cache: {checks} checks passed.')

if __name__=='__main__':main()
