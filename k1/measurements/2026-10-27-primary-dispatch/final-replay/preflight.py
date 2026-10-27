#!/usr/bin/env python3
"""Exact compatibility preflight; deliberately records no performance timing."""
import hashlib,json,subprocess,shutil
from pathlib import Path
root=Path(__file__).resolve().parent; exe=root/'dispatch-bench'; out=root/'artifacts';out.mkdir(exist_ok=True)
def sha(data):return hashlib.sha256(data).hexdigest()
def command(mode,path):
 r=subprocess.run([str(exe),mode,str(path),'once'],capture_output=True,check=True)
 fields=r.stdout.decode('ascii').rstrip('\n').split(' ',3);status,argument,result=map(int,fields[:3]);raw=bytes.fromhex(fields[3] if len(fields)>3 else '')
 if status!=0 and raw:raise RuntimeError('failure returned Wasm bytes')
 return {'status':status,'argument':argument,'result':result,'wasm':raw}
sources=sorted((root/'cases').glob('*.blot'));rows=[]
for path in sources:
 a,b=command('previous',path),command('primary',path)
 if a['status']==0 and a!=b:raise RuntimeError('old success lost byte/metadata parity: '+path.stem)
 if a['status']!=0 and b['status']!=0 and a!=b:raise RuntimeError('rejection status/bytes mismatch: '+path.stem)
 if path.stem.startswith('invalid_') and (a['status']==0 or b['status']==0):raise RuntimeError('invalid accepted: '+path.stem)
 if not path.stem.startswith('invalid_') and b['status']!=0:raise RuntimeError('primary rejected positive: '+path.stem)
 both=a['status']==0 and b['status']==0;new=a['status']!=0 and b['status']==0
 row={'case':path.stem,'source_sha256':sha(path.read_bytes()),'previous_status':a['status'],'primary_status':b['status'],'argument':b['argument'],'result':b['result'],'identical':a==b,'class':'both_accepted' if both else 'primary_only' if new else 'both_rejected','timing_eligible':bool(both or (a['status']!=0 and b['status']!=0))}
 if b['status']==0:
  (out/(path.stem+'.wasm')).write_bytes(b['wasm']);row['wasm_sha256']=sha(b['wasm']);row['wasm_bytes']=len(b['wasm'])
  witness=subprocess.run(['node',str(root/'witness.mjs'),str(out),path.stem],capture_output=True,text=True,check=True);row['witness']=json.loads(witness.stdout)
 rows.append(row)
sourcefiles={p.name:sha(p.read_bytes()) for p in sorted((root/'k1').glob('*.goose'))}
stdlib=Path('/tmp/k1-goose/stdlib');stdlibfiles={str(p.relative_to(stdlib)):sha(p.read_bytes()) for p in sorted(stdlib.rglob('*')) if p.is_file()}
cc=Path(shutil.which('cc')).resolve();generated=Path('/tmp/k1-goose-home/build/prog/dispatch_bench_driver-67db7183/dispatch_bench_driver.c')
report={'description':'Exact private dispatcher compatibility preflight; no performance measurements or public K1 qualification.', 'driver_sha256':sha(exe.read_bytes()),'driver_source_sha256':sha((root/'k1'/'dispatch_bench_driver.goose').read_bytes()),'goose_version':subprocess.check_output(['/tmp/k1-goose/build/goose','version'],text=True).strip(),'node_version':subprocess.check_output(['node','--version'],text=True).strip(),'dependency_file_sha256':sourcefiles,'stdlib_file_sha256':stdlibfiles,'goose_binary_sha256':sha(Path('/tmp/k1-goose/build/goose').read_bytes()),'cc_path':str(cc),'cc_binary_sha256':sha(cc.read_bytes()),'cc_version':subprocess.check_output([str(cc),'--version'],text=True).splitlines()[0],'generated_c_sha256':sha(generated.read_bytes()),'note':'Whole copied .goose snapshot and local standard-library files hashed; OS/runtime libraries and build provenance are not attested. Primary-only successes excluded from paired timings.','cases':rows}
(root/'preflight.json').write_text(json.dumps(report,indent=2)+'\n')
for r in rows:print(r['case'],r['class'],'prior status',r['previous_status'],'primary status',r['primary_status'],'exact',r['identical'])
