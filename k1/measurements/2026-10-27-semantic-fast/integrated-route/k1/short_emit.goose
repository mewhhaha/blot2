// Independently validate the source-bound mixed target before publication.
namespace short_emit;
import short_core;
import short_check;
import common_decl_header;


import mixed_compiler_core;
import short_wasm;
import short_target;
fn emit(expected:u8[:],p:short_core::Program&)->u8[] {
 if !short_check::verify(expected,p){return [];}
 let flat=common_decl_header::project(expected,p.head);
 var old=mixed_compiler_core::Program {source:copy(flat),variant:2,name_start:p.name_start,name_end:p.name_end,fn_start:p.fn_start,body:copy(p.tree)};
 let bytes=short_wasm::emit(flat,old,p.head.argument,p.head.result);if bytes.len==0 {return [];}
 if !short_target::verify(expected,p,bytes){return [];}return bytes;
}
