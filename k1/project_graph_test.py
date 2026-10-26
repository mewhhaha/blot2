#!/usr/bin/env python3
"""Private descriptor-root project graph and failure-injection fixtures."""
import ctypes
import os
import pathlib
import subprocess
import sys
import tempfile
import threading

HERE=pathlib.Path(__file__).resolve().parent
GOOSE=os.environ.get('GOOSE','goose')

def setup(root,outside):
 root.mkdir();outside.mkdir();(root/'sub').mkdir()
 (root/'main.blot').write_text('import "./a.blot" as a\nimport "./b.blot" as b\nlet f: U32 -> U32 = fn x => return x\n')
 for name in ('a','b'):
  (root/f'{name}.blot').write_text(f'import "./shared.blot" as s\nlet {name}: U32 -> U32 = fn x => return x\n')
 (root/'shared.blot').write_text('let g: U32 -> U32 = fn x => return x\n')
 (root/'sub'/'child.blot').write_text('import "../shared.blot" as s\nlet x: U32 = 1\n')
 (root/'cycle.blot').write_text('import "./cycle.blot" as self\n')
 (root/'dup.blot').write_text('import "./a.blot" as a\nimport "./b.blot" as a\n')
 (root/'bad-import.blot').write_text('let x: U32 = 1\nimport "./a.blot" as a\n')
 (root/'escape.blot').write_text('import "./escape-link.blot" as a\n')
 (outside/'secret.blot').write_text('let secret: U32 = 1\n')
 (root/'escape-link.blot').symlink_to('../outside/secret.blot')
 os.mkfifo(root/'fifo')
 for prefix,count in [('n',65),('m',64)]:
  for i in range(count):
   text=f'import "./{prefix}{i+1}.blot" as child\n' if i+1<count else 'let end: U32 = 0\n'
   (root/f'{prefix}{i}.blot').write_text(text)
 for count in (256,257):
  text=''.join(f'import "./shared.blot" as a{i}\n' for i in range(count))
  (root/f'edges{count}.blot').write_text(text)

def race(root, outside, executable):
 source=b'import "./slot/secret.blot" as s\nlet x: U32 = 0\n'
 inside=b'let value: U32 = 1\n'
 (root/'race.blot').write_bytes(source)
 slot=root/'slot';slot.mkdir();(slot/'secret.blot').write_bytes(inside)
 swap=root/'slot-swap';swap.symlink_to('../'+outside.name,target_is_directory=True)
 libc=ctypes.CDLL(None,use_errno=True); exchange=getattr(libc,'renameat2',None)
 if exchange is None:
  print('project rename-exchange race skipped: renameat2 unavailable');return
 exchange.argtypes=[ctypes.c_int,ctypes.c_char_p,ctypes.c_int,ctypes.c_char_p,ctypes.c_uint]
 exchange.restype=ctypes.c_int
 a,b=os.fsencode(slot),os.fsencode(swap)
 if exchange(-100,a,-100,b,2)!=0:
  print(f'project rename-exchange race skipped: errno {ctypes.get_errno()}');return
 stop=threading.Event();count=[1];errors=[]
 def toggle():
  while not stop.is_set():
   if exchange(-100,a,-100,b,2)!=0: errors.append(ctypes.get_errno());return
   count[0]+=1
 thread=threading.Thread(target=toggle);thread.start()
 try:
  for _ in range(200):
   result=subprocess.run([str(executable),str(root)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=10)
   if result.returncode==0: assert result.stdout==source+inside,'graph read escaped its root or published a mixed module'
   else: assert result.stdout==b'','failed graph published partial bytes'
 finally:
  stop.set();thread.join()
 assert not errors and count[0]>1,(errors,count)
 print(f'project path race: 200 graph attempts, {count[0]} rename exchanges')

def main():
 with tempfile.TemporaryDirectory(prefix='k1-project-graph-') as d:
  d=pathlib.Path(d)
  if sys.platform!='linux':
   unsupported=d/'project-platform-unsupported'
   subprocess.run([GOOSE,'build','-O2','-o',str(unsupported),str(HERE/'project_probe_platform_test.goose')],
                  check=True,stdout=subprocess.DEVNULL)
   subprocess.run([str(unsupported)],check=True)
   print('Linux-only project graph and race fixtures skipped; unsupported host adapters failed closed')
   return
  for level in (0,2):
   root=d/f'root{level}'; other=d/f'other{level}'; outside=d/'outside'
   if not outside.exists(): outside.mkdir()
   # Each resolver must see its own root and a sibling "outside".
   setup(root,d/f'outside{level}'); other.mkdir()
   (root/'escape-link.blot').unlink(); (root/'escape-link.blot').symlink_to(f'../outside{level}/secret.blot')
   exe=d/f'project-graph-{level}'
   subprocess.run([GOOSE,'build',f'-O{level}','-o',str(exe),str(HERE/'project_graph_test.goose')],check=True,stdout=subprocess.DEVNULL)
   result=subprocess.run([str(exe),str(root),str(other)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
   assert result.returncode==0,(level,result.stdout,result.stderr)
   subprocess.run([GOOSE,'--debug',f'-O{level}',str(HERE/'project_imports_test.goose')],check=True,stdout=subprocess.DEVNULL)
  cc=os.environ.get('CC','cc'); fault=d/'probe-fault'
  subprocess.run([cc,'-std=c11',str(HERE/'project_probe.c'),str(HERE/'project_probe_fault_test.c'),
                  '-Wl,--wrap=syscall','-o',str(fault)],check=True,stdout=subprocess.DEVNULL)
  subprocess.run([str(fault),str(d/'root0')],check=True)
  unsupported=d/'probe-unsupported'
  subprocess.run([cc,'-std=c11','-Wall','-Wextra','-Werror','-U__linux__',str(HERE/'project_probe.c'),
                  str(HERE/'project_probe_unsupported_test.c'),'-o',str(unsupported)],check=True,stdout=subprocess.DEVNULL)
  subprocess.run([str(unsupported)],check=True)
  race_exe=d/'project-race'
  subprocess.run([GOOSE,'build','-O2','-o',str(race_exe),str(HERE/'project_graph_race.goose')],check=True,stdout=subprocess.DEVNULL)
  race(d/'root0',d/'outside0',race_exe)
 print('private project graph, observation and revision tests passed at O0/O2')

if __name__=='__main__': main()
