// Private deterministic target association check. This recomputes the existing
// emitter, so equality is not an independent Wasm semantic certificate.
namespace joined_driver_gate;
import joined_public_core;
import joined_public_verify;
import joined_public_wasm;
fn matches(source:u8[:],program:joined_public_core::Program&,target:u8[:])->bool {
 if target.len==0 || !joined_public_verify::verify(source,program) {return false;}
 let expected=joined_public_wasm::emit(source,program);
 return expected.len>0 && expected[..]==target;
}
