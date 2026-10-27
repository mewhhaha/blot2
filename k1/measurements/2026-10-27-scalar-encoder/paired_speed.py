#!/usr/bin/env python3
"""Paired private scheduled-scalar experiment, not a full compiler benchmark."""
import argparse,hashlib,json,os,subprocess,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--rounds',type=int,default=25);p.add_argument('--warmup',type=int,default=3);p.add_argument('--out',required=True,type=Path);a=p.parse_args()
if a.rounds<1 or a.warmup<0:p.error('invalid rounds')
root=Path('/tmp/k1-speed-exp');corpus=root/'corpus';base=b'let f: U32 -> U32 = fn x => return x\n// '
(corpus/'medium_ascii.blot').write_bytes(base+b'a'*16384+b'\n')
(corpus/'dense_utf8.blot').write_bytes(base+('é'.encode()*524288)+b'\n')
(corpus/'mixed_utf8.blot').write_bytes(base+((b'a'*6+'é'.encode())*131072)+b'\n')
(corpus/'long_name.blot').write_bytes(b'let '+b'f'*1048576+b': U32 -> U32 = fn x => return x\n')
cases={'short':corpus/'identity.blot','medium':corpus/'medium_ascii.blot','long':corpus/'long_ascii.blot','dense':corpus/'dense_utf8.blot','mixed':corpus/'mixed_utf8.blot','name':corpus/'long_name.blot'}
binpaths={x:root/(x+'-speed') for x in ('before','after')}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
hashes={k:sha(v) for k,v in binpaths.items()}; source={k:sha(v) for k,v in cases.items()};results=[];outputs={}
report={'complete':False,'scope':'Repeated private scheduled scalar compilations; optimized UTF-8 ASCII detection only; not a full compiler, ABI, C09 or cross-language performance comparison.', 'affinity':sorted(os.sched_getaffinity(0)),'binaries':hashes,'sources':source,'rounds':a.rounds,'warmup':a.warmup,'samples':results,'outputs':outputs}
a.out.write_text(json.dumps(report,indent=2))
for n in range(a.rounds+a.warmup):
 ordercases=list(cases) if n%2==0 else list(reversed(cases))
 for case in ordercases:
  for variant in (('before','after') if n%2==0 else ('after','before')):
   tmp=root/'child.stdout';err=root/'child.stderr'
   with tmp.open('wb') as o,err.open('wb') as e:
    start=time.perf_counter_ns();child=subprocess.Popen([str(binpaths[variant]),str(cases[case]),case],stdout=o,stderr=e);_,status,ru=os.wait4(child.pid,0);end=time.perf_counter_ns();child.returncode=os.waitstatus_to_exitcode(status)
   if child.returncode:raise RuntimeError(f'{case}/{variant} exit {child.returncode}: {err.read_text()}')
   out=tmp.read_text().strip()
   if case in outputs and outputs[case]!=out:raise RuntimeError(f'output/semantic counter mismatch: {case}')
   outputs[case]=out
   if n>=a.warmup:results.append({'round':n-a.warmup,'case':case,'variant':variant,'wall_ms':(end-start)/1e6,'user_ms':ru.ru_utime*1000,'system_ms':ru.ru_stime*1000,'peak_rss_kib':ru.ru_maxrss})
if {k:sha(v) for k,v in binpaths.items()}!=hashes or {k:sha(v) for k,v in cases.items()}!=source:raise RuntimeError('binary or source changed during experiment')
report['complete']=True;a.out.write_text(json.dumps(report,indent=2)+'\n');print(a.out)
