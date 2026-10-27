import std;
import primary_dispatch;
import typed_dispatch;
fn main(){
 let source="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n";
 let old=typed_dispatch::compile(source);let normal=primary_dispatch::compile(source);assert(old.status==0 && normal.status==0 && old.wasm[..]==normal.wasm[..]);
 for mode in 1..3 {let bad=primary_dispatch::compile_with_fault(source,mode);assert(bad.status!=0 && bad.wasm.len==0 && bad.argument==0 && bad.result==0);}
 let loop_source="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = for i in 0..3 carry (a=1) do:\n    next (U32.wrapping_mul(a,2))\n  return y\n";
 let candidate=primary_dispatch::compile(loop_source);assert(candidate.status==0 && candidate.wasm.len>0);
 for mode in 1..3 {let untouched=primary_dispatch::compile_with_fault(loop_source,mode);assert(untouched.status==0 && untouched.wasm[..]==candidate.wasm[..]);}
 let invalid="pub let f: U32 -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => return x < 7\n";
 for mode in 0..3 {let bad=primary_dispatch::compile_with_fault(invalid,mode);assert(bad.status!=0 && bad.wasm.len==0);}
 print("matched legacy target emission and target-validation failure closed without publication");
}
