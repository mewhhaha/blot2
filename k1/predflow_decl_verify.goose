// Independently replay original signature and source-bound lexical body.
namespace predflow_decl_verify;
import predicate_header;
import public_frontend;
import generic_fn_core;
import predflow_decl_core;
import predflow_check;
fn project(source:u8[:],head:generic_fn_core::Header)->u8[] {
 let normalized=predicate_header::normalize(source,head);if normalized.len==0 {return [];}
 return public_frontend::projected(normalized,head.let_start,head.effect_start,head.resources_end);
}
fn verify(source:u8[:],p:predflow_decl_core::Program&)->bool {
 if source!=p.source {return false;}let a=predicate_header::header(source);let b=p.head;
 if !a.ok || !b.ok || a.let_start!=b.let_start || a.type_start!=b.type_start || a.type_end!=b.type_end || a.effect_start!=b.effect_start || a.resources_end!=b.resources_end || a.depth!=b.depth || a.frame!=b.frame || a.form!=b.form {return false;}
 let flat=project(source,a);return flat.len>0 && predflow_check::verify(flat,p.body);
}
