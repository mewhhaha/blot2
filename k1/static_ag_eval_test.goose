import work;
import static_product_parse;
import static_product_eval;
import static_ag_parse;
import static_ag_eval;
fn main() {
 for source in ["static let a = #[(1,2),(1,2)]", "static let a = #[(1,-0.0),(2,0.0/0.0)]", "static let a = #[(4294967295+1,2),(1,2)]", "static let a = (1+2,3)"] {
  var p=static_product_parse::parse(source);assert(p.status==0);
  let baseline=static_product_eval::evaluate(source,p.tree);
  let cold=static_ag_eval::evaluate(source,p.tree,work::Meter {},false);let hot=static_ag_eval::evaluate(source,p.tree,work::Meter {},true);
  assert(cold.status==baseline.status && hot.status==baseline.status && cold.steps==baseline.steps && hot.steps==baseline.steps);
  assert(cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
  if baseline.status==0 {assert(cold.value.data[..]==baseline.data[..] && hot.value.data[..]==baseline.data[..]);}
  else {assert(cold.value.data.len==0 && hot.value.data.len==0);}
  let visits=cold.meter.semantic;
  for allowed in visits+1 {
   let a=static_ag_eval::evaluate(source,p.tree,work::Meter {semantic:1048576-allowed},false);
   let b=static_ag_eval::evaluate(source,p.tree,work::Meter {semantic:1048576-allowed},true);
   assert(a.status==b.status && a.steps==b.steps && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
   if allowed<visits {assert(a.status==4 && a.value.data.len==0 && a.meter.semantic==1048576);}else {assert(a.status==baseline.status);}
  }
  var invalid=copy(p.tree);invalid.parts[0].start+=1;assert(static_ag_eval::evaluate(source,invalid,work::Meter {},true).status!=0);
  assert(static_ag_eval::evaluate(source,p.tree,work::Meter {source_byte_reads:~(0 as u64)},true).status==6);
 }
 let source="static let x = #[(1,2),(1,2)]";let parsed=static_ag_parse::parse(source,work::Meter {});assert(parsed.status==0);
 let value=static_ag_eval::evaluate(source,parsed.tree,parsed.meter,true);assert(value.status==0 && value.meter.semantic>parsed.meter.semantic);
 print("actual metered aggregate evaluation cold/cache parity passed");
}
