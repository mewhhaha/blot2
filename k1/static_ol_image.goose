// Phase-6 private source/image association. Output-byte comparison and helper
// internals are not a complete C09 or static manifest certificate.
namespace static_ol_image;
import work;
import static_ol_layout;
import static_product_eval;
import static_publish_core;
fn verify(source:u8[:],value:static_product_eval::Result&,rows:i64,width:i64,image:static_publish_core::Image&,w:work::ScheduledWork&)->i64 {
 let a=static_ol_layout::visit(w,6);if a!=0{return a;}if value.status!=0{return 1;}
 let b=static_ol_layout::visit(w,6);if b!=0{return b;}if source.len!=image.source.len{return 1;}
 let c=static_ol_layout::visit(w,6);if c!=0{return c;}if image.rows!=rows{return 1;}
 let d=static_ol_layout::visit(w,6);if d!=0{return d;}if image.width!=width{return 1;}
 let e=static_ol_layout::visit(w,6);if e!=0{return e;}if image.steps!=value.steps{return 1;}
 let f=static_ol_layout::visit(w,6);if f!=0{return f;}if image.bytes!=value.bytes{return 1;}
 let g=static_ol_layout::visit(w,6);if g!=0{return g;}if image.data.len!=value.data.len{return 1;}
 for i in source.len {let read=work::source_read(w.meter,2);if read.status!=0{return if read.status==5 {5} else {6};}
  if source[i]!=image.source[i]{return 1;}}
 for i in image.data.len {let read=work::scheduled_charge(w,6,3);if read.status!=0{return if read.status==1 {4} else {5};}if image.data[i]!=value.data[i]{return 1;}}
 return 0;
}
