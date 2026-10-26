import std;
import static_product_parse;
import static_product_eval;
import static_fast_eval;
fn main() {
 for count in [14285,14286] {
  var s:u8[>..]=[];s.append("static let data = #[");for i in count {if i>0 {s.push(',');}s.append("(1+1,2+2)");}s.push(']');
  var tree=static_product_parse::parse(s);assert(tree.status==0);
  let a=static_product_eval::evaluate(s,tree.tree);let b,_=static_fast_eval::evaluate(s,tree.tree);
  assert(a.status==b.status && a.steps==b.steps && a.bytes==b.bytes && a.data[..]==b.data[..]);
  assert(if count==14285 {a.status==0 && a.steps==99996} else {a.status==2 && a.steps==100000 && a.data.len==0});
 }
 print("static budget boundary and failure atomicity matched");
}
