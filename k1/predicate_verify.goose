// Caller owns immutable expected source. All type and span facts are replayed.
namespace predicate_verify;
import predicate_core;
import predicate_header;
import public_frontend;
fn verify(source:u8[:],p:predicate_core::Program&)->bool {
 if source!=p.source {return false;}let a=predicate_header::header(source);let b=p.head;
 if !a.ok || !b.ok || a.let_start!=b.let_start || a.type_start!=b.type_start || a.type_end!=b.type_end || a.effect_start!=b.effect_start || a.resources_end!=b.resources_end || a.depth!=b.depth || a.frame!=b.frame || a.form!=b.form {return false;}
 let projected=predicate_header::normalize(source,a);return projected.len>0 && p.body.core.result_type==2 && public_frontend::verify(projected,p.body);
}
