// Closed private module fixture: source-verified owned construction, direct
// consumer call, lexical loan and scalar return in fresh private state.
// Not a public ABI, compiler artifact or general K1 ownership implementation.
namespace owned_wasm_plan;
import lexer;
import source_owned_admit;
import source_owned_run;
import owned_scalar_source;
import owned_scalar_verify;
import owned_scalar_runtime;
struct Result {status:i64=1,flag:bool=false,core:owned_scalar_source::Core=owned_scalar_source::Core {},consumer:source_owned_core::Program=source_owned_core::Program {}}
import source_owned_core;
struct Scan {lex:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false,last:i64=0}
fn step(s:u8[:],r:Scan&) {if !r.bad {r.last=r.t.end;r.t=lexer::next(s,r.lex);if r.t.kind==9 {r.bad=true;}}}
fn tok(s:u8[:],r:Scan&,word:u8[:])->bool {let t=r.t;if r.bad || t.start<0 || t.end<=t.start || t.end>s.len || (t.kind!=1 && t.kind!=5) || s[t.start..t.end]!=word {r.bad=true;return false;}step(s,r);return !r.bad;}
fn seq(s:u8[:],r:Scan&,words:const u8[:][:])->bool {for x in words {if !tok(s,r,x){return false;}}return true;}
fn kind(s:u8[:],r:Scan&,k:i64)->bool {if r.bad || r.t.kind!=k {r.bad=true;return false;}step(s,r);return !r.bad;}
fn tag(s:u8[:],r:Scan&,name:u8[:])->bool {if !tok(s,r,"#") || r.t.start!=r.last {return false;}return tok(s,r,name);}
// Strip the enclosing function indentation only; every projected byte comes
// from this checked source slice. The owned parser checks the complete result.
fn project_owned(s:u8[:])->u8[] {
 var out:u8[>..]=[];var i:i64=0;var line=false;
 while i<s.len {if line {if s.len-i<2 || s[i]!=' ' || s[i+1]!=' ' {return [];}i+=2;line=false;if i==s.len {break;}}
  let ch=s[i];out.push(ch);i+=1;if ch=='\n' {line=true;}}
 return copy(out);
}
fn plan(s:u8[:])->Result {
 if s.len>65536 {return Result {};}
 var r=Scan {lex:lexer::init(s)};step(s,r);if !tok(s,r,"type") {return Result {};}
 // The exact prior consumer module is independently recognized below. Find
 // its one top-level continuation and require the declaration name consume.
 var prefix:i64=0;var depth:i64=0;var named=false;
 while !r.bad && r.t.kind!=0 {
  if r.t.kind==7 {depth+=1;step(s,r);continue;}if r.t.kind==8 {depth-=1;if depth<0{return Result {};}step(s,r);continue;}
  if depth==0 && r.t.kind==1 && s[r.t.start..r.t.end]=="let" && !named {step(s,r);if !tok(s,r,"consume") {return Result {};}named=true;continue;}
  if depth==0 && r.t.kind==1 && s[r.t.start..r.t.end]=="type" && named {prefix=r.t.start;break;}
  step(s,r);
 }
 if prefix<=0 || r.bad {return Result {};}
 var consumer=source_owned_admit::admit(s[..prefix]);if consumer.status!=0 || consumer.program.head.mode!=2 {return Result {};}
 if !seq(s,r,["type","ScalarPayload","[","r",":","Region","]","=","U32"]) || !kind(s,r,6) {return Result {};}
 if !seq(s,r,["let","main",":","Unit","->","Result","[","U32",","]) || !tag(s,r,"Reserve") || !seq(s,r,["(","ReserveError",")","|"]) || !tag(s,r,"Body") || !seq(s,r,["("]) || !tag(s,r,"Cancelled") || !seq(s,r,[")","]","!","{","reserve",",","release","}","=","fn","(",")","=>","do",":"]) || !kind(s,r,6) || !kind(s,r,7) || !seq(s,r,["let","built","="]) {return Result {};}
 if r.t.kind!=1 || s[r.t.start..r.t.end]!="owned" {return Result {};}let start=r.t.start;
 while !r.bad && r.t.kind!=8 && r.t.kind!=0 {step(s,r);}if r.bad || r.t.kind!=8 || r.t.start<start || r.t.start>s.len {return Result {};}
 let end=r.t.start;let projected=project_owned(s[start..end]);if projected.len==0 {return Result {};}let built=owned_scalar_source::parse(projected);if built.status!=0 || !owned_scalar_verify::verify(projected,built.core) || !kind(s,r,8) {return Result {};}
 if !seq(s,r,["case","built",":"]) || !kind(s,r,6) || !kind(s,r,7) || !tag(s,r,"Err") || !seq(s,r,["(","e",")","=>","return"]) || !tag(s,r,"Err") || !seq(s,r,["(","e",")"]) || !kind(s,r,6) || !tag(s,r,"Ok") || !seq(s,r,["(","h",")","=>","return"]) || !tag(s,r,"Ok") || !seq(s,r,["(","consume","(","h",","]) || !tok(s,r,"#") || r.t.start!=r.last {return Result {};}
 var flag=false;if r.t.kind==1 && s[r.t.start..r.t.end]=="True" {flag=true;step(s,r);}else if r.t.kind==1 && s[r.t.start..r.t.end]=="False" {step(s,r);}else {return Result {};}
 if !seq(s,r,[")",")"]) {return Result {};}if r.t.kind==6 && !kind(s,r,6) {return Result {};}
 if !kind(s,r,8) || !kind(s,r,8) || r.bad || r.t.kind!=0 {return Result {};}
 return Result {status:0,flag:flag,core:built.core,consumer:copy(consumer.program)};
}
