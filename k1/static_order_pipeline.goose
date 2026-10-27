// Partial ordered source-to-static-Wasm fixture. All phases have a single
// compiler-owned ScheduledWork; helper internals and full C09 still require
// instrumentation. Any failure discards the candidate bytes and owner.
namespace static_order_pipeline;
import work;
import static_publish_core;
import static_order_core;
import static_order_parse;
import static_order_verify;
import static_order_eval;
import static_order_emit;
import static_order_target;
import static_order_image;
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
 var parsed=static_order_parse::parse(source,w);if parsed.status!=0{return fail(w,parsed.status);}
 if !work::schedule_end(w,1) || !work::schedule_begin(w,2){return fail(w,5);}
 let checked=static_order_verify::verify(source,parsed.owned,w.meter);w.meter=checked.meter;if checked.status!=0{return fail(w,checked.status);}
 if !work::schedule_end(w,2) || !work::schedule_begin(w,3){return fail(w,5);}
 let value=static_order_eval::evaluate(parsed.owned,w);if value.status!=0{return fail(w,value.status);}
 if !work::schedule_end(w,3) || !work::schedule_skip_proof(w) || !work::schedule_begin(w,5){return fail(w,5);}
 let semantic=work::scheduled_charge(w,5,10);if semantic.status!=0{return fail(w,if semantic.status==1 {4} else {5});}
 let rows=parsed.owned.product.rows;let width=parsed.owned.product.width;
 if rows<1 || width<2 || width>16 || rows>100000/width || value.data.len!=value.bytes || (rows as u64)*(width as u64)*4!=value.bytes as u64 {return fail(w,1);}
 if !work::schedule_end(w,5) || !work::schedule_begin(w,6){return fail(w,5);}
 let layout=work::scheduled_charge(w,6,10);if layout.status!=0{return fail(w,if layout.status==1 {4} else {5});}
 let retain=work::source_read(w.meter,source.len as u64);if retain.status!=0{return fail(w,if retain.status==5 {5} else {6});}
 var image=static_publish_core::Image {source:source,width:width as u32,rows:rows as u32,steps:value.steps,bytes:value.bytes,data:copy(value.data)};
 let image_check=static_order_image::verify(source,value,rows,width,image,w);if image_check!=0{return fail(w,image_check);}
 if !work::schedule_end(w,6) || !work::schedule_begin(w,7){return fail(w,5);}
 let bytes=static_order_emit::emit(image);let target=static_order_target::verify(image,bytes,w);if target!=0{return fail(w,target);}
 if !work::schedule_end(w,7) || !work::schedule_complete(w){return fail(w,5);}
 return static_order_core::Output {status:0,work:w,wasm:copy(bytes)};
}
