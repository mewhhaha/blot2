namespace generic_bool_wasm;
import generic_bool_core;
import generic_bool_verify;
import flow_decl_wasm;
import generic_bool_target;
fn emit(source:u8[:],p:generic_bool_core::Program&)->u8[] {if !generic_bool_verify::verify(source,p) {return [];}let flat=generic_bool_verify::project(source,p.head);let bytes=flow_decl_wasm::emit(flat,p.body);if bytes.len==0 || !generic_bool_target::verify(source,p,bytes) {return [];}return bytes;}
