// Private staged publication only after the source/target decoder agrees.
namespace owned_wasm_compile;
import owned_wasm_emit;
import owned_wasm_check;
fn compile(source:u8[:])->u8[] {
 let target=owned_wasm_emit::emit(source);if target.len==0 || !owned_wasm_check::verify(source,target) {return [];}
 return copy(target);
}
