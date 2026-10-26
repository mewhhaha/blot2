// Independent recognition of the exact canonical I08 signature and its
// source-owned quantified bindings. This is a syntax seam only: it neither
// proves View loans and bounds nor authorizes effects, types or a backend.
namespace i08_header_verify;
import lexer;
import i08_core;
import i08_verify;
fn verify(tree:i08_core::Tree&,expected:u8[:])->bool {
 if expected.len>65536 || tree.source[..]!=expected {return false;}
 var state=lexer::init(expected);var token=lexer::next(expected,state);
 while token.kind==6 {token=lexer::next(expected,state);}
 var seeds:lexer::Token[5]=[lexer::Token {};5];var seed_count:i64=0;var in_binders=false;var scope:i64=0;
 for text in [
  "pub","let","project",":","forall","[","r",":","Region",",","s",":","Region",",","n",":","Nat",",","c",":","Nat",",","d",":","Domain","]","=>",
  "Fn","[","static",",","Many",",","(","View","[","r",",","{","x",":","F32",",","y",":","F32",",","vx",":","F32",",","vy",":","F32","}",",","n",",","d","]",",",
  "F32",",","Builder","[","s",",","{","x",":","F32",",","y",":","F32","}",",","0",",","c",",","Append","]",")",",",
  "exists","[","e",":","Domain","]","=>","View","[","s",",","{","x",":","F32",",","y",":","F32","}",",","n",",","e","]","]",
  "!","{","read","r",",","write","s","}","requires","[","Le","(","n",",","c",")","]","resources","{","depth",":","2",",","frame",":","256","}","="
 ] {
  let first=text[0];let kind=if first>='0' && first<='9' {2} else if (first>='a' && first<='z') || (first>='A' && first<='Z') || first=='_' {1} else {5};
  if token.kind!=kind || token.start<0 || token.end<=token.start || token.end>expected.len || expected[token.start..token.end]!=text {return false;}
  if text=="forall" {scope=token.start+1;in_binders=true;}
  else if in_binders && text=="]" {in_binders=false;}
  else if in_binders && (text=="r" || text=="s" || text=="n" || text=="c" || text=="d") {
   if seed_count>=5 {return false;}seeds[seed_count]=token;seed_count+=1;
  }
  token=lexer::next(expected,state);
 }
 if seed_count!=5 || scope<=0 || token.kind!=1 || token.start<0 || token.end<=token.start || token.end>expected.len || expected[token.start..token.end]!="fn" {return false;}
 return i08_verify::verify_from(tree,expected,state,token,seeds[..],scope);
}
