#!/usr/bin/env python3
import os,pathlib,subprocess,tempfile
HERE=pathlib.Path(__file__).resolve().parent;G=os.environ.get('GOOSE','/tmp/k1-goose/build/goose');os.environ.setdefault('GOOSE_HOME','/tmp/k1-goose-home')
LEAF=lambda n:f'pub let f: U32 -> U32 ! {{}} resources {{depth: 1, frame: 0}} = fn x => return {n}\n'
MID='import "./leaf.blot" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return leaf.f(x)\n'
ROOT='import "./middle.blot" as middle\nimport "./leaf.blot" as leaf\nlet first: U32 -> U32 = fn x => return middle.f(x)\nlet second: U32 -> U32 = fn x => return leaf.f(x)\n'
SINGLE='pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    return x + 5\n  return x\n'
def run(exe,root,name='first',fault='none',depth='normal',path='main.blot'):
 return subprocess.run([str(exe),str(root),'pkg',path,name,fault,depth],capture_output=True,timeout=10)
def reject(r):assert r.returncode and not r.stdout,(r.returncode,len(r.stdout),r.stderr)
def exec_wasm(data,names):
 with tempfile.NamedTemporaryFile() as f:
  f.write(data);f.flush();js='const fs=require("fs"),e=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(process.argv[1]))).exports;for(const [n,v] of JSON.parse(process.argv[2]))if((e[n](0,2)>>>0)!==v)process.exit(1)';import json;subprocess.run(['node','-e',js,f.name,json.dumps(names)],check=True)
with tempfile.TemporaryDirectory(prefix='k1-semantic-graph-') as td:
 td=pathlib.Path(td);root=td/'root';root.mkdir();outside=td/'outside';outside.write_text(LEAF(99));
 for level in (0,2):
  exe=td/f'job{level}';subprocess.run([G,'build',f'-O{level}','-o',str(exe),str(HERE/'semantic_graph_fixture.goose')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  (root/'main.blot').write_text(SINGLE);a=run(exe,root,'f');assert a.returncode==0,a.stderr;exec_wasm(a.stdout,[['f',7]])
  (root/'main.blot').write_text(ROOT);(root/'middle.blot').write_text(MID);(root/'leaf.blot').write_text(LEAF(3));a=run(exe,root);assert a.returncode==0,a.stderr;exec_wasm(a.stdout,[['first',3],['second',3]])
  control=td/f'control{level}';subprocess.run([G,'build',f'-O{level}','-o',str(control),str(HERE/'semantic_graph_job_test.goose')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);subprocess.run([str(control),str(root)],check=True)
  (root/'leaf.blot').write_text(LEAF(7));b=run(exe,root);assert b.returncode==0 and b.stdout!=a.stdout;exec_wasm(b.stdout,[['first',7],['second',7]])
  for fault in ['after-read','after-check','after-emit','invalid']:reject(run(exe,root,fault=fault))
  reject(run(exe,root,depth='depth'));reject(run(exe,root,name='absent'));reject(run(exe,root,path='../outside'))
  # Wrong member and missing import fail closed.
  (root/'leaf.blot').write_text(LEAF(7).replace('pub let f:','pub let other:'));reject(run(exe,root))
  (root/'leaf.blot').unlink();reject(run(exe,root));(root/'leaf.blot').symlink_to(outside);reject(run(exe,root));(root/'leaf.blot').unlink()
  # Cyclic imports, duplicate alias, and argument/import shadowing reject.
  (root/'leaf.blot').write_text('import "./middle.blot" as middle\n'+LEAF(7));reject(run(exe,root))
  (root/'leaf.blot').write_text(LEAF(7));(root/'middle.blot').write_text('import "./leaf.blot" as leaf\nimport "./leaf.blot" as leaf\n'+MID.split('\n',1)[1]);reject(run(exe,root))
  (root/'middle.blot').write_text(MID.replace('fn x => return leaf.f(x)','fn leaf => return leaf.f(leaf)'));reject(run(exe,root))
  (root/'middle.blot').write_text(MID.replace('depth: 2','depth: 1'));reject(run(exe,root))
  print(f'O{level} leaf and multi-module graph/call identity, failures, cycle and execution passed')
