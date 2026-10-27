#!/usr/bin/env python3
"""Emit, but do not solve, conditional fixed-helper counterexample queries."""
import argparse,hashlib,json,subprocess,tempfile
from pathlib import Path
from copy import deepcopy
from m12_audit_symbolic import execute,contract,land,lor,ne,eq,B
P=Path(__file__).resolve().parent
PRE='(set-option :timeout 30000)\n(set-logic QF_AUFBV)\n(declare-const M (Array (_ BitVec 32) (_ BitVec 32)))\n'+'\n'.join(f'(declare-const {v} (_ BitVec 32))' for v in ['slot','gen','arg','owner','close_result'])+'\n(declare-const close_mem (Array (_ BitVec 32) (_ BitVec 32)))\n'
def digest(data):return hashlib.sha256(data).hexdigest()
def equiv(ops,f,good):
 paths=execute(ops,good);base,ref,mem=contract(f,good)
 bad=[land(*p,lor(ne(r,ref),ne(m,mem))) for p,r,m in paths]
 return f'(assert {base})\n(assert {lor(*bad)})\n'
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--target',type=Path,required=True);parser.add_argument('--out',type=Path,required=True);a=parser.parse_args()
 if a.out.exists() and any(a.out.iterdir()):raise SystemExit('output directory must be empty')
 a.out.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory() as temp:
  p=Path(temp)/'bodies.json';subprocess.run(['node',str(P/'m12_audit_extract.mjs'),str(a.target),str(p)],check=True)
  source=p.read_bytes();ops=json.loads(source)
 manifest={'format':'private-helper-smt-v1','target_sha256':digest(a.target.read_bytes()),'decoded_sha256':digest(source),'queries':[]}
 def emit(name,form,expected):
  data=(PRE+form+'(check-sat)\n').encode();path=a.out/(name+'.smt2');path.write_bytes(data)
  manifest['queries'].append({'file':path.name,'sha256':digest(data),'expect':expected})
 for f in (1,4,5,6,8,11,12,13):
  for good in ((True,) if f in (1,4) else (False,True)):
   emit(f'helper_{f}_owner_{int(good)}',equiv(ops[str(f)],f,good),'unsat')
 _,owner,_=contract(4,True)
 for f in (5,6,8,11,12,13):
  base,_,_=contract(f,True);emit(f'composition_{f}',f'(assert {land(ne(owner,B(0)),eq("owner",owner),f"(not {base})")})\n','unsat')
 for f in (5,6,8,11,12,13):
  base,ret,_=contract(f,True)
  for value in ([0,-4,-1,-2] if f in (5,8) else [0,-4]):emit(f'nonvacuity_{f}_{value}',f'(assert {base})\n(assert {eq(ret,B(value))})\n','sat')
  mutated=deepcopy(ops[str(f)])
  if f==11:
   i=next(i for i,x in enumerate(mutated) if x['op']==0x46);mutated[i]['op']=0x47
  else:
   i=next(i for i,x in enumerate(mutated) if x['op']==0x36);mutated[i]['imm']['offset']+=4
  emit(f'mutation_{f}',equiv(mutated,f,True),'sat')
 for f in (1,4):
  _,ret,_=contract(f,True)
  for value in (0,1):
   cond=eq(ret,B(0)) if value==0 else ne(ret,B(0))
   emit(f'nonvacuity_{f}_{value}',f'(assert {cond})\n','sat')
 mutated=deepcopy(ops['4']);i=next(i for i,x in enumerate(mutated) if x['op']==0x41 and x.get('imm')==4);mutated[i]['imm']=5
 emit('mutation_4',equiv(mutated,4,True),'sat')
 for name in ('bitmap','retirement'):
  mutated=deepcopy(ops['1'])
  if name=='bitmap':
   i=next(i for i,x in enumerate(mutated) if x['op']==0x36);mutated[i]['imm']['offset']=4
  else:
   indices=[i for i,x in enumerate(mutated) if x['op']==0x41 and x.get('imm')==3];assert len(indices)==1;mutated[indices[0]]['imm']=0
  emit('mutation_close_'+name,equiv(mutated,1,True),'sat')
 (a.out/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
 print(f'Generated {len(manifest["queries"])} SMT-LIB queries in {a.out}; no solver has been run.')
if __name__=='__main__':main()
