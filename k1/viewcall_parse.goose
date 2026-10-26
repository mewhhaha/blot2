// Checked source declaration forwarding a borrowed formal View to the
// exact earlier source declaration. No external capability IDs are accepted.
namespace viewcall_parse;
import lexer;
import viewproof_core;
import viewproof_verify;
import viewcall_core;
import viewproof_parse;
fn bound(src:u8[:])->i64 {
 var state=lexer::init(src);var found:i64=0;var depth:i64=-1;
 while true {let t=lexer::next(src,state);if t.kind==9 {return -1;}if t.kind==0 {break;}
  if t.kind==1 && t.start>=0 && t.end<=src.len && src[t.start..t.end]=="resources" {
   found+=1;let a=lexer::next(src,state);let b=lexer::next(src,state);let c=lexer::next(src,state);let d=lexer::next(src,state);
   if a.kind!=5 || src[a.start..a.end]!="{" || b.kind!=1 || src[b.start..b.end]!="depth" || c.kind!=5 || src[c.start..c.end]!=":" || d.kind!=2 {return -1;}
   var x:i64=0;for ch in src[d.start..d.end] {if ch<'0' || ch>'9' || x>128 {return -1;}x=x*10+(ch-'0') as i64;}depth=x;
  }
 }
 if found!=1 || depth<1 || depth>127 {return -1;}return depth;
}
fn caller(src:u8[:],callee:viewproof_core::Program&)->viewcall_core::Program,i64 {
 if src.len>65536 {return viewcall_core::Program {},2;}var c=viewproof_parse::C {s:lexer::init(src)};viewproof_parse::next(src,c);while !c.bad && c.t.kind==6 {viewproof_parse::next(src,c);}
 let _=viewproof_parse::word(src,c,"let");let name=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,":");let _=viewproof_parse::word(src,c,"forall");let _=viewproof_parse::sym(src,c,"[");let r=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,":");let _=viewproof_parse::word(src,c,"Region");let _=viewproof_parse::sym(src,c,",");let n=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,":");let _=viewproof_parse::word(src,c,"Nat");let _=viewproof_parse::sym(src,c,",");let d=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,":");let _=viewproof_parse::word(src,c,"Domain");let _=viewproof_parse::sym(src,c,"]");let _=viewproof_parse::sym(src,c,"=>");
 let _=viewproof_parse::word(src,c,"Fn");let _=viewproof_parse::sym(src,c,"[");let _=viewproof_parse::word(src,c,"static");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"Many");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::sym(src,c,"(");let _=viewproof_parse::word(src,c,"View");let _=viewproof_parse::sym(src,c,"[");let _=viewproof_parse::use_id(src,c,r);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"U32");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,n);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,d);let _=viewproof_parse::sym(src,c,"]");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"U32");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"U32");let _=viewproof_parse::sym(src,c,")");let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"U32");let _=viewproof_parse::sym(src,c,"]");let _=viewproof_parse::sym(src,c,"!");let _=viewproof_parse::sym(src,c,"{");let _=viewproof_parse::word(src,c,"read");let _=viewproof_parse::use_id(src,c,r);let _=viewproof_parse::sym(src,c,"}");let _=viewproof_parse::word(src,c,"resources");let _=viewproof_parse::sym(src,c,"{");let _=viewproof_parse::word(src,c,"depth");let _=viewproof_parse::sym(src,c,":");let depth=viewproof_parse::num(src,c);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::word(src,c,"frame");let _=viewproof_parse::sym(src,c,":");let frame=viewproof_parse::num(src,c);let _=viewproof_parse::sym(src,c,"}");let _=viewproof_parse::sym(src,c,"=");let _=viewproof_parse::word(src,c,"fn");let _=viewproof_parse::sym(src,c,"(");let v=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,",");let i=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,",");let j=viewproof_parse::id(src,c);let _=viewproof_parse::sym(src,c,")");let _=viewproof_parse::sym(src,c,"=>");let _=viewproof_parse::word(src,c,"do");let _=viewproof_parse::sym(src,c,":");viewproof_parse::kind(src,c,6);viewproof_parse::kind(src,c,7);
 let _=viewproof_parse::word(src,c,"return");let call=viewproof_parse::id(src,c);
 let _=viewproof_parse::sym(src,c,"@");let _=viewproof_parse::sym(src,c,"[");let _=viewproof_parse::use_id(src,c,r);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,n);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,d);let _=viewproof_parse::sym(src,c,"]");let _=viewproof_parse::sym(src,c,"(");let loan=viewproof_parse::use_id(src,c,v);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,i);let _=viewproof_parse::sym(src,c,",");let _=viewproof_parse::use_id(src,c,j);let _=viewproof_parse::sym(src,c,")");if c.t.kind==6 {viewproof_parse::next(src,c);}viewproof_parse::kind(src,c,8);while !c.bad && c.t.kind==6 {viewproof_parse::next(src,c);}
 let callee_depth=bound(callee.source);
 if c.bad || c.t.kind!=0 || callee_depth<1 || (depth as i64)<callee_depth+1 || depth>128 || frame!=0 {return viewcall_core::Program {},1;}
 if viewproof_parse::same(src,r,n) || viewproof_parse::same(src,r,d) || viewproof_parse::same(src,n,d) || viewproof_parse::same(src,v,i) || viewproof_parse::same(src,v,j) || viewproof_parse::same(src,i,j) {return viewcall_core::Program {},1;}
 if src[call.start..call.end]!=callee.source[callee.name.start..callee.name.end] || (viewproof_parse::same(src,name,call) || viewproof_parse::same(src,v,call) || viewproof_parse::same(src,i,call) || viewproof_parse::same(src,j,call) || viewproof_parse::same(src,r,call) || viewproof_parse::same(src,n,call) || viewproof_parse::same(src,d,call)) {return viewcall_core::Program {},1;}
 return viewcall_core::Program {name:name,region:r,nat:n,domain:d,view:v,index:i,middle:j,call:call,loan_arg:loan},0;
}
// Parse exactly two top-level declarations; the split is derived from tokens,
// not accepted as a context identity or authority from the caller.
fn parse(src:u8[:])->viewcall_core::Program,i64 {
 if src.len>65536 {return viewcall_core::Program {},2;}
 var state=lexer::init(src);var depth:i64=0;var count:i64=0;var split:i64=0;
 while true {let t=lexer::next(src,state);if t.kind==9 {return viewcall_core::Program {},1;}if t.kind==0 {break;}if t.kind==7 {depth+=1;}else if t.kind==8 {depth-=1;}else if depth==0 && t.kind==1 && t.start>=0 && t.end<=src.len && src[t.start..t.end]=="let" {count+=1;if count==2 {split=t.start;}}}
 if count!=2 || split<=0 || split>=src.len {return viewcall_core::Program {},1;}
 var callee,status=viewproof_parse::parse(src[..split]);if status!=0 || !viewproof_verify::verify(src[..split],callee) {return viewcall_core::Program {},1;}
 var p,code=caller(src[split..],callee);if code!=0 {return viewcall_core::Program {},code;}return viewcall_core::Program {source:src,split:split,callee:callee,name:p.name,region:p.region,nat:p.nat,domain:p.domain,view:p.view,index:p.index,middle:p.middle,call:p.call,loan_arg:p.loan_arg},0;
}
