import work;
import os;
import static_publish_build;
import static_ot_emit;
fn phase7()->work::ScheduledWork {
 var w=work::ScheduledWork {};for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 for p in 5..7 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){let source="static let a = #[(1,-0.0),(3,0.0/0.0)]";var image=static_publish_build::build(source);assert(image.status==0);var w=phase7();let actual=static_ot_emit::emit(image.image,w);assert(actual.status==0);assert(write_file("audit-static.wasm",actual.bytes));assert(w.meter.target_visits==456);print("emitter target visits ",w.meter.target_visits);}
