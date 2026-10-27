namespace generic_fn_wasm;
import generic_fn_core;
import generic_fn_verify;
import compiler_wasm;
fn emit(source:u8[:],p:generic_fn_core::Program&)->u8[] {if !generic_fn_verify::verify(source,p) {return [];}let flat=generic_fn_verify::project(source,p.head);return compiler_wasm::emit(flat,p.body);}
