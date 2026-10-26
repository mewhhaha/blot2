// Private source projection, checked independently by joined_public_verify.
namespace joined_public_frontend;
import joined_public_core;
import joined_public_verify;
import compiler_frontend;
fn parse(source:u8[:])->joined_public_core::Result {
 let h=joined_public_verify::header(source);if !h.ok {return joined_public_core::Result {status:1};}
 let flat=joined_public_verify::project(source,h);var body=compiler_frontend::parse(flat);if body.status!=0 {return joined_public_core::Result {status:body.status};}
 var p=joined_public_core::Program {source:source,head:h,body:copy(body.program)};
 if !joined_public_verify::verify(source,p) {return joined_public_core::Result {status:1};}
 return joined_public_core::Result {program:p};
}
