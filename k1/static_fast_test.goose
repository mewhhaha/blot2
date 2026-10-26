import std;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_fast_verify;
import static_fast_eval;
fn compare(s:u8[:]) {
 var p=static_product_parse::parse(s);assert(p.status==0);
 let expected=static_product_eval::evaluate(s,p.tree);let actual,stats=static_fast_eval::evaluate(s,p.tree);
 assert(static_product_verify::verify(s,p.tree)==static_fast_verify::verify(s,p.tree));
 assert(expected.status==actual.status && expected.steps==actual.steps && expected.bytes==actual.bytes && expected.data[..]==actual.data[..]);
 assert(stats.verify_parses<=p.tree.parts.len && stats.eval_parses<=p.tree.parts.len);
 for i in p.tree.parts.len {
  let old=p.tree.parts[i].start;p.tree.parts[i].start+=1;
  assert(!static_product_verify::verify(s,p.tree) && !static_fast_verify::verify(s,p.tree));
  let x,_=static_fast_eval::evaluate(s,p.tree);assert(x.status==1 && x.data.len==0);p.tree.parts[i].start=old;
 }
}
fn main() {
 for s in ["static let a = #[(1,2),(1,2)]", "static let a = #[(1,2),(3,4),(1,2)]",
   "static let a = #[(4294967295+1,0),(1,0)]", "static let a = #[(1,-0.0),(1,0.0/0.0)]",
   "static let a = #[(1,2),(1,2),(0-1,2)]"] {compare(s);}
 for size in [2,3,16] {for seed in 20 {
   var s:u8[>..]=[];s.append("static let data = #[");
   for row in 6 {if row>0 {s.push(',');}s.push('(');for col in size {if col>0 {s.push(',');}
     let n=(seed*31+row*7+col*3)%19;format(s,n);if (seed+col)%3==0 {s.append(" & 7");}}
     s.push(')');}s.push(']');compare(s);
 }}
 var repetitive:u8[>..]=[];repetitive.append("static let many = #[");for i in 8193 {if i>0 {repetitive.push(',');}repetitive.append("(1,2)");}repetitive.push(']');
 var p=static_product_parse::parse(repetitive);assert(p.status==0);let expected=static_product_eval::evaluate(repetitive,p.tree);let actual,stats=static_fast_eval::evaluate(repetitive,p.tree);
 assert(expected.status==0 && actual.status==0 && actual.data[..]==expected.data[..] && actual.steps==expected.steps && actual.bytes==expected.bytes);
 assert(stats.verify_parses==2 && stats.eval_parses==2 && stats.eval_hits==16386);
 print("equivalent source-bound static cache cases passed");
}
