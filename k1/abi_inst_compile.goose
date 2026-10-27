// Publishes private fixture bytes only after exact-source and independent
// target validation. No general K1 ABI/resource/loan/manifest admission.
namespace abi_inst_compile;
import abi_inst_wasm;
import abi_inst_check;
fn emit(module:u8[:])->u8[] {let bytes=abi_inst_wasm::emit(module);if bytes.len==0 || !abi_inst_check::verify(module,bytes){return [];}return bytes;}
fn public_eligible(module:u8[:])->bool {let _=module;return false;}
