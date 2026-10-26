// Source-derived bounded typed declaration; no context/identity argument.
namespace viewproof_parse;
import lexer;
import validate;
import viewproof_core;
struct C {s:lexer::State=lexer::State {},t:lexer::Token=lexer::Token {},bad:bool=false}
fn next(src:u8[:],c:C&) {if !c.bad {c.t=lexer::next(src,c.s);if c.t.kind==9 {c.bad=true;}}}
fn take(src:u8[:],c:C&,kind:i64,txt:u8[:])->viewproof_core::Span {
 let t=c.t;if c.bad || t.kind!=kind || t.start<0 || t.end<=t.start || t.end>src.len || src[t.start..t.end]!=txt {c.bad=true;return viewproof_core::Span {};}
 next(src,c);return viewproof_core::Span {start:t.start,end:t.end};
}
fn sym(src:u8[:],c:C&,txt:u8[:])->viewproof_core::Span {return take(src,c,5,txt);}
fn word(src:u8[:],c:C&,txt:u8[:])->viewproof_core::Span {return take(src,c,1,txt);}
fn kind(src:u8[:],c:C&,k:i64) {if c.bad || c.t.kind!=k {c.bad=true;return;}next(src,c);}
fn id(src:u8[:],c:C&)->viewproof_core::Span {let t=c.t;if c.bad || t.kind!=1 || t.start<0 || t.end<=t.start || t.end>src.len || !validate::name_valid(src[t.start..t.end]) {c.bad=true;return viewproof_core::Span {};}
 next(src,c);return viewproof_core::Span {start:t.start,end:t.end};}
fn same(src:u8[:],a:viewproof_core::Span,b:viewproof_core::Span)->bool {return src[a.start..a.end]==src[b.start..b.end];}
fn use_id(src:u8[:],c:C&,a:viewproof_core::Span)->viewproof_core::Span {let b=id(src,c);if !c.bad && !same(src,a,b) {c.bad=true;}return b;}
fn num(src:u8[:],c:C&)->u32 {let t=c.t;if c.bad || t.kind!=2 || t.start<0 || t.end<=t.start || t.end>src.len {c.bad=true;return 0;}var n:u64=0;for x in src[t.start..t.end] {if x<'0' || x>'9' {c.bad=true;return 0;}let d=(x-'0') as u64;if n>(4294967295-d)/10 {c.bad=true;return 0;}n=n*10+d;}next(src,c);return n as u32;}

struct Term {id:i64=0,start:i64=0,end:i64=0}
fn term(src:u8[:],c:C&,v:viewproof_core::Span,i:viewproof_core::Span,j:viewproof_core::Span)->Term {
 let t=id(src,c);if c.bad{return Term {};}
 if same(src,t,i) {return Term {id:1,start:t.start,end:t.end};}
 if same(src,t,j) {return Term {id:2,start:t.start,end:t.end};}
 if same(src,t,v) {let _=sym(src,c,".");let length=word(src,c,"length");return Term {id:3,start:t.start,end:length.end};}
 c.bad=true;return Term {};
}
// Deterministic BFS over (term, has-strict-edge). Searches only actual source
// guards true on this conjunction's branch. No transitive table is stored.
fn path(gs:viewproof_core::Guard[:])->viewproof_core::Evidence,i64 {
 var seen:bool[6]=[false;6];var q:i64[6]=[0;6];var prev:i64[6]=[-1;6];var via:i64[6]=[-1;6];
 var n:i64=1;var head:i64=0;q[0]=0;seen[0]=true;var target:i64=-1;
 while head<n {let state=q[head];head+=1;if state==5 {target=state;break;}let l=state/2+1;let strict=state%2==1;
  for g,k in gs {if g.left!=l {continue;}let next=(g.right-1)*2+(if strict || g.strict {1} else {0});if next<0 || next>=6 || seen[next] {continue;}seen[next]=true;prev[next]=state;via[next]=k;n+=1;q[n-1]=next;}}
 if target<0 {return viewproof_core::Evidence {},5;}var reverse:i64[6]=[0;6];var count:i64=0;var x=target;
 while x!=0 {if x<0 || x>=6 || count>=6 || via[x]<0 {return viewproof_core::Evidence {},1;}reverse[count]=via[x]+1;count+=1;x=prev[x];}
 var e=viewproof_core::Evidence {path_len:count};for k in count {e.path[k]=reverse[count-k-1];}return e,0;
}
// Returns private status 1 for unsupported/malformed and 2 for source limit.
fn parse(src:u8[:])->viewproof_core::Program,i64 {
 if src.len>65536 {return viewproof_core::Program {},2;}var c=C {s:lexer::init(src)};next(src,c);while !c.bad && c.t.kind==6 {next(src,c);}
 let _=word(src,c,"let");let name=id(src,c);let _=sym(src,c,":");let _=word(src,c,"forall");let _=sym(src,c,"[");let r=id(src,c);let _=sym(src,c,":");let _=word(src,c,"Region");let _=sym(src,c,",");let n=id(src,c);let _=sym(src,c,":");let _=word(src,c,"Nat");let _=sym(src,c,",");let d=id(src,c);let _=sym(src,c,":");let _=word(src,c,"Domain");let _=sym(src,c,"]");let _=sym(src,c,"=>");
 let _=word(src,c,"Fn");let _=sym(src,c,"[");let _=word(src,c,"static");let _=sym(src,c,",");let _=word(src,c,"Many");let _=sym(src,c,",");let _=sym(src,c,"(");let _=word(src,c,"View");let _=sym(src,c,"[");let _=use_id(src,c,r);let _=sym(src,c,",");let _=word(src,c,"U32");let _=sym(src,c,",");let _=use_id(src,c,n);let _=sym(src,c,",");let _=use_id(src,c,d);let _=sym(src,c,"]");let _=sym(src,c,",");let _=word(src,c,"U32");let _=sym(src,c,",");let _=word(src,c,"U32");let _=sym(src,c,")");let _=sym(src,c,",");let _=word(src,c,"U32");let _=sym(src,c,"]");let _=sym(src,c,"!");let _=sym(src,c,"{");let _=word(src,c,"read");let _=use_id(src,c,r);let _=sym(src,c,"}");let _=word(src,c,"resources");let _=sym(src,c,"{");let _=word(src,c,"depth");let _=sym(src,c,":");let depth=num(src,c);let _=sym(src,c,",");let _=word(src,c,"frame");let _=sym(src,c,":");let frame=num(src,c);let _=sym(src,c,"}");let _=sym(src,c,"=");let _=word(src,c,"fn");let _=sym(src,c,"(");let v=id(src,c);let _=sym(src,c,",");let i=id(src,c);let _=sym(src,c,",");let j=id(src,c);let _=sym(src,c,")");let _=sym(src,c,"=>");let _=word(src,c,"do");let _=sym(src,c,":");kind(src,c,6);kind(src,c,7);
 let _=word(src,c,"if");var guards:viewproof_core::Guard[>..]=[];
 while !c.bad {
  let a=term(src,c,v,i,j);if c.bad {break;}var strict=false;
  if c.t.kind==5 && c.t.start>=0 && c.t.end<=src.len && src[c.t.start..c.t.end]=="<" {strict=true;next(src,c);}
  else {let _=sym(src,c,"<=");}
  let b=term(src,c,v,i,j);if c.bad {break;}if guards.len>=16 {return viewproof_core::Program {},2;}guards.push(viewproof_core::Guard {left:a.id,right:b.id,strict:strict,source:viewproof_core::Span {start:a.start,end:b.end}});
  if c.t.kind==5 && c.t.start>=0 && c.t.end<=src.len && src[c.t.start..c.t.end]=="&&" {next(src,c);continue;}break;
 }
 let _=sym(src,c,":");kind(src,c,6);kind(src,c,7);let _=word(src,c,"return");let rd=use_id(src,c,v);let _=sym(src,c,"[");let ri=use_id(src,c,i);let _=sym(src,c,"]");if c.t.kind==6 {next(src,c);}kind(src,c,8);let _=word(src,c,"else");let _=sym(src,c,":");kind(src,c,6);kind(src,c,7);let _=word(src,c,"return");let fallback=num(src,c);if c.t.kind==6 {next(src,c);}kind(src,c,8);kind(src,c,8);while !c.bad && c.t.kind==6 {next(src,c);}
 if c.bad || c.t.kind!=0 || depth<1 || depth>128 || frame!=0 {return viewproof_core::Program {},1;}
 if same(src,r,n) || same(src,r,d) || same(src,n,d) || same(src,v,i) || same(src,v,j) || same(src,i,j) {return viewproof_core::Program {},1;}
 var e,status=path(guards);if status!=0 {return viewproof_core::Program {},status;}e.access=rd;e.index=ri;e.view=v;
 return viewproof_core::Program {source:src,name:name,region:r,nat:n,domain:d,view:v,index:i,middle:j,guards:copy(guards),read:rd,fallback:fallback,evidence:e},0;
}
