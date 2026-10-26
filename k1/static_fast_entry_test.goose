import static_product_parse;
import static_product_eval;
import static_publish_build;
import static_publish_wasm;
import static_fast_entry;
fn main() {
 for source in ["static let a = #[(1,2),(1,2)]", "static let f = #[(1,0.0/0.0),(2,-0.0)]", "static let p = (1,2)"] {
  var parsed=static_product_parse::parse(source);assert(parsed.status==0);
  let baseline=static_product_eval::evaluate(source,parsed.tree);let fast,_=static_fast_entry::evaluate(source);
  assert(baseline.status==fast.status && baseline.steps==fast.steps && baseline.bytes==fast.bytes && baseline.data[..]==fast.data[..]);
  var standard=static_publish_build::build(source);var candidate,_=static_fast_entry::build_image(source);
  assert(standard.status==candidate.status);
  if standard.status==0 {
   assert(standard.image.data[..]==candidate.image.data[..] && standard.image.steps==candidate.image.steps);
   let expected=static_publish_wasm::emit(source,standard.image);let actual=static_publish_wasm::emit(source,candidate.image);
   assert(expected.len>0 && expected[..]==actual[..]);
  } else {assert(candidate.image.data.len==0);}
 }
 for source in ["static let x = #[]", "static let x = #[(4294967295+1,0)]", "static let x = #[(1,host())]"] {
  let value,_=static_fast_entry::evaluate(source);let image,_=static_fast_entry::build_image(source);
  assert(value.status!=0 && value.data.len==0 && image.status!=0 && image.image.data.len==0);
 }
 print("optional source-bound static entry matches baseline");
}
