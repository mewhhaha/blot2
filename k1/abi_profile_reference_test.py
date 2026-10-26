"""Small independent one-shot BLAKE3 reference for private profile audit."""
from pathlib import Path
import struct
IV=(0x6A09E667,0xBB67AE85,0x3C6EF372,0xA54FF53A,0x510E527F,0x9B05688C,0x1F83D9AB,0x5BE0CD19)
PERM=(2,6,3,10,7,0,4,13,1,11,12,5,9,14,15,8)
M=0xffffffff
def rotate(v,n):return ((v>>n)|(v<<(32-n)))&M
def compress(cv,block,counter,length,flags):
 v=list(cv)+list(IV[:4])+[counter&M,counter>>32,length,flags];m=list(block)
 def g(a,b,c,d,x,y):
  v[a]=(v[a]+v[b]+x)&M;v[d]=rotate(v[d]^v[a],16);v[c]=(v[c]+v[d])&M;v[b]=rotate(v[b]^v[c],12)
  v[a]=(v[a]+v[b]+y)&M;v[d]=rotate(v[d]^v[a],8);v[c]=(v[c]+v[d])&M;v[b]=rotate(v[b]^v[c],7)
 for _ in range(7):
  g(0,4,8,12,m[0],m[1]);g(1,5,9,13,m[2],m[3]);g(2,6,10,14,m[4],m[5]);g(3,7,11,15,m[6],m[7])
  g(0,5,10,15,m[8],m[9]);g(1,6,11,12,m[10],m[11]);g(2,7,8,13,m[12],m[13]);g(3,4,9,14,m[14],m[15]);m=[m[i] for i in PERM]
 return tuple(v[i]^v[i+8] for i in range(8))+tuple(v[i+8]^cv[i] for i in range(8))
def words(data):return struct.unpack('<16I',data.ljust(64,b'\0'))
def cv(out):return compress(*out)[:8]
def chunk(data,counter):
 state=IV; blocks=[data[i:i+64] for i in range(0,len(data),64)] or [b'']
 for i,b in enumerate(blocks):
  out=(state,words(b),counter,len(b),(1 if i==0 else 0)|(2 if i==len(blocks)-1 else 0))
  if i!=len(blocks)-1:state=cv(out)
 return out
def parent(left,right):return (IV,tuple(left)+tuple(right),0,64,4)
def digest(data):
 chunks=[data[i:i+1024] for i in range(0,len(data),1024)] or [b''];stack=[]
 for i,c in enumerate(chunks[:-1]):
  state=cv(chunk(c,i));total=i+1
  while total&1==0:state=cv(parent(stack.pop(),state));total>>=1
  stack.append(state)
 out=chunk(chunks[-1],len(chunks)-1)
 while stack:out=parent(stack.pop(),cv(out))
 return struct.pack('<16I',*compress(out[0],out[1],0,out[3],out[4]|8))[:32]
assert digest(b'').hex()=='af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262'
assert digest(b'abc').hex()=='6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85'
profile=Path('profile.bin').read_bytes(); actual=Path('digest.bin').read_bytes(); assert digest(profile)==actual
print('independent BLAKE3 reference matches profile digest',actual.hex())
