// Producer identifies actual call sites in the verified, fixed caller body.
// Independent semantic consumer remains required before using the result.
namespace m12_caller_flow_build;
import m12_adapter_core;
import m12_internal_target;
import m12_caller_flow_core;
import m12_caller_flow_bytes;
import i08_same_target;
fn build(p:m12_adapter_core::Program&,source:u8[:],target:u8[:])->m12_caller_flow_core::Result {
 if !m12_internal_target::verify(p,source,target){return m12_caller_flow_core::Result {};}
 let slice=m12_caller_flow_bytes::body(target);if !slice.ok{return m12_caller_flow_core::Result {};}
 let code=target[slice.start..slice.end];if code.len<3 || code[..3]!=[1 as u8,13,0x7f] {return m12_caller_flow_core::Result {};}
 let from:u32[12]=[0,0,1,1,3,7,11,27,43,11,3,1];let to:u32[12]=[0,1,3,0,7,11,27,43,11,3,1,0];
 var pos:i64=3;var depth:i64=0;var count:i64=0;var parents:i64[128]=[0;128];var loads:i64=0;var stores:i64=0;var proof=m12_caller_flow_core::Proof {source:source,target:target};
 while pos<code.len {let site=pos;let op=code[pos];pos+=1;
  if op==2 || op==3 || op==4 {if pos>=code.len{return m12_caller_flow_core::Result {};}pos+=1;if depth>=128{return m12_caller_flow_core::Result {};}parents[depth]=site;depth+=1;}
  else if op==11 {if depth>0 {depth-=1;}else if pos!=code.len {return m12_caller_flow_core::Result {};}}
  else if op==5 {} 
  else if op==0x10 {let n=i08_same_target::read_leb(code,pos,code.len);if !n.ok || count>=12{return m12_caller_flow_core::Result {};}
   proof.steps[count]=m12_caller_flow_core::Step {kind:count+1,site:site,callee:n.value,depth:depth,parent:if depth>0 {parents[depth-1]} else {-1},before:from[count],after:to[count]};count+=1;pos=n.next;}
  else if op==0x0c || op==0x0d || op==0x20 || op==0x21 || op==0x22 {pos=m12_caller_flow_bytes::unsigned_end(code,pos);}
  else if op==0x41 {pos=m12_caller_flow_bytes::skip_signed(code,pos);}
  else if op==0x28 || op==0x2d || op==0x36 || op==0x3a {
   if op==0x2d {if loads==0 {proof.padding_load=site;}else if loads==1 {proof.input_load=site;}else if loads==2 {proof.output_load=site;}loads+=1;}
   if op==0x3a {if stores==0 {proof.input_store=site;}else if stores==1 {proof.output_store=site;}stores+=1;}
   pos=m12_caller_flow_bytes::unsigned_end(code,pos);if pos<0{return m12_caller_flow_core::Result {};}pos=m12_caller_flow_bytes::unsigned_end(code,pos);}
  else if op!=0 && op!=0x0f && op!=0x45 && op!=0x46 && op!=0x47 && op!=0x48 && op!=0x49 && op!=0x4b && op!=0x4c && op!=0x4d && op!=0x4f && op!=0x6a && op!=0x6b && op!=0x6c && op!=0x71 && op!=0x72 {return m12_caller_flow_core::Result {};}
  if pos<0 || pos>code.len || depth>128 {return m12_caller_flow_core::Result {};}
 }
 if count!=12 || depth!=0 || loads!=3 || stores!=2 {return m12_caller_flow_core::Result {};}
 return m12_caller_flow_core::Result {status:0,proof:proof};
}
