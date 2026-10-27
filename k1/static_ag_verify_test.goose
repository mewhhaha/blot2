import work;
import static_product_parse;
import static_product_verify;
import static_ag_verify;
fn main(){
 for source in ["static let a = #[(1,2),(1,2)]", "static let a = #[(1,-0.0),(2,0.0/0.0)]", "static let a = (1+2,3)"] {
  var p=static_product_parse::parse(source);assert(p.status==0 && static_product_verify::verify(source,p.tree));
  let cold=static_ag_verify::verify(source,p.tree,work::Meter {},false);let hot=static_ag_verify::verify(source,p.tree,work::Meter {},true);
  assert(cold.status==0 && hot.status==0 && cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
  let n=cold.meter.semantic;for allowed in n+1 {
   let a=static_ag_verify::verify(source,p.tree,work::Meter {semantic:1048576-allowed},false);let b=static_ag_verify::verify(source,p.tree,work::Meter {semantic:1048576-allowed},true);
   assert(a.status==b.status && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
   if allowed<n {assert(a.status==4 && a.meter.semantic==1048576);}else {assert(a.status==0);}
  }
  var forged=copy(p.tree);forged.parts[0].end+=1;assert(static_ag_verify::verify(source,forged,work::Meter {},true).status!=0);
  assert(static_ag_verify::verify(source,p.tree,work::Meter {source_byte_reads:~(0 as u64)},true).status==6);
 }
 print("actual aggregate validator cold/cache semantic-visit parity passed");
}
