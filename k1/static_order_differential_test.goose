import std;
import work;
import static_publish_build;
import static_publish_wasm;
import static_order_pipeline;
fn main(){
 for seed in 120 {
  var source:u8[>..]=[];source.append("static let a = #[");
  for row in 4 {if row>0 {source.push(',');}let a=(seed*7+row*3)%31;let b=(seed*11+row*5)%31;
   format(source,"(",a,if seed%3==0 {" + 0"} else {""},",",b,if seed%5==0 {".0 / 0.0"} else if seed%2==0 {".0"} else {""},")");}
  source.push(']');var base=static_publish_build::build(source);let actual=static_order_pipeline::build(source,0);assert(base.status==actual.status);
  if base.status==0 {let bytes=static_publish_wasm::emit(source,base.image);assert(bytes[..]==actual.wasm[..] && work::schedule_complete(actual.work));}
  else {assert(actual.wasm.len==0 && actual.work.failed);}
 }
 print("ordered static target matches 120 baseline programs");
}
