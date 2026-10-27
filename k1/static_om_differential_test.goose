import std;
import work;
import static_publish_build;
import static_publish_wasm;
import static_ot_emit;
import static_ot_check;
import static_om_pipeline;
fn phase7()->work::ScheduledWork {
 var w=work::ScheduledWork {};for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 for p in 5..7 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){
 for seed in 120 {
  var source:u8[>..]=[];source.append("static let a = #[");for row in 4 {if row>0 {source.push(',');}
   let a=(seed*7+row*3)%31;let b=(seed*11+row*5)%31;
   format(source,"(",a,if seed%3==0 {" + 0"} else {""},",",b,if seed%5==0 {".0 / 0.0"} else if seed%2==0 {".0"} else {""},")");}source.push(']');
  var base=static_publish_build::build(source);let built=static_om_pipeline::build(source,0);assert(base.status==built.status);
  if base.status==0 {let expected=static_publish_wasm::emit(source,base.image);assert(built.wasm[..]==expected[..] && work::schedule_complete(built.work));
   var w=phase7();assert(static_ot_check::verify(base.image,expected,w)==0);}else {assert(built.wasm.len==0 && built.work.failed);}
 }
 var source:u8[>..]=[];source.append("static let wide = #[");for i in 8193 {if i>0 {source.push(',');}source.append("(1,2)");}source.push(']');
 var image=static_publish_build::build(source);assert(image.status==0 && image.image.bytes==65544);
 let baseline=static_publish_wasm::emit(source,image.image);var w=phase7();let made=static_ot_emit::emit(image.image,w);assert(made.status==0 && made.bytes[..]==baseline[..]);
 var checked=phase7();assert(static_ot_check::verify(image.image,made.bytes,checked)==0);
 for i in [0,8,64,128,made.bytes.len-1] {var changed=copy(made.bytes);changed[i]^=1;var denied=phase7();assert(static_ot_check::verify(image.image,changed,denied)!=0);}
 var extra:u8[>..]=[];extra.append(made.bytes);extra.push(0);var denied=phase7();assert(static_ot_check::verify(image.image,extra,denied)!=0);
 print("metered target matches baseline over 120 programs and multi-page data");
}
