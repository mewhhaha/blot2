namespace generic_fn_frontend;
import generic_fn_core;
import generic_fn_verify;
import compiler_frontend;
fn parse(source:u8[:])->generic_fn_core::Result {
 let h=generic_fn_verify::header(source);if !h.ok {return generic_fn_core::Result {status:1};}
 let flat=generic_fn_verify::project(source,h);var body=compiler_frontend::parse(flat);if body.status!=0 {return generic_fn_core::Result {status:body.status};}
 var p=generic_fn_core::Program {source:source,head:h,body:copy(body.program)};
 if !generic_fn_verify::verify(source,p) {return generic_fn_core::Result {status:1};}
 return generic_fn_core::Result {program:p};
}
