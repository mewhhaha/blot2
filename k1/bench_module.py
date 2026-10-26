#!/usr/bin/env python3
"""Paired cold-process timings for identical *private v3 fixture* work.

Not a qualified K1 benchmark or a legacy compiler comparison. Requires idle host.
"""
import hashlib,json,os,platform,resource,statistics,subprocess,sys,tempfile,time
from pathlib import Path
if len(sys.argv)!=4: raise SystemExit('usage: python3 bench.py BEFORE AFTER OUT.json')
before,after,out=[Path(s).resolve() for s in sys.argv[1:]]
for p in (before,after):
    if not p.is_file(): raise SystemExit(f'missing {p}')
sha=lambda x:hashlib.sha256(x).hexdigest()
def cpu_stat():
    return Path('/sys/fs/cgroup/cpu.stat').read_text()
def chain(n):
    return ''.join(f'let f{i}: U32 -> U32 = fn x => return '+(f'f{i+1}(x)' if i+1<n else 'x')+'\n' for i in range(n)).encode()
def leaves(n):
    return ''.join(f'let f{i}: U32 -> U32 = fn x => return x & {i}\n' for i in range(n)).encode()
cases={'chain1':chain(1),'chain16':chain(16),'chain64':chain(64),'chain128':chain(128),'leaves256':leaves(256),'comment1MiB':b'//'+b'a'*(1048576-3)+b'\n'+chain(1)}
def run(exe,p):
    prev=resource.getrusage(resource.RUSAGE_CHILDREN)
    t=time.perf_counter_ns(); x=subprocess.run([str(exe),'module-fixture',str(p)],stdout=subprocess.PIPE,stderr=subprocess.PIPE); dt=time.perf_counter_ns()-t
    now=resource.getrusage(resource.RUSAGE_CHILDREN)
    if x.returncode: raise RuntimeError(f'{exe} rejected {p}: {x.stderr.decode(errors="replace")}')
    return {'wall_ns':dt,'cpu_us':int(((now.ru_utime-prev.ru_utime)+(now.ru_stime-prev.ru_stime))*1e6),'output_sha256':sha(bytes.fromhex(x.stdout.decode('ascii')))}
start_cpu=cpu_stat(); reports={}
with tempfile.TemporaryDirectory(prefix='k1-perf-paired-') as d:
 p=Path(d)/'program.blot'
 for name,src in cases.items():
    p.write_bytes(src)
    witness=subprocess.run([str(before),'module-fixture',str(p)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
    wasm=Path(d)/'witness.wasm'; wasm.write_bytes(bytes.fromhex(witness.stdout.decode('ascii')))
    js='''const fs=require("fs");(async()=>{const f=(await WebAssembly.instantiate(fs.readFileSync(process.argv[1]))).instance.exports.f0;for(const x of [0,1,2147483647,2147483648,4294967295]){const want=process.argv[2]==="leaves256"?0:x;if((f(0,x)>>>0)!==want)throw Error("semantic witness failed "+x)}})().catch(e=>{console.error(e);process.exit(1)})'''
    subprocess.run(['node','-e',js,str(wasm),name],check=True)
    for i in range(4):
        a=run(before,p);b=run(after,p)
        if a['output_sha256']!=b['output_sha256']:raise RuntimeError('output mismatch during warmup '+name)
    rows=[]
    for i in range(31):
        a,b=(run(before,p),run(after,p)) if i%2==0 else (None,None)
        if i%2==1: b=run(after,p);a=run(before,p)
        if a['output_sha256']!=b['output_sha256']:raise RuntimeError('output mismatch '+name)
        rows.append({'before':a,'after':b})
    ratios=[r['after']['wall_ns']/r['before']['wall_ns'] for r in rows]
    ordered=sorted(ratios)
    reports[name]={'source_bytes':len(src),'source_sha256':sha(src),'median_before_ms':statistics.median(r['before']['wall_ns'] for r in rows)/1e6,'median_after_ms':statistics.median(r['after']['wall_ns'] for r in rows)/1e6,'median_paired_ratio_after_over_before':statistics.median(ratios),'paired_ratio_p10':ordered[int((len(ordered)-1)*.1)],'paired_ratio_p90':ordered[int((len(ordered)-1)*.9)],'samples':rows}
report={'scope':'paired fresh-process timings for the same private v3 experimental fixture, not comparison to legacy and not qualified K1','platform':platform.platform(),'node_version':subprocess.check_output(['node','--version'],text=True).strip(),'cpu_model':next((line.split(':',1)[1].strip() for line in Path('/proc/cpuinfo').read_text().splitlines() if line.startswith('model name')), 'unknown'),'cpu_affinity_count':len(os.sched_getaffinity(0)),'cpu_quota':Path('/sys/fs/cgroup/cpu.max').read_text().strip(),'before_sha256':sha(before.read_bytes()),'after_sha256':sha(after.read_bytes()),'warmups':4,'pairs':31,'cpu_stat_before':start_cpu,'cpu_stat_after':cpu_stat(),'cases':reports}
out.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({name:{k:v for k,v in x.items() if k.startswith('median')} for name,x in reports.items()},indent=2))
