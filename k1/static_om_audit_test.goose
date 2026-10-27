import work;
import static_float;
import static_om_float;
import static_om_pipeline;
import static_om_image;
import static_product_eval;
fn phase6(seed:u32)->work::ScheduledWork {
 var w=work::ScheduledWork {meter:work::Meter {semantic:seed}};
 for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));
 assert(work::schedule_begin(w,5) && work::schedule_end(w,5) && work::schedule_begin(w,6));return w;
}
fn main() {
 var state:u32=0x12345678;
 for i in 4096 {
  state=((state as u64*1664525+1013904223)&4294967295) as u32;let a=state;
  state=((state as u64*1664525+1013904223)&4294967295) as u32;let b=state;
  for op in [5,6,7,8] {var m=work::Meter {};let actual=static_om_float::arithmetic(op,a,b,m);assert(actual.status==0 && actual.value==static_float::arithmetic(op,a,b));}
 }
 let source="static let a = #[(1,2)]";
 var value=static_product_eval::Result {status:0,steps:3,bytes:8,data:[1,2,3,4,5,6,7,8]};
 var w=phase6(0);var made=static_om_pipeline::make_image(source,value,1,2,w);assert(made.status==0 && made.image.data[..]==value.data[..]);let copy_visits=w.meter.semantic;assert(copy_visits==8);
 for allowed in copy_visits {var cut=phase6(1048576-allowed);let failed=static_om_pipeline::make_image(source,value,1,2,cut);assert(failed.status==4 && failed.image.data.len==0);}
 var checked=phase6(0);assert(static_om_image::verify(source,value,1,2,made.image,checked)==0);let check_visits=checked.meter.semantic;assert(check_visits==9);
 for allowed in check_visits {var cut=phase6(1048576-allowed);assert(static_om_image::verify(source,value,1,2,made.image,cut)==4);}
 for i in value.data.len {var forged=copy(made.image);forged.data[i]^=1;var cut=phase6(0);assert(static_om_image::verify(source,value,1,2,forged,cut)!=0);}
 for i in source.len {var forged=copy(made.image);forged.source[i]^=1;var cut=phase6(0);assert(static_om_image::verify(source,value,1,2,forged,cut)!=0);}
 print("random F32 bit parity and independent image precharge/forgery controls passed");
}
