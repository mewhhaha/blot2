import json,os,shutil,subprocess,sys,tempfile
from pathlib import Path
here=Path(__file__).resolve().parent;target=Path(sys.argv[1]);queries=Path(sys.argv[2]);check=here/'m12_audit_check.py'
with tempfile.TemporaryDirectory() as temp:
 root=Path(temp);fake=root/'unknown-solver';fake.write_text('#!/bin/sh\nprintf "unknown\\n"\n');fake.chmod(0o755)
 for name in ['missing','changed','manifest','unknown']:
  q=root/name;shutil.copytree(queries,q);m=json.loads((q/'manifest.json').read_text());f=q/m['queries'][0]['file']
  if name=='missing':f.unlink()
  if name=='changed':f.write_text(f.read_text()+'; altered\n')
  if name=='manifest':m['queries'].pop();(q/'manifest.json').write_text(json.dumps(m))
  solver=str(fake)
  r=subprocess.run([sys.executable,str(check),'--target',str(target),'--queries',str(q),'--solver',solver],capture_output=True,text=True)
  if r.returncode==0:raise AssertionError(name+' accepted')
  print(name,'rejected')
