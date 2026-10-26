import os, pathlib, random, subprocess, tempfile
HERE=pathlib.Path(__file__).resolve().parent
rng=random.Random(3737)
NAMES=['original','condition','a','b','c','d','e','f','g','r','p','out','inner','item']
class Bad(Exception): pass
class Stop(Exception):
 def __init__(self,kind,value=None): self.kind,self.value=kind,value
class Machine:
 def __init__(self,flag,mode):
  self.flag,self.mode=flag,mode; self.frames=[{'original':['owned',True], 'condition':['bool',False]}]; self.loans=[]
 def lookup(self,n):
  for frame in reversed(self.frames):
   if n in frame:return frame[n]
  raise Bad()
 def bind(self,n,value):
  if any(n in f for f in self.frames):raise Bad()
  self.frames[-1][n]=value
 def owner(self,n):
  v=self.lookup(n)
  if v[0]!='owned' or not v[1]:raise Bad()
  return v
 def block(self,seq,scoped=True):
  if scoped:self.frames.append({})
  try:
   for stmt in seq:self.stmt(stmt)
  finally:
   if scoped:
    frame=self.frames.pop()
    if any(v[0]=='owned' and v[1] for v in frame.values()):raise Bad()
 def stmt(self,s):
  k=s[0]
  if k=='move':
   if self.loans:raise Bad()
   old=self.owner(s[2]);self.bind(s[1],['owned',True]);old[1]=False
  elif k=='close':
   if self.loans:raise Bad()
   self.owner(s[1])[1]=False
  elif k=='return':
   if self.loans:raise Bad()
   value=s[1]
   if value=='()':
    if self.mode!=0 or any(v[0]=='owned' and v[1] for f in self.frames for v in f.values()):raise Bad()
   else:
    v=self.lookup(value)
    if self.mode==1 and v[0]=='owned' and v[1]:v[1]=False
    elif self.mode==2 and v[0]=='scalar' and not any(v[0]=='owned' and v[1] for f in self.frames for v in f.values()):pass
    else:raise Bad()
   raise Stop('return')
  elif k=='break':
   if not self.loans or s[1]!=self.loans[-1] or self.lookup(s[1])[0]!='payload':raise Bad()
   raise Stop('break',s[1])
  elif k=='if':
   branch=s[1] if self.flag else s[2]
   if branch is not None:self.block(branch)
  elif k=='open':
   out,ref,reg,payload,inner=s[1:];self.owner(ref)
   if len({out,reg,payload})!=3 or any(any(n in f for f in self.frames) for n in (out,reg,payload)):raise Bad()
   self.frames.append({reg:['region',False],payload:['payload',False]});self.loans.append(payload)
   try:
    try:self.block(inner,False)
    except Stop as stop:
     if stop.kind!='break' or stop.value!=payload:raise Bad()
    else:raise Bad()
   finally:self.loans.pop();self.frames.pop()
   self.bind(out,['scalar',False])
  else:raise AssertionError(k)
 def run(self,program):
  try:self.block(program)
  except Stop as stop:
   if stop.kind!='return':raise Bad()
  else:raise Bad()

def render(seq,depth=1):
 out=[];pad='  '*depth
 for s in seq:
  k=s[0]
  if k=='move':out.append(f'{pad}let {s[1]} = {s[2]}')
  elif k=='close':out.append(f'{pad}owned.close({s[1]})')
  elif k=='return':out.append(f'{pad}return {s[1]}')
  elif k=='break':out.append(f'{pad}break {s[1]}')
  elif k=='if':
   out.append(f'{pad}if condition:');out.extend(render(s[1],depth+1))
   if s[2] is not None:out.append(f'{pad}else:');out.extend(render(s[2],depth+1))
  elif k=='open':
   out.append(f'{pad}let {s[1]} = owned.open({s[2]}) as {s[3]} {s[4]} in do:');out.extend(render(s[5],depth+1))
 return out

def generate(depth=0):
 nodes=[]
 for _ in range(rng.randint(1,3)):
  choices=['move','close','return','break'] + (['if','open'] if depth<2 else [])
  k=rng.choice(choices);n=lambda:rng.choice(NAMES)
  if k=='move':nodes.append((k,n(),n()))
  elif k=='close':nodes.append((k,n()))
  elif k=='return':nodes.append((k,rng.choice(NAMES+['()'])))
  elif k=='break':nodes.append((k,n()))
  elif k=='if':nodes.append((k,generate(depth+1),generate(depth+1) if rng.choice([True,False]) else None))
  else:nodes.append((k,n(),n(),n(),n(),generate(depth+1)))
 return nodes

fixed=[
 ([('close','original'),('return','()')],0),
 ([('move','a','original'),('move','b','a'),('return','b')],1),
 ([('open','out','original','r','p',[('if',[('break','p')],[('break','p')])]),('close','original'),('return','out')],2),
 ([('if',[('move','a','original'),('return','a')],None),('return','original')],1),
 ([('if',[('close','original'),('return','()')],[('close','original'),('return','()')])],0),
]
programs=[]
for _ in range(400):programs.append(rng.choice(fixed))
for _ in range(300):
 count=rng.randint(1,7); chain=[]; owner="original"
 for i in range(count):
  newname=f"move{i}";chain.append(("move",newname,owner));owner=newname
 if rng.choice([True,False]):chain.append(("if",[("return",owner)],[('return',owner)]))
 else:chain.append(("return",owner))
 programs.append((chain,1))
for _ in range(300):
 count=rng.randint(1,6);inner=[]
 for i in range(count-1,-1,-1):
  payload=f"item{i}"
  tail=[("if",[("break",payload)],[('break',payload)])] if rng.choice([True,False]) else [("break",payload)]
  body=inner+tail
  inner=[("open",f"value{i}","original",f"region{i}",payload,body)]
 programs.append((inner+[("close","original"),("return","value0")],2))
for _ in range(3000):programs.append((generate(),rng.randrange(3)))
with tempfile.TemporaryDirectory(prefix='k1-ownership-audit-') as tmp:
 root=pathlib.Path(tmp); path=root/'case.blot'
 goose=os.environ.get('GOOSE','goose'); reference=None
 for level in (0,2):
  driver=root/f'driver-{level}'
  subprocess.run([goose,'build',f'-O{level}','-o',str(driver),str(HERE/'ownership_oracle_driver.goose')],check=True,stdout=subprocess.DEVNULL)
  accepted=0;rejected=0; verdicts=[]
  for index,(program,mode) in enumerate(programs):
   path.write_text('do:\n'+'\n'.join(render(program))+'\n')
   result=subprocess.run([str(driver),str(path),str(mode)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=5)
   assert result.returncode==0, (level,index,mode,path.read_text(),result.returncode,result.stderr)
   verdict=result.stdout.strip();verdicts.append(verdict)
   if verdict==b'accept':
    accepted+=1
    for flag in (False,True):
     try:Machine(flag,mode).run(program)
     except Bad:raise AssertionError((level,index,mode,flag,path.read_text()))
   elif verdict.startswith((b'parse ',b'check ')):rejected+=1
   else:raise AssertionError((level,index,result.stdout,result.stderr))
  assert accepted>=1000 and rejected>0
  if reference is None: reference=verdicts
  else: assert verdicts==reference, 'Goose optimization levels disagree on ownership verdicts'
  print(f'ownership oracle O{level}: {len(programs)} programs, {accepted} accepted on both Bool paths, {rejected} rejected')
