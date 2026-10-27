#!/usr/bin/env python3
import os,pathlib,subprocess,tempfile
G=os.environ.get('GOOSE','/tmp/k1-goose/build/goose');HOME=os.environ.get('GOOSE_HOME','/tmp/k1-goose-home'); HERE=pathlib.Path(__file__).resolve().parent
os.environ['GOOSE_HOME']=HOME
S=lambda n:f'pub let f: U32 -> U32 ! {{}} resources {{depth: 1, frame: 0}} = fn x => do:\n  return U32.wrapping_add(x,{n})\n'.encode()
def call(exe,root,module='main.blot',name='f',fault='none',depth='normal',package='pkg'):
 return subprocess.run([str(exe),str(root),package,module,name,fault,depth],capture_output=True,timeout=10)
def reject(r):assert r.returncode and not r.stdout,(r.returncode,len(r.stdout),r.stderr)
with tempfile.TemporaryDirectory(prefix='k1-semantic-job-') as d:
 root=pathlib.Path(d)/'root';root.mkdir();outside=pathlib.Path(d)/'outside.blot';outside.write_bytes(S(99));(root/'main.blot').write_bytes(S(1));(root/'bad.blot').write_bytes(b'\xff');(root/'empty.blot').write_bytes(b'');(root/'escape.blot').symlink_to(outside);(root/'inside.blot').symlink_to('main.blot');(root/'outside-dir').symlink_to('..',target_is_directory=True)
 for level in (0,2):
  exe=pathlib.Path(d)/f'job-{level}';subprocess.run([G,'build',f'-O{level}','-o',str(exe),str(HERE/'semantic_job_fixture.goose')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
  first=call(exe,root);assert first.returncode==0 and first.stdout[:8]==b'\0asm\1\0\0\0',(first.returncode,first.stderr)
  inside=call(exe,root,'inside.blot');assert inside.returncode==0 and inside.stdout==first.stdout
  for module,name in [('escape.blot','f'),('../outside.blot','f'),('/tmp/outside.blot','f'),('outside-dir/outside.blot','f'),('missing.blot','f'),('bad.blot','f'),('empty.blot','f'),('main.blot','other')]:reject(call(exe,root,module,name))
  for fault in ('after-read','after-check','after-emit','invalid'):reject(call(exe,root,fault=fault))
  reject(call(exe,root,depth='depth'));reject(call(exe,root,package=''))
  (root/'main.blot').write_bytes(S(2));second=call(exe,root);assert second.returncode==0 and second.stdout!=first.stdout
  (root/'main.blot').write_bytes(S(1));again=call(exe,root);assert again.returncode==0 and again.stdout==first.stdout
  offset=b'pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    return x + 5\n  return x\n';(root/'main.blot').write_bytes(offset);checked=call(exe,root);assert checked.returncode==0 and checked.stdout!=first.stdout;offset_path=pathlib.Path(d)/'offset.wasm';offset_path.write_bytes(checked.stdout)
  subprocess.run(['node','-e','const f=new WebAssembly.Instance(new WebAssembly.Module(require("fs").readFileSync(process.argv[1]))).exports.f;if((f(0,4294967290)>>>0)!==4294967295||(f(0,4294967291)>>>0)!==4294967291)process.exit(1)',str(offset_path)],check=True)
  (root/'main.blot').write_bytes(S(1))
  a=pathlib.Path(d)/'a.wasm';b=pathlib.Path(d)/'b.wasm';a.write_bytes(first.stdout);b.write_bytes(second.stdout)
  js='const fs=require("fs");for(const [p,w] of [[process.argv[1],8],[process.argv[2],9]]){let m=new WebAssembly.Instance(new WebAssembly.Module(fs.readFileSync(p)));if((m.exports.f(0,7)>>>0)!==w)process.exit(1)}'
  subprocess.run(['node','-e',js,str(a),str(b)],check=True)
  print(f'O{level} resolver-bound source/identity, paths, staged failures and changed-source execution passed')
