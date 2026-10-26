// No external caller selects the records: construct compiler-owned candidate.
namespace abi_profile_build;
import public_artifact;
import abi_profile_catalog;
import blake3;
fn canonical()->u8[] {
 var out:u8[>..]=[];out.append("K1ABI001");public_artifact::put32(out,abi_profile_catalog::count() as u32);
 for i in abi_profile_catalog::count() {public_artifact::putstr(out,abi_profile_catalog::key(i));public_artifact::putstr(out,abi_profile_catalog::value(i));}
 return out;
}
fn digest()->u8[32] {let bytes=canonical();return blake3::hash(bytes);}
