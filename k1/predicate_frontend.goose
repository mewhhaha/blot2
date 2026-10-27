namespace predicate_frontend;
import predicate_core;
import predicate_header;
import predicate_verify;
import public_frontend;
fn parse(source:u8[:])->predicate_core::Result {
 let h=predicate_header::header(source);if !h.ok {return predicate_core::Result {status:1};}
 let normalized=predicate_header::normalize(source,h);let c=public_frontend::parse(normalized);if c.status!=0 {return predicate_core::Result {status:c.status};}
 var p=predicate_core::Program {source:source,head:h,body:c};if !predicate_verify::verify(source,p) {return predicate_core::Result {status:1};}return predicate_core::Result {program:p};
}
