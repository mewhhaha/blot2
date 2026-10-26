#!/usr/bin/env python3
"""Private source-bound cross-module checker integration fixtures."""
import os
import pathlib
import subprocess
import sys
import tempfile
HERE=pathlib.Path(__file__).resolve().parent
GOOSE=os.environ.get('GOOSE','goose')
def main():
 with tempfile.TemporaryDirectory(prefix='k1-link-check-') as tmp:
  tmp=pathlib.Path(tmp)
  if sys.platform!='linux':
   exe=tmp/'unsupported'
   subprocess.run([GOOSE,'build','-O2','-o',str(exe),str(HERE/'project_probe_platform_test.goose')],check=True,stdout=subprocess.DEVNULL)
   subprocess.run([str(exe)],check=True)
   print('private link fixtures skipped; unsupported source adapters failed closed')
   return
  for level in (0,2):
   root=tmp/f'root{level}';other=tmp/f'other{level}';root.mkdir();other.mkdir()
   (root/'main.blot').write_text('import "./lib.blot" as lib\nlet caller: U32 -> U32 = fn x => return lib.f(x)\n')
   (root/'lib.blot').write_text('pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n')
   forged=tmp/f'link-forged-{level}'
   subprocess.run([GOOSE,'build',f'-O{level}','-o',str(forged),str(HERE/'link_forged_graph_test.goose')],check=True,stdout=subprocess.DEVNULL)
   subprocess.run([str(forged),str(root)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=30)
   exe=tmp/f'link-{level}'
   subprocess.run([GOOSE,'build',f'-O{level}','-o',str(exe),str(HERE/'link_check_test.goose')],check=True,stdout=subprocess.DEVNULL)
   result=subprocess.run([str(exe),str(root),str(other)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
   assert result.returncode==0,(level,result.stdout,result.stderr)
 print('private cross-module semantic observation tests passed at O0/O2')
if __name__=='__main__':main()
