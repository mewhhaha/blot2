// Phase 3 executes each independently validated retained scalar tree, with
// primitive and semantic work charged before the covered operations.
namespace static_order_eval;
import work;
import static_budget;
import static_product_eval;
import static_ag_scalar;
import static_order_core;
fn evaluate(owned:static_order_core::Owned&,w:work::ScheduledWork&)->static_product_eval::Result {
 var budget=static_budget::Budget {};var out:u8[>..]=[];
 if owned.scalars.len>0 {let first=work::scheduled_charge(w,3,2);if first.status!=0{return static_product_eval::Result {status:if first.status==1 {4} else {5}};}}
 for scalar,i in owned.scalars {
  let value=static_ag_scalar::evaluate(scalar,w.meter,budget);
  if value.status!=0{return static_product_eval::Result {status:value.status,steps:budget.steps};}
  if !static_budget::produce(budget,4){return static_product_eval::Result {status:2,steps:budget.steps};}
  let output=work::scheduled_charge(w,3,3);if output.status!=0{return static_product_eval::Result {status:if output.status==1 {4} else {5},steps:budget.steps};}
  for k in 4 {out.push(((value.bits>>(k*8))&255) as u8);}
  if (i+1)%owned.product.width==0 && !static_budget::step(budget){return static_product_eval::Result {status:2,steps:budget.steps};}
  if i+1<owned.scalars.len {let next=work::scheduled_charge(w,3,2);if next.status!=0{return static_product_eval::Result {status:if next.status==1 {4} else {5},steps:budget.steps};}}
 }
 if !static_budget::step(budget){return static_product_eval::Result {status:2,steps:budget.steps};}
 return static_product_eval::Result {status:0,steps:budget.steps,bytes:budget.bytes,data:copy(out)};
}
