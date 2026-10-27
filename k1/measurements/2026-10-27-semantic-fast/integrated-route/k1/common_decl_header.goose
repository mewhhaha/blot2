// Authoritative original-source recognizer for one private scalar signature.
namespace common_decl_header;
import lexer;
import validate;
import joined_public_verify;
import common_decl_core;
import public_frontend;
fn scalar(s:u8[:],r:joined_public_verify::Reader&)->i64 {if joined_public_verify::is(s,r.token,1,"U32") {joined_public_verify::next(s,r);return 1;}if joined_public_verify::is(s,r.token,1,"Bool") {joined_public_verify::next(s,r);return 2;}return 0;}
fn header(s:u8[:])->common_decl_core::Header {
 if s.len>16777216{return common_decl_core::Header {};}
 var r=joined_public_verify::Reader {state:lexer::init(s)};joined_public_verify::next(s,r);while !r.bad && r.token.kind==6 {joined_public_verify::next(s,r);}
 let pub=r.token;if !joined_public_verify::take(s,r,1,"pub"){return common_decl_core::Header {};}
 var line=pub.start;while line>0 && s[line-1]!='\n' {line-=1;}if line!=pub.start{return common_decl_core::Header {};}
 let start=r.token.start;if !joined_public_verify::take(s,r,1,"let"){return common_decl_core::Header {};}
 let name=r.token;if r.bad || name.kind!=1 || name.start<0 || name.end<=name.start || name.end>s.len || !validate::name_valid(s[name.start..name.end]){return common_decl_core::Header {};}joined_public_verify::next(s,r);
 if !joined_public_verify::take(s,r,5,":"){return common_decl_core::Header {};}
 let ts=r.token.start;var form:i64=0;var te:i64=0;var argument:i64=0;var result:i64=0;
 if joined_public_verify::is(s,r.token,1,"Fn") {
  form=2;if !joined_public_verify::take(s,r,1,"Fn") || !joined_public_verify::take(s,r,5,"[") || !joined_public_verify::take(s,r,1,"static") || !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"Many") || !joined_public_verify::take(s,r,5,","){return common_decl_core::Header {};}
  argument=scalar(s,r);if argument==0 || !joined_public_verify::take(s,r,5,","){return common_decl_core::Header {};}
  result=scalar(s,r);te=r.token.end;if result==0 || !joined_public_verify::take(s,r,5,"]"){return common_decl_core::Header {};}
 } else {form=1;argument=scalar(s,r);if argument==0 || !joined_public_verify::take(s,r,5,"->"){return common_decl_core::Header {};}
  te=r.token.end;result=scalar(s,r);if result==0{return common_decl_core::Header {};}}
 let effects=r.token.start;if !joined_public_verify::take(s,r,5,"!") || !joined_public_verify::take(s,r,5,"{") || !joined_public_verify::take(s,r,5,"}") || !joined_public_verify::take(s,r,1,"resources") || !joined_public_verify::take(s,r,5,"{") || !joined_public_verify::take(s,r,1,"depth") || !joined_public_verify::take(s,r,5,":"){return common_decl_core::Header {};}
 let depth,ok=joined_public_verify::number(s,r.token);if !ok || depth<1 || depth>128{return common_decl_core::Header {};}joined_public_verify::next(s,r);
 if !joined_public_verify::take(s,r,5,",") || !joined_public_verify::take(s,r,1,"frame") || !joined_public_verify::take(s,r,5,":"){return common_decl_core::Header {};}
 let frame,valid=joined_public_verify::number(s,r.token);if !valid{return common_decl_core::Header {};}joined_public_verify::next(s,r);let end=r.token.end;
 if !joined_public_verify::take(s,r,5,"}") || !joined_public_verify::is(s,r.token,5,"="){return common_decl_core::Header {};}
 for c in s[pub.start..r.token.start] {if c=='\n' || c=='\r' {return common_decl_core::Header {};}}
 if start<0 || ts<start || te<ts || effects<te || end<effects || end>s.len{return common_decl_core::Header {};}
 return common_decl_core::Header {ok:true,let_start:start,type_start:ts,type_end:te,effect_start:effects,resources_end:end,argument:argument,result:result,depth:depth,frame:frame,form:form};
}
fn project(s:u8[:],h:common_decl_core::Header)->u8[] {
 if !h.ok || h.let_start<0 || h.type_start<h.let_start || h.type_end<h.type_start || h.effect_start<h.type_end || h.resources_end<h.effect_start || h.resources_end>s.len || h.argument<1 || h.argument>2 || h.result<1 || h.result>2{return [];}
 var normalized:u8[>..]=[];normalized.append(s);
 if h.form==2 {let arg=if h.argument==1 {"U32"} else {"Bool"};let res=if h.result==1 {"U32"} else {"Bool"};var text:u8[>..]=[];text.append(arg);text.append(" -> ");text.append(res);if text.len>h.type_end-h.type_start{return [];}
  for i in h.type_start..h.type_end {normalized[i]=' ';}for ch,i in text {normalized[h.type_start+i]=ch;}}
 else if h.form!=1 {return [];}
 return public_frontend::projected(normalized,h.let_start,h.effect_start,h.resources_end);
}
