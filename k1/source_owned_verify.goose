// Independently replays the full header and checks body lexical loan authority.
namespace source_owned_verify;
import lexer;
import validate;
import ownership_check;
import source_owned_core;
struct Scan {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn step(s:u8[:],r:Scan&) {if !r.bad {r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn expect(s:u8[:],r:Scan&,word:u8[:])->bool {let t=r.t;if r.bad || t.start<0 || t.end<=t.start || t.end>s.len || (t.kind!=1 && t.kind!=5) || s[t.start..t.end]!=word {r.bad=true;return false;}step(s,r);return !r.bad;}
fn words(s:u8[:],r:Scan&,items:const u8[:][:])->bool {for x in items {if !expect(s,r,x) {return false;}}return true;}
fn ident(s:u8[:],r:Scan&)->lexer::Token {let t=r.t;if r.bad || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>s.len || !validate::name_valid(s[t.start..t.end]) {r.bad=true;return lexer::Token {kind:9};}step(s,r);return t;}
fn verify(s:u8[:],p:source_owned_core::Program&)->bool {
 if s.len>65536 || p.source[..]!=s {return false;}var r=Scan {lex:lexer::init(s)};step(s,r);
 if !words(s,r,["type","Scalar","[","r",":","Region","]","=","U32"]) || r.t.kind!=6 {return false;}step(s,r);
 if !expect(s,r,"let") {return false;}let function=ident(s,r);if r.bad || s[function.start..function.end]=="Scalar" {return false;}
 if !words(s,r,[":","(","Owned","[","Scalar","[","_","]","]",",","Bool",")","->"]) {return false;}
 var mode:i64=0;if r.t.kind==1 && s[r.t.start..r.t.end]=="Unit" {step(s,r);mode=0;}
 else if r.t.kind==1 && s[r.t.start..r.t.end]=="U32" {step(s,r);mode=2;}
 else {if !words(s,r,["Owned","[","Scalar","[","_","]","]"]) {return false;}mode=1;}
 if !words(s,r,["!","{","release","}","=","fn","("]) {return false;}let owner=ident(s,r);
 if !expect(s,r,",") {return false;}let flag=ident(s,r);if !words(s,r,[")","=>"]) || r.bad || r.t.kind!=1 || r.t.start<0 || r.t.end> s.len || s[r.t.start..r.t.end]!="do" {return false;}
 let h=p.head;if !h.ok || h.body!=r.t.start || h.owner_start!=owner.start || h.owner_end!=owner.end || h.flag_start!=flag.start || h.flag_end!=flag.end || h.mode!=mode || s[owner.start..owner.end]==s[flag.start..flag.end] {return false;}
 if h.body<0 || h.body>=s.len || p.tree.source[..]!=s[h.body..] {return false;}
 var owner_bytes:u8[>..]=[];owner_bytes.append(s[owner.start..owner.end]);var flag_bytes:u8[>..]=[];flag_bytes.append(s[flag.start..flag.end]);var c=ownership_check::Contract {owner:copy(owner_bytes),flag:copy(flag_bytes),return_mode:mode};
 return ownership_check::check(p.tree,s[h.body..],c)==0;
}
