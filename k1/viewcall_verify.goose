// Independently rechecks source linkage and the caller's typed formal loan.
// This proves forwarding, not the external caller's ability to supply a loan.
namespace viewcall_verify;
import lexer;
import viewproof_core;
import viewproof_verify;
import viewcall_core;
fn bound(src:u8[:])->i64 {
 var state=lexer::init(src);var found:i64=0;var result:i64=-1;
 while true {let t=lexer::next(src,state);if t.kind==9 {return -1;}if t.kind==0 {break;}
  if t.kind==1 && t.start>=0 && t.end<=src.len && src[t.start..t.end]=="resources" {
   found+=1;let a=lexer::next(src,state);let b=lexer::next(src,state);let c=lexer::next(src,state);let d=lexer::next(src,state);
   if a.kind!=5 || src[a.start..a.end]!="{" || b.kind!=1 || src[b.start..b.end]!="depth" || c.kind!=5 || src[c.start..c.end]!=":" || d.kind!=2 {return -1;}
   var n:i64=0;for digit in src[d.start..d.end] {if digit<'0' || digit>'9' || n>128 {return -1;}n=n*10+(digit-'0') as i64;}result=n;
  }
 }
 if found!=1 || result<1 || result>127 {return -1;}return result;
}
fn verify_caller(src:u8[:],p:viewcall_core::Program&)->bool {
 if src.len>65536 || false {return false;}var c=viewproof_verify::Cursor {lex:lexer::init(src)};viewproof_verify::step(src,c);while c.ok && c.tok.kind==6 {viewproof_verify::step(src,c);}
 viewproof_verify::kw(src,c,"let");viewproof_verify::saved(src,c,p.name);viewproof_verify::punct(src,c,":");viewproof_verify::kw(src,c,"forall");viewproof_verify::punct(src,c,"[");viewproof_verify::saved(src,c,p.region);viewproof_verify::punct(src,c,":");viewproof_verify::kw(src,c,"Region");viewproof_verify::punct(src,c,",");viewproof_verify::saved(src,c,p.nat);viewproof_verify::punct(src,c,":");viewproof_verify::kw(src,c,"Nat");viewproof_verify::punct(src,c,",");viewproof_verify::saved(src,c,p.domain);viewproof_verify::punct(src,c,":");viewproof_verify::kw(src,c,"Domain");viewproof_verify::punct(src,c,"]");viewproof_verify::punct(src,c,"=>");
 viewproof_verify::kw(src,c,"Fn");viewproof_verify::punct(src,c,"[");viewproof_verify::kw(src,c,"static");viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"Many");viewproof_verify::punct(src,c,",");viewproof_verify::punct(src,c,"(");viewproof_verify::kw(src,c,"View");viewproof_verify::punct(src,c,"[");viewproof_verify::matches(src,c,p.region);viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"U32");viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.nat);viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.domain);viewproof_verify::punct(src,c,"]");viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"U32");viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"U32");viewproof_verify::punct(src,c,")");viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"U32");viewproof_verify::punct(src,c,"]");viewproof_verify::punct(src,c,"!");viewproof_verify::punct(src,c,"{");viewproof_verify::kw(src,c,"read");viewproof_verify::matches(src,c,p.region);viewproof_verify::punct(src,c,"}");viewproof_verify::kw(src,c,"resources");viewproof_verify::punct(src,c,"{");viewproof_verify::kw(src,c,"depth");viewproof_verify::punct(src,c,":");let depth=viewproof_verify::integer(src,c);viewproof_verify::punct(src,c,",");viewproof_verify::kw(src,c,"frame");viewproof_verify::punct(src,c,":");let frame=viewproof_verify::integer(src,c);viewproof_verify::punct(src,c,"}");viewproof_verify::punct(src,c,"=");viewproof_verify::kw(src,c,"fn");viewproof_verify::punct(src,c,"(");viewproof_verify::saved(src,c,p.view);viewproof_verify::punct(src,c,",");viewproof_verify::saved(src,c,p.index);viewproof_verify::punct(src,c,",");viewproof_verify::saved(src,c,p.middle);viewproof_verify::punct(src,c,")");viewproof_verify::punct(src,c,"=>");viewproof_verify::kw(src,c,"do");viewproof_verify::punct(src,c,":");viewproof_verify::layout(src,c,6);viewproof_verify::layout(src,c,7);
 viewproof_verify::kw(src,c,"return");viewproof_verify::saved(src,c,p.call);
 viewproof_verify::punct(src,c,"@");viewproof_verify::punct(src,c,"[");viewproof_verify::matches(src,c,p.region);viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.nat);viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.domain);viewproof_verify::punct(src,c,"]");viewproof_verify::punct(src,c,"(");viewproof_verify::saved(src,c,p.loan_arg);if c.ok && !viewproof_verify::same(src,p.loan_arg,p.view) {return false;}viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.index);viewproof_verify::punct(src,c,",");viewproof_verify::matches(src,c,p.middle);viewproof_verify::punct(src,c,")");if c.tok.kind==6 {viewproof_verify::step(src,c);}viewproof_verify::layout(src,c,8);while c.ok && c.tok.kind==6 {viewproof_verify::step(src,c);}
 let d=bound(p.callee.source);
 if !c.ok || c.tok.kind!=0 || d<1 || (depth as i64)<d+1 || depth>128 || frame!=0 {return false;}
 if viewproof_verify::same(src,p.region,p.nat) || viewproof_verify::same(src,p.region,p.domain) || viewproof_verify::same(src,p.nat,p.domain) || viewproof_verify::same(src,p.view,p.index) || viewproof_verify::same(src,p.view,p.middle) || viewproof_verify::same(src,p.index,p.middle) {return false;}
 if src[p.call.start..p.call.end]!=p.callee.source[p.callee.name.start..p.callee.name.end] || (viewproof_verify::same(src,p.name,p.call) || viewproof_verify::same(src,p.view,p.call) || viewproof_verify::same(src,p.index,p.call) || viewproof_verify::same(src,p.middle,p.call) || viewproof_verify::same(src,p.region,p.call) || viewproof_verify::same(src,p.nat,p.call) || viewproof_verify::same(src,p.domain,p.call)) {return false;}return true;
}
fn verify(src:u8[:],p:viewcall_core::Program&)->bool {
 if src.len>65536 || p.source[..]!=src || p.split<=0 || p.split>=src.len {return false;}
 if !viewproof_verify::verify(src[..p.split],p.callee) {return false;}return verify_caller(src[p.split..],p);
}
