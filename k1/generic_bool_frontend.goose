namespace generic_bool_frontend;
import generic_bool_core;
import generic_bool_verify;
import flow_decl;
fn parse(source:u8[:])->generic_bool_core::Result {
 let h=generic_bool_verify::header(source);if !h.ok {return generic_bool_core::Result {status:1};}
 let flat=generic_bool_verify::project(source,h);var body=flow_decl::build(flat);if body.status!=0 {return generic_bool_core::Result {status:body.status};}
 var p=generic_bool_core::Program {source:source,head:h,body:copy(body.decl)};
 if !generic_bool_verify::verify(source,p) {return generic_bool_core::Result {status:1};}
 return generic_bool_core::Result {program:p};
}
