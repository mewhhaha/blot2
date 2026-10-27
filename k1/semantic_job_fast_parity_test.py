import os,subprocess,pathlib,tempfile
G=os.environ.get('GOOSE','/tmp/k1-goose/build/goose'); os.environ.setdefault('GOOSE_HOME','/tmp/k1-goose-home')
p=pathlib.Path(__file__).resolve().parent
sources=[
 b'pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n',
 b'pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x && #True\n',
 b'pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    return x + 5\n  return x\n',
 b'pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return total\n',
 b'pub let f: U32 -> U32 ! {host} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n', b'\xff']
with tempfile.TemporaryDirectory() as d:
 d=pathlib.Path(d);root=d/'root';root.mkdir()
 for opt in (0,2):
  ex=[]
  for kind in ('semantic_job_baseline_fixture','semantic_job_fixture'):
   out=d/f'{kind}-{opt}';subprocess.run([G,'build',f'-O{opt}','-o',str(out),str(p/f'{kind}.goose')],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE);ex.append(out)
  def compare(module='main.blot',name='f',fault='none',depth='normal'):
   x=[subprocess.run([str(e),str(root),'pkg',module,name,fault,depth],capture_output=True,timeout=10) for e in ex]
   assert (x[0].returncode,x[0].stdout)==(x[1].returncode,x[1].stdout),(module,name,fault,depth,x[0].returncode,x[1].returncode)
   if x[0].returncode: assert not x[0].stdout
   return x[0]
  for i,s in enumerate(sources):
   (root/'main.blot').write_bytes(s);x=compare();assert (x.returncode==0)==(i<4)
   if i<4:
    for fault in ('after-read','after-check','after-emit','invalid'):assert compare(fault=fault).returncode
    assert compare(depth='depth').returncode
    assert compare(name='wrong').returncode
  assert compare(module='../outside.blot').returncode
  print(f'O{opt} baseline/fast resolver job exact status and output parity passed')
