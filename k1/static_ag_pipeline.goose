// Private source-to-image prototype. All success paths perform the actual
// metered aggregate parser/evaluator and independently replayed image checker.
// No public compilation, target certificate or complete C09 receipt is issued.
namespace static_ag_pipeline;
import work;
import static_publish_core;
import static_ag_core;
import static_ag_parse;
import static_ag_eval;
import static_ag_publish;
fn build(source:u8[:],meter:work::Meter,cached:bool)->static_ag_core::ImageResult {
 var p=static_ag_parse::parse(source,meter);var m=p.meter;if p.status!=0{return static_ag_core::ImageResult {status:p.status,meter:m};}
 let shape=work::charge(m,6,10);if shape.status!=0{return static_ag_core::ImageResult {status:if shape.status==1 {4} else {5},meter:m};}
 if !p.tree.is_array{return static_ag_core::ImageResult {meter:m};}
 let value=static_ag_eval::evaluate(source,p.tree,m,cached);m=value.meter;if value.status!=0{return static_ag_core::ImageResult {status:value.status,meter:m};}
 let read=work::source_read(m,source.len as u64);if read.status!=0{return static_ag_core::ImageResult {status:if read.status==5 {5} else {6},meter:m};}
 var image=static_publish_core::Image {source:source,width:p.tree.width as u32,rows:p.tree.rows as u32,steps:value.steps,
    bytes:value.value.bytes,data:copy(value.value.data)};
 let verified=static_ag_publish::verify(source,image,m,cached);m=verified.meter;
 if verified.status!=0{return static_ag_core::ImageResult {status:verified.status,meter:m};}
 return static_ag_core::ImageResult {status:0,meter:m,image:image};
}
