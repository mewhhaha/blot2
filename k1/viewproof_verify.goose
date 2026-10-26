// Independent source replay for the private formal View read contract. It
// establishes only a declaration obligation, not a valid call or live loan.
namespace viewproof_verify;
import lexer;
import validate;
import viewproof_core;
struct Cursor {lex:lexer::State=lexer::State {},tok:lexer::Token=lexer::Token {},ok:bool=true}
fn step(src:u8[:],c:Cursor&) {if c.ok {c.tok=lexer::next(src,c.lex);if c.tok.kind==9 {c.ok=false;}}}
fn exact(src:u8[:],c:Cursor&,kind:i64,value:u8[:]) {
 let t=c.tok;if !c.ok || t.kind!=kind || t.start<0 || t.end<=t.start || t.end>src.len || src[t.start..t.end]!=value {c.ok=false;return;}step(src,c);
}
fn punct(src:u8[:],c:Cursor&,s:u8[:]) {exact(src,c,5,s);}
fn kw(src:u8[:],c:Cursor&,s:u8[:]) {exact(src,c,1,s);}
fn layout(src:u8[:],c:Cursor&,kind:i64) {if !c.ok || c.tok.kind!=kind {c.ok=false;return;}step(src,c);}
fn saved(src:u8[:],c:Cursor&,s:viewproof_core::Span) {let t=c.tok;if !c.ok || t.kind!=1 || t.start!=s.start || t.end!=s.end || t.start<0 || t.end<=t.start || t.end>src.len || !validate::name_valid(src[t.start..t.end]) {c.ok=false;return;}step(src,c);}
fn matches(src:u8[:],c:Cursor&,s:viewproof_core::Span) {let t=c.tok;if !c.ok || s.start<0 || s.end<=s.start || s.end>src.len || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>src.len || src[t.start..t.end]!=src[s.start..s.end] {c.ok=false;return;}step(src,c);}
fn integer(src:u8[:],c:Cursor&)->u64 {let t=c.tok;if !c.ok || t.kind!=2 || t.start<0 || t.end<=t.start || t.end>src.len {c.ok=false;return 0;}var v:u64=0;for ch in src[t.start..t.end] {if ch<'0' || ch>'9' {c.ok=false;return 0;}let d=(ch-'0') as u64;if v>(4294967295-d)/10 {c.ok=false;return 0;}v=v*10+d;}step(src,c);return v;}
fn same(src:u8[:],a:viewproof_core::Span,b:viewproof_core::Span)->bool {return src[a.start..a.end]==src[b.start..b.end];}
struct Term {id:i64=0,start:i64=0,end:i64=0}
fn term(src:u8[:],c:Cursor&,p:viewproof_core::Program&)->Term {
 let t=c.tok;if !c.ok || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>src.len {c.ok=false;return Term {};}
 let val=src[t.start..t.end];var which:i64=0;if val==src[p.index.start..p.index.end] {which=1;}else if val==src[p.middle.start..p.middle.end] {which=2;}else if val==src[p.view.start..p.view.end] {which=3;}else {c.ok=false;return Term {};}
 step(src,c);var end=t.end;if which==3 {punct(src,c,".");end=c.tok.end;kw(src,c,"length");}return Term {id:which,start:t.start,end:end};
}
fn verify(src:u8[:],p:viewproof_core::Program&)->bool {
 if src.len>65536 || p.source[..]!=src {return false;}var c=Cursor {lex:lexer::init(src)};step(src,c);while c.ok && c.tok.kind==6 {step(src,c);}
 kw(src,c,"let");saved(src,c,p.name);punct(src,c,":");kw(src,c,"forall");punct(src,c,"[");saved(src,c,p.region);punct(src,c,":");kw(src,c,"Region");punct(src,c,",");saved(src,c,p.nat);punct(src,c,":");kw(src,c,"Nat");punct(src,c,",");saved(src,c,p.domain);punct(src,c,":");kw(src,c,"Domain");punct(src,c,"]");punct(src,c,"=>");
 kw(src,c,"Fn");punct(src,c,"[");kw(src,c,"static");punct(src,c,",");kw(src,c,"Many");punct(src,c,",");punct(src,c,"(");kw(src,c,"View");punct(src,c,"[");matches(src,c,p.region);punct(src,c,",");kw(src,c,"U32");punct(src,c,",");matches(src,c,p.nat);punct(src,c,",");matches(src,c,p.domain);punct(src,c,"]");punct(src,c,",");kw(src,c,"U32");punct(src,c,",");kw(src,c,"U32");punct(src,c,")");punct(src,c,",");kw(src,c,"U32");punct(src,c,"]");punct(src,c,"!");punct(src,c,"{");kw(src,c,"read");matches(src,c,p.region);punct(src,c,"}");kw(src,c,"resources");punct(src,c,"{");kw(src,c,"depth");punct(src,c,":");let depth=integer(src,c);punct(src,c,",");kw(src,c,"frame");punct(src,c,":");let frame=integer(src,c);punct(src,c,"}");punct(src,c,"=");kw(src,c,"fn");punct(src,c,"(");saved(src,c,p.view);punct(src,c,",");saved(src,c,p.index);punct(src,c,",");saved(src,c,p.middle);punct(src,c,")");punct(src,c,"=>");kw(src,c,"do");punct(src,c,":");layout(src,c,6);layout(src,c,7);
 kw(src,c,"if");var count:i64=0;
 while c.ok {
  if count>=16 || count>=p.guards.len {return false;}
  let a=term(src,c,p);if !c.ok {return false;}var strict=false;
  if c.tok.kind==5 && c.tok.start>=0 && c.tok.end<=src.len && src[c.tok.start..c.tok.end]=="<" {strict=true;step(src,c);}else {punct(src,c,"<=");}
  let b=term(src,c,p);let g=viewproof_core::Guard {left:a.id,right:b.id,strict:strict,source:viewproof_core::Span {start:a.start,end:b.end}};
  if !c.ok || !viewproof_core::guard_eq(g,p.guards[count]) {return false;}count+=1;
  if c.tok.kind==5 && c.tok.start>=0 && c.tok.end<=src.len && src[c.tok.start..c.tok.end]=="&&" {step(src,c);continue;}break;
 }
 if count!=p.guards.len {return false;}
 punct(src,c,":");layout(src,c,6);layout(src,c,7);kw(src,c,"return");saved(src,c,p.read);if c.ok && !same(src,p.read,p.view) {return false;}punct(src,c,"[");let read_index=viewproof_core::Span {start:c.tok.start,end:c.tok.end};matches(src,c,p.index);punct(src,c,"]");if c.tok.kind==6 {step(src,c);}layout(src,c,8);kw(src,c,"else");punct(src,c,":");layout(src,c,6);layout(src,c,7);kw(src,c,"return");let fallback=integer(src,c);if c.tok.kind==6 {step(src,c);}layout(src,c,8);layout(src,c,8);while c.ok && c.tok.kind==6 {step(src,c);}
 if !c.ok || c.tok.kind!=0 || depth<1 || depth>128 || frame!=0 || fallback!=p.fallback {return false;}
 if same(src,p.region,p.nat) || same(src,p.region,p.domain) || same(src,p.nat,p.domain) || same(src,p.view,p.index) || same(src,p.view,p.middle) || same(src,p.index,p.middle) {return false;}
 let e=p.evidence;if !viewproof_core::span_eq(e.access,p.read) || !viewproof_core::span_eq(e.index,read_index) || !viewproof_core::span_eq(e.view,p.view) || e.path_len<1 || e.path_len>6 {return false;}
 var current:i64=1;var strict=false;
 for k in 6 {if k>=e.path_len {if e.path[k]!=0 {return false;}continue;}let id=e.path[k];if id<1 || id>p.guards.len {return false;}let g=p.guards[id-1];if g.left!=current {return false;}current=g.right;strict=strict || g.strict;}
 return current==3 && strict;
}
