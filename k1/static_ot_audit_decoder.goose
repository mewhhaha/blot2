import work;
import os;
import static_publish_build;
import static_ot_emit;
import static_ot_check;
fn phase7()->work::ScheduledWork {
 var w=work::ScheduledWork {};for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 for p in 5..7 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){let source="static let a = #[(1,-0.0),(3,0.0/0.0)]";var image=static_publish_build::build(source);assert(image.status==0);var w=phase7();let actual=static_ot_emit::emit(image.image,w);assert(actual.status==0);assert(write_file("audit-static.wasm",actual.bytes));print("emitter target visits ",w.meter.target_visits);var checked=phase7();assert(static_ot_check::verify(image.image,actual.bytes,checked)==0);assert(checked.meter.target_visits==(actual.bytes.len as u64)+(image.image.data.len as u64));print("independent decoder-byte bound ",checked.meter.target_visits);}
