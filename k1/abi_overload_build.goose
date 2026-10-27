// Encodes a proposed private schema inventory. Provisional zero flags make
// clear that none of the names is an admitted compiler operation ID.
namespace abi_overload_build;
import abi_overload_catalog;
import public_artifact;
fn canonical()->u8[] {
 var out:u8[>..]=[];out.append("K1OPS001");public_artifact::put32(out,abi_overload_catalog::count() as u32);
 for i in abi_overload_catalog::count() {
  public_artifact::put32(out,(i+1) as u32);
  public_artifact::putstr(out,"PRIVATE-OVERLOAD-CANDIDATE1");
  public_artifact::putstr(out,abi_overload_catalog::name(i));public_artifact::putstr(out,abi_overload_catalog::operands(i));
  public_artifact::putstr(out,abi_overload_catalog::result(i));public_artifact::putstr(out,abi_overload_catalog::evidence(i));
  public_artifact::putstr(out,abi_overload_catalog::behavior(i));public_artifact::putstr(out,abi_overload_catalog::transition(i));
  public_artifact::putstr(out,abi_overload_catalog::failure(i));public_artifact::putstr(out,"target-and-implementation-unqualified");
  public_artifact::put32(out,0);
 }
 return out;
}
