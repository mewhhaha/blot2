from pathlib import Path
import re,json,hashlib
# A schema authoring reader, not a Goose checker/compiler. It emits concrete
# record, enum and typed-run codecs; the generated program is the implementation.
def clean(s):
 out=[];i=0
 while i<len(s):
  if s.startswith('//',i):
   end=s.find('\n',i);i=len(s) if end<0 else end;continue
  if s.startswith('/*',i):
   end=s.find('*/',i+2);i=len(s) if end<0 else end+2;continue
  if s[i] in '\"\'':
   q=s[i];j=i+1
   while j<len(s):
    if s[j]=='\\':j+=2;continue
    if s[j]==q:j+=1;break
    j+=1
   out.append(s[i:j]);i=j;continue
  out.append(s[i]);i+=1
 return ''.join(out)
def balanced(s,start,op='{',cl='}'):
 depth=1;i=start+1
 while i<len(s):
  c=s[i]
  if c in '\"\'':
   q=c;i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==q:break
    i+=1
  elif c==op:depth+=1
  elif c==cl:
   depth-=1
   if depth==0:return i
  i+=1
 raise ValueError('unterminated authoring declaration')
def split(s,sep=','):
 out=[];start=0;i=0;stack=[]
 while i<len(s):
  c=s[i]
  if c in '\"\'':
   q=c;i+=1
   while i<len(s):
    if s[i]=='\\':i+=2;continue
    if s[i]==q:break
    i+=1
  elif c in '[{(<':stack.append(c)
  elif c in ']})>':
   if stack:stack.pop()
  elif c==sep and not stack:out.append(s[start:i].strip());start=i+1
  i+=1
 if s[start:].strip():out.append(s[start:].strip())
 return out
def fields(body):
 result=[]
 for item in split(body):
  name,ty=item.split(':',1);ty=split(ty,'=')[0].strip()
  result.append((name.strip(),ty))
 return result
