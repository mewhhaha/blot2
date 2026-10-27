// Phase-6 private source/image association. Output-byte comparison and helper
// internals are not a complete C09 or static manifest certificate.
namespace static_om_image;
import work;
import static_product_eval;
import static_publish_core;
fn verify(source:u8[:],value:static_product_eval::Result&,rows:i64,width:i64,image:static_publish_core::Image&,w:work::ScheduledWork&)->i64 {
 let visit=work::scheduled_charge(w,6,10);if visit.status!=0{return if visit.status==1 {4} else {5};}
 if value.status!=0 || source.len!=image.source.len || image.rows!=rows || image.width!=width || image.steps!=value.steps ||
    image.bytes!=value.bytes || image.data.len!=value.data.len{return 1;}
 for i in source.len {let read=work::source_read(w.meter,2);if read.status!=0{return if read.status==5 {5} else {6};}
  if source[i]!=image.source[i]{return 1;}}
 for i in image.data.len {let read=work::scheduled_charge(w,6,3);if read.status!=0{return if read.status==1 {4} else {5};}if image.data[i]!=value.data[i]{return 1;}}
 return 0;
}
