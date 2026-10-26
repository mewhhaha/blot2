namespace joined_public_wasm;
import joined_public_core;
import joined_public_verify;
import compiler_wasm;
fn emit(source:u8[:],p:joined_public_core::Program&)->u8[] {if !joined_public_verify::verify(source,p) {return [];}let flat=joined_public_verify::project(source,p.head);return compiler_wasm::emit(flat,p.body);}
