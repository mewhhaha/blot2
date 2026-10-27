// Private, PARTIAL visit schedule for the actual source-bound leaf contract.
// Existing source/type/proof replay is unmetered. This is not C09 admission.
namespace semantic_contract_metered;
import work;
import short_check;
import semantic_leaf;
struct Result {status:i64=1,receipt:work::Receipt=work::Receipt {}}
fn event(m:work::Meter&,phase:u32,kind:u32)->Result {
 let r=work::charge(m,phase,kind);
 if r.status==0{return Result {status:0};}
 return Result {status:if r.status==1 {2} else {3},receipt:r};
}
// 0 valid, 1 invalid, 2 semantic limit, 3 accounting error. Source replay
// remains required and runs before contract events, but is not yet metered.
fn check(source:u8[:],c:semantic_leaf::Core&,m:work::Meter&,phase:u32)->Result {
 if !short_check::verify(source,c.program) {return Result {};}
 let effect=event(m,phase,7);if effect.status!=0{return effect;}
 if c.effects!=0 {return Result {};}
 let layout=event(m,phase,10);if layout.status!=0{return layout;}
 if c.actual_depth!=1 || c.actual_frame!=0 || c.declared_depth!=c.program.head.depth || c.declared_frame!=c.program.head.frame || c.declared_depth<1 || c.declared_depth>128 {return Result {};}
 if c.program.binding_types.len!=c.program.tree.bindings.len || c.program.types.len!=c.program.tree.nodes.len {return Result {};}
 for i in c.program.binding_types.len {
  let q=event(m,phase,6);if q.status!=0{return q;}
  let t=c.program.binding_types[i];if t!=1 && t!=2{return Result {};}
 }
 var loops:u32=0;
 for i in c.program.tree.nodes.len {
  let q=event(m,phase,4);if q.status!=0{return q;}
  let n=c.program.tree.nodes[i];if n.tag==15 {loops+=1;}
  if n.tag!=1 && n.tag!=2 && n.tag!=3 && n.tag!=4 && n.tag!=6 && n.tag!=9 && n.tag!=10 && n.tag!=11 && n.tag!=12 && n.tag!=13 && n.tag!=14 && n.tag!=15 && n.tag!=16 && n.tag!=17 && n.tag!=18 && n.tag!=19 && n.tag!=20 && n.tag!=21 && n.tag!=22 && n.tag!=23 && n.tag!=24 && n.tag!=25 && n.tag!=26 && n.tag!=27 && n.tag!=28 {return Result {};}
  let ty=event(m,phase,6);if ty.status!=0{return ty;}
  if c.program.types[i]<1 || c.program.types[i]>4{return Result {};}
 }
 if loops!=c.loops || loops>128{return Result {};}
 return Result {status:0};
}
