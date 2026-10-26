// Bounded source-level branch-aware builder use. No runtime loan, ABI,
// dynamic SSA generation, invariant proof or execution authority.
namespace i08_flow_build;
import i08_core;
import i08_bound_shape;
import i08_flow_completion;
import i08_flow_core;
struct Reach {status:i64=0,falls:bool=true}
fn is(t:i08_core::Tree&,id:i64,tag:i64)->bool {return id>0 && id<=t.nodes.len && t.nodes[id-1].tag==tag;}
fn ref(t:i08_core::Tree&,id:i64,b:i64)->bool {return is(t,id,1) && t.nodes[id-1].a==b;}
recursive fn numeric(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=64 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag==2 {return true;}if n.tag==1 {return n.a==index || n.a==3 || n.a==4;}
 if n.tag==20 {return numeric(t,n.a,index,depth+1);}return false;
}
// 0 unknown, 1 literal false, 2 literal true, -1 unsupported.
recursive fn condition(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->i64 {
 if depth>=64 || id<1 || id>t.nodes.len{return -1;}let n=t.nodes[id-1];
 if n.tag==3 {return 2;}if n.tag==4 {return 1;}if n.tag==20 {return condition(t,n.a,index,depth+1);}
 if n.tag==22 && numeric(t,n.a,index,depth+1) && numeric(t,n.b,index,depth+1) {return 0;}return -1;
}
recursive fn row_value(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag==1 {return n.a==7;}if n.tag==29{return true;}if n.tag==20{return row_value(t,n.a,index,depth+1);}
 if n.tag==21 || n.tag==25 {return row_value(t,n.a,index,depth+1) && row_value(t,n.b,index,depth+1);}
 if n.tag==23 && n.b>=1 && n.b<=4 && is(t,n.a,24) {let read=t.nodes[n.a-1];return ref(t,read.a,6) && ref(t,read.b,index);}return false;
}
// Each reachable path retains the current builder until exactly one next;
// dead arms still require the same valid, length-preserving transfer shape.
recursive fn body(t:i08_core::Tree&,id:i64,index:i64,carry_id:i64,target:i64,live:bool,edges:i08_flow_core::Edge[>..]&,depth:i64)->Reach {
 if depth>64 || id<1 || id>t.nodes.len{return Reach {status:1};}let n=t.nodes[id-1];
 if n.tag==17 {let a=body(t,n.a,index,carry_id,target,live,edges,depth+1);if a.status!=0{return a;}if !a.falls{return Reach {status:1};}return body(t,n.b,index,carry_id,target,live,edges,depth+1);}
 if n.tag==14 {
  let v=condition(t,n.a,index,0);if v<0{return Reach {status:1};}
  let y=body(t,n.b,index,carry_id,target,live && v!=1,edges,depth+1);if y.status!=0{return y;}
  var z=Reach {};if n.c!=0 {z=body(t,n.c,index,carry_id,target,live && v!=2,edges,depth+1);if z.status!=0{return z;}}
  return Reach {falls:if v==2 {y.falls} else if v==1 {z.falls} else {y.falls || z.falls}};
 }
 if n.tag==9 {
  if n.target!=target || n.b!=1 || !is(t,n.a,27) {return Reach {status:1};}let app=t.nodes[n.a-1];
  if !ref(t,app.a,carry_id) || !is(t,app.b,26) {return Reach {status:1};}let row=t.nodes[app.b-1];
  if !row_value(t,row.a,index,0) || !row_value(t,row.b,index,0) {return Reach {status:1};}
  if live {if edges.len>=256{return Reach {status:2};}edges.push(i08_flow_core::Edge {next_node:id,append:n.a,row:app.b});}return Reach {falls:false};
 }
 return Reach {status:1};
}
fn build(t:i08_core::Tree&,source:u8[:])->i08_flow_core::Result {
 if !i08_bound_shape::verify(t,source) || i08_flow_completion::check(t,source)!=0 || t.bindings.len!=11 || !is(t,t.root,18) {return i08_flow_core::Result {status:1};}
 let root=t.nodes[t.root-1];if root.b!=3 || !is(t,root.a,17) {return i08_flow_core::Result {status:1};}let seq=t.nodes[root.a-1];
 if !is(t,seq.a,16) || !is(t,seq.b,13) {return i08_flow_core::Result {status:1};}let bound=t.nodes[seq.a-1];let ret=t.nodes[seq.b-1];
 if !is(t,bound.a,15) || !is(t,ret.a,28) || ret.target!=root.target || !ref(t,t.nodes[ret.a-1].a,bound.b) {return i08_flow_core::Result {status:1};}
 let cycle=t.nodes[bound.a-1];if cycle.g!=1 || !is(t,cycle.a,2) || !ref(t,cycle.b,3) || !is(t,cycle.c,6) || !is(t,cycle.d,8) ||
    cycle.f<1 || cycle.f>t.bindings.len || t.bindings[cycle.f-1].kind!=2 || bound.b<1 || bound.b>t.bindings.len || t.bindings[bound.b-1].kind!=4 {return i08_flow_core::Result {status:1};}
 let zero=t.nodes[cycle.a-1];if zero.start<0 || zero.end<=zero.start || zero.end>source.len || source[zero.start..zero.end]!="0" {return i08_flow_core::Result {status:1};}
 let carry=t.nodes[cycle.c-1];let inv=t.nodes[cycle.d-1];
 if carry.b<1 || carry.b>t.bindings.len || t.bindings[carry.b-1].kind!=3 || !ref(t,carry.a,8) || inv.c!=1 || !is(t,inv.a,7) || !ref(t,inv.b,cycle.f) {return i08_flow_core::Result {status:1};}
 let obs=t.nodes[inv.a-1];if obs.b!=1 || !ref(t,obs.a,carry.b) {return i08_flow_core::Result {status:1};}
 var edges:i08_flow_core::Edge[>..]=[];let result=body(t,cycle.e,cycle.f,carry.b,cycle.target,true,edges,0);
 if result.status!=0 || result.falls || edges.len==0 {return i08_flow_core::Result {status:1};}
 return i08_flow_core::Result {plan:i08_flow_core::Plan {initial:8,view:6,nat:3,capacity:4,loop_id:bound.a,index:cycle.f,carry_id:carry.b,result:bound.b,carry_node:cycle.c,invariant_id:cycle.d,freeze:ret.a,return_node:seq.b,root:t.root,edges:copy(edges)}};
}
