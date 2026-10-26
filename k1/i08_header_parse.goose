// Bounded canonical I08 declaration recognizer. This is a source syntax
// bridge, not typed capability, loan, proof or executable admission.
namespace i08_header_parse;
import lexer;
import i08_core;
import i08_parse;
fn parse(source:u8[:])->i08_core::Tree,i64 {
 if source.len>65536 {return i08_core::Tree {},2;}
 var lex=lexer::init(source);var t=lexer::next(source,lex);while t.kind==6 {t=lexer::next(source,lex);}
 var seeds:lexer::Token[5]=[lexer::Token {};5];var scope:i64=0;
    for text in [
        "pub","let","project",":","forall","[","r",":","Region",",","s",":","Region",",","n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>",
        "Fn","[","static",",","Many",",","(","View","[","r",",","{","x",":","F32",",","y",":","F32",",","vx",":","F32",",","vy",":","F32","}",",","n",",","d","]",",",
        "F32",",","Builder","[","s",",","{","x",":","F32",",","y",":","F32","}",",","0",",","c",",","Append","]",")",",",
        "exists","[","e",":","Domain","]","=>","View","[","s",",","{","x",":","F32",",","y",":","F32","}",",","n",",","e","]","]",
        "!","{","read","r",",","write","s","}","requires","[","Le","(","n",",","c",")","]","resources","{","depth",":","2",",","frame",":","256","}","=","fn"] {
  let ch=text[0];let kind=if ch>='0' && ch<='9' {2} else if (ch>='a' && ch<='z') || (ch>='A' && ch<='Z') || ch=='_' {1} else {5};
  if t.kind!=kind || t.start<0 || t.end<=t.start || t.end>source.len || source[t.start..t.end]!=text {return i08_core::Tree {},1;}
  if text=="forall" {scope=t.start+1;}
  if text=="r" && seeds[0].end==0 {seeds[0]=t;}else if text=="s" && seeds[1].end==0 {seeds[1]=t;}
  else if text=="n" && seeds[2].end==0 {seeds[2]=t;}else if text=="c" && seeds[3].end==0 {seeds[3]=t;}
  else if text=="d" && seeds[4].end==0 {seeds[4]=t;}
  if text!="fn" {t=lexer::next(source,lex);}
 }
 if scope==0 {return i08_core::Tree {},1;}return i08_parse::parse_from(source,lex,t,seeds,scope);
}
