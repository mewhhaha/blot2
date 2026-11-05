"""Use typed empty views, rather than borrowed temporary array literals."""
from pathlib import Path
import re,sys
from normalize_syntax import tokens
ROOT=Path(__file__).resolve().parents[1]/'src'
paths=[Path(p) for p in sys.argv[1:]]
aliases={};namespaces={}
for p in ROOT.rglob('*.goose'):
 ts=tokens(p.read_text());ns=next((ts[i+1][0] for i,t in enumerate(ts[:-1]) if t[0]=='namespace'),'');namespaces[p]=ns
 for i,(w,a,b) in enumerate(ts[:-3]):
  if w=='type' and ts[i+2][0]=='=':
   j=i+3
   while j<len(ts) and ts[j][0]!=';':j+=1
   if j<len(ts):aliases[ns+'::'+ts[i+1][0]]=p.read_text()[ts[i+2][2]:ts[j][1]].strip()
def slice_type(raw,ns):
 seen=set()
 while True:
  raw=raw.strip()
  if raw.endswith('[:]'):return True
  key=raw
  if '::' not in key:key=ns+'::'+key
  if key not in aliases or key in seen:return False
  seen.add(key);raw=aliases[key]
count=0
for path in paths:
 s=path.read_text();ts=tokens(s);edits={};ns=namespaces.get(path,'')
 # Annotation/default pairs. Stop at statement, body or parameter boundaries.
 for i,(w,a,b) in enumerate(ts):
  if w!=':':continue
  j=i+1;depth=0
  while j<len(ts):
   word=ts[j][0]
   if depth==0 and word in (';',',','{','}','(',')'):break
   if word in ('<','['):depth+=1
   elif word in ('>',']'):depth-=1
   if word=='=' and depth==0:
    if j+2<len(ts) and ts[j+1][0]=='[' and ts[j+2][0]==']':
     raw=s[b:ts[j][1]].strip()
     if slice_type(raw,ns):edits[ts[j+1][1]]=(ts[j+2][2],'default<'+raw+'>()')
    break
   j+=1
 # Function result signatures and their lexical bodies.
 pairs={};stack=[]
 for i,(w,a,b) in enumerate(ts):
  if w in ('(','{'):stack.append(i)
  elif w in (')','}') and stack:
   start=stack.pop();pairs[start]=i
 funcs=[]
 for i,(w,a,b) in enumerate(ts):
  if w!='fn':continue
  j=i+1
  while j<len(ts) and ts[j][0] not in ('(',';','{'):j+=1
  if j not in pairs:continue
  end=pairs[j];k=end+1
  if k+1>=len(ts) or ts[k][0]!='-' or ts[k+1][0]!='>':continue
  k+=2;first=k;depth=0
  while k<len(ts):
   word=ts[k][0]
   if depth==0 and word in (',','{',';'):break
   if word in ('<','['):depth+=1
   elif word in ('>',']'):depth-=1
   k+=1
  raw=s[ts[first][1]:ts[k][1]].strip() if k<len(ts) else ''
  while k<len(ts) and ts[k][0] not in ('{',';'):k+=1
  if k not in pairs:continue
  funcs.append((k,pairs[k],raw))
 for i,(w,a,b) in enumerate(ts[:-2]):
  if w!='return' or ts[i+1][0]!='[' or ts[i+2][0]!=']':continue
  active=[f for f in funcs if f[0]<i<f[1]]
  if not active:continue
  raw=max(active,key=lambda x:x[0])[2]
  if slice_type(raw,ns):edits[ts[i+1][1]]=(ts[i+2][2],'default<'+raw+'>()')
 for a,(b,value) in sorted(edits.items(),reverse=True):s=s[:a]+value+s[b:]
 if edits:path.write_text(s);count+=len(edits)
print('typed empty slices',count)
