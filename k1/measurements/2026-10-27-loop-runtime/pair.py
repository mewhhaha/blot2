#!/usr/bin/env python3
"""Private canonical vs legacy equivalent-loop preflight / paired benchmark.

--verify-only runs no timers. --runtime-only collects only runtime samples;
--measure collects paired compile and runtime samples. Use timed modes only
after compiler builds and competing suites have finished.
This is a narrow fixture, not a full language or ABI comparison.
"""
import argparse, hashlib, json, os, platform, re, shutil, subprocess, sys, time
from pathlib import Path

LEGACY = b'''entry const f = fn (x: U32) -> U32 => do:\n  let out = 17\n  for i in 0..x:\n    out := i\n  break out\n'''
CANONICAL = b'''pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n'''

def digest(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1<<20),b''):h.update(chunk)
    return h.hexdigest()

def run_child(command, stdout, stderr, measured):
    # Linux wait4 reports this individual child's user/system CPU and peak RSS;
    # stdout/stderr go to disk to avoid pipe-buffer deadlock. Wall includes
    # process startup and its own output transport, not this helper's decoding.
    with stdout.open('wb') as out,stderr.open('wb') as err:
        start=time.perf_counter_ns() if measured else None
        child=subprocess.Popen(command,stdout=out,stderr=err,env={**os.environ,'BLOT_CACHE_DIR':''})
        _,status,usage=os.wait4(child.pid,0)
        end=time.perf_counter_ns() if measured else None
        child.returncode=os.waitstatus_to_exitcode(status)
    if child.returncode:
        raise RuntimeError(f'compiler exit {child.returncode}: {command!r}\n{stderr.read_text(errors="replace")}')
    return None if not measured else {'wall_ms':(end-start)/1e6,'user_ms':usage.ru_utime*1000,
        'system_ms':usage.ru_stime*1000,'peak_rss_kib':usage.ru_maxrss}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--legacy',required=True,type=Path);p.add_argument('--canonical',required=True,type=Path)
    p.add_argument('--out',required=True,type=Path);p.add_argument('--node',default='node')
    p.add_argument('--legacy-build-id',required=True,help='compiler commit/build mode; explicitly describe dirty tree if applicable')
    p.add_argument('--canonical-build-id',required=True,help='Goose version, optimization and frozen source snapshot identity')
    mode=p.add_mutually_exclusive_group(required=True);mode.add_argument('--verify-only',action='store_true');mode.add_argument('--runtime-only',action='store_true');mode.add_argument('--measure',action='store_true')
    p.add_argument('--compile-rounds',type=int,default=10);p.add_argument('--compile-warmup',type=int,default=2)
    p.add_argument('--runtime-rounds',type=int,default=31);p.add_argument('--runtime-repeats',type=int,default=16);p.add_argument('--runtime-warmup',type=int,default=8)
    a=p.parse_args()
    if a.compile_rounds<1 or a.compile_warmup<0:p.error('invalid compile rounds/warmup')
    legacy=a.legacy.resolve(strict=True);canonical=a.canonical.resolve(strict=True);out=a.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    paths={k:out/(k+'.blot') for k in ('legacy','canonical')}
    paths['legacy'].write_bytes(LEGACY);paths['canonical'].write_bytes(CANONICAL)
    outputs={k:out/(k+'.wasm') for k in paths};binaries={'legacy':legacy,'canonical':canonical}
    before={k:digest(v) for k,v in binaries.items()}; hashes={};samples={'legacy':[],'canonical':[]}
    commands={'legacy':[str(legacy),'build',str(paths['legacy']),str(outputs['legacy']),'--prelude','none'],
              'canonical':[str(canonical),str(paths['canonical'])]}
    report={'complete':False,'scope':'One finite scalar loop only; experimental typed canonical fixture is not the full K1 compiler.',
      'caveats':['Legacy source and canonical source use different language syntax, implementations and output protocols.',
       'Legacy writes Wasm plus compiler logs; canonical fixture writes hexadecimal Wasm to stdout; end-to-end process times include those different costs.',
       'Release/compiler settings and enabled checks differ. Identical output witnesses do not establish identical safety or ABI guarantees.',
       'Fresh processes use warm filesystem cache; there is no cold-disk or full-project comparison.'],
      'platform':platform.platform(),'machine':platform.machine(),'python':sys.version,'node':subprocess.check_output([a.node,'--version'],text=True).strip(),
      'affinity':sorted(os.sched_getaffinity(0)) if hasattr(os,'sched_getaffinity') else None,
      'compiler_sha256':before,'build_identity':{'legacy':a.legacy_build_id,'canonical':a.canonical_build_id},
      'source_sha256':{k:digest(v) for k,v in paths.items()},'commands':commands,
      'environment_overrides':{'BLOT_CACHE_DIR':''},'measure':a.measure,'runtime_only':a.runtime_only,'compile_samples':samples,'wasm_sha256':hashes}
    report_path=out/'results.json'; save=lambda:report_path.write_text(json.dumps(report,indent=2)+'\n');save()
    n=(a.compile_warmup+a.compile_rounds) if a.measure else 1
    for i in range(n):
      for name in (('legacy','canonical') if i%2==0 else ('canonical','legacy')):
        outputs[name].unlink(missing_ok=True)
        stdout=out/f'{name}-{i}.stdout';stderr=out/f'{name}-{i}.stderr'
        measured=a.measure and i>=a.compile_warmup
        sample=run_child(commands[name],stdout,stderr,measured)
        if name=='canonical':
          raw=stdout.read_bytes().strip()
          if not raw or len(raw)%2 or not re.fullmatch(rb'[0-9a-f]+',raw):raise RuntimeError('canonical output is not lowercase hex Wasm')
          outputs[name].write_bytes(bytes.fromhex(raw.decode('ascii')))
        elif not outputs[name].is_file():raise RuntimeError('legacy emitted no Wasm')
        else:
          try:
            records=[json.loads(line) for line in stdout.read_text().splitlines() if line.strip()]
            records=[v for v in records if v.get('kind')=='compilation' and v.get('success') is True]
            if len(records)!=1 or records[0].get('restart_cache',{}).get('loaded') is not False or records[0].get('restart_cache',{}).get('saved') is not False:
              raise ValueError('expected one successful build record with restart cache loaded/saved=false')
          except (ValueError,TypeError,AttributeError,json.JSONDecodeError) as error:
            raise RuntimeError('legacy cache/freshness check failed') from error
        new=digest(outputs[name])
        if name in hashes and hashes[name]!=new:raise RuntimeError(f'{name} output changed between fresh builds')
        hashes[name]=new
        if sample is not None: samples[name].append({'round':i-a.compile_warmup,**sample})
    runtime=[a.node,str(Path(__file__).with_name('runtime_pair.mjs')),'--legacy',str(outputs['legacy']),'--canonical',str(outputs['canonical'])]
    if a.verify_only: runtime.append('--verify-only')
    else: runtime += ['--rounds',str(a.runtime_rounds),'--repeats',str(a.runtime_repeats),'--warmup',str(a.runtime_warmup)]
    node=subprocess.run(runtime,capture_output=True,text=True,check=False)
    if node.returncode:raise RuntimeError('Wasm witness/runtime check failed:\n'+node.stderr)
    report['runtime_command']=runtime;report['runtime']=json.loads(node.stdout)
    if {k:digest(v) for k,v in binaries.items()}!=before:raise RuntimeError('compiler binary changed during run')
    report['complete']=True;save()
    print(report_path)

if __name__=='__main__':main()
