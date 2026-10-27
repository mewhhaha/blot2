// Independent pre-emission source/affine replay. No numeric record is a live
// handle; all ownership roles are scoped inside this one checked bridge.
namespace bridge_plan_verify;
import bridge_plan_core;
import bridge_plan_affine;

import m12_adapter_core;
import m12_adapter_verify;
fn verify(p:m12_adapter_core::Program&,source:u8[:],plan:bridge_plan_core::Plan&)->bool {
 if plan.source[..]!=source || !m12_adapter_verify::verify(p,source) || p.events.len!=5{return false;}
 for i in 5 {let e=p.events[i];if e.kind!=i+1 || e.site<0 || e.site>=source.len || plan.source_sites[i]!=e.site{return false;}if i>0 && plan.source_sites[i-1]>=e.site{return false;}}
 for i in 9 {
  let n=i as u32;let end=n*16;let expected=bridge_plan_core::Case {count:n,input_start:0,input_end:end,output_start:end,output_end:end+64,result_end:end+n*8,capacity:8,frontier:end+64};
  let c=plan.cases[i];if !bridge_plan_core::same(c,expected) || c.input_end>c.output_start || c.result_end<c.output_start || c.result_end>c.output_end || c.output_end>192 || c.count>c.capacity || (c.output_start & 3)!=0{return false;}
 }
 // Exact failure/status schemas, independently checked before codegen.
 let status:u32[7]=[4,1,5,3,2,0,4294967295];let cleanup:u32[7]=[0,0,0,1,2,2,3];let phase:u32[7]=[0,0,0,1,7,7,255];
 for i in 7 {let b=plan.branches[i];if b.kind!=(i+1) as u32 || b.status!=status[i] || b.cleanup!=cleanup[i] || b.phase!=phase[i] || !bridge_plan_affine::branch_exit(b.kind,b.cleanup,b.phase){return false;}}
 var st=bridge_plan_affine::State {};
 for i in 13 {if plan.ops[i]!=(i+1) as u32 || !bridge_plan_affine::transition(st,plan.ops[i]){return false;}}
 var failed=bridge_plan_affine::State {frame:true};if !bridge_plan_affine::reserve_failure(failed) || failed.frame || failed.owner || failed.space!=0 || !failed.done{return false;}
 return st.done && !st.frame && !st.owner && st.space==0 && st.input==0 && st.output==0;
}
fn public_eligible(p:m12_adapter_core::Program&,source:u8[:],plan:bridge_plan_core::Plan&)->bool {let _=p;let _=source;let _=plan;return false;}
