import os,pathlib,subprocess,tempfile,sys
here=pathlib.Path(__file__).resolve().parent
goose=os.environ.get('GOOSE','goose')
if sys.platform!='linux':
 with tempfile.TemporaryDirectory(prefix='k1-chain-unsupported-') as td:
  exe=pathlib.Path(td)/'unsupported'
  subprocess.run([goose,'build','-O2','-o',str(exe),str(here/'project_probe_platform_test.goose')],check=True)
  subprocess.run([str(exe)],check=True)
 print('call-chain fixture skipped; unsupported source adapters failed closed')
 sys.exit(0)
with tempfile.TemporaryDirectory(prefix='k1-chain-') as td:
 td=pathlib.Path(td)
 for level in (0,2):
  root=td/f'root{level}';out=td/f'out{level}';root.mkdir();out.mkdir()
  (root/'main.blot').write_text('import "./middle.blot" as middle\nimport "./leaf.blot" as leaf\nlet first: U32 -> U32 = fn x => return middle.f(x)\nlet second: U32 -> U32 = fn x => return leaf.f(x)\n')
  (root/'middle.blot').write_text('import "./leaf.blot" as leaf\npub let f: U32 -> U32 ! {} resources {depth: 2, frame: 0} = fn x => return leaf.f(x)\n')
  (root/'leaf.blot').write_text('pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x & 255\n')
  exe=td/f'test-{level}'
  subprocess.run([goose,'build',f'-O{level}','-o',str(exe),str(here/'chain_test.goose')],check=True)
  subprocess.run([str(exe),str(root)],cwd=out,check=True)
  subprocess.run(['node',str(here/'chain_test.mjs')],cwd=out,check=True)
print('multi-module chain fixture passed O0/O2 and Node')
