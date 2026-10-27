import work;
import static_publish_build;
import static_ag_pipeline;
fn main() {
 for source in ["static let a = #[(1,2),(1,2)]", "static let b = #[(1,-0.0),(3,0.0/0.0)]"] {
  var baseline=static_publish_build::build(source);assert(baseline.status==0);
  let cold=static_ag_pipeline::build(source,work::Meter {},false);let hot=static_ag_pipeline::build(source,work::Meter {},true);
  assert(cold.status==0 && hot.status==0 && cold.image.data[..]==baseline.image.data[..] && hot.image.data[..]==baseline.image.data[..]);
  assert(cold.image.steps==baseline.image.steps && hot.image.steps==baseline.image.steps && cold.meter.semantic==hot.meter.semantic && cold.meter.phase_semantic[..]==hot.meter.phase_semantic[..]);
  for allowed in cold.meter.semantic+1 {
   let a=static_ag_pipeline::build(source,work::Meter {semantic:1048576-allowed},false);let b=static_ag_pipeline::build(source,work::Meter {semantic:1048576-allowed},true);
   assert(a.status==b.status && a.meter.semantic==b.meter.semantic && a.meter.phase_semantic[..]==b.meter.phase_semantic[..]);
   if allowed<cold.meter.semantic {assert(a.status==4 && a.image.data.len==0 && a.meter.semantic==1048576);}else {assert(a.status==0 && a.image.data[..]==baseline.image.data[..]);}
  }
 }
 for source in ["static let a = #[(4294967295+1,0)]", "static let a = #[]", "static let a = (1,2)"] {
  let a=static_ag_pipeline::build(source,work::Meter {},false);let b=static_ag_pipeline::build(source,work::Meter {},true);
  assert(a.status!=0 && b.status==a.status && a.image.data.len==0 && b.image.data.len==0 && a.meter.semantic==b.meter.semantic);
 }
 print("metered source-to-image cold/cache parity and failure atomicity passed");
}
