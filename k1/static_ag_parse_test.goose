import work;
import static_product_parse;
import static_ag_parse;
fn main(){
 for source in ["static let a = #[(1,2),(3,4)]", "static let a = #[(1,-0.0),(2,0.0/0.0)]", "static let a = (1+2,3)"] {
  var old=static_product_parse::parse(source);var p=static_ag_parse::parse(source,work::Meter {});
  assert(old.status==0 && p.status==0 && p.tree.source[..]==old.tree.source[..] && p.tree.parts.len==old.tree.parts.len && p.tree.width==old.tree.width && p.tree.rows==old.tree.rows);
  for part,i in old.tree.parts {let q=p.tree.parts[i];assert(q.start==part.start && q.end==part.end && q.ty==part.ty);}
  assert(p.meter.semantic>0 && p.meter.source_byte_reads>0);let v=p.meter.semantic;
  for allowed in v {let no=static_ag_parse::parse(source,work::Meter {semantic:1048576-allowed});assert(no.status==4 && no.meter.semantic==1048576 && no.tree.parts.len==0);}
  let exact=static_ag_parse::parse(source,work::Meter {semantic:1048576-v});assert(exact.status==0 && exact.meter.semantic==1048576);
  for allowed in p.meter.source_byte_reads {let no=static_ag_parse::parse(source,work::Meter {source_byte_reads:~(0 as u64)-allowed});assert(no.status==6 && no.tree.parts.len==0);}
 }
 for source in ["static let a = #[]", "static let a = (1,host())", "static let a = #[(1,2),(3,4.0)]"] {
  let old=static_product_parse::parse(source);let p=static_ag_parse::parse(source,work::Meter {});assert(old.status==p.status && p.status!=0);
 }
 print("actual aggregate parser metering and early failures passed");
}
