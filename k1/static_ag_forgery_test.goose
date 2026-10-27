import work;
import static_ag_parse;
import static_ag_verify;
import static_ag_eval;
import static_ag_pipeline;
fn main(){let source="static let q = #[(1,2.0),(1,2.0),(3,2.0)]";var p=static_ag_parse::parse(source,work::Meter {});assert(p.status==0);
 for i in p.tree.parts.len {for field in 3 {for value in [-1,0,9223372036854775807] {let old=p.tree.parts[i];if field==0 {p.tree.parts[i].start=value;}else if field==1 {p.tree.parts[i].end=value;}else {p.tree.parts[i].ty=value;}if p.tree.parts[i].start!=old.start || p.tree.parts[i].end!=old.end || p.tree.parts[i].ty!=old.ty {let a=static_ag_eval::evaluate(source,p.tree,work::Meter {},true);assert(a.status!=0 && a.value.data.len==0);}p.tree.parts[i]=old;}}}
 for i in source.len {var changed:u8[>..]=[];changed.append(source);changed[i]^=1;let v=static_ag_verify::verify(changed,p.tree,work::Meter {},true);assert(v.status!=0);}
 for field in 5 {var t=copy(p.tree);if field==0 {t.width=9223372036854775807;}else if field==1 {t.rows=9223372036854775807;}else if field==2 {t.name_start=-1;}else if field==3 {t.name_end=9223372036854775807;}else {t.is_array=false;}let a=static_ag_eval::evaluate(source,t,work::Meter {},true);assert(a.status!=0 && a.value.data.len==0);}
 print("independent aggregate Core forgery and malformed bounds controls passed");}
