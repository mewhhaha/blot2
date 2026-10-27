import std;
import os;
import common_frontend;
import common_check;
import common_wasm;
fn yes(s:u8[:],i:i64) {var r=common_frontend::parse(s);if r.status!=0 {print("reject ",r.status," ",s);}assert(r.status==0 && common_check::verify(s,r.program));let b=common_wasm::emit(s,r.program);assert(b.len>0 && write_file(str("common-bool-",i,".wasm"),b));for k in s.len {var x:u8[>..]=[];x.append(s);x[k]^=1;assert(!common_check::verify(x,r.program));}for j in r.program.nodes.len {for f in 8 {var x=copy(r.program);if f==0 {x.nodes[j].tag=999;}else if f==1 {x.nodes[j].start= -1;}else if f==2 {x.nodes[j].end=9223372036854775807;}else if f==3 {x.nodes[j].a= -1;}else if f==4 {x.nodes[j].b= -1;}else if f==5 {x.nodes[j].c= -1;}else if f==6 {x.nodes[j].literal^=1;}else {x.nodes[j].ty^=1;}assert(!common_check::verify(s,x));}}}
fn no(s:u8[:]) {let r=common_frontend::parse(s);assert(r.status!=0 && r.program.source.len==0);}
fn main(){
 yes("let f: Bool -> U32 = fn x => do:\n  let y = 17\n  if x && #True:\n    return y\n  return 42\n",0);
 yes("let f: Bool -> Bool = fn x => do:\n  if x:\n    return x || #False\n  return #True\n",1);
 no("let f: Bool -> U32 = fn x => do:\n  return x + 1\n");
 no("let f: Bool -> Bool = fn x => do:\n  return x < 1\n");
 no("let f: Bool -> U32 = fn x => do:\n  let y = x\n  return y\n");
 no("let f: U32 -> Bool = fn x => do:\n  return x\n");
 no("let f: Bool -> U32 = fn x => do:\n  if #False:\n    return y\n  return 1\n");
 print("common scalar Bool argument source/type controls passed");
}
