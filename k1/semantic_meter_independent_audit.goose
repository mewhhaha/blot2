// Private partial-meter parity/forgery controls; these counts are not C09.
import std;import semantic_owner;import semantic_owner_metered;import work;
fn check(s:u8[:]) {
 var b=semantic_owner::build("pkg","src/main.blot","f",s);assert(b.status==0);
 let baseline=semantic_owner::emit("pkg","src/main.blot","f",s,b.owner,0,128,0,4294967295);assert(baseline.status==0);
 let n:u32=2+(b.owner.core.program.binding_types.len as u32)+2*(b.owner.core.program.tree.nodes.len as u32);
 var job=semantic_owner_metered::Job {};for i in 3 {let a=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,job,5,0,128,0,4294967295);assert(a.status==0 && a.bytes[..]==baseline.wasm[..] && job.meter.semantic==(i+1)*n && !job.failed);}
 var exact=semantic_owner_metered::Job {meter:work::Meter {semantic:1048576-n}};let final=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,exact,5,0,128,0,4294967295);assert(final.status==0 && exact.meter.semantic==1048576 && final.bytes[..]==baseline.wasm[..]);
 for k in n {var bounded=semantic_owner_metered::Job {meter:work::Meter {semantic:1048576-k}};let out=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,bounded,5,0,128,0,4294967295);assert(out.status==2 && out.bytes.len==0 && bounded.failed && bounded.meter.semantic==1048576 && out.receipt.quantity==1 && out.receipt.measured==1048576);let again=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,bounded,5,0,128,0,4294967295);assert(again.status==3 && again.bytes.len==0 && bounded.meter.semantic==1048576);}
 for field in 9 {var bad=copy(b.owner);if field==0 {bad.core.effects=1;}else if field==1 {bad.core.actual_depth=2;}else if field==2 {bad.core.actual_frame=1;}else if field==3 {bad.core.declared_depth+=1;}else if field==4 {bad.core.declared_frame+=1;}else if field==5 {bad.core.loops+=1;}else if field==6 {bad.core.program.types[0]=9;}else if field==7 {bad.core.program.tree.nodes[0].tag=999;}else {bad.origin.fingerprint[0]^=1;}
 var j=semantic_owner_metered::Job {};let out=semantic_owner_metered::emit("pkg","src/main.blot","f",s,bad,j,5,0,128,0,4294967295);assert(out.status==1 && out.bytes.len==0 && j.failed);let used=j.meter.semantic;let again=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,j,5,0,128,0,4294967295);assert(again.status==3 && again.bytes.len==0 && j.meter.semantic==used);}
}
fn main(){
 for s in [
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n",
 "pub let f: Bool -> Bool ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return x && #True\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  if x < 10:\n    return x\n  return 7\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  let total = for i in 0..3 carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return total\n"
 ] {check(s);}
 print("independent partial meter parity/forgery/terminal/budget matrix passed");
}
