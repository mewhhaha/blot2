import abi_profile_build;
import abi_profile_verify;
import abi_profile_manifest_verify;
import blake3;
fn main(){let original=abi_profile_build::canonical();let hash=abi_profile_build::digest();assert(abi_profile_verify::verify_digest(original,hash));
 for pos in [8,12,16,20,24,28,32] {for v in [0 as u8,255] {var b:u8[>..]=[];b.append(original);b[pos]=v;if b[..]!=original[..] {let d=blake3::hash(b);assert(!abi_profile_verify::verify_digest(b,d));}}}
 var tail:u8[>..]=[];tail.append(original);tail.push(0);assert(!abi_profile_verify::verify(tail));
 assert(!abi_profile_verify::verify_digest(original,hash[..31]));
 var oversized:u8[>..]=[0;16385];assert(!abi_profile_verify::verify(oversized));
 var envelope:u8[>..]=[0;147457];assert(!abi_profile_manifest_verify::verify(envelope,"","","",""));
 for i in original.len {if i%5==0 {var altered:u8[>..]=[];altered.append(original);altered[i]^=0x80;let new_digest=blake3::hash(altered);assert(!abi_profile_verify::matching_fields(altered,new_digest,new_digest,new_digest,new_digest));}}
 print("independent private ABI length, version, digest and forgery controls passed");}
