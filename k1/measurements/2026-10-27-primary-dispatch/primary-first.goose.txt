// Scratch private migration experiment: the source-owned typed arena is the
// primary path; existing dispatcher remains fallback for unsupported programs.
// There is no public ABI, effect/resource, ownership or C09 qualification.
namespace primary_dispatch;
import generic_callable;
import short_frontend;
import short_check;
import short_legacy_wasm;
import short_emit;
import typed_dispatch;
fn compile_with_fault(source:u8[:],fault:i64)->generic_callable::Result {
 var p=short_frontend::parse(source);
 if p.status!=0 {return typed_dispatch::compile(source);}
 if !short_check::verify(source,p.program) {return generic_callable::Result {status:1};}
 let compat=short_legacy_wasm::build(source,p.program,fault);
 if compat.matched {if compat.bytes.len==0 {return generic_callable::Result {status:1};}return generic_callable::Result {argument:p.program.head.argument,result:p.program.head.result,wasm:copy(compat.bytes)};}
 let bytes=short_emit::emit(source,p.program);
 if bytes.len==0 {return generic_callable::Result {status:1};}
 return generic_callable::Result {argument:p.program.head.argument,result:p.program.head.result,wasm:bytes};
}

fn compile(source:u8[:])->generic_callable::Result {return compile_with_fault(source,0);}
