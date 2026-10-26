// Independent decoder for a deliberately ineligible private particle/window
// candidate. The supplied expected source/package/module are trusted compiler
// request inputs. This is not a public M12 manifest or ABI qualification.
namespace m12_candidate_verify;
import public_interface;
import i08_link_build;
import i08_link_verify;
import i08_link_affine;
import i08_transition_build;
import i08_transition_verify;
import i08_same_target;
import m12_adapter_build;
import m12_adapter_verify;
import source_wire_order;
struct Reader {at:i64=0,end:i64=0,bad:bool=false}
fn word(s:u8[:],r:Reader&)->u32 {
 if r.bad || r.at<0 || r.end<r.at || r.end>s.len || r.end-r.at<4 {r.bad=true;return 0;}
 let p=r.at;r.at+=4;return (s[p] as u32)|((s[p+1] as u32)<<8)|((s[p+2] as u32)<<16)|((s[p+3] as u32)<<24);
}
fn blob(s:u8[:],r:Reader&,maximum:i64)->i64,i64 {
 let n=word(s,r) as i64;if r.bad || n>maximum || n>r.end-r.at {r.bad=true;return 0,0;}
 let start=r.at;r.at+=n;return start,r.at;
}
fn exact(s:u8[:],r:Reader&,expected:u8[:])->bool {
 let a,b=blob(s,r,65536);return !r.bad && b-a==expected.len && s[a..b]==expected;
}
fn verify(bytes:u8[:],source:u8[:],adapter:u8[:],package:u8[:],module:u8[:],abi:u8[:])->bool {
 if bytes.len<12 || bytes.len>131072 || source.len>65536 || adapter.len>65536-source.len || abi.len!=32 ||
    !public_interface::identity_valid(package,module,"project") || !public_interface::identity_valid(package,module,"export") || bytes[..8]!="K1FMAN01" {return false;}
 var r=Reader {at:8,end:bytes.len};if word(bytes,r)!=bytes.len {return false;}
 // Exact private edition/codec/schema profile. None is a qualified M12 hash.
 if !exact(bytes,r,"PRIVATE-I08-SOURCE-ORDER-V1") || !exact(bytes,r,package) || !exact(bytes,r,module) ||
  !exact(bytes,r,"project") || !exact(bytes,r,"export") || !exact(bytes,r,abi) ||
  !exact(bytes,r,"source:View[{x:F32,y:F32,vx:F32,vy:F32}];dt:F32;output:{x:F32,y:F32}") ||
  !exact(bytes,r,"source:View[{x:F32,y:F32,vx:F32,vy:F32}];dt:F32;output:Dest[{x:F32,y:F32}]") {return false;}
 // Canonical ABI fields include explicit zeros for all unsupported authority.
 let expected:u32[23]=[0x4b310001,91,256,256,12,0,16,8,8,8,192,2,256,3,512,768,0,1,0,0,0,0,0];
 for x in expected {if word(bytes,r)!=x || r.bad {return false;}}
 if !exact(bytes,r,source) || !exact(bytes,r,adapter) {return false;}
 let a,b=blob(bytes,r,65536);if r.bad || r.at!=r.end || a==b {return false;}
 var linked,status=i08_link_build::build(source);if status!=0 || !i08_link_verify::verify(linked,source) {return false;}
 let affine=i08_link_affine::build(linked,source);if affine.status!=0 || !i08_link_affine::verify(linked,source,affine.plan) {return false;}
 let proof=i08_transition_build::build(linked,source,affine.plan);
 if proof.status!=0 || !i08_transition_verify::verify(linked,source,affine.plan,proof.proof) {return false;}
 if !i08_same_target::verify(linked.cap.job.core,source,linked.cap.job.core.context,bytes[a..b]) {return false;}
 var candidate,adapter_status=m12_adapter_build::build(source,adapter);if adapter_status!=0 {return false;}
 var expected_module:u8[>..]=[];expected_module.append(source);expected_module.append(adapter);
 return m12_adapter_verify::verify(candidate,expected_module) && source_wire_order::verify(candidate,expected_module) && !m12_adapter_verify::public_eligible(candidate,expected_module);
}
