namespace predflow_decl_wasm;
import predflow_decl_core;
import predflow_decl_verify;
import predflow_wasm;
fn emit(source:u8[:],p:predflow_decl_core::Program&)->u8[] {
 if !predflow_decl_verify::verify(source,p){return [];}
 let flat=predflow_decl_verify::project(source,p.head);return predflow_wasm::emit(flat,p.body);
}
