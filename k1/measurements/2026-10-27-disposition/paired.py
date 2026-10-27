#!/usr/bin/env python3
"""Private dispatch before/after paired experiment; not public K1 qualification."""
import argparse,hashlib,json,os,platform,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parent
p=argparse.ArgumentParser();mode=p.add_mutually_exclusive_group(required=True);mode.add_argument('--verify-only',action='store_true');mode.add_argument('--measure',action='store_true');p.add_argument('--out',required=True,type=Path);p.add_argument('--rounds',type=int,default=25);p.add_argument('--warmup',type=int,default=3);a=p.parse_args()
if a.rounds<1 or a.warmup<0:p.error('invalid rounds')
a.out.mkdir(parents=True,exist_ok=False)
subprocess.run(['python3',str(root/'preflight.py')],check=True)
pre=json.loads((root/'preflight.json').read_text()); exe=root/'dispatch-bench';before=hashlib.sha256(exe.read_bytes()).hexdigest()
cases=[r for r in pre['cases'] if r['timing_eligible']];rows=[]
report={'complete':False,'scope':'Private previous versus primary dispatcher in the same native binary; no public K1, complete C09, or full-compiler speed claim.','platform':platform.platform(),'affinity':sorted(os.sched_getaffinity(0)), 'goose':pre['goose_version'],'node':pre['node_version'],'binary_sha256':before,'dependency_file_sha256':pre['dependency_file_sha256'],'stdlib_file_sha256':pre['stdlib_file_sha256'],'goose_binary_sha256':pre['goose_binary_sha256'],'cc_path':pre['cc_path'],'cc_binary_sha256':pre['cc_binary_sha256'],'cc_version':pre['cc_version'],'generated_c_sha256':pre['generated_c_sha256'],'preflight_cases':pre['cases'],'batch_compilations':64,'warmup':a.warmup if a.measure else 0,'rounds':a.rounds if a.measure else 0,'samples':rows,'method':'same-binary mode switch, fresh process per sample, source read once and 64 compilations; exact bytes/status checked each iteration and output compared to preflight. Alternating case/order, warm filesystem. Primary-only successes excluded. Checks and I/O differ between dispatcher paths.'}
output=a.out/'results.json';save=lambda:output.write_text(json.dumps(report,indent=2)+'\n');save()
if a.measure:
 expected={}
 for case in cases:
  name=case['case'];src=root/'cases'/(name+'.blot')
  expected[name]=subprocess.run([str(exe),'previous',str(src),'once'],capture_output=True,check=True).stdout
  parts=expected[name].decode('ascii').rstrip('\n').split(' ',3)
  payload=bytes.fromhex(parts[3] if len(parts)>3 else '')
  if [int(parts[0]),int(parts[1]),int(parts[2])] != [case['previous_status'],case['argument'],case['result']]:raise RuntimeError('preflight result changed: '+name)
  if case['previous_status']==0 and hashlib.sha256(payload).hexdigest()!=case['wasm_sha256']:raise RuntimeError('preflight artifact changed: '+name)
  if case['previous_status']!=0 and payload:raise RuntimeError('failure produced bytes: '+name)
 for i in range(a.warmup+a.rounds):
  order=cases if i%2==0 else list(reversed(cases))
  for case in order:
   name=case['case'];src=root/'cases'/(name+'.blot')
   if hashlib.sha256(src.read_bytes()).hexdigest()!=case['source_sha256']:raise RuntimeError('source changed')
   for variant in (('previous','primary') if i%2==0 else ('primary','previous')):
    o=a.out/'child.stdout';e=a.out/'child.stderr'
    with o.open('wb') as stdout,e.open('wb') as stderr:
     start=time.perf_counter_ns();child=subprocess.Popen([str(exe),variant,str(src),'batch'],stdout=stdout,stderr=stderr);_,status,usage=os.wait4(child.pid,0);end=time.perf_counter_ns();child.returncode=os.waitstatus_to_exitcode(status)
    if child.returncode or o.read_bytes()!=expected[name]:raise RuntimeError('sample status/bytes changed for '+name+' '+variant)
    if i>=a.warmup:rows.append({'round':i-a.warmup,'global_round':i,'order':'previous-first' if i%2==0 else 'primary-first','case':name,'variant':variant,'wall_ms':(end-start)/1e6,'user_ms':usage.ru_utime*1000,'system_ms':usage.ru_stime*1000,'peak_rss_kib':usage.ru_maxrss})
if hashlib.sha256(exe.read_bytes()).hexdigest()!=before:raise RuntimeError('binary changed during run')
for name,expected in pre['dependency_file_sha256'].items():
 if hashlib.sha256((root/'k1'/name).read_bytes()).hexdigest()!=expected:raise RuntimeError('source snapshot changed: '+name)
report['complete']=True;save();print(output)
