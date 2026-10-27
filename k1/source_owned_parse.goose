// Producer: recognizes one private function with an exact scalar schema.
namespace source_owned_parse;
import lexer;
import validate;
import ownership_parse;
import source_owned_core;
struct Cursor {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn next(s:u8[:],c:Cursor&) {c.t=lexer::next(s,c.lex);if c.t.kind==9 {c.bad=true;}}
fn take(s:u8[:],c:Cursor&,kind:i64,word:u8[:])->bool {let t=c.t;if c.bad || t.kind!=kind || t.start<0 || t.end<=t.start || t.end>s.len || s[t.start..t.end]!=word {c.bad=true;return false;}next(s,c);return !c.bad;}
fn name(s:u8[:],c:Cursor&)->lexer::Token {let t=c.t;if c.bad || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || !validate::name_valid(s[t.start..t.end]) {c.bad=true;return lexer::Token {kind:9};}next(s,c);return t;}
fn header(s:u8[:])->source_owned_core::Header {
 var c=Cursor {lex:lexer::init(s)};next(s,c);
 if !take(s,c,1,"type") || !take(s,c,1,"Scalar") || !take(s,c,5,"[") || !take(s,c,1,"r") || !take(s,c,5,":") || !take(s,c,1,"Region") || !take(s,c,5,"]") || !take(s,c,5,"=") || !take(s,c,1,"U32") || c.t.kind!=6 {return source_owned_core::Header {};}
 next(s,c);if !take(s,c,1,"let") {return source_owned_core::Header {};}let function=name(s,c);if c.bad || s[function.start..function.end]=="Scalar" {return source_owned_core::Header {};}
 if !take(s,c,5,":") || !take(s,c,5,"(") || !take(s,c,1,"Owned") || !take(s,c,5,"[") || !take(s,c,1,"Scalar") || !take(s,c,5,"[") || !take(s,c,1,"_") || !take(s,c,5,"]") || !take(s,c,5,"]") || !take(s,c,5,",") || !take(s,c,1,"Bool") || !take(s,c,5,")") || !take(s,c,5,"->") {return source_owned_core::Header {};}
 var mode:i64=0;
 if c.t.kind==1 && s[c.t.start..c.t.end]=="Unit" {next(s,c);mode=0;}
 else if c.t.kind==1 && s[c.t.start..c.t.end]=="U32" {next(s,c);mode=2;}
 else if take(s,c,1,"Owned") && take(s,c,5,"[") && take(s,c,1,"Scalar") && take(s,c,5,"[") && take(s,c,1,"_") && take(s,c,5,"]") && take(s,c,5,"]") {mode=1;}
 else {return source_owned_core::Header {};}
 if !take(s,c,5,"!") || !take(s,c,5,"{") || !take(s,c,1,"release") || !take(s,c,5,"}") || !take(s,c,5,"=") || !take(s,c,1,"fn") || !take(s,c,5,"(") {return source_owned_core::Header {};}
 let owner=name(s,c);if !take(s,c,5,",") {return source_owned_core::Header {};}let flag=name(s,c);
 if !take(s,c,5,")") || !take(s,c,5,"=>") || c.bad || c.t.kind!=1 || s[c.t.start..c.t.end]!="do" {return source_owned_core::Header {};}
 if s[owner.start..owner.end]==s[flag.start..flag.end] {return source_owned_core::Header {};}
 return source_owned_core::Header {ok:true,body:c.t.start,owner_start:owner.start,owner_end:owner.end,flag_start:flag.start,flag_end:flag.end,mode:mode};
}
fn build(s:u8[:])->source_owned_core::Result {
 if s.len>65536 {return source_owned_core::Result {};}
 let h=header(s);if !h.ok || h.body<0 || h.body>=s.len {return source_owned_core::Result {};}
 var body=ownership_parse::parse(s[h.body..]);if body.status!=0 {return source_owned_core::Result {status:body.status};}
 var stored:u8[>..]=[];stored.append(s);return source_owned_core::Result {status:0,program:source_owned_core::Program {source:stored,head:h,tree:copy(body.tree)}};
}
