// Paired local benchmark of one private static-array evaluation phase, NOT a
// K1/legacy compiler comparison. Identical owned source and candidate tree are
// checked and evaluated by both implementations; source parse is outside the
// timed interval. Keep the outputs and order visible for reproducibility.
import os;
import std;
import static_product_parse;
import static_product_eval;
import static_fast_eval;
fn fingerprint(data:u8[:])->u32 {
 var h:u32=2166136261;for v in data {h=(((h^v) as u64*16777619)&4294967295) as u32;}return h;
}
fn bench(vary:bool) {
 var source:u8[>..]=[];source.append("static let data = #[");
 for i in 8193 {if i>0 {source.push(',');}if vary {format(source,"(",i,",",i+8193,")");}else {source.append("(1,2)");}}
 source.push(']');var p=static_product_parse::parse(source);assert(p.status==0);
 let old=static_product_eval::evaluate(source,p.tree);let fresh,stats=static_fast_eval::evaluate(source,p.tree);
 assert(old.status==0 && fresh.status==0 && old.steps==fresh.steps && old.bytes==fresh.bytes && old.data[..]==fresh.data[..]);
 print("case ",if vary {"unique"} else {"repeated"}," rows=8193 bytes=",old.bytes," steps=",old.steps," old_fnv32=",fingerprint(old.data)," new_fnv32=",fingerprint(fresh.data)," verify_parses=",stats.verify_parses," eval_parses=",stats.eval_parses);
 for _ in 4 {let a=static_product_eval::evaluate(source,p.tree);let b,_=static_fast_eval::evaluate(source,p.tree);assert(a.status==0 && b.status==0 && a.steps==b.steps && a.data[..]==b.data[..]);}
 for round in 31 {
  if round%2==0 {
   let a=clock_ns();let x=static_product_eval::evaluate(source,p.tree);let b=clock_ns();let y,_=static_fast_eval::evaluate(source,p.tree);let c=clock_ns();
   assert(x.status==0 && y.status==0 && x.steps==y.steps && x.data[..]==y.data[..]);print("sample ",round," old_ns=",b-a," new_ns=",c-b);
  } else {
   let a=clock_ns();let y,_=static_fast_eval::evaluate(source,p.tree);let b=clock_ns();let x=static_product_eval::evaluate(source,p.tree);let c=clock_ns();
   assert(x.status==0 && y.status==0 && x.steps==y.steps && x.data[..]==y.data[..]);print("sample ",round," new_ns=",b-a," old_ns=",c-b);
  }
 }
}
fn main(){bench(false);bench(true);}
