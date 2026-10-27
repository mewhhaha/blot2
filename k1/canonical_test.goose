import std;
import os;
import canonical_wasm;
import canonical_frontend;
import canonical_check;
fn yes(s:u8[:], index:i64) {var p=canonical_frontend::parse(s);if p.status!=0 {print("status ",p.status," ",s);}assert(p.status==0 && canonical_check::verify(s,p.program));let bytes=canonical_wasm::emit(s,p.program);assert(bytes.len>0 && write_file(str("canonical-",index,".wasm"),bytes));for i in s.len {var wrong:u8[>..]=[];wrong.append(s);wrong[i]^=1;assert(!canonical_check::verify(wrong,p.program));}for i in p.program.types.len {var q=copy(p.program);q.types[i]^=1;assert(!canonical_check::verify(s,q));}for i in p.program.tree.nodes.len {for f in 10 {var q=copy(p.program);if f==0 {q.tree.nodes[i].tag=999;}else if f==1 {q.tree.nodes[i].start= -1;}else if f==2 {q.tree.nodes[i].end=9223372036854775807;}else if f==3 {q.tree.nodes[i].a= -1;}else if f==4 {q.tree.nodes[i].b= -1;}else if f==5 {q.tree.nodes[i].c= -1;}else if f==6 {q.tree.nodes[i].d= -1;}else if f==7 {q.tree.nodes[i].e= -1;}else if f==8 {q.tree.nodes[i].f= -1;}else {q.tree.nodes[i].target= -1;}assert(!canonical_check::verify(s,q));}}}
fn more(s:u8[:]) {var p=canonical_frontend::parse(s);assert(p.status==0);for f in 9 {var q=copy(p.program);if f==0 {q.head.ok=false;}else if f==1 {q.head.let_start= -1;}else if f==2 {q.head.effect_start= -1;}else if f==3 {q.head.resources_end=9223372036854775807;}else if f==4 {q.head.depth+=1;}else if f==5 {q.head.frame+=1;}else if f==6 {q.name_start= -1;}else if f==7 {q.name_end=9223372036854775807;}else {q.fn_start= -1;}assert(!canonical_check::verify(s,q) && canonical_wasm::emit(s,q).len==0);}
 for i in p.program.tree.bindings.len {for f in 4 {var q=copy(p.program);if f==0 {q.tree.bindings[i].start= -1;}else if f==1 {q.tree.bindings[i].end=9223372036854775807;}else if f==2 {q.tree.bindings[i].kind=999;}else {q.tree.bindings[i].scope= -1;}assert(!canonical_check::verify(s,q));}}
 for i in p.program.tree.nodes.len {var q=copy(p.program);q.tree.nodes[i].g= -1;assert(!canonical_check::verify(s,q));}}
fn no(s:u8[:]) {let p=canonical_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
fn main(){
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y\n",0);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,i))\n  return total\n",1);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    if i < 4294967295:\n      next (i + 1)\n    else:\n      next (a)\n  return total\n",2);
 more("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    if i < 4294967295:\n      next (i + 1)\n    else:\n      next (a)\n  return total\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x + 1\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    next (i + 1)\n  return total\n");
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return 1\n");
 no("pub let f: U32 -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 print("source-owned scalar/loop typed arena validated");
}
