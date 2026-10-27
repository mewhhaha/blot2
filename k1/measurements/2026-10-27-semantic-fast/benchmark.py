#!/usr/bin/env python3
"""Controlled private resolver→semantic target comparison; timing is opt-in."""
import argparse, hashlib, json, os, pathlib, random, re, shutil, statistics, subprocess, time
P=pathlib.Path(__file__).resolve().parent; K=P/'k1'; DRIVER=P/'bench-driver'; R=P/'bench-inputs'; RES=P/'bench-results'
def h(p): return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()
def source(sig,body,decl='depth: 1, frame: 0',effect='{}'):
 return f'pub let f: {sig} ! {effect} resources {{{decl}}} = fn x => do:\n{body}'.encode()
CASES=[
 ('u32_identity',source('U32 -> U32','  return x\n'),'normal','f',0,[(0,0),(7,7),(4294967295,4294967295)]),
 ('bool_short',source('Bool -> Bool','  return x && #True\n'),'normal','f',0,[(0,0),(1,1)]),
 ('guard_offset',source('U32 -> U32','  if x <= 4294967290:\n    return x + 5\n  return x\n'),'normal','f',0,[(0,5),(4294967290,4294967295),(4294967291,4294967291)]),
 ('bounded_loop',source('U32 -> U32','  let total = for i in 0..4 carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return total\n'),'normal','f',0,[(0,4),(7,4)]),
 ('comment_4k',b'// '+b'a'*4096+b'\n'+source('U32 -> U32','  return x\n'),'normal','f',0,[(7,7)]),
 ('invalid_effect',source('U32 -> U32','  return x\n',effect='{host}'),'normal','f',1,[]),
 ('invalid_type',source('Bool -> U32','  return x\n'),'normal','f',1,[]),
 ('depth_limit',source('U32 -> U32','  return x\n'),'depth','f',2,[]),
 ('wrong_export',source('U32 -> U32','  return x\n'),'normal','missing',1,[]),
 ('missing_module',None,'normal','f',11,[]),
]
def dependencies():
 todo=['semantic_job_bench.goose']; seen=set(); external=set()
 while todo:
  n=todo.pop()
  if n in seen: continue
  p=K/n
  if not p.is_file(): raise RuntimeError(f'missing dependency {n}')
  seen.add(n)
  for mod in re.findall(r'\bimport\s+([A-Za-z_][A-Za-z_0-9]*)\s*;',p.read_text()):
   child=mod+'.goose'
   if (K/child).is_file(): todo.append(child)
   else: external.add(mod)
 seen.update(['semantic_job_bench.build','source_resolver.c'])
 return {n:h(K/n) for n in sorted(seen)}, sorted(external)
def cpu_stats():
 p=pathlib.Path('/sys/fs/cgroup/cpu.stat')
 try: return {k:int(v) for k,v in (line.split() for line in p.read_text().splitlines())}
 except (OSError, ValueError): return None
def cpu_info():
 def read(p):
  try: return pathlib.Path(p).read_text().strip()
  except OSError: return None
 return {'affinity':sorted(os.sched_getaffinity(0)),'cpu_max':read('/sys/fs/cgroup/cpu.max'),'cpuset_effective':read('/sys/fs/cgroup/cpuset.cpus.effective'),'loadavg':read('/proc/loadavg')}
def invoke(case,mode,batch):
 name,_,depth,decl,_,_=case
 x=subprocess.run([str(DRIVER),mode,str(R),name+'.blot',decl,depth,batch],capture_output=True,timeout=120)
 if x.returncode: raise RuntimeError((name,mode,batch,x.returncode,x.stderr.decode(errors='replace')))
 return x.stdout
NODE="""const fs=require('fs'),assert=require('assert/strict');const b=fs.readFileSync(process.argv[1]);const e=new WebAssembly.Instance(new WebAssembly.Module(b)).exports.f;for(const [x,y] of JSON.parse(process.argv[2]))assert.equal(e(0,x)>>>0,y);"""
def execute(bytes_,tests):
 t=RES/'witness.wasm';t.write_bytes(bytes_)
 try: subprocess.run(['node','-e',NODE,str(t),json.dumps(tests)],check=True,capture_output=True,timeout=30)
 finally: t.unlink(missing_ok=True)
def verify_files(manifest):
 if h(DRIVER)!=manifest['binary_sha256'] or h(P/'benchmark.py')!=manifest['harness_sha256'] or h(P/'build-record.json')!=manifest['build_record_sha256']:raise RuntimeError('binary, harness, or build record changed')
 deps,ext=dependencies()
 if deps!=manifest['dependencies'] or ext!=manifest['external_imports']:raise RuntimeError('dependency changed')
 for name,digest in manifest['inputs'].items():
  p=R/(name+'.blot')
  if digest is None:
   if p.exists():raise RuntimeError('missing input unexpectedly present')
  elif not p.is_file() or h(p)!=digest:raise RuntimeError('input changed: '+name)
 for name,digest in manifest['expected_sha256'].items():
  if h(RES/(name+'.out'))!=digest:raise RuntimeError('expected witness changed: '+name)
def prepare():
 if R.exists() or RES.exists():raise RuntimeError('inputs/results already exist; delete explicitly or use a fresh directory')
 R.mkdir();RES.mkdir();inputs={};expected={}
 for case in CASES:
  name,data,_,_,want,tests=case
  if data is not None:(R/(name+'.blot')).write_bytes(data)
  inputs[name]=h(R/(name+'.blot')) if data is not None else None
  results=[invoke(case,mode,batch) for mode in ['baseline','candidate'] for batch in ['once','batch']]
  if any(x!=results[0] for x in results) or not results[0] or results[0][0]!=want:raise RuntimeError('preflight mismatch: '+name)
  if want==0:
   if results[0][1:9]!=b'\0asm\1\0\0\0':raise RuntimeError('bad Wasm: '+name)
   execute(results[0][1:],tests)
  elif len(results[0])!=1:raise RuntimeError('failed compilation produced bytes: '+name)
  (RES/(name+'.out')).write_bytes(results[0]);expected[name]=h(RES/(name+'.out'))
 deps,ext=dependencies();build=json.loads((P/'build-record.json').read_text());
 if build['dependencies']!=deps or build['external_imports']!=ext or build['binary_sha256']!=h(DRIVER):raise RuntimeError('build record mismatch')
 goose=pathlib.Path(os.environ.get('GOOSE','/tmp/k1-goose/build/goose')).resolve();node=pathlib.Path(shutil.which('node')).resolve();manifest={'binary_sha256':h(DRIVER),'build_record_sha256':h(P/'build-record.json'),'goose_binary_sha256':h(goose),'node_binary_sha256':h(node),'node_version':subprocess.check_output([str(node),'--version'],text=True).strip(),'harness_sha256':h(P/'benchmark.py'),'dependencies':deps,'external_imports':ext,'inputs':inputs,'expected_sha256':expected,'cases':[{'name':c[0],'status':c[4],'expected_runtime':c[5]} for c in CASES]}
 (RES/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');verify_files(manifest)
 print('preflight exact baseline/candidate status/bytes and Node execution passed for',len(CASES),'cases')
def timed(pairs,warmups):
 m=json.loads((RES/'manifest.json').read_text());verify_files(m)
 before=cpu_stats();env_before=cpu_info();rng=random.Random(370037)
 for _ in range(warmups):
  order=list(CASES);rng.shuffle(order)
  for c in order:
   for mode in ('baseline','candidate'):
    if invoke(c,mode,'batch')!=(RES/(c[0]+'.out')).read_bytes():raise RuntimeError('warmup mismatch')
 records=[]
 for index in range(pairs):
  order=list(CASES);rng.shuffle(order)
  for c in order:
   first='baseline' if (index+CASES.index(c))%2==0 else 'candidate';modes=[first,'candidate' if first=='baseline' else 'baseline'];times={}
   for mode in modes:
    t=time.perf_counter_ns();out=invoke(c,mode,'batch');times[mode]=time.perf_counter_ns()-t
    if out!=(RES/(c[0]+'.out')).read_bytes():raise RuntimeError('timed output mismatch')
   records.append({'pair':index,'case':c[0],'order':modes,'baseline_ns':times['baseline'],'candidate_ns':times['candidate']})
 verify_files(m);after=cpu_stats();env_after=cpu_info()
 (RES/'timings.json').write_text(json.dumps({'pairs':pairs,'warmups':warmups,'iterations_per_batch':32,'records':records,'cpu_before':before,'cpu_after':after,'environment_before':env_before,'environment_after':env_after,'manifest_sha256':h(RES/'manifest.json')},indent=2)+'\n')
 for c in CASES:
  x=[r['candidate_ns']/r['baseline_ns'] for r in records if r['case']==c[0]];print(c[0],'median candidate/baseline',round(statistics.median(x),4))
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('command',choices=['prepare','time']);a.add_argument('--pairs',type=int,default=31);a.add_argument('--warmups',type=int,default=4);a.add_argument('--cpu',type=int);args=a.parse_args()
 if args.cpu is not None:os.sched_setaffinity(0,{args.cpu})
 if args.command=='prepare':prepare()
 else:
  if args.pairs<2 or args.warmups<1:raise SystemExit('pairs >= 2 and warmups >= 1 required')
  timed(args.pairs,args.warmups)
