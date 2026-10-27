// Independently validate the source-bound mixed target before publication.
namespace canonical_wasm;
import canonical_core;
import canonical_check;
import joined_public_verify;
import joined_public_core;
import compiler_core;
import mixed_compiler_core;
import mixed_wasm;
import joined_target_scalar;
fn emit(expected:u8[:],p:canonical_core::Program&)->u8[] {
 if !canonical_check::verify(expected,p){return [];}
 let flat=joined_public_verify::project(expected,p.head);
 var old=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 let bytes=mixed_wasm::emit(flat,old);if bytes.len==0 {return [];}
 var wrapper=joined_public_core::Program {source:expected,head:p.head,body:compiler_core::Program {source:copy(flat),variant:3,mixed:copy(old)}};
 if !joined_target_scalar::verify(expected,wrapper,bytes){return [];}return bytes;
}
