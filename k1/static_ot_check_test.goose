import work;
import static_publish_build;
import static_publish_wasm;
import static_ot_check;
fn phase7(seed:u32,target:u64)->work::ScheduledWork {
 var w=work::ScheduledWork {meter:work::Meter {semantic:seed,target_visits:target}};
 for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 for p in 5..7 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_begin(w,7));return w;
}
fn main(){let source="static let a = #[(1,-0.0),(3,0.0/0.0)]";var image=static_publish_build::build(source);assert(image.status==0);let bytes=static_publish_wasm::emit(source,image.image);
 var w=phase7(0,0);assert(static_ot_check::verify(image.image,bytes,w)==0);let visits=w.meter.semantic;let target=w.meter.target_visits;assert(visits>0 && target>bytes.len);
 for allowed in visits+1 {var m=phase7(1048576-allowed,0);let status=static_ot_check::verify(image.image,bytes,m);
  if allowed<visits {assert(status==4 && m.meter.semantic==1048576 && m.failed);}else {assert(status==0);}}
 for allowed in target {var m=phase7(0,~(0 as u64)-allowed);let status=static_ot_check::verify(image.image,bytes,m);assert(status==6 && m.failed);}
 for i in bytes.len {var changed=copy(bytes);changed[i]^=1;var m=phase7(0,0);assert(static_ot_check::verify(image.image,changed,m)!=0);}
 for i in bytes.len {var m=phase7(0,0);assert(static_ot_check::verify(image.image,bytes[..i],m)!=0);}
 print("independent metered target decode and boundaries passed");}
