namespace common_decl_frontend;
import common_decl_core;
import common_decl_header;
import common_decl_verify;
import common_frontend;
fn parse(source:u8[:])->common_decl_core::Result {
 let h=common_decl_header::header(source);if !h.ok{return common_decl_core::Result {status:1};}let flat=common_decl_header::project(source,h);var body=common_frontend::parse(flat);if body.status!=0{return common_decl_core::Result {status:body.status};}
 var p=common_decl_core::Program {source:source,header:h,body:copy(body.program)};if !common_decl_verify::verify(source,p){return common_decl_core::Result {status:1};}return common_decl_core::Result {program:p};
}
