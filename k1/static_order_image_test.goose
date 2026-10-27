import work;
import static_product_parse;
import static_product_eval;
import static_publish_build;
import static_order_image;
fn phase6()->work::ScheduledWork {
 var w=work::ScheduledWork {};for p in 1..4 {assert(work::schedule_begin(w,p as u32));assert(work::schedule_end(w,p as u32));}
 assert(work::schedule_skip_proof(w));assert(work::schedule_begin(w,5) && work::schedule_end(w,5) && work::schedule_begin(w,6));return w;
}
fn main(){let s="static let a = #[(1,2),(3,4)]";var product=static_product_parse::parse(s);let value=static_product_eval::evaluate(s,product.tree);var image=static_publish_build::build(s);assert(image.status==0);
 var w=phase6();assert(static_order_image::verify(s,value,2,2,image.image,w)==0);
 for f in 6 {var bad=copy(image.image);if f==0 {bad.source[0]='?';}else if f==1 {bad.width+=1;}else if f==2 {bad.rows+=1;}else if f==3 {bad.steps+=1;}else if f==4 {bad.bytes+=1;}else {bad.data[0]^=1;}
  var temp=phase6();assert(static_order_image::verify(s,value,2,2,bad,temp)!=0);}
 var over=phase6();over.meter.source_byte_reads=~(0 as u64);assert(static_order_image::verify(s,value,2,2,image.image,over)==6);
 print("ordered source/image forgery and copy telemetry passed");}
