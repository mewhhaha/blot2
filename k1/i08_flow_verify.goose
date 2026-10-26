// Independent source-bound validation of a bounded branch/transfer plan.
// This is not a complete ownership checker, intrinsic proof or live authority.
namespace i08_flow_verify;
import i08_core;
import i08_bound_shape;
import i08_flow_completion;
import i08_flow_core;
struct Summary {ok:bool=true,live:bool=true,dead:bool=true,falls:bool=true}
struct Visit {id:i64=0,live:bool=false}
fn has(t:i08_core::Tree&,id:i64,tag:i64)->bool {return id>=1 && id<=t.nodes.len && t.nodes[id-1].tag==tag;}
fn use(t:i08_core::Tree&,id:i64,b:i64)->bool{return has(t,id,1) && t.nodes[id-1].a==b;}
recursive fn number(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=64 || id<1 || id>t.nodes.len{return false;}let x=t.nodes[id-1];
 if x.tag==2{return true;}if x.tag==1{return x.a==index || x.a==3 || x.a==4;}
 return x.tag==20 && number(t,x.a,index,depth+1);
}
recursive fn truth(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->i64 {
 if depth>=64 || id<1 || id>t.nodes.len{return -1;}let x=t.nodes[id-1];
 if x.tag==3{return 2;}if x.tag==4{return 1;}if x.tag==20{return truth(t,x.a,index,depth+1);}
 if x.tag==22 && number(t,x.a,index,depth+1) && number(t,x.b,index,depth+1){return 0;}return -1;
}
recursive fn term(t:i08_core::Tree&,id:i64,index:i64,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let x=t.nodes[id-1];
 if x.tag==29{return true;}if x.tag==1{return x.a==7;}
 if x.tag==20{return term(t,x.a,index,depth+1);}
 if x.tag==21 || x.tag==25{return term(t,x.a,index,depth+1) && term(t,x.b,index,depth+1);}
 if x.tag!=23 || x.b<1 || x.b>4 || !has(t,x.a,24){return false;}let read=t.nodes[x.a-1];return use(t,read.a,6) && use(t,read.b,index);
}
recursive fn analyze(t:i08_core::Tree&,id:i64,index:i64,carry_id:i64,target:i64,depth:i64)->Summary {
 if depth>64 || id<1 || id>t.nodes.len{return Summary {ok:false};}let x=t.nodes[id-1];
 if x.tag==17 {let a=analyze(t,x.a,index,carry_id,target,depth+1);let b=analyze(t,x.b,index,carry_id,target,depth+1);
  if !a.ok || !b.ok || !a.falls{return Summary {ok:false};}return Summary {live:a.live && b.live,dead:a.dead && b.dead,falls:a.falls && b.falls};}
 if x.tag==14 {let c=truth(t,x.a,index,0);if c<0{return Summary {ok:false};}let y=analyze(t,x.b,index,carry_id,target,depth+1);var z=Summary {};
  if x.c!=0 {z=analyze(t,x.c,index,carry_id,target,depth+1);}if !y.ok || !z.ok{return Summary {ok:false};}
  return Summary {live:if c==2 {y.live && z.dead} else if c==1 {y.dead && z.live} else {y.live && z.live},
   dead:y.dead && z.dead,falls:if c==2 {y.falls} else if c==1 {z.falls} else {y.falls || z.falls}};
 }
 if x.tag==9 {
  if x.target!=target || x.b!=1 || !has(t,x.a,27){return Summary {ok:false};}let append=t.nodes[x.a-1];
  if !use(t,append.a,carry_id) || !has(t,append.b,26){return Summary {ok:false};}let row=t.nodes[append.b-1];
  if !term(t,row.a,index,0) || !term(t,row.b,index,0){return Summary {ok:false};}return Summary {falls:false};
 }
 return Summary {ok:false};
}
fn verify(t:i08_core::Tree&,source:u8[:],p:i08_flow_core::Plan&)->bool {
 if !i08_bound_shape::verify(t,source) || i08_flow_completion::check(t,source)!=0 || t.bindings.len!=11 || p.initial!=8 || p.view!=6 || p.nat!=3 || p.capacity!=4 ||
    p.root!=t.root || !has(t,p.root,18) || !has(t,p.loop_id,15) || !has(t,p.carry_node,6) || !has(t,p.invariant_id,8) || !has(t,p.freeze,28) || !has(t,p.return_node,13) || p.edges.len<1 || p.edges.len>256 {return false;}
 let root=t.nodes[p.root-1];if root.b!=3 || !has(t,root.a,17){return false;}let seq=t.nodes[root.a-1];
 if !has(t,seq.a,16) || seq.b!=p.return_node{return false;}let binding=t.nodes[seq.a-1];if binding.a!=p.loop_id || binding.b!=p.result || p.result<1 || p.result>t.bindings.len || t.bindings[p.result-1].kind!=4{return false;}
 let ret=t.nodes[p.return_node-1];if ret.target!=root.target || ret.a!=p.freeze || !use(t,t.nodes[p.freeze-1].a,p.result){return false;}
 let cycle=t.nodes[p.loop_id-1];if cycle.g!=1 || cycle.f!=p.index || cycle.c!=p.carry_node || cycle.d!=p.invariant_id || p.index<1 || p.index>t.bindings.len || t.bindings[p.index-1].kind!=2 || !use(t,cycle.b,p.nat) || !has(t,cycle.a,2){return false;}
 let zero=t.nodes[cycle.a-1];if zero.start<0 || zero.end<=zero.start || zero.end>source.len || source[zero.start..zero.end]!="0"{return false;}
 let carry=t.nodes[p.carry_node-1];if carry.b!=p.carry_id || p.carry_id<1 || p.carry_id>t.bindings.len || t.bindings[p.carry_id-1].kind!=3 || !use(t,carry.a,p.initial){return false;}
 let inv=t.nodes[p.invariant_id-1];if inv.c!=1 || !use(t,inv.b,p.index) || !has(t,inv.a,7){return false;}let obs=t.nodes[inv.a-1];if obs.b!=1 || !use(t,obs.a,p.carry_id){return false;}
 let summary=analyze(t,cycle.e,p.index,p.carry_id,cycle.target,0);if !summary.ok || !summary.live || summary.falls{return false;}
 var stack:Visit[2048]=[Visit {};2048];var count:i64=1;stack[0]=Visit {id:cycle.e,live:true};var at:i64=0;
 while count>0 {count-=1;let q=stack[count];if q.id<1 || q.id>t.nodes.len{return false;}let x=t.nodes[q.id-1];
  if x.tag==17 {if count+2>2048{return false;}stack[count]=Visit {id:x.b,live:q.live};stack[count+1]=Visit {id:x.a,live:q.live};count+=2;}
  else if x.tag==14 {let c=truth(t,x.a,p.index,0);if c<0 || count+2>2048{return false;}
   if x.c!=0 {stack[count]=Visit {id:x.c,live:q.live && c!=2};count+=1;}
   stack[count]=Visit {id:x.b,live:q.live && c!=1};count+=1;
  } else if x.tag==9 && q.live {
   if at>=p.edges.len{return false;}let e=p.edges[at];if e.next_node!=q.id || e.append!=x.a || !has(t,x.a,27) || e.row!=t.nodes[x.a-1].b{return false;}at+=1;
  }
 }
 return at==p.edges.len;
}
