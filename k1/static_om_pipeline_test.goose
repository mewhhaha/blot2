import os;
import work;
import static_publish_build;
import static_publish_wasm;
import static_om_pipeline;
fn main(){
 let s="static let a = #[(1,-0.0),(3,0.0/0.0)]";var base=static_publish_build::build(s);assert(base.status==0);let expected=static_publish_wasm::emit(s,base.image);
 let result=static_om_pipeline::build(s,0);assert(result.status==0 && work::schedule_complete(result.work) && result.wasm[..]==expected[..]);
 let phases:u8[7]=[2,2,2,3,2,2,2];assert(result.work.phases[..]==phases[..]);assert(write_file("static-om.wasm",result.wasm));
 let visits=result.work.meter.semantic;assert(visits>0 && result.work.meter.target_visits>result.wasm.len);
 for allowed in visits+1 {let x=static_om_pipeline::build(s,1048576-allowed);
  if allowed<visits {assert(x.status==4 && x.work.failed && x.wasm.len==0 && x.work.meter.semantic==1048576);}else {assert(x.status==0 && x.wasm[..]==expected[..]);}}
 let max:u64=~(0 as u64);let byte_reads=result.work.meter.source_byte_reads;
 for allowed in byte_reads {let failed=static_om_pipeline::build_with_meter(s,work::Meter {source_byte_reads:max-allowed});
  assert(failed.status==6 && failed.work.failed && failed.wasm.len==0);}
 let byte_exact=static_om_pipeline::build_with_meter(s,work::Meter {source_byte_reads:max-byte_reads});
 assert(byte_exact.status==0 && byte_exact.work.meter.source_byte_reads==max);
 for allowed in result.work.meter.target_visits {let failed=static_om_pipeline::build_with_meter(s,work::Meter {target_visits:max-allowed});
  assert(failed.status==6 && failed.work.failed && failed.wasm.len==0);}
 let target_exact=static_om_pipeline::build_with_meter(s,work::Meter {target_visits:max-result.work.meter.target_visits});
 assert(target_exact.status==0 && target_exact.work.meter.target_visits==max);
 for bad in ["static let a = (1,2)","static let a = #[]","static let a = #[(4294967295+1,2)]"] {let x=static_om_pipeline::build(bad,0);assert(x.status!=0 && x.work.failed && x.wasm.len==0);}
 print("private ordered source-to-static target and ceiling passed");
}
