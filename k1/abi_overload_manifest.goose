// A source/target candidate bound to the expanded private policy digest.
// No public ABI, executable adapter or manifest admission is claimed.
namespace abi_overload_manifest;
import abi_overload_policy;
import m12_candidate_build;
import m12_candidate_verify;
import public_artifact;
import blake3;
fn make(source:u8[:],adapter:u8[:],package:u8[:],module:u8[:])->u8[] {
 let policy=abi_overload_policy::canonical();if !abi_overload_policy::verify(policy) {return [];}
 let hash=blake3::hash(policy);let candidate=m12_candidate_build::make(source,adapter,package,module,hash);
 if candidate.len==0 {return [];}
 var body:u8[>..]=[];public_artifact::putstr(body,policy);public_artifact::putstr(body,hash);public_artifact::putstr(body,candidate);
 if body.len>278528-12 {return [];}
 var out:u8[>..]=[];out.append("K1OMNF02");public_artifact::put32(out,(body.len+12) as u32);out.append(body);
 if !verify(out,source,adapter,package,module) {return [];}
 return out;
}
fn verify(s:u8[:],source:u8[:],adapter:u8[:],package:u8[:],module:u8[:])->bool {
 if s.len<12 || s.len>278528 || s[..8]!="K1OMNF02" {return false;}
 var r=abi_overload_policy::Reader {at:8,end:s.len};if abi_overload_policy::word(s,r)!=s.len {return false;}
 let a,b=abi_overload_policy::blob(s,r,147456);let h,j=abi_overload_policy::blob(s,r,32);let m,n=abi_overload_policy::blob(s,r,131072);
 if r.bad || r.at!=r.end || a==b || j-h!=32 || m==n {return false;}
 let policy=s[a..b];let claimed=s[h..j];if !abi_overload_policy::verify(policy) {return false;}
 let hash=blake3::hash(policy);if hash[..]!=claimed{return false;}
 return m12_candidate_verify::verify(s[m..n],source,adapter,package,module,claimed);
}
