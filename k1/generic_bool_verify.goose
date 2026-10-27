// The header is reconstructed from the authoritative bytes on each verify.
// No independent resource, ABI or effect qualification is implied.
namespace generic_bool_verify;
import lexer;
import validate;
import flow_decl_check;
import generic_bool_core;
import joined_public_verify;
import generic_fn_core;
fn header(s:u8[:])->generic_fn_core::Header {
 if s.len>16777216 {return generic_fn_core::Header {};}
 var r=joined_public_verify::Reader {state:lexer::init(s)};joined_public_verify::next(s,r);while !r.bad && r.token.kind==6 {joined_public_verify::next(s,r);}
 let pub=r.token;if !joined_public_verify::take(s,r,1,"pub") {return generic_fn_core::Header {};}
 var line=pub.start;while line>0 && s[line-1]!='\n' {line-=1;}if line!=pub.start {return generic_fn_core::Header {};}
 let start=r.token.start;if !joined_public_verify::take(s,r,1,"let") {return generic_fn_core::Header {};}
 let name=r.token;if r.bad || name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || !validate::name_valid(s[name.start..name.end]) {return generic_fn_core::Header {};}joined_public_verify::next(s,r);
 if !joined_public_verify::take(s,r,5,":") {return generic_fn_core::Header {};}
 let ts=r.token.start;var form:i64=0;var te:i64=0;
 if joined_public_verify::is(s,r.token,1,"Bool") {
  form=1;if !joined_public_verify::take(s,r,1,"Bool") || !joined_public_verify::take(s,r,5,"->") {return generic_fn_core::Header {};}te=r.token.end;if !joined_public_verify::take(s,r,1,"U32") {return generic_fn_core::Header {};}
 } else {
  form=2;if !joined_public_verify::take(s,r,1,"Fn") || !joined_public_verify::take(s,r,5,"[") || !joined_public_verify::take(s,r,1,"static") || !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"Many") || !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"Bool") || !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"U32") {return generic_fn_core::Header {};}te=r.token.end;if !joined_public_verify::take(s,r,5,"]") {return generic_fn_core::Header {};}
 }
 let effects=r.token.start;if !joined_public_verify::take(s,r,5,"!") || !joined_public_verify::take(s,r,5,"{") || !joined_public_verify::take(s,r,5,"}") || !joined_public_verify::take(s,r,1,"resources") || !joined_public_verify::take(s,r,5,"{") || !joined_public_verify::take(s,r,1,"depth") || !joined_public_verify::take(s,r,5,":") {return generic_fn_core::Header {};}
 let depth,ok=joined_public_verify::number(s,r.token);if !ok || depth<1 || depth>128 {return generic_fn_core::Header {};}joined_public_verify::next(s,r);
 if !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"frame") || !joined_public_verify::take(s,r,5,":") {return generic_fn_core::Header {};}
 let frame,valid=joined_public_verify::number(s,r.token);if !valid {return generic_fn_core::Header {};}joined_public_verify::next(s,r);
 let end=r.token.end;if !joined_public_verify::take(s,r,5,"}") || !joined_public_verify::is(s,r.token,5,"=") {return generic_fn_core::Header {};}
 for c in s[pub.start..r.token.start] {if c=='\n' || c=='\r' {return generic_fn_core::Header {};}}
 if start<0 || ts<start || te<ts || effects<te || end<effects || end>s.len || (form==2 && te-ts<11) {return generic_fn_core::Header {};}
 return generic_fn_core::Header {ok:true,let_start:start,type_start:ts,type_end:te,effect_start:effects,resources_end:end,depth:depth,frame:frame,form:form};
}
fn project(s:u8[:],h:generic_fn_core::Header)->u8[] {
 if !h.ok || h.let_start<0 || h.type_start<h.let_start || h.type_end<h.type_start || h.effect_start<h.type_end || h.resources_end<h.effect_start || h.resources_end>s.len {return [];}
 var out:u8[>..]=[];out.append(s[h.let_start..]);
 if h.form==2 {if h.type_end-h.type_start<11 {return [];}let replacement="Bool -> U32";for i in h.type_start-h.let_start..h.type_end-h.let_start {out[i]=' ';}for i in replacement.len {out[h.type_start-h.let_start+i]=replacement[i];}}
 else if h.form!=1 {return [];}
 for i in h.effect_start-h.let_start..h.resources_end-h.let_start {out[i]=' ';}return out;
}
fn verify(expected:u8[:],p:generic_bool_core::Program&)->bool {
 if expected!=p.source {return false;}let h=header(expected);let b=p.head;
 if !h.ok || !b.ok || h.let_start!=b.let_start || h.type_start!=b.type_start || h.type_end!=b.type_end || h.effect_start!=b.effect_start || h.resources_end!=b.resources_end || h.depth!=b.depth || h.frame!=b.frame || h.form!=b.form {return false;}
 let flat=project(expected,h);return flat.len>0 && flat[..]==p.body.source && flow_decl_check::verify(p.body);
}
