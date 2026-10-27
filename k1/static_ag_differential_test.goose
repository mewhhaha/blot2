import std;
import work;
import static_product_parse;
import static_product_verify;
import static_product_eval;
import static_publish_build;
import static_ag_parse;
import static_ag_verify;
import static_ag_eval;
import static_ag_pipeline;
fn compare(source:u8[:]) {
 var baseline=static_product_parse::parse(source);var parsed=static_ag_parse::parse(source,work::Meter {});assert(baseline.status==parsed.status);
 if baseline.status!=0{return;}
 assert(static_product_verify::verify(source,baseline.tree));
 let v1=static_ag_verify::verify(source,parsed.tree,work::Meter {},false);let v2=static_ag_verify::verify(source,parsed.tree,work::Meter {},true);
 assert(v1.status==0 && v2.status==0 && v1.meter.semantic==v2.meter.semantic && v1.meter.phase_semantic[..]==v2.meter.phase_semantic[..]);
 let old=static_product_eval::evaluate(source,baseline.tree);let a=static_ag_eval::evaluate(source,parsed.tree,work::Meter {},false);let b=static_ag_eval::evaluate(source,parsed.tree,work::Meter {},true);
 assert(old.status==a.status && a.status==b.status && old.steps==a.steps && a.steps==b.steps && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
 if old.status==0 {assert(a.value.data[..]==old.data[..] && b.value.data[..]==old.data[..]);}else {assert(a.value.data.len==0 && b.value.data.len==0);}
 var expected=static_publish_build::build(source);let x=static_ag_pipeline::build(source,work::Meter {},false);let y=static_ag_pipeline::build(source,work::Meter {},true);
 assert(x.status==expected.status && y.status==expected.status && x.meter.semantic==y.meter.semantic && x.meter.phase_semantic[..]==y.meter.phase_semantic[..]);
 if x.status==0 {assert(x.image.data[..]==expected.image.data[..] && y.image.data[..]==expected.image.data[..]);}else {assert(x.image.data.len==0 && y.image.data.len==0);}
}
fn main(){
 for seed in 120 {
  var source:u8[>..]=[];source.append("static let p = #[");
  for row in 4 {if row>0 {source.push(',');}let a=(seed*7+row*3)%31;let b=if seed%4==0 {1} else {(seed*11+row*5)%31};
   format(source,"(",a,if seed%3==0 {" + 0"} else {""},",",b,if seed%5==0 {".0 / 0.0"} else if seed%2==0 {".0"} else {""},")");}
  source.push(']');compare(source);
 }
 for source in ["static let bad = #[(4294967295+1,2)]", "static let bad = #[(1,2),(1,2.0)]", "static let bad = #[]", "static let bad = #[(host(),1)]"] {compare(source);}
 print("source/image aggregate baseline and metered cold/cache differential passed");
}
