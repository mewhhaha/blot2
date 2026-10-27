// Closed independent target decoding for the private joined driver.
// This is not a public ABI or general M13 certificate.
namespace joined_driver_gate;
import joined_public_core;
import joined_target_scalar;
fn matches(source:u8[:],program:joined_public_core::Program&,target:u8[:])->bool {
 return joined_target_scalar::verify(source,program,target);
}
