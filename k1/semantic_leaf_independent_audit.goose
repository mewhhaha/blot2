import std;
import semantic_leaf;
fn main(){
 let a="pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return x\n";
 let b="pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return U32.wrapping_add(x,1)\n";
 var p=semantic_leaf::build(a);var q=semantic_leaf::build(b);assert(p.status==0 && q.status==0);
 let x=semantic_leaf::emit(a,p.core,0,128,0,100);let y=semantic_leaf::emit(b,q.core,0,128,0,100);assert(x.status==0 && y.status==0 && !semantic_leaf::verify(a,p.core,y.wasm) && !semantic_leaf::verify(b,q.core,x.wasm));
 assert(!semantic_leaf::valid(b,p.core) && !semantic_leaf::valid(a,q.core));
 var cases:i64=0;for used in [0 as u32,125,126,128,4294967295] {for limit in [0 as u32,3,127,128,129,4294967295] {for fm in [0 as u32,4294967288,4294967289,4294967295] {
  let out=semantic_leaf::emit(a,p.core,used,limit,fm,4294967295);
  let expected=if limit>128 || used>limit || (used as u64)+3>(limit as u64) {2} else if (fm as u64)+7>4294967295 {3} else {0};
  assert(out.status==expected);assert((out.status==0)==(out.wasm.len>0));if out.status==0 {assert(semantic_leaf::verify(a,p.core,out.wasm));}cases+=1;
 }}}
 print("independent semantic source/target and resource oracle ",cases," cases passed");
}
