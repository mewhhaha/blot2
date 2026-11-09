#!/usr/bin/env python3
"""Bounded real-Goose pool/mmap observations; requires private observer compiler."""
import argparse
import hashlib
import json
import shutil
import resource
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def run(command, expected=0):
    result=subprocess.run([str(v) for v in command],capture_output=True,text=True,timeout=30)
    if result.returncode!=expected:
        raise RuntimeError(f"exit {result.returncode}, expected {expected}: {command}\n{result.stderr}")
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose',type=Path,required=True)
    parser.add_argument('--cc',default='clang')
    parser.add_argument('--output',type=Path,default=ROOT.parent/'build/goose-port/runtime-observer-tests')
    args=parser.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    work=args.output.resolve();work.mkdir(parents=True,exist_ok=True)
    started=time.monotonic()
    source_paths=[ROOT/name for name in (
        'tests/runtime_observer.goose','src/runtime/memory.goose','src/support/native.goose',
        'native/platform.c','native/allocation_observer.c','native/allocation_observer.h',
        'native/tests/allocation_observer_test.c','native/tests/runtime_observer_probe.c',
        'tools/test_runtime_observer.py')]
    identities={str(path.relative_to(ROOT)):digest(path) for path in source_paths}
    runtime=work/'runtime.c';program=work/'probe.c'
    run([args.goose,'--emit-runtime',runtime])
    source=work/'src';source.mkdir(exist_ok=True)
    for module in (ROOT/'src').iterdir():
        if module.name=='main.goose':
            continue
        link=source/module.name
        if not link.is_symlink():
            link.symlink_to(module,target_is_directory=module.is_dir())
    shutil.copyfile(ROOT/'tests/runtime_observer.goose',source/'main.goose')
    stdlib=ROOT.parent.parent/'goose-to-wasm/build/source/stdlib'
    run([args.goose,'-O0','--stdlib',stdlib,'-o',program,'--header',work/'probe.h',source/'main.goose'])
    flags=['-std=gnu11','-D_GNU_SOURCE','-O0','-pthread','-I'+str(ROOT/'native')]
    probe=work/'probe'
    run([args.cc,*flags,program,runtime,ROOT/'native/allocation_observer.c',
         ROOT/'native/tests/runtime_observer_probe.c',ROOT/'native/platform.c','-lm','-o',probe])
    native=work/'native-test'
    run([args.cc,'-std=gnu11','-Wall','-Wextra','-Werror','-I'+str(ROOT/'native'),ROOT/'native/allocation_observer.c',
         ROOT/'native/tests/allocation_observer_test.c','-o',native])
    run([native])
    result=json.loads(run([probe]).stdout)
    # Cover every observed attempt, including reused spans/slots and stack requests.
    count=result['attempts']
    for ordinal in range(1,count+1):
        failed=run([probe,'inject',ordinal,0],73)
        assert failed.stderr=='OBSERVER_OOM\n'
    run([probe,'inject',count+1,0])
    refused=run([probe,'allocator-refusal'],73)
    assert refused.stderr=='OBSERVER_OOM\n'
    for mode in ('panic','invalid','signal','kill'):
        failed=subprocess.run([str(probe),mode],capture_output=True,text=True,timeout=30)
        assert failed.returncode!=0 and 'OBSERVER_OOM' not in failed.stderr,(mode,failed)
    report=json.loads(run([probe,'report']).stdout)
    observed=report['runtime_observations']
    assert report['live_bytes'] is None and report['allocations'] is None
    assert observed['coverage']=='pool-operations-and-region-reservations'
    assert observed['request']==123 and observed['pool_allocations']==6
    assert observed['pool_reallocations']==2 and observed['pool_frees']==4
    assert observed['pool_payload_allocated_bytes']==112 and observed['pool_payload_freed_bytes']==96
    assert observed['pool_capacity_growth_bytes']==104 and observed['region_reserved_bytes']>0
    assert observed['pool_operations'] and observed['region_reservations_observed']
    assert observed['explicit_capacity_requests_observed'] and observed['registry_allocation_observed']
    assert not observed['whole_runtime_fault_coverage']
    for field in ('active_pool_payload_bytes','retained_pool_capacity_bytes','scratch_bytes','rss_bytes'):
        assert observed[field] is None
    # The same production Goose reporting path links without the observer module.
    absent_main=work/'absent-main.c'
    absent_main.write_text('extern void goose_init(int,char **); extern void observer_report(void); '
                           'int main(int argc,char **argv){goose_init(argc,argv);observer_report();return 0;}\n')
    absent=work/'absent'
    run([args.cc,*flags,program,runtime,absent_main,ROOT/'native/platform.c','-lm','-o',absent])
    unavailable=json.loads(run([absent]).stdout)['runtime_observations']
    assert unavailable['coverage']=='unavailable' and not unavailable['pool_operations']
    assert 'pool_allocations' not in unavailable and unavailable['active_pool_payload_bytes'] is None
    # The adapter also links safely when the runtime has no optional hook ABI.
    no_hooks_main=work/'no-hooks-main.c'
    no_hooks_main.write_text('#include "allocation_observer.h"\n'
        'int main(void){blot_allocation_observer_install(0);'
        'return blot_allocation_observer_value(0)!=0;}\n')
    no_hooks=work/'no-hooks'
    run([args.cc,*flags,'-I'+str(ROOT/'native'),no_hooks_main,
         ROOT/'native/allocation_observer.c','-o',no_hooks])
    run([no_hooks])
    if {str(path.relative_to(ROOT)):digest(path) for path in source_paths}!=identities:
        raise RuntimeError('fixture sources changed while verifying')
    result['productionReport']=report
    result['optionalObserverAbsent']=True
    result['runtimeHooksAbsent']=True
    result['source_sha256']=identities
    result['artifact_sha256']={path.name:digest(path) for path in (runtime,program,probe,native,absent,no_hooks)}
    result['goose_sha256']=digest(args.goose)
    result.update({'injectedRefusals':count,
                   'allocatorRefusal':{'mechanism':'RLIMIT_AS','physicalRAMExhaustionTested':False},
                   'genericFailuresNeverOOM':['panic','invalid-size','SIGSEGV','SIGKILL'],
                   'seconds':round(time.monotonic()-started,3),
                   'goose':str(args.goose.resolve()),'cc':args.cc})
    (work/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))

if __name__=='__main__':
    main()
