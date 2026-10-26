import os,pathlib,subprocess,tempfile,sys
here=pathlib.Path(__file__).resolve().parent
goose=os.environ.get('GOOSE','goose')
if sys.platform!='linux':
 with tempfile.TemporaryDirectory(prefix='k1-multilink-unsupported-') as td:
  exe=pathlib.Path(td)/'unsupported'
  subprocess.run([goose,'build','-O2','-o',str(exe),str(here/'project_probe_platform_test.goose')],check=True)
  subprocess.run([str(exe)],check=True)
 print('multi-entry fixtures skipped; unsupported source adapters failed closed')
 sys.exit(0)
with tempfile.TemporaryDirectory(prefix='k1-multilink-') as td:
 td=pathlib.Path(td)
 for level in (0,2):
  root=td/f'root{level}';out=td/f'out{level}';root.mkdir();out.mkdir()
  (root/'main.blot').write_text('import "./lib.blot" as lib\nimport "./other.blot" as other\nlet first: U32 -> U32 = fn x => return lib.f(x)\nlet second: U32 -> U32 = fn y => return other.g(y)\nlet third: U32 -> U32 = fn z => return other.h(z)\n')
  (root/'lib.blot').write_text('pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n')
  (root/'other.blot').write_text('pub let g: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 42\npub let h: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x & 255\n')
  exe=td/f'test-{level}'
  subprocess.run([goose,'build',f'-O{level}','-o',str(exe),str(here/'multilink_test.goose')],check=True)
  subprocess.run([str(exe),str(root)],cwd=out,check=True)
  subprocess.run(['node',str(here/'multilink_test.mjs')],cwd=out,check=True)
print('multi-entry linked fixture passed O0/O2 and Node')
