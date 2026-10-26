// Candidate envelope uses a compiler-generated policy identity, never a
// caller-supplied opaque digest. Public eligibility remains false.
namespace abi_profile_manifest_build;
import abi_profile_build;
import abi_profile_verify;
import abi_profile_manifest_verify;
import m12_candidate_build;
import public_artifact;
fn make(source:u8[:],adapter:u8[:],package:u8[:],module:u8[:])->u8[] {
 let profile=abi_profile_build::canonical();let hash=abi_profile_build::digest();
 if !abi_profile_verify::verify_digest(profile,hash) {return [];}
 let candidate=m12_candidate_build::make(source,adapter,package,module,hash);if candidate.len==0 {return [];}
 var body:u8[>..]=[];public_artifact::putstr(body,profile);public_artifact::putstr(body,hash);public_artifact::putstr(body,candidate);
 if body.len>147456-12 {return [];}
 var out:u8[>..]=[];out.append("K1AMNF01");public_artifact::put32(out,(body.len+12) as u32);out.append(body);
 if !abi_profile_manifest_verify::verify(out,source,adapter,package,module) {return [];}
 return out;
}
