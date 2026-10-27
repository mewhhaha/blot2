// Private common source entry; no public callable or ABI authority.
namespace generic_callable;
import generic_fn_frontend;
import generic_fn_verify;
import generic_fn_wasm;
import generic_bool_frontend;
import generic_bool_wasm;
import predicate_frontend;
import predicate_header;
import predicate_wasm;
import predflow_decl_frontend;
import predflow_decl_wasm;
struct Result {status:i64=0,argument:i64=0,result:i64=0,wasm:u8[]=[]}
// Internal chain helper: `recognized` is a fresh, caller-owned local flag;
// only the outer compile_record entry resets it. Never use it as admission.
fn compile_into_fault(source:u8[:],recognized:bool&,fault:i64)->Result {
 var a=generic_fn_frontend::parse(source);if a.status==0 {recognized=true;if fault==10 {return Result {status:1};}let bytes=generic_fn_wasm::emit(source,a.program);if bytes.len==0 {return Result {status:1};}return Result {argument:1,result:1,wasm:bytes};}
 var b=generic_bool_frontend::parse(source);if b.status==0 {recognized=true;if fault==11 {return Result {status:1};}let bytes=generic_bool_wasm::emit(source,b.program);if bytes.len==0 {return Result {status:1};}return Result {argument:2,result:1,wasm:bytes};}
 var c=predicate_frontend::parse(source);if c.status==0 {recognized=true;if fault==12 {return Result {status:1};}let bytes=predicate_wasm::emit(source,c.program);if bytes.len==0 {return Result {status:1};}return Result {argument:1,result:2,wasm:bytes};}
 var d=predflow_decl_frontend::parse(source);if d.status==0 {recognized=true;if fault==13 {return Result {status:1};}let bytes=predflow_decl_wasm::emit(source,d.program);if bytes.len==0 {return Result {status:1};}return Result {argument:1,result:2,wasm:bytes};}
 // Preserve a checked-body diagnostic when exactly one header is supported.
 if generic_fn_verify::header(source).ok {return Result {status:a.status};}
 if predicate_header::header(source).ok {return Result {status:c.status};}
 return Result {status:b.status};
}

fn compile_into(source:u8[:],recognized:bool&)->Result {return compile_into_fault(source,recognized,0);}
fn compile(source:u8[:])->Result {var recognized=false;return compile_into(source,recognized);}
