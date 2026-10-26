// Independently re-lex original public header and recheck the entire projected
// body. It proves only this private syntactic/type subset, not public ABI.
namespace joined_public_verify;
import lexer;
import validate;
import compiler_validate;
import joined_public_core;
struct Reader {state:lexer::State=lexer::State {},token:lexer::Token=lexer::Token {},bad:bool=false}
fn next(s:u8[:],r:Reader&) {if !r.bad {r.token=lexer::next(s,r.state);if r.token.kind==9 {r.bad=true;}}}
fn is(s:u8[:],t:lexer::Token,k:i64,v:u8[:])->bool {return t.kind==k && t.start>=0 && t.end>t.start && t.end<=s.len && s[t.start..t.end]==v;}
fn take(s:u8[:],r:Reader&,k:i64,v:u8[:])->bool {if r.bad || !is(s,r.token,k,v) {r.bad=true;return false;}next(s,r);return !r.bad;}
fn number(s:u8[:],t:lexer::Token)->u32,bool {if t.kind!=2 || t.start<0 || t.end<=t.start || t.end>s.len {return 0,false;}var n:u64=0;for c in s[t.start..t.end] {if c<'0' || c>'9' {return 0,false;}let d=(c-'0') as u64;if n>(4294967295-d)/10 {return 0,false;}n=n*10+d;}return n as u32,true;}
fn header(s:u8[:])->joined_public_core::Header {
 if s.len>16777216 {return joined_public_core::Header {};}
 var r=Reader {state:lexer::init(s)};next(s,r);while !r.bad && r.token.kind==6 {next(s,r);}
 let pub=r.token;if !take(s,r,1,"pub") {return joined_public_core::Header {};}
 var line=pub.start;while line>0 && s[line-1]!='\n' {line-=1;}if line!=pub.start {return joined_public_core::Header {};}
 let start=r.token.start;if !take(s,r,1,"let") {return joined_public_core::Header {};}
 let name=r.token;if r.bad || name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || !validate::name_valid(s[name.start..name.end]) {return joined_public_core::Header {};}next(s,r);
 if !take(s,r,5,":") || !take(s,r,1,"U32") || !take(s,r,5,"->") || !take(s,r,1,"U32") {return joined_public_core::Header {};}
 let effects=r.token.start;if !take(s,r,5,"!") || !take(s,r,5,"{") || !take(s,r,5,"}") || !take(s,r,1,"resources") || !take(s,r,5,"{") || !take(s,r,1,"depth") || !take(s,r,5,":") {return joined_public_core::Header {};}
 let depth,ok=number(s,r.token);if !ok || depth<1 || depth>128 {return joined_public_core::Header {};}next(s,r);
 if !take(s,r,5,",") || !take(s,r,1,"frame") || !take(s,r,5,":") {return joined_public_core::Header {};}
 let frame,valid=number(s,r.token);if !valid {return joined_public_core::Header {};}next(s,r);
 let end=r.token.end;if !take(s,r,5,"}") || !is(s,r.token,5,"=") {return joined_public_core::Header {};}
 for c in s[pub.start..r.token.start] {if c=='\n' || c=='\r' {return joined_public_core::Header {};}}
 if start<0 || effects<start || end<effects || end>s.len {return joined_public_core::Header {};}
 return joined_public_core::Header {ok:true,let_start:start,effect_start:effects,resources_end:end,depth:depth,frame:frame};
}
fn project(s:u8[:],h:joined_public_core::Header)->u8[] {if !h.ok || h.let_start<0 || h.effect_start<h.let_start || h.resources_end<h.effect_start || h.resources_end>s.len {return [];}var out:u8[>..]=[];out.append(s[h.let_start..]);for i in h.effect_start-h.let_start..h.resources_end-h.let_start {out[i]=' ';}return out;}
fn verify(expected:u8[:],p:joined_public_core::Program&)->bool {
 if expected!=p.source {return false;}let h=header(expected);let b=p.head;
 if !h.ok || !b.ok || h.let_start!=b.let_start || h.effect_start!=b.effect_start || h.resources_end!=b.resources_end || h.depth!=b.depth || h.frame!=b.frame {return false;}
 let flat=project(expected,h);return flat.len>0 && compiler_validate::verify(flat,p.body);
}
