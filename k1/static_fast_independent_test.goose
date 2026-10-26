import std;
import static_product_core;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_fast_verify;
import static_fast_eval;
fn equal(s:u8[:],t:static_product_core::Tree&) {
 let a=static_product_verify::verify(s,t);let b=static_fast_verify::verify(s,t);assert(a==b);
 let x=static_product_eval::evaluate(s,t);let y,_=static_fast_eval::evaluate(s,t);
 assert(x.status==y.status && x.steps==y.steps && x.bytes==y.bytes && x.data[..]==y.data[..]);
}
fn main() {
 let src="static let item = #[(1+1,1.0),(1+1,1.0),(1 + 1,1.0),(1+1,0.0/0.0),(1+2,1.0)]";
 var p=static_product_parse::parse(src);assert(p.status==0);equal(src,p.tree);
 for i in p.tree.parts.len {for f in 3 {for v in [-1,0,999999,9223372036854775807] {
  let old=p.tree.parts[i];if f==0 {p.tree.parts[i].start=v;}else if f==1 {p.tree.parts[i].end=v;}else {p.tree.parts[i].ty=v;}
  equal(src,p.tree);p.tree.parts[i]=old;
 }}}
 for f in 5 {for v in [-1,0,999999,9223372036854775807] {
 let old=p.tree.name_start;let end=p.tree.name_end;let width=p.tree.width;let rows=p.tree.rows;let arr=p.tree.is_array;
 if f==0 {p.tree.name_start=v;}else if f==1 {p.tree.name_end=v;}else if f==2 {p.tree.width=v;}else if f==3 {p.tree.rows=v;}else {p.tree.is_array=!arr;}
 equal(src,p.tree);p.tree.name_start=old;p.tree.name_end=end;p.tree.width=width;p.tree.rows=rows;p.tree.is_array=arr;
 }}
 for i in p.tree.source.len {let old=p.tree.source[i];p.tree.source[i]=if old=='?' {'!'} else {'?'};equal(src,p.tree);p.tree.source[i]=old;}
 for s in ["static let a = #[(0-1,2),(1+1,2)]","static let a = #[(1+1,2),(0-1,2)]",
 "static let a = #[(4294967295+1,0.0),(1,0.0/0.0)]", "static let a = #[(0,2),(0,2),(0,3),(0,2)]"] {
 var q=static_product_parse::parse(s);assert(q.status==0);equal(s,q.tree);
 }
 print("static exact-key and adversarial equivalence passed");
}
