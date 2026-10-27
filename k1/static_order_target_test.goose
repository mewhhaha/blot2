import work;
import static_publish_build;
import static_publish_wasm;
import static_order_target;
fn phase7()->work::ScheduledWork {
 var w=work::ScheduledWork {};for p in 1..4 {assert(work::schedule_begin(w,p as u32));assert(work::schedule_end(w,p as u32));}
 assert(work::schedule_skip_proof(w));for p in 5..7 {assert(work::schedule_begin(w,p as u32));assert(work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){let s="static let a = #[(1,2),(3,4)]";var image=static_publish_build::build(s);assert(image.status==0);let bytes=static_publish_wasm::emit(s,image.image);assert(bytes.len>0);
 var ok=phase7();assert(static_order_target::verify(image.image,bytes,ok)==0 && ok.meter.target_visits==bytes.len);
 for i in bytes.len {var altered=copy(bytes);altered[i]^=1;var m=phase7();assert(static_order_target::verify(image.image,altered,m)!=0);}
 for i in bytes.len {var m=phase7();assert(static_order_target::verify(image.image,bytes[..i],m)!=0);}
 var wrong=phase7();wrong.meter.target_visits=~(0 as u64);assert(static_order_target::verify(image.image,bytes,wrong)==6);
 print("ordered target byte forgery and telemetry boundary passed");}
