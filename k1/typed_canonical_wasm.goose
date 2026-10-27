// Independently validate the source-bound mixed target before publication.
namespace typed_canonical_wasm;
import typed_canonical_core;
import typed_canonical_check;
import joined_public_verify;


import mixed_compiler_core;
import typed_mixed_wasm;
import typed_canonical_target;
fn emit(expected:u8[:],p:typed_canonical_core::Program&)->u8[] {
 if !typed_canonical_check::verify(expected,p){return [];}
 let flat=joined_public_verify::project(expected,p.head);
 var old=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 let bytes=typed_mixed_wasm::emit(flat,old);if bytes.len==0 {return [];}
 if !typed_canonical_target::verify(expected,p,bytes){return [];}return bytes;
}
