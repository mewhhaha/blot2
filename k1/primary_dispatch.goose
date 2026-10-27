// Private compatibility dispatcher: the existing checked path runs first;
// the source-owned typed arena admits its additional independently checked subset.
// There is no public ABI, effect/resource, ownership or C09 qualification.
namespace primary_dispatch;
import generic_callable;
import short_frontend;
import short_check;
import short_legacy_wasm;
import short_emit;
import typed_dispatch;
import generic_fn_frontend;
import generic_bool_frontend;
import predicate_frontend;
import predflow_decl_frontend;
import common_decl_frontend;
import typed_canonical_frontend;
// Only used on the rejection edge. If a prior frontend accepted this source,
// a nonzero prior result must not be turned into a successful new target.
fn previous_recognizes(source:u8[:])->bool {
 let a=generic_fn_frontend::parse(source);if a.status==0{return true;}
 let b=generic_bool_frontend::parse(source);if b.status==0{return true;}
 let c=predicate_frontend::parse(source);if c.status==0{return true;}
 let d=predflow_decl_frontend::parse(source);if d.status==0{return true;}
 let e=common_decl_frontend::parse(source);if e.status==0{return true;}
 let f=typed_canonical_frontend::parse(source);return f.status==0;
}
fn compile_with_fault(source:u8[:],fault:i64)->generic_callable::Result {
 let previous=typed_dispatch::compile(source);
 if previous.status==0 && fault!=7 {return previous;}
 if previous_recognizes(source) {if fault==7 && previous.status==0 {return generic_callable::Result {status:1};}return previous;}
 if previous.status==0 {return generic_callable::Result {status:1};}
 var p=short_frontend::parse(source);
 if p.status!=0 {return previous;}
 if !short_check::verify(source,p.program) {return generic_callable::Result {status:1};}
 let compat=short_legacy_wasm::build(source,p.program,fault);
 if compat.matched {if compat.bytes.len==0 {return generic_callable::Result {status:1};}return generic_callable::Result {argument:p.program.head.argument,result:p.program.head.result,wasm:copy(compat.bytes)};}
 if fault==6 {return generic_callable::Result {status:1};}
 let bytes=short_emit::emit(source,p.program);
 if bytes.len==0 {return generic_callable::Result {status:1};}
 return generic_callable::Result {argument:p.program.head.argument,result:p.program.head.result,wasm:bytes};
}

fn compile(source:u8[:])->generic_callable::Result {return compile_with_fault(source,0);}
