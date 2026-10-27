namespace predflow_decl_frontend;
import predicate_header;
import predflow_decl_core;
import predflow_decl_verify;
import predflow_frontend;
fn parse(source:u8[:])->predflow_decl_core::Result {
 let h=predicate_header::header(source);if !h.ok{return predflow_decl_core::Result {status:1};}
 let flat=predflow_decl_verify::project(source,h);var body=predflow_frontend::parse(flat);
 if body.status!=0{return predflow_decl_core::Result {status:body.status};}
 var p=predflow_decl_core::Program {source:source,head:h,body:copy(body.program)};
 if !predflow_decl_verify::verify(source,p){return predflow_decl_core::Result {status:1};}
 return predflow_decl_core::Result {program:p};
}
