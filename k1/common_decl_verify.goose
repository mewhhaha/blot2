// Reconstruct header and exact body against the caller-retained original.
namespace common_decl_verify;
import common_decl_core;
import common_decl_header;
import common_check;
fn verify(source:u8[:],p:common_decl_core::Program&)->bool {
 if source!=p.source{return false;}let a=common_decl_header::header(source);let b=p.header;
 if !a.ok || !b.ok || a.let_start!=b.let_start || a.type_start!=b.type_start || a.type_end!=b.type_end || a.effect_start!=b.effect_start || a.resources_end!=b.resources_end || a.argument!=b.argument || a.result!=b.result || a.depth!=b.depth || a.frame!=b.frame || a.form!=b.form{return false;}
 let flat=common_decl_header::project(source,a);return flat.len>0 && common_check::verify(flat,p.body);
}
