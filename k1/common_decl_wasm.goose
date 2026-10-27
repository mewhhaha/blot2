namespace common_decl_wasm;
import common_decl_core;
import common_decl_header;
import common_decl_verify;
import common_wasm;
fn emit(source:u8[:],p:common_decl_core::Program&)->u8[] {if !common_decl_verify::verify(source,p){return [];}let flat=common_decl_header::project(source,p.header);return common_wasm::emit(flat,p.body);}
