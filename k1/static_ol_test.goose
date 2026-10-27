import work;
import static_ol_layout;
import static_ol_image;
import static_ol_pipeline;
import static_product_eval;
import static_publish_core;
fn phase5(seed:u32)->work::ScheduledWork {
 var w=work::ScheduledWork {meter:work::Meter {semantic:seed}};for p in 1..4 {assert(work::schedule_begin(w,p as u32) && work::schedule_end(w,p as u32));}assert(work::schedule_skip_proof(w));assert(work::schedule_begin(w,5));return w;
}
fn phase6(seed:u32)->work::ScheduledWork {
 var w=phase5(seed);assert(work::schedule_end(w,5) && work::schedule_begin(w,6));return w;
}
fn main() {
 let source="static let a = #[(1,2)]";
 var value=static_product_eval::Result {status:0,steps:3,bytes:8,data:[1,2,3,4,5,6,7,8]};
 var w=phase5(0);assert(static_ol_layout::check(1,2,value,w)==0 && w.meter.semantic==5);
 for allowed in 5 {var cut=phase5((1048576-allowed) as u32);assert(static_ol_layout::check(1,2,value,cut)==4 && cut.meter.semantic==1048576);}
 for case in 5 {var bad=copy(value);var rows:i64=1;var width:i64=2;
  if case==0 {rows=0;}else if case==1 {width=0;}else if case==2 {rows=50001;}else if case==3 {bad.bytes=0;}else {rows=2;}
  var test=phase5(0);assert(static_ol_layout::check(rows,width,bad,test)==1 && test.meter.semantic==case+1);
 }
 var make=phase6(0);var made=static_ol_pipeline::make_image(source,value,1,2,make);assert(made.status==0);
 var checked=phase6(0);assert(static_ol_image::verify(source,value,1,2,made.image,checked)==0 && checked.meter.semantic==15);
 for allowed in 15 {var cut=phase6((1048576-allowed) as u32);assert(static_ol_image::verify(source,value,1,2,made.image,cut)==4);}
 for case in 6 {var bad=copy(made.image);var input=copy(value);var expected=source;
  if case==0 {input.status=1;}else if case==1 {expected="";}else if case==2 {bad.rows=2;}else if case==3 {bad.width=3;}else if case==4 {bad.steps=4;}else {bad.bytes=7;}
  var test=phase6(0);assert(static_ol_image::verify(expected,input,1,2,bad,test)==1 && test.meter.semantic==case+1);
 }
 var short=static_publish_core::Image {source:source,rows:1,width:2,steps:3,bytes:8};var test=phase6(0);assert(static_ol_image::verify(source,value,1,2,short,test)==1 && test.meter.semantic==7);
 print("actual metadata and layout precharge controls passed");
}
