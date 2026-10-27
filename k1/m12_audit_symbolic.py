#!/usr/bin/env python3
"""Conditional symbolic Wasm helper replay; NOT capability authentication.

The input is decoded from an already source-checked and pinned fixture. Function 4 (valid_owner) is separately replayed against an independently
stated predicate. Calls to it within other helpers are abstracted, and a
separate composition check relates the result to each helper premise. The underlying pool-close function is also replayed separately; the
checked-close call is abstracted to an arbitrary result and memory, so that
proof applies to the separately checked implementation. Globally consistent
pool state and exclusive private memory remain assumptions. Supported Wasm operations are interpreted as exact
32-bit bitvectors over aligned word memory; unknown opcodes fail closed.
"""

from copy import deepcopy

B=lambda n:f'(_ bv{n & 0xffffffff} 32)'
def app(op,*args):return '('+op+' '+' '.join(args)+')'
def eq(a,b):return app('=',a,b)
def ne(a,b):return app('not',eq(a,b))
def ite(c,a,b):return app('ite',c,a,b)
def neg(a):return eq(a,B(0))
def land(*args):return app('and',*args)
def lor(*args):return app('or',*args)
def s(m,p):return app('select',m,p)
def put(m,p,v):return app('store',m,p,v)
def add(a,b):return app('bvadd',a,b)
def mul(a,b):return app('bvmul',a,b)
def gt(a,b):return app('bvugt',a,b)
def le(a,b):return app('bvule',a,b)
def nz(a):return ne(a,B(0))

def matches(ops):
 stack=[]; els={}; ends={}
 for i,x in enumerate(ops):
  op=x['op']
  if op==4:stack.append([i,None])
  elif op==5:
   if not stack or stack[-1][1] is not None:raise ValueError('bad else')
   stack[-1][1]=i
  elif op==11:
   if stack:
    i0,j=stack.pop();ends[i0]=i
    if j is not None:els[i0]=j;ends[j]=i
 if stack:raise ValueError('unterminated if')
 return els,ends

def execute(ops,good):
 els,ends=matches(ops);out=[]
 init={'pc':0,'stack':[],'locals':['slot','gen','arg']+[B(0)]*8,'mem':'M','path':[]}
 todo=[init]; visits=0
 while todo:
  q=todo.pop(); visits+=1
  if visits>10000:raise ValueError('work cap')
  while q['pc']<len(ops):
   pc=q['pc'];o=ops[pc];op=o['op'];imm=o.get('imm');q['pc']+=1;st=q['stack'];loc=q['locals']
   if op==0x20:st.append(loc[imm])
   elif op==0x21:loc[imm]=st.pop()
   elif op==0x41:st.append(B(imm))
   elif op==0x28:st.append(s(q['mem'],add(st.pop(),B(imm['offset']))))
   elif op==0x36:
    v=st.pop();a=st.pop();q['mem']=put(q['mem'],add(a,B(imm['offset'])),v)
   elif op==0x10:
    if imm not in (1,4):raise ValueError(f'unknown call {imm}')
    b=st.pop();a=st.pop()
    if a!='slot' or b!='gen':raise ValueError('unexpected owner actuals')
    if imm==4:st.append('owner' if good else B(0))
    else:
     if q['mem']!='M':raise ValueError('unexpected pre-close mutation')
     q['mem']='close_mem';st.append('close_result')
   elif op==0x45:st.append(ite(neg(st.pop()),B(1),B(0)))
   elif op in (0x46,0x47,0x49,0x4b,0x4f):
    b=st.pop();a=st.pop();cond={0x46:eq,0x47:ne,0x49:lambda x,y:app('bvult',x,y),0x4b:gt,0x4f:lambda x,y:app('bvuge',x,y)}[op](a,b);st.append(ite(cond,B(1),B(0)))
   elif op in (0x74,0x76):
    b=st.pop();a=st.pop();st.append(app('bvshl' if op==0x74 else 'bvlshr',a,app('bvand',b,B(31))))
   elif op in (0x6a,0x6b,0x6c,0x71,0x72,0x73):
    b=st.pop();a=st.pop();st.append(app({0x6a:'bvadd',0x6b:'bvsub',0x6c:'bvmul',0x71:'bvand',0x72:'bvor',0x73:'bvxor'}[op],a,b))
   elif op==0x04:
    cond=nz(st.pop()); other=deepcopy(q); other['path'].append(app('not',cond)); other['pc']=els.get(pc,ends[pc])+1;todo.append(other)
    q['path'].append(cond)
   elif op==0x05:q['pc']=ends[pc]+1
   elif op==0x0f:out.append((q['path'],st.pop(),q['mem']));break
   elif op==0x0b:
    if q['pc']==len(ops):out.append((q['path'],st.pop(),q['mem']));break
   else:raise ValueError(f'unsupported opcode {op:x} at {pc}')
  else:raise ValueError('fell off function')
 return out

def contract(f,good):
 # valid-owner oracle: returns owner pointer, and the actual owner contract is
 # trusted only on the success case. Initial memory M and all parameters are
 # otherwise symbolic; the SMT memory models aligned i32 accesses as words.
 M='M';owner='owner';slot='slot';gen='gen';arg='arg';
 desc=add(B(256 if f in (5,6,12) else 320),mul(add(slot,B(-1)),B(16)))
 cap=add(B(384),mul(add(slot,B(-1)),B(4)))
 field=lambda p,n:s(M,add(p,B(n)))
 state=field(desc,0);dg=field(desc,4);data=field(desc,8);length=field(desc,12)
 ownerbase=field(owner,0);size=field(owner,4);top=field(owner,12)
 active=land(nz(state),eq(dg,gen))
 base=land(le(B(1),slot),le(slot,B(4)),nz(gen),eq(owner,add(B(16),mul(add(slot,B(-1)),B(32)))),le(top,size),le(size,B(4294963200))) if good else 'true'
 if f==1:
  _,owner_ret,_=contract(4,True);p=add(B(16),mul(add(slot,B(-1)),B(32)));fld=lambda n:s(M,add(p,B(n)))
  rounded=fld(8);obase=fld(0);first=app('bvlshr',app('bvsub',obase,B(4096)),B(12));count=app('bvlshr',rounded,B(12));mask=app('bvshl',app('bvsub',app('bvshl',B(1),app('bvand',count,B(31))),B(1)),app('bvand',first,B(31)))
  bitmap=s(M,B(144));cleared=app('bvand',bitmap,app('bvxor',mask,B(-1)));after_bitmap=ite(neg(rounded),M,put(M,B(144),cleared));out=put(after_bitmap,add(p,B(20)),ite(eq(gen,B(-1)),B(3),B(0)));valid=nz(owner_ret)
  return 'true',ite(valid,B(0),B(-4)),ite(valid,out,M)
 if f==4:
  p=add(B(16),mul(add(slot,B(-1)),B(32)));fld=lambda n:s(M,add(p,B(n)))
  size=fld(4);rounded=fld(8);obase=fld(0);first=app('bvlshr',app('bvsub',obase,B(4096)),B(12));count=app('bvlshr',rounded,B(12))
  mask=app('bvshl',app('bvsub',app('bvshl',B(1),app('bvand',count,B(31))),B(1)),app('bvand',first,B(31)))
  empty=neg(rounded);bitmap=s(M,B(144))
  run=land(le(B(4096),obase),eq(app('bvand',app('bvsub',obase,B(4096)),B(4095)),B(0)),le(first,B(6)),le(count,app('bvsub',B(6),first)),eq(app('bvand',bitmap,mask),mask))
  valid=land(le(B(1),slot),le(slot,B(4)),nz(gen),eq(fld(20),B(1)),eq(fld(16),gen),le(fld(12),size),le(size,B(4294963200)),eq(app('bvand',add(size,B(4095)),B(-4096)),rounded),ite(empty,neg(obase),run))
  return 'true',ite(valid,p,B(0)),M
 if not good:return base,B(-4),M
 if f==5:
  bytes_=mul(arg,B(16));err1=lor(active,nz(top));err2=gt(arg,B(268435455));err3=gt(bytes_,size)
  ret=ite(err1,B(-4),ite(err2,B(-1),ite(err3,B(-2),B(0))))
  out=put(M,add(owner,B(12)),bytes_);out=put(out,desc,B(1));out=put(out,add(desc,B(4)),gen);out=put(out,add(desc,B(8)),ite(neg(arg),B(0),ownerbase));out=put(out,add(desc,B(12)),arg)
  mem=ite(lor(err1,err2,err3),M,out)
 elif f==6:
  err=lor(ne(state,B(1)),ne(dg,gen),gt(length,B(268435455)),ne(mul(length,B(16)),top),ite(neg(length),nz(data),ne(data,ownerbase)))
  ret=ite(err,B(-4),length);mem=ite(err,M,put(M,desc,B(2)))
 elif f==8:
  bytes_=mul(arg,B(8));aligned=app('bvand',add(top,B(3)),B(-4))
  err1=active;err2=gt(arg,B(536870911));err3=lor(gt(aligned,size),gt(bytes_,app('bvsub',size,aligned)))
  ret=ite(err1,B(-4),ite(err2,B(-1),ite(err3,B(-2),B(0))))
  out=put(M,add(owner,B(12)),add(aligned,bytes_));out=put(out,desc,B(1));out=put(out,add(desc,B(4)),gen);out=put(out,add(desc,B(8)),add(ownerbase,aligned));out=put(out,add(desc,B(12)),B(0));out=put(out,cap,arg)
  mem=ite(lor(err1,err2,err3),M,out)
 elif f==11:
  inp=add(B(256),mul(add(slot,B(-1)),B(16)));out=add(B(320),mul(add(slot,B(-1)),B(16)))
  live=lambda p:land(nz(field(p,0)),eq(field(p,4),gen))
  err=lor(live(inp),live(out));ret=ite(err,B(-4),'close_result');mem=ite(err,M,'close_mem')
 elif f in (12,13):
  badstate=ne(state,B(2)) if f==12 else land(ne(state,B(1)),ne(state,B(2)))
  err=lor(ne(dg,gen),badstate);ret=ite(err,B(-4),B(0));mem=ite(err,M,put(M,desc,B(0)))
 else:raise ValueError('unsupported function')
 return base,ret,mem

