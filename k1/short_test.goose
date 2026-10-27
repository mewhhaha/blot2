import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_target;
fn yes(s:u8[:],i:i64,arg:i64,res:i64,form:i64) {var p=short_frontend::parse(s);if p.status!=0 {print("reject ",p.status," ",s);}assert(p.status==0 && p.program.head.argument==arg && p.program.head.result==res && p.program.head.form==form && short_check::verify(s,p.program));let bytes=short_emit::emit(s,p.program);assert(bytes.len>0 && write_file(str("short-",i,".wasm"),bytes));
 if i==0 {let pattern:u8[8]=[0x04,0x7f,0x41,1,0x05,0x41,0,0x0b];var found:i64=0;for k in bytes.len-7 {if bytes[k..k+8]==pattern[..] {var q=copy(bytes);if found==0 {q[k+2]=0;q[k+3]=1;}else if found==1 {q[k+5]=0;q[k+6]=1;}else {assert(false);}assert(!short_target::verify(s,p.program,q));assert(write_file(if found==0 {"short-mutant-and.wasm"} else {"short-mutant-or.wasm"},q));found+=1;}}assert(found==2);}
 for k in s.len {var x:u8[>..]=[];x.append(s);x[k]^=1;assert(!short_check::verify(x,p.program));}
 for k in p.program.types.len {var q=copy(p.program);q.types[k]^=1;assert(!short_check::verify(s,q));}for k in p.program.binding_types.len {var q=copy(p.program);q.binding_types[k]^=3;assert(!short_check::verify(s,q));}
 for k in p.program.tree.nodes.len {for f in 10 {var q=copy(p.program);if f==0 {q.tree.nodes[k].tag=999;}else if f==1 {q.tree.nodes[k].start= -1;}else if f==2 {q.tree.nodes[k].end=9223372036854775807;}else if f==3 {q.tree.nodes[k].a= -1;}else if f==4 {q.tree.nodes[k].b= -1;}else if f==5 {q.tree.nodes[k].c= -1;}else if f==6 {q.tree.nodes[k].d= -1;}else if f==7 {q.tree.nodes[k].e= -1;}else if f==8 {q.tree.nodes[k].f= -1;}else {q.tree.nodes[k].target= -1;}assert(!short_check::verify(s,q));}}
 for k in bytes.len {var q=copy(bytes);q[k]^=1;assert(!short_target::verify(s,p.program,q));assert(!short_target::verify(s,p.program,bytes[..k]));}
 for f in 12 {var q=copy(p.program);if f==0 {q.head.ok=false;}else if f==1 {q.head.let_start= -1;}else if f==2 {q.head.type_start= -1;}else if f==3 {q.head.type_end=9223372036854775807;}else if f==4 {q.head.effect_start= -1;}else if f==5 {q.head.resources_end=9223372036854775807;}else if f==6 {q.head.argument=3;}else if f==7 {q.head.result=3;}else if f==8 {q.head.depth+=1;}else if f==9 {q.head.frame+=1;}else if f==10 {q.head.form=3;}else {q.tree.root= -1;}assert(!short_check::verify(s,q) && short_emit::emit(s,q).len==0);}}
fn no(s:u8[:]) {let p=short_frontend::parse(s);if p.status==0 {print("unexpected accepted ",s);}assert(p.status!=0 && p.program.source.len==0);}
fn main(){for arg in 1..3 {for res in 1..3 {for form in 1..3 {let a=if arg==1 {"U32"} else {"Bool"};let r=if res==1 {"U32"} else {"Bool"};let sig=if form==1 {str(a," -> ",r)} else {str("Fn[static,Many,",a,",",r,"]")};let first=if arg==1 {"  let flag = (x < 5) && #True\n"} else {"  let flag = x && #True\n"};let last=if res==1 {"  return total\n"} else {"  return flag\n"};let s=str("pub let f: ",sig," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",first,"  let total = for i in 0..3 carry (a=0) do:\n    if flag || #False:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n",last);yes(s,(arg-1)*4+(res-1)*2+form-1,arg,res,form);}}}
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x + 1\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    next (a)\n  return x\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let safe = x < 4294967295\n  if safe:\n    return x + 1\n  return 0\n");
 no("pub let f: Bool -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 let dead=short_frontend::parse("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False && (x + 1) < 5\n");assert(dead.status==0);
 no("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x && 1\n");
 print("source-bound short-circuit typed scalar/loop passed");}
