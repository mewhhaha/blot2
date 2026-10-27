import std;
import typed_dispatch;
import primary_dispatch;
import short_frontend;
import short_legacy_wasm;
import short_emit;
fn main(){
 let source="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n";
 let old=typed_dispatch::compile(source);assert(old.status==0 && old.wasm.len>0);
 for mode in 0..7 {let actual=primary_dispatch::compile_with_fault(source,mode);assert(actual.status==0 && old.wasm[..]==actual.wasm[..]);}
 let old_failure=primary_dispatch::compile_with_fault(source,7);assert(old_failure.status!=0 && old_failure.wasm.len==0 && old_failure.argument==0 && old_failure.result==0);
 var p=short_frontend::parse(source);assert(p.status==0);
 for mode in 1..6 {let bad=short_legacy_wasm::build(source,p.program,mode);assert(bad.matched && bad.bytes.len==0);}
 let loop_source="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = for i in 0..3 carry (a=1) do:\n    next (U32.wrapping_mul(a,2))\n  return y\n";
 let previous=typed_dispatch::compile(loop_source);let now=primary_dispatch::compile(loop_source);assert(previous.status!=0 && now.status==0 && now.wasm.len>0);
 for mode in 1..6 {let same=primary_dispatch::compile_with_fault(loop_source,mode);assert(same.status==0 && now.wasm[..]==same.wasm[..]);}
 let unchanged=primary_dispatch::compile_with_fault(loop_source,7);assert(unchanged.status==0 && unchanged.wasm[..]==now.wasm[..]);
 let blocked=primary_dispatch::compile_with_fault(loop_source,6);assert(blocked.status!=0 && blocked.wasm.len==0 && blocked.argument==0 && blocked.result==0);
 let special="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x\t< 7\n";
 var parsed=short_frontend::parse(special);assert(parsed.status==0);let mismatch=short_legacy_wasm::build(special,parsed.program,0);assert(!mismatch.matched && mismatch.bytes.len==0);let emitted=primary_dispatch::compile(special);let modern=short_emit::emit(special,parsed.program);assert(emitted.status==0 && emitted.wasm[..]==modern[..]);
 let invalid="pub let f: U32 -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => return x < 7\n";
 for mode in 0..7 {let before=typed_dispatch::compile(invalid);let bad=primary_dispatch::compile_with_fault(invalid,mode);assert(bad.status==before.status && bad.status!=0 && bad.wasm.len==0);}
 print("old-success byte/status retention, fallback and injected failures passed");
}
