// Actual source/image publication verifier under one partial shared meter.
// Semantic charges here cover explicit image shape, component and data visits;
// this is not the full C09/manifest/target/publication admission pipeline.
namespace static_ag_publish;
import work;
import static_publish_core;
import static_ag_core;
import static_ag_parse;
import static_ag_eval;
fn charge(m:work::Meter&,event:u32)->i64 {let x=work::charge(m,6,event);return if x.status==0 {0} else if x.status==1 {4} else {5};}
fn verify(source:u8[:],image:static_publish_core::Image&,meter:work::Meter,cached:bool)->static_ag_core::Checked {
 var m=meter;let shape=charge(m,10);if shape!=0{return static_ag_core::Checked {status:shape,meter:m};}
 if source.len>16777216 || source.len!=image.source.len || image.width<2 || image.width>16 || image.rows<1 || image.bytes>4194304 ||
    image.data.len!=image.bytes || (image.rows as u64)*(image.width as u64)*4!=image.bytes as u64 {return static_ag_core::Checked {meter:m};}
 for i in source.len {let x=work::source_read(m,2);if x.status!=0{return static_ag_core::Checked {status:if x.status==5 {5} else {6},meter:m};}
  if source[i]!=image.source[i]{return static_ag_core::Checked {meter:m};}}
 var parsed=static_ag_parse::parse(source,m);m=parsed.meter;if parsed.status!=0{return static_ag_core::Checked {status:parsed.status,meter:m};}
 let tree=charge(m,2);if tree!=0{return static_ag_core::Checked {status:tree,meter:m};}
 if !parsed.tree.is_array || parsed.tree.width!=image.width || parsed.tree.rows!=image.rows{return static_ag_core::Checked {meter:m};}
 let value=static_ag_eval::evaluate(source,parsed.tree,m,cached);m=value.meter;if value.status!=0{return static_ag_core::Checked {status:value.status,meter:m};}
 if value.steps!=image.steps || value.value.bytes!=image.bytes || value.value.data.len!=image.data.len{return static_ag_core::Checked {meter:m};}
 for i in image.data.len {let visit=charge(m,10);if visit!=0{return static_ag_core::Checked {status:visit,meter:m};}
  if image.data[i]!=value.value.data[i]{return static_ag_core::Checked {meter:m};}}
 return static_ag_core::Checked {status:0,meter:m};
}
