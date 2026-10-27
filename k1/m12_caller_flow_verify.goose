// Independent fixed-caller operation replay. The target is first checked
// against the exact source-bound base and pinned caller bytes. Roles below
// refer to lexical machine operations, not transferable numerical authority.
// Conclusions remain conditional on the trusted helper/loan/frame contracts.
namespace m12_caller_flow_verify;
import m12_adapter_core;
import m12_internal_target;
import m12_caller_flow_core;
import m12_caller_flow_bytes;
import i08_same_target;
fn before(c:u8[:],site:i64,want:u8[:])->bool {return site>=want.len && site<=c.len && c[site-want.len..site]==want;}
fn after(c:u8[:],site:i64,want:u8[:])->bool {return site>=0 && site<=c.len && want.len<=c.len-site && c[site..site+want.len]==want;}
fn verify(p:m12_adapter_core::Program&,source:u8[:],target:u8[:],proof:m12_caller_flow_core::Proof&)->bool {
 if proof.source[..]!=source || proof.target[..]!=target || !m12_internal_target::verify(p,source,target) {return false;}
 let loc=m12_caller_flow_bytes::body(target);if !loc.ok{return false;}let code=target[loc.start..loc.end];
 if code.len<3 || code[..3]!=[1 as u8,13,0x7f] {return false;}
 let calls:i64[12]=[16,18,0,19,5,6,8,21,13,12,11,19];
 var state:u32=0;var pos:i64=3;var depth:i64=0;var stack:i64[128]=[0;128];var scopes:u8[128]=[0;128];var count:i64=0;var loads:i64=0;var stores:i64=0;
 var load_site:i64[3]=[-1;3];var store_site:i64[2]=[-1;2];
 while pos<code.len {let site=pos;let op=code[pos];pos+=1;
  if op==2 || op==3 || op==4 {if pos>=code.len || depth>=128 {return false;}let blocktype=code[pos];if blocktype!=0x40 && blocktype!=0x7f {return false;}pos+=1;stack[depth]=site;scopes[depth]=op;depth+=1;}
  else if op==5 {if depth<1 || scopes[depth-1]!=4 {return false;}}
  else if op==11 {if depth>0 {depth-=1;}else if pos!=code.len {return false;}}
  else if op==0x10 {let n=i08_same_target::read_leb(code,pos,code.len);if !n.ok || n.next!=pos+1 || count>=12 || n.value!=calls[count] {return false;}
   let step=proof.steps[count];let parent=if depth>0 {stack[depth-1]} else {-1};
   if step.kind!=count+1 || step.site!=site || step.callee!=n.value || step.depth!=depth || step.parent!=parent ||
      (count==3 && depth!=1) || (count!=3 && depth!=0) {return false;}
   // Abstract bits: entered frame=1, owner=2, uninitialized input=4,
   // frozen input loan=8, exclusive builder=16, frozen result loan=32.
   // This bookkeeping is a local proof of the fixed trace, not a handle.
   if count==3 {if state!=3 || step.before!=1 || step.after!=0 {return false;}}
   else {
    if step.before!=state {return false;}var next=state;
    if count==1 {if state!=0{return false;}next=1;}
    else if count==2 {if state!=1{return false;}next=3;}
    else if count==4 {if state!=3{return false;}next=7;}
    else if count==5 {if state!=7{return false;}next=11;}
    else if count==6 {if state!=11{return false;}next=27;}
    else if count==7 {if state!=27{return false;}next=43;}
    else if count==8 {if state!=43{return false;}next=11;}
    else if count==9 {if state!=11{return false;}next=3;}
    else if count==10 {if state!=3{return false;}next=1;}
    else if count==11 {if state!=1{return false;}next=0;}
    if step.after!=next {return false;}state=next;
   }
   count+=1;pos=n.next;}
  else if op==0x0c || op==0x0d || op==0x20 || op==0x21 || op==0x22 {pos=m12_caller_flow_bytes::unsigned_end(code,pos);}
  else if op==0x41 {pos=m12_caller_flow_bytes::skip_signed(code,pos);}
  else if op==0x28 || op==0x2d || op==0x36 || op==0x3a {
   if op==0x2d {if loads>=3{return false;}load_site[loads]=site;loads+=1;}
   if op==0x3a {if stores>=2{return false;}store_site[stores]=site;stores+=1;}
   pos=m12_caller_flow_bytes::unsigned_end(code,pos);if pos<0{return false;}pos=m12_caller_flow_bytes::unsigned_end(code,pos);
  }
  else if op!=0 && op!=0x0f && op!=0x45 && op!=0x46 && op!=0x47 && op!=0x48 && op!=0x49 && op!=0x4b && op!=0x4c && op!=0x4d && op!=0x4f && op!=0x6a && op!=0x6b && op!=0x6c && op!=0x71 && op!=0x72 {return false;}
  if pos<0 || pos>code.len{return false;}
 }
 if count!=12 || depth!=0 || state!=0 || loads!=3 || stores!=2 || proof.padding_load!=load_site[0] || proof.input_load!=load_site[1] ||
    proof.input_store!=store_site[0] || proof.output_load!=load_site[2] || proof.output_store!=store_site[1] {return false;}
 let x=proof.steps;
 // Source of owner slot/gen/count and result-slot operands must be the same
 // local values passed through each checked runtime transition.
 if !before(code,x[0].site,[0x41 as u8,0x80,0x08]) || !before(code,x[2].site,[0x41 as u8,0xc0,0x01]) ||
    !after(code,x[2].site+2,[0x21 as u8,7]) || !before(code,x[4].site,[0x20 as u8,7,0x20,8,0x20,5]) ||
    !before(code,x[5].site,[0x20 as u8,7,0x20,8]) || !before(code,x[6].site,[0x20 as u8,7,0x20,8,0x41,8]) ||
    !before(code,x[7].site,[0x41 as u8,0,0x41,0xa0,0x81,3,0x41,0x80,0x81,3]) {return false;}
 for i in 8..11 {if !before(code,x[i].site,[0x20 as u8,7,0x20,8]) {return false;}}
 // Reservation-failure frame leave must be nested under owner <= 0;
 // cleanup calls are at the top level in output/input/owner/frame order.
 if x[3].parent<5 || !before(code,x[3].parent,[0x20 as u8,7,0x41,0,0x4c]) ||
    !after(code,x[3].parent,[0x04 as u8,0x40]) {return false;}
 let trap_on_error:u8[6]=[0x45,0x45,0x04,0x40,0,0x0b];
 for i in [0,3,4,6,8,9,10,11] {if !after(code,x[i].site+2,trap_on_error) {return false;}}
 if !after(code,x[1].site+2,[0x21 as u8,14]) || !after(code,x[5].site+2,[0x20 as u8,5,0x47,0x04,0x40,0,0x0b]) {return false;}
 // These independently pinned instruction segments connect the call sites to
 // actual argument construction, checked result, copy loops and publication.
 let frame_fail:u8[109]=[33,14,32,14,69,69,4,64,32,14,65,123,71,4,64,0,11,65,128,160,2,65,129,128,196,217,4,54,2,0,65,132,160,2,65,219,0,54,2,0,65,136,160,2,65,5,54,2,0,65,140,160,2,65,0,54,2,0,65,144,160,2,65,0,54,2,0,65,148,160,2,65,0,54,2,0,65,152,160,2,65,0,54,2,0,65,156,160,2,65,0,54,2,0,65,160,3,65,0,54,2,0,65,5,15,11,65,192,1];
 let reserve_fail:u8[147]=[4,64,32,7,69,4,64,0,11,32,7,65,125,72,4,64,0,11,65,0,32,7,107,65,1,107,33,4,16,19,69,69,4,64,0,11,65,128,160,2,65,129,128,196,217,4,54,2,0,65,132,160,2,65,219,0,54,2,0,65,136,160,2,65,3,54,2,0,65,140,160,2,65,0,54,2,0,65,144,160,2,65,0,54,2,0,65,148,160,2,65,0,54,2,0,65,156,160,2,65,0,54,2,0,65,152,160,2,32,4,54,2,0,65,160,3,65,0,54,2,0,65,3,15,11,32,7,65,1,71,4,64,0,11,65,32,40,2,0,33,8,32,7,32,8,32,5];
 let input_copy:u8[68]=[69,69,4,64,0,11,65,136,2,40,2,0,33,9,65,0,33,12,2,64,3,64,32,12,32,5,65,16,108,79,13,1,32,9,32,12,106,65,160,128,2,32,6,106,32,12,106,45,0,0,58,0,0,32,12,65,1,106,33,12,12,0,11,11,32,7,32,8];
 let record_map:u8[83]=[69,69,4,64,0,11,65,200,2,40,2,0,33,10,65,128,129,3,32,5,69,4,127,65,0,5,32,9,11,54,2,0,65,128,129,3,32,5,54,2,4,65,128,129,3,65,168,128,2,40,2,0,54,2,8,65,128,129,3,32,10,54,2,12,65,128,129,3,65,8,54,2,16,65,0,65,160,129,3,65,128,129,3];
 let result_copy:u8[160]=[65,160,129,3,40,2,0,69,69,4,64,0,11,65,164,129,3,40,2,0,32,5,71,4,64,0,11,65,172,129,3,40,2,0,32,5,71,4,64,0,11,65,168,129,3,40,2,0,32,5,69,4,127,65,0,5,32,10,11,71,4,64,0,11,65,8,32,5,65,8,108,106,33,11,65,0,33,3,32,11,32,2,75,4,64,65,2,33,3,5,65,160,160,2,32,5,54,2,0,65,164,160,2,65,8,54,2,0,65,0,33,12,2,64,3,64,32,12,32,5,65,8,108,79,13,1,65,168,160,2,32,12,106,32,10,32,12,106,45,0,0,58,0,0,32,12,65,1,106,33,12,12,0,11,11,11,32,7,32,8];
 let publish:u8[111]=[69,69,4,64,0,11,65,0,33,4,32,3,69,4,127,32,11,5,65,0,11,33,14,65,128,160,2,65,129,128,196,217,4,54,2,0,65,132,160,2,65,219,0,54,2,0,65,136,160,2,32,3,54,2,0,65,140,160,2,32,14,54,2,0,65,144,160,2,32,11,54,2,0,65,148,160,2,32,5,54,2,0,65,152,160,2,32,4,54,2,0,65,156,160,2,65,0,54,2,0,65,160,3,65,0,54,2,0,32,3,11];
 if !after(code,x[1].site+2,frame_fail) || x[1].site+2+frame_fail.len!=x[2].site ||
    !after(code,x[3].parent,reserve_fail) || x[3].parent+reserve_fail.len!=x[4].site ||
    !after(code,x[4].site+2,input_copy) || x[4].site+2+input_copy.len!=x[5].site ||
    !after(code,x[6].site+2,record_map) || x[6].site+2+record_map.len!=x[7].site ||
    !after(code,x[7].site+2,result_copy) || x[7].site+2+result_copy.len!=x[8].site ||
    !after(code,x[11].site+2,publish) || x[11].site+2+publish.len!=code.len {return false;}
 // Initialized input is copied before freeze; output bytes are copied only
 // after the source-bound call and before ending either loan.
 return proof.padding_load<x[0].site && x[4].site<proof.input_load && proof.input_load<proof.input_store && proof.input_store<x[5].site &&
  x[7].site<proof.output_load && proof.output_load<proof.output_store && proof.output_store<x[8].site &&
  x[8].site<x[9].site && x[9].site<x[10].site && x[10].site<x[11].site;
}
