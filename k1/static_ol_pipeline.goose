// Partial ordered source-to-static-Wasm fixture. All phases have a single
// compiler-owned ScheduledWork; helper internals and full C09 still require
// instrumentation. Any failure discards the candidate bytes and owner.
namespace static_ol_pipeline;
import work;
import static_publish_core;
import static_product_eval;
import static_order_core;
import static_ot_parse;
import static_ot_verify;
import static_om_eval;
import static_ot_emit;
import static_ot_check;
import static_ol_image;
import static_ol_layout;
struct ImageResult {status:i64=0,image:static_publish_core::Image=static_publish_core::Image {}}
fn make_image(source:u8[:],value:static_product_eval::Result&,rows:i64,width:i64,w:work::ScheduledWork&)->ImageResult {
 var data:u8[>..]=[];for i in value.data.len {let item=work::scheduled_charge(w,6,3);if item.status!=0{return ImageResult {status:if item.status==1 {4} else {5}};}data.push(value.data[i]);}
 return ImageResult {image:static_publish_core::Image {source:source,width:width as u32,rows:rows as u32,steps:value.steps,bytes:value.bytes,data:data}};
}
fn fail(w:work::ScheduledWork&,status:i64)->static_order_core::Output {
 w.failed=true;w.meter.gate=9;return static_order_core::Output {status:status,work:copy(w)};
}
fn build(source:u8[:],seed:u32)->static_order_core::Output {
 return build_with_meter(source,work::Meter {semantic:seed});
}
fn build_with_meter(source:u8[:],meter:work::Meter)->static_order_core::Output {
 if meter.semantic>1048576{return static_order_core::Output {};}
 var w=work::ScheduledWork {meter:meter};
 if !work::schedule_begin(w,1){return fail(w,5);}
 var parsed=static_ot_parse::parse(source,w);if parsed.status!=0{return fail(w,parsed.status);}
 if !work::schedule_end(w,1) || !work::schedule_begin(w,2){return fail(w,5);}
 let checked=static_ot_verify::verify(source,parsed.owned,w.meter);w.meter=checked.meter;if checked.status!=0{return fail(w,checked.status);}
 if !work::schedule_end(w,2) || !work::schedule_begin(w,3){return fail(w,5);}
 let value=static_om_eval::evaluate(parsed.owned,w);if value.status!=0{return fail(w,value.status);}
 if !work::schedule_end(w,3) || !work::schedule_skip_proof(w) || !work::schedule_begin(w,5){return fail(w,5);}
 let row_visit=static_ol_layout::visit(w,5);if row_visit!=0{return fail(w,row_visit);}let rows=parsed.owned.product.rows;
 let width_visit=static_ol_layout::visit(w,5);if width_visit!=0{return fail(w,width_visit);}let width=parsed.owned.product.width;
 let shape=static_ol_layout::check(rows,width,value,w);if shape!=0{return fail(w,shape);}
 if !work::schedule_end(w,5) || !work::schedule_begin(w,6){return fail(w,5);}
 let layout=work::scheduled_charge(w,6,10);if layout.status!=0{return fail(w,if layout.status==1 {4} else {5});}
 let retain=work::source_read(w.meter,source.len as u64);if retain.status!=0{return fail(w,if retain.status==5 {5} else {6});}
 let data_alloc=work::scheduled_charge(w,6,10);if data_alloc.status!=0{return fail(w,if data_alloc.status==1 {4} else {5});}
 var made=make_image(source,value,rows,width,w);if made.status!=0{return fail(w,made.status);}
 var image=made.image;
 let image_check=static_ol_image::verify(source,value,rows,width,image,w);if image_check!=0{return fail(w,image_check);}
 if !work::schedule_end(w,6) || !work::schedule_begin(w,7){return fail(w,5);}
 let bytes=static_ot_emit::emit(image,w);if bytes.status!=0{return fail(w,bytes.status);}
 let target=static_ot_check::verify(image,bytes.bytes,w);if target!=0{return fail(w,target);}
 let alloc=work::scheduled_charge(w,7,10);if alloc.status!=0{return fail(w,if alloc.status==1 {4} else {5});}
 var retained:u8[>..]=[];
 for i in bytes.bytes.len {
  let read=work::target_visit(w.meter);if read.status!=0{return fail(w,if read.status==6 {6} else {5});}
  let value=bytes.bytes[i];let write=work::target_visit(w.meter);if write.status!=0{return fail(w,if write.status==6 {6} else {5});}retained.push(value);
 }
 if !work::schedule_end(w,7) || !work::schedule_complete(w){return fail(w,5);}
 return static_order_core::Output {status:0,work:w,wasm:retained};
}
