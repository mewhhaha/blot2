// Independently validate the source-bound mixed target before publication.
namespace poly_canonical_wasm;
import poly_canonical_core;
import poly_canonical_check;
import common_decl_header;


import mixed_compiler_core;
import poly_mixed_wasm;
import poly_canonical_target;
fn emit(expected:u8[:],p:poly_canonical_core::Program&)->u8[] {
 if !poly_canonical_check::verify(expected,p){return [];}
 let flat=common_decl_header::project(expected,p.head);
 var old=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 let bytes=poly_mixed_wasm::emit(flat,old,p.head.argument,p.head.result);if bytes.len==0 {return [];}
 if !poly_canonical_target::verify(expected,p,bytes){return [];}return bytes;
}
