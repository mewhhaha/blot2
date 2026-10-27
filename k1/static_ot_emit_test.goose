import work;
import static_publish_build;
import static_publish_wasm;
import static_ot_emit;
fn phase7(seed:u32,target:u64)->work::ScheduledWork {
 var w=work::ScheduledWork {meter:work::Meter {semantic:seed,target_visits:target}};
 for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 for p in 5..7 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){let source="static let a = #[(1,-0.0),(3,0.0/0.0)]";var image=static_publish_build::build(source);assert(image.status==0);let expected=static_publish_wasm::emit(source,image.image);
 var w=phase7(0,0);let actual=static_ot_emit::emit(image.image,w);assert(actual.status==0 && actual.bytes[..]==expected[..]);let visits=w.meter.semantic;let target=w.meter.target_visits;assert(visits>0 && target>actual.bytes.len);
 for allowed in visits+1 {var m=phase7(1048576-allowed,0);let x=static_ot_emit::emit(image.image,m);
  if allowed<visits {assert(x.status==4 && x.bytes.len==0 && m.meter.semantic==1048576 && m.failed);}else {assert(x.status==0 && x.bytes[..]==expected[..]);}}
 for allowed in target {var m=phase7(0,~(0 as u64)-allowed);let x=static_ot_emit::emit(image.image,m);assert(x.status==6 && x.bytes.len==0 && m.failed);}
 var exact=phase7(0,~(0 as u64)-target);let x=static_ot_emit::emit(image.image,exact);assert(x.status==0 && exact.meter.target_visits==~(0 as u64));
 print("actual metered target construction boundaries passed");}
