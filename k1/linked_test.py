#!/usr/bin/env python3
import os,pathlib,subprocess,sys,tempfile
HERE=pathlib.Path(__file__).resolve().parent
GOOSE=os.environ.get('GOOSE','goose')
if sys.platform!='linux':
 with tempfile.TemporaryDirectory(prefix='k1-linked-unsupported-') as td:
  exe=pathlib.Path(td)/'unsupported'
  subprocess.run([GOOSE,'build','-O2','-o',str(exe),str(HERE/'project_probe_platform_test.goose')],check=True,stdout=subprocess.DEVNULL)
  subprocess.run([str(exe)],check=True)
 print('private linked scalar fixtures skipped; unsupported source adapters failed closed');sys.exit(0)
with tempfile.TemporaryDirectory(prefix='k1-linked-scalar-') as td:
 td=pathlib.Path(td)
 for level in (0,2):
  root=td/f'root{level}';out=td/f'out{level}';root.mkdir();out.mkdir()
  (root/'main.blot').write_text('import "./lib.blot" as lib\nlet caller: U32 -> U32 = fn x => return lib.f(x)\n')
  (root/'lib.blot').write_text('pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n')
  exe=td/f'linked-{level}'
  subprocess.run([GOOSE,'build',f'-O{level}','-o',str(exe),str(HERE/'linked_test.goose')],check=True,stdout=subprocess.DEVNULL)
  subprocess.run([str(exe),str(root)],cwd=out,check=True,stdout=subprocess.DEVNULL)
  subprocess.run(['node',str(HERE/'linked_test.mjs')],cwd=out,check=True,stdout=subprocess.DEVNULL)
print('private linked scalar source/target/revision execution passed at O0/O2')
