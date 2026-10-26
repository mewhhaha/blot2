// Private canonical source/target manifest producer, no M12 eligibility.
namespace m12_candidate_build;
import public_interface;
import public_artifact;
import i08_link_build;
import i08_link_verify;
import i08_link_affine;
import i08_transition_build;
import i08_transition_verify;
import i08_same_wasm;
import i08_same_target;
import m12_candidate_verify;
import m12_adapter_build;
import m12_adapter_verify;
import source_wire_order;
fn make(source:u8[:],adapter:u8[:],package:u8[:],module:u8[:],abi:u8[:])->u8[] {
 if source.len>65536 || adapter.len>65536-source.len || abi.len!=32 ||
  !public_interface::identity_valid(package,module,"project") || !public_interface::identity_valid(package,module,"export") {return [];}
 var candidate,adapter_status=m12_adapter_build::build(source,adapter);if adapter_status!=0 {return [];}
 var expected_module:u8[>..]=[];expected_module.append(source);expected_module.append(adapter);
 if !m12_adapter_verify::verify(candidate,expected_module) || !source_wire_order::verify(candidate,expected_module) || m12_adapter_verify::public_eligible(candidate,expected_module) {return [];}
 var linked,status=i08_link_build::build(source);if status!=0 || !i08_link_verify::verify(linked,source) {return [];}
 let affine=i08_link_affine::build(linked,source);if affine.status!=0 || !i08_link_affine::verify(linked,source,affine.plan) {return [];}
 let proof=i08_transition_build::build(linked,source,affine.plan);
 if proof.status!=0 || !i08_transition_verify::verify(linked,source,affine.plan,proof.proof) {return [];}
 let target=i08_same_wasm::emit(linked.cap.job.core,source,linked.cap.job.core.context);
 if target.len==0 || !i08_same_target::verify(linked.cap.job.core,source,linked.cap.job.core.context,target) {return [];}
 var body:u8[>..]=[];public_artifact::putstr(body,"PRIVATE-I08-SOURCE-ORDER-V1");public_artifact::putstr(body,package);
 public_artifact::putstr(body,module);public_artifact::putstr(body,"project");public_artifact::putstr(body,"export");public_artifact::putstr(body,abi);
 public_artifact::putstr(body,"source:View[{x:F32,y:F32,vx:F32,vy:F32}];dt:F32;output:{x:F32,y:F32}");
 // The independent source verifier checks this source record order; the
 // corresponding private wire fixture encodes source descriptor before dt.
 public_artifact::putstr(body,"source:View[{x:F32,y:F32,vx:F32,vy:F32}];dt:F32;output:Dest[{x:F32,y:F32}]");
 let values:u32[23]=[0x4b310001,91,256,256,12,0,16,8,8,8,192,2,256,3,512,768,0,1,0,0,0,0,0];
 for x in values {public_artifact::put32(body,x);}
 public_artifact::putstr(body,source);public_artifact::putstr(body,adapter);public_artifact::putstr(body,target);
 if body.len>131072-12 {return [];}
 var out:u8[>..]=[];out.append("K1FMAN01");public_artifact::put32(out,(body.len+12) as u32);out.append(body);
 if !m12_candidate_verify::verify(out,source,adapter,package,module,abi) {return [];}
 return out;
}
