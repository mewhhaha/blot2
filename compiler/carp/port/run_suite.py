#!/usr/bin/env python3
"""Run unmodified compiler tests against the Carp native binary.

Temporarily selects Carp at the existing generated/compiler/blotc path. With
--source-adapter, also redirects the synchronous source.ts API through native
Carp using a test-only import map. Pure model/JS tests remain reference tests.
The previous generated executable is restored even when Deno reports failure.
"""
from __future__ import annotations
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[3]

def publish(source: Path, target: Path) -> None:
    temp=target.with_name(target.name+'.carp-test-new')
    shutil.copy2(source,temp)
    os.replace(temp,target)

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-adapter',action='store_true')
    parser.add_argument('--native-only',action='store_true')
    parser.add_argument('--source-only',action='store_true')
    parser.add_argument('--executable',type=Path,default=ROOT/'generated/carp-port/blotc-carp-native')
    parser.add_argument('--log',type=Path,default=ROOT/'generated/carp-port/suite.log')
    parser.add_argument('files',nargs='*')
    args=parser.parse_args()
    if args.native_only and args.source_only:parser.error('select only one suite')
    if args.source_only:args.source_adapter=True
    deno=shutil.which(os.environ.get('DENO','deno'))
    if not deno:parser.error('DENO (default deno) must be executable')
    binary=args.executable.resolve()
    target=ROOT/'generated/compiler/blotc'
    if not binary.is_file():parser.error('build the Carp backend before testing')
    target.parent.mkdir(parents=True,exist_ok=True)
    folder=ROOT/'generated/carp-port'
    lock=(folder/'suite.lock').open('w')
    fcntl.flock(lock,fcntl.LOCK_EX)
    binary_hash=hashlib.sha256(binary.read_bytes()).hexdigest()
    config=json.loads((ROOT/'deno.json').read_text())
    imports=dict(config.get('imports',{}))
    imports[(ROOT/'compiler/source.ts').as_uri()]=(ROOT/'compiler/carp/port/source_test_adapter.ts').as_uri()
    mapping=folder/'source-test.deno.json'
    mapping.write_text(json.dumps({'imports':imports,'lock':'../../deno.lock'},indent=2)+'\n')
    files=args.files or [str(p.relative_to(ROOT)) for p in sorted((ROOT/'compiler').glob('*native*.test.ts' if args.native_only else '*.test.ts'))]
    if args.source_only:files=[name for name in files if 'native' not in Path(name).name]
    command=[deno,'test','--no-check','--allow-read=compiler,generated,examples,std,scripts',
      '--allow-run=generated/compiler/blotc,generated/carp-port/blotc-carp-native,chrt,nice,ionice,ps,prlimit,setsid']
    if args.source_adapter:command += ['--config='+str(mapping),'--allow-env=NODE_V8_COVERAGE']
    command+=files
    env=dict(os.environ)
    env.setdefault('DENO_DIR',str(ROOT/'.deno-cache'))
    args.log.parent.mkdir(parents=True,exist_ok=True)
    start=time.perf_counter()
    existed=target.is_file()
    with tempfile.TemporaryDirectory(prefix='carp-test-',dir=folder) as temporary:
        backup=Path(temporary)/'blotc-before'
        if existed:shutil.copy2(target,backup)
        try:
            publish(binary,target)
            with args.log.open('w') as log:
                log.write('Carp binary SHA256: '+binary_hash+'\n')
                log.write('Source API redirected: '+str(args.source_adapter)+'\n')
                log.flush()
                result=subprocess.run(command,cwd=ROOT,env=env,stdout=log,stderr=subprocess.STDOUT)
        finally:
            if existed:publish(backup,target)
            else:target.unlink(missing_ok=True)
    report={'exit_code':result.returncode,'elapsed_seconds':time.perf_counter()-start,
            'source_adapter':args.source_adapter,'files':files,'log':str(args.log),
            'binary_sha256':binary_hash}
    args.log.with_suffix('.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
    return result.returncode

if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,subprocess.SubprocessError) as error:
        print(error,file=sys.stderr);raise SystemExit(1)
