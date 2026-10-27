import std;
import os;
import semantic_leaf;
fn expect_fail(s:u8[:],c:semantic_leaf::Core&) {
 assert(!semantic_leaf::valid(s,c));let out=semantic_leaf::emit(s,c,0,128,0,4294967295);assert(out.status!=0 && out.wasm.len==0);
}
fn test(s:u8[:],index:i64) {
 var b=semantic_leaf::build(s);assert(b.status==0 && semantic_leaf::valid(s,b.core));
 let out=semantic_leaf::emit(s,b.core,0,128,0,4294967295);assert(out.status==0 && semantic_leaf::verify(s,b.core,out.wasm));
 assert(write_file(str("semantic-leaf-",index,".wasm"),out.wasm));
 for k in s.len {var x:u8[>..]=[];x.append(s);x[k]^=1;expect_fail(x,b.core);}
 for k in out.wasm.len {var x=copy(out.wasm);x[k]^=1;assert(!semantic_leaf::verify(s,b.core,x));assert(!semantic_leaf::verify(s,b.core,out.wasm[..k]));}
 for i in 9 {var c=copy(b.core);if i==0 {c.effects=1;}else if i==1 {c.declared_depth+=1;}else if i==2 {c.declared_frame+=1;}else if i==3 {c.actual_depth+=1;}else if i==4 {c.actual_frame+=1;}else if i==5 {c.loops+=1;}else if i==6 {c.program.head.depth+=1;}else if i==7 {c.program.types[0]=9;}else {c.program.tree.nodes[0].tag=999;}expect_fail(s,c);}
 let depth=semantic_leaf::emit(s,b.core,128,128,0,4294967295);assert(depth.status==2 && depth.wasm.len==0);
 let frame=semantic_leaf::emit(s,b.core,0,128,4294967295,0);assert(frame.status==3 && frame.wasm.len==0);
}
fn main() {
 test("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n",0);
 test("pub let f: Bool -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  let total = for i in 0..3 carry (a=0) do:\n    if x:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n",1);
 let s="pub let f: Bool -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return 0\n";
 var b=semantic_leaf::build(s);assert(b.status==0);
 let exact=semantic_leaf::emit(s,b.core,125,128,4294967288,4294967295);assert(exact.status==0);
 let d=semantic_leaf::emit(s,b.core,126,128,4294967288,4294967295);assert(d.status==2 && d.wasm.len==0);
 let f=semantic_leaf::emit(s,b.core,125,128,4294967289,4294967295);assert(f.status==3 && f.wasm.len==0);
 let both=semantic_leaf::emit(s,b.core,126,128,4294967289,4294967295);assert(both.status==2 && both.wasm.len==0);
 assert(semantic_leaf::build("pub let f: U32 -> U32 ! {host} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n").status!=0);
 assert(semantic_leaf::build("pub let f: U32 -> U32 ! {} resources {depth: 0, frame: 0} = fn x => do:\n  return x\n").status!=0);
 assert(semantic_leaf::build("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return missing(x)\n").status!=0);
 print("source-bound semantic Core, declared contracts and target preflight passed");
}
