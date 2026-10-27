// Actual private aggregate traversal with a shared compiler-owned work meter;
// the optional verifier cache replays cold scalar parse/verify visit totals.
// Phase re-entry, runtime/layout/publication work and the full C09 schedule
// remain outside this isolated fixture.
namespace static_ag_eval;
import work;
import static_budget;
import static_product_core;
import static_product_eval;
import static_b_parse;
import static_b_verify;
import static_ag_core;
import static_ag_verify;
import static_ag_scalar;
fn evaluate(source:u8[:],p:static_product_core::Tree&,meter:work::Meter,cached:bool)->static_ag_core::Evaluated {
 let check=static_ag_verify::verify(source,p,meter,cached);if check.status!=0{return static_ag_core::Evaluated {status:check.status,meter:check.meter};}
 var m=check.meter;var budget=static_budget::Budget {};var out:u8[>..]=[];
 for i in p.parts.len {
  let c=static_ag_scalar::charge(m,2);if c!=0{return static_ag_core::Evaluated {status:c,meter:m,steps:budget.steps};}let item=p.parts[i];
  let t=static_ag_scalar::charge(m,6);if t!=0{return static_ag_core::Evaluated {status:t,meter:m,steps:budget.steps};}
  var own:u8[>..]=[];if item.ty==1 {own.append("static let v: U32 = ");}else {own.append("static let v: F32 = ");}
  let read=work::source_read(m,(item.end-item.start) as u64);if read.status!=0{return static_ag_core::Evaluated {status:if read.status==5 {5} else {6},meter:m,steps:budget.steps};}
  own.append(source[item.start..item.end]);own.push('\n');var parsed=static_b_parse::parse(own,m);m=parsed.meter;
  if parsed.status!=0{return static_ag_core::Evaluated {status:parsed.status,meter:m,steps:budget.steps};}
  let verified=static_b_verify::verify(own,parsed.tree,m);m=verified.meter;
  if !verified.ok{return static_ag_core::Evaluated {status:if verified.limited {4} else if verified.work_status==5 {5} else if verified.work_status==6 {6} else {1},meter:m,steps:budget.steps};}
  let value=static_ag_scalar::evaluate(parsed.tree,m,budget);
  if value.status!=0{return static_ag_core::Evaluated {status:value.status,meter:m,steps:budget.steps};}
  if !static_budget::produce(budget,4){return static_ag_core::Evaluated {status:2,meter:m,steps:budget.steps};}
  for k in 4 {out.push(((value.bits>>(k*8))&255) as u8);}
  if (i+1)%p.width==0 && !static_budget::step(budget){return static_ag_core::Evaluated {status:2,meter:m,steps:budget.steps};}
 }
 if p.is_array && !static_budget::step(budget){return static_ag_core::Evaluated {status:2,meter:m,steps:budget.steps};}
 return static_ag_core::Evaluated {status:0,meter:m,steps:budget.steps,value:static_product_eval::Result {status:0,steps:budget.steps,bytes:budget.bytes,data:copy(out)}};
}
