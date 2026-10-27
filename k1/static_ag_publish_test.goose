import work;
import static_publish_build;
import static_publish_verify;
import static_ag_publish;
fn main(){
 let source="static let a = #[(1,2.0),(1,2.0)]";var built=static_publish_build::build(source);assert(built.status==0 && static_publish_verify::verify(source,built.image));
 let a=static_ag_publish::verify(source,built.image,work::Meter {},false);let b=static_ag_publish::verify(source,built.image,work::Meter {},true);
 assert(a.status==0 && b.status==0 && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
 for allowed in a.meter.semantic+1 {
  let cold=static_ag_publish::verify(source,built.image,work::Meter {semantic:1048576-allowed},false);
  let hot=static_ag_publish::verify(source,built.image,work::Meter {semantic:1048576-allowed},true);
  assert(cold.status==hot.status && cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
  if allowed<a.meter.semantic {assert(cold.status==4 && cold.meter.semantic==1048576);}else {assert(cold.status==0);}
 }
 for f in 5 {var bad=copy(built.image);if f==0 {bad.source[0]='?';}else if f==1 {bad.width+=1;}else if f==2 {bad.rows+=1;}
  else if f==3 {bad.steps+=1;}else {bad.data[0]^=1;}
  assert(static_ag_publish::verify(source,bad,work::Meter {},false).status!=0 && static_ag_publish::verify(source,bad,work::Meter {},true).status!=0);
 }
 assert(static_ag_publish::verify(source,built.image,work::Meter {source_byte_reads:~(0 as u64)},true).status==6);
 print("actual metered source/image verification cold/cache parity passed");
}
