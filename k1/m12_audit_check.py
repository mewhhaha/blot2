#!/usr/bin/env python3
"""Verify complete query set with an explicitly selected external solver."""
import argparse,hashlib,json,subprocess,sys,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--queries',type=Path,required=True);p.add_argument('--target',type=Path,required=True);p.add_argument('--solver',required=True);p.add_argument('--solver-arg',action='append',default=[]);a=p.parse_args()
try:
 manifest=json.loads((a.queries/'manifest.json').read_text())
 with tempfile.TemporaryDirectory() as tmp:
  generated=Path(tmp)/'queries'
  subprocess.run([sys.executable,str(Path(__file__).resolve().parent/'m12_audit_emit.py'),'--target',str(a.target),'--out',str(generated)],capture_output=True,text=True,check=True)
  expected=json.loads((generated/'manifest.json').read_text())
  if manifest!=expected:raise ValueError('query manifest differs from regenerated source-bound manifest')
  for q in expected['queries']:
   path=a.queries/q['file']
   if path.parent!=a.queries or path.name!=q['file']:raise ValueError('invalid path')
   if hashlib.sha256(path.read_bytes()).hexdigest()!=q['sha256']:raise ValueError('query content mismatch: '+path.name)
   r=subprocess.run([a.solver,*a.solver_arg,str(path)],capture_output=True,text=True,timeout=60)
   if r.returncode!=0 or r.stdout.strip()!=q['expect']:
    raise ValueError(f'{path.name}: expected {q["expect"]}; rc={r.returncode} output={r.stdout.strip()!r} error={r.stderr.strip()!r}')
except (OSError,ValueError,KeyError,subprocess.SubprocessError) as e:
 print(f'FAIL: {e}',file=sys.stderr);sys.exit(1)
print(f'All {len(expected["queries"])} source-bound queries matched their expected sat/unsat results.')
