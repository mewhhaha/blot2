import std;
import semantic_owner;
import semantic_owner_metered;
import semantic_contract_metered;
import work;
fn main() {
 let s="pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  let total = for i in 0..3 carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return total\n";
 var b=semantic_owner::build("pkg","src/main.blot","f",s);assert(b.status==0);
 let baseline=semantic_owner::emit("pkg","src/main.blot","f",s,b.owner,0,128,0,7);assert(baseline.status==0);
 let visits:u32=2 + (b.owner.core.program.binding_types.len as u32) + 2 * (b.owner.core.program.tree.nodes.len as u32);
 var m=semantic_owner_metered::Job {};let result=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,m,5,0,128,0,7);
 assert(result.status==0 && result.bytes[..]==baseline.wasm[..] && m.meter.semantic==visits && m.meter.phase_semantic[4]==visits);
 let repeated=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,m,5,0,128,0,7);
 assert(repeated.status==0 && m.meter.semantic==2*visits && m.meter.phase_semantic[4]==2*visits);
 var exact=semantic_owner_metered::Job {meter:work::Meter {semantic:1048576-visits}};let at=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,exact,5,0,128,0,7);assert(at.status==0 && exact.meter.semantic==1048576);
 for k in visits {var limited=semantic_owner_metered::Job {meter:work::Meter {semantic:1048576-k}};let q=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,limited,5,0,128,0,7);
  assert(q.status==2 && q.bytes.len==0 && limited.meter.semantic==1048576 && q.receipt.quantity==1 && q.receipt.measured==1048576 && q.receipt.limit==1048576);
 }
 var malformed=copy(b.owner);malformed.core.effects=1;var empty=semantic_owner_metered::Job {meter:work::Meter {semantic:1048576}};let priority=semantic_owner_metered::emit("pkg","src/main.blot","f",s,malformed,empty,5,0,128,0,7);assert(priority.status==2 && priority.bytes.len==0 && empty.failed);let retry=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,empty,5,0,128,0,7);assert(retry.status==3 && retry.bytes.len==0);
 var enough=semantic_owner_metered::Job {};let wrong=semantic_owner_metered::emit("pkg","src/main.blot","f",s,malformed,enough,5,0,128,0,7);assert(wrong.status==1 && wrong.bytes.len==0 && enough.meter.semantic==1);
 var gate=semantic_owner_metered::Job {meter:work::Meter {gate:2}};let rejected=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,gate,5,0,128,0,7);assert(rejected.status==3 && rejected.bytes.len==0 && gate.meter.gate==9);
 var identity=semantic_owner_metered::Job {};let mismatch=semantic_owner_metered::emit("other","src/main.blot","f",s,b.owner,identity,5,0,128,0,7);assert(mismatch.status==1 && mismatch.bytes.len==0 && identity.meter.semantic==0);
 var badphase=semantic_owner_metered::Job {};let bad=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,badphase,6,0,128,0,7);assert(bad.status==3 && bad.bytes.len==0 && badphase.failed && badphase.meter.semantic==0);
 var depth=semantic_owner_metered::Job {};let d=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,depth,5,126,128,0,7);assert(d.status==4 && d.bytes.len==0 && depth.meter.semantic==visits);
 var frame=semantic_owner_metered::Job {};let f=semantic_owner_metered::emit("pkg","src/main.blot","f",s,b.owner,frame,5,0,128,1,7);assert(f.status==5 && f.bytes.len==0 && frame.meter.semantic==visits);
 print("partial semantic owner contract events and budget boundaries passed");
}
