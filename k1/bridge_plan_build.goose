// Construct compiler-owned closed bridge Core before target emission.
namespace bridge_plan_build;
import bridge_plan_core;

import m12_adapter_core;
import m12_adapter_verify;
fn build(p:m12_adapter_core::Program&,source:u8[:])->bridge_plan_core::Result {
 if !m12_adapter_verify::verify(p,source) || p.events.len!=5{return bridge_plan_core::Result {};}
 var q=bridge_plan_core::Plan {source:source};
 for i in 5 {q.source_sites[i]=p.events[i].site;}
 for i in 13 {q.ops[i]=(i+1) as u32;}
 let statuses:u32[7]=[4,1,5,3,2,0,4294967295];let cleanup:u32[7]=[0,0,0,1,2,2,3];let phase:u32[7]=[0,0,0,1,7,7,255];
 for i in 7 {q.branches[i]=bridge_plan_core::Branch {kind:(i+1) as u32,status:statuses[i],cleanup:cleanup[i],phase:phase[i]};}
 for i in 9 {let n=i as u32;let end=n*16;q.cases[i]=bridge_plan_core::Case {count:n,input_start:0,input_end:end,output_start:end,output_end:end+64,result_end:end+n*8,capacity:8,frontier:end+64};}
 return bridge_plan_core::Result {status:0,plan:q};
}
