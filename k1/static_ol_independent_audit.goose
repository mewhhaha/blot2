import work;
import static_ol_layout;
import static_ol_image;
import static_ol_pipeline;
import static_product_eval;
fn phase5(seed:u32)->work::ScheduledWork {
 var w=work::ScheduledWork {meter:work::Meter {semantic:seed}};for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));assert(work::schedule_begin(w,5));return w;
}
fn phase6(seed:u32)->work::ScheduledWork {var w=phase5(seed);assert(work::schedule_end(w,5) && work::schedule_begin(w,6));return w;}
fn main(){
 let source="static let a = #[(1,2)]";var value=static_product_eval::Result {status:0,steps:3,bytes:8,data:[1,2,3,4,5,6,7,8]};
 let hi:i64=9223372036854775807;let lo:i64= -9223372036854775807-1;
 for rows in [lo,-1,0] {var w=phase5(0);assert(static_ol_layout::check(rows,2,value,w)==1 && w.meter.semantic==1);}
 for width in [lo,-1,0,1,17,hi] {var w=phase5(0);assert(static_ol_layout::check(1,width,value,w)==1 && w.meter.semantic==2);}
 for width in 2..17 {var w=phase5(0);assert(static_ol_layout::check(hi,width,value,w)==1 && w.meter.semantic==3);}
 var mk=phase6(0);var made=static_ol_pipeline::make_image(source,value,1,2,mk);assert(made.status==0);
 for i in source.len {var bad=copy(made.image);bad.source[i]^=1;var w=phase6(0);assert(static_ol_image::verify(source,value,1,2,bad,w)==1);assert(w.meter.semantic==7 && w.meter.source_byte_reads==(2*(i+1)) as u64);}
 for i in value.data.len {var bad=copy(made.image);bad.data[i]^=1;var w=phase6(0);assert(static_ol_image::verify(source,value,1,2,bad,w)==1);assert(w.meter.semantic==8+i && w.meter.source_byte_reads==(2*source.len) as u64);}
 let max:u64=~(0 as u64);var w=phase6(0);w.meter.source_byte_reads=max;assert(static_ol_image::verify(source,value,1,2,made.image,w)==6 && w.meter.source_byte_reads==max);
 print("independent extreme metadata, short-circuit and source-byte controls passed");
}
