// Source-owned mixed loop candidate; no general K1 SSA/loop proof or receipt.
namespace short_fact_build;
import mixed_core;
import mixed_fact_core;
struct Edge {left:i64=0,right:i64=0,guard_id:i64=0,truth:bool=false}
struct Env {aliases:i64[257]=[0;257],facts:i64[257]=[0;257],truth:bool[257]=[false;257],edges:Edge[64]=[Edge {};64],count:i64=0}
struct Route {status:i64=5,terminal:i64=0,count:i64=0,guards:i64[16]=[0;16],truth:bool[16]=[false;16]}
fn fresh()->Env {var e=Env {};for i in 257 {e.aliases[i]=i;}return e;}
fn ref(t:mixed_core::Tree&,id:i64,e:Env)->i64 {
 var x=id;var depth:i64=0;while x>0 && x<=t.nodes.len && t.nodes[x-1].tag==20 {x=t.nodes[x-1].a;depth+=1;if depth>128{return 0;}}
 if x<1 || x>t.nodes.len {return 0;}let n=t.nodes[x-1];if n.tag!=1 || n.a<1 || n.a>=257 {return 0;}return e.aliases[n.a];
}
fn literal(t:mixed_core::Tree&,id:i64)->u64,bool {
 if id<1 || id>t.nodes.len {return 0,false;}let n=t.nodes[id-1];if n.tag!=2 || n.start<0 || n.end<=n.start || n.end>t.source.len {return 0,false;}
 var v:u64=0;for c in t.source[n.start..n.end] {if c<'0' || c>'9' {return 0,false;}let d=(c-'0') as u64;if v>(4294967295-d)/10 {return 0,false;}v=v*10+d;}return v,true;
}
fn path(e:Env,slot:i64)->Route {
 if slot<1 || slot>=257 {return Route {};}
 var visited:bool[257]=[false;257];var queue:i64[257]=[0;257];var prev:i64[257]=[0;257];var via:i64[257]=[0;257];
 var head:i64=0;var count:i64=1;queue[0]=slot;visited[slot]=true;var found:i64=0;
 while head<count {let x=queue[head];head+=1;if e.facts[x]!=0 {found=x;break;}
  for i in e.count {let edge=e.edges[i];if edge.left==x && edge.right>0 && edge.right<257 && !visited[edge.right] {visited[edge.right]=true;prev[edge.right]=x;via[edge.right]=i+1;queue[count]=edge.right;count+=1;}}
 }
 if found==0 {return Route {};}
 var rev:i64[16]=[0;16];var len:i64=0;var cur=found;
 while cur!=slot {if len>=16 || via[cur]==0{return Route {status:2};}rev[len]=via[cur]-1;len+=1;cur=prev[cur];}
 var out=Route {status:0,terminal:found,count:len};for i in len {let edge=e.edges[rev[len-1-i]];out.guards[i]=edge.guard_id;out.truth[i]=edge.truth;}return out;
}
fn edge(e:Env&,a:i64,b:i64,guard_id:i64,truth:bool)->i64 {
 if a==0 || b==0 || a==b {return 0;}if e.count>=64 {return 2;}e.edges[e.count]=Edge {left:a,right:b,guard_id:guard_id,truth:truth};e.count+=1;return 0;
}
recursive fn value(t:mixed_core::Tree&,id:i64,e:Env,events:mixed_fact_core::Evidence[>..]&,depth:i64)->i64 {
 if depth>=128 || id<1 || id>t.nodes.len {return 2;}let n=t.nodes[id-1];
 if n.tag>=1 && n.tag<=4 {return 0;}
 if n.tag==20 {return value(t,n.a,e,events,depth+1);}
 if n.tag==19 || n.tag==21 || n.tag==22 || n.tag==23 || n.tag==24 || n.tag==25 || n.tag==26 || n.tag==27 || n.tag==28 {
  let a=value(t,n.a,e,events,depth+1);if a!=0{return a;}let b=value(t,n.b,e,events,depth+1);if b!=0{return b;}
  if n.tag==21 {
   let x,xok=literal(t,n.a);let y,yok=literal(t,n.b);
   if (xok && x==0) || (yok && y==0) || (xok && yok && x+y<=4294967295) {return 0;}
   var subject:i64=0;var reference:i64=0;var one:i64=0;
   if yok && y==1 {subject=ref(t,n.a,e);reference=n.a;one=n.b;}else if xok && x==1 {subject=ref(t,n.b,e);reference=n.b;one=n.a;}
   let route=path(e,subject);if route.status!=0{return route.status;}
   events.push(mixed_fact_core::Evidence {guard_id:e.facts[route.terminal],truth:e.truth[route.terminal],subject:subject,reference:reference,one:one,addition:id,count:route.count,guards:route.guards,edges:route.truth});
  }return 0;
 }
 return 1;
}
// A sequence is flattened without consuming the nesting budget; lexical
// branch and loop nesting remain independently bounded.
recursive fn walk(t:mixed_core::Tree&,id:i64,env:Env&,events:mixed_fact_core::Evidence[>..]&,depth:i64)->i64 {
 if depth>64 {return 2;}var todo:i64[2048]=[0;2048];var count:i64=1;todo[0]=id;
 while count>0 {count-=1;let item=todo[count];if item<1 || item>t.nodes.len{return 1;}let n=t.nodes[item-1];
  if n.tag==17 {if count+2>2048{return 2;}todo[count]=n.b;todo[count+1]=n.a;count+=2;}
  else {let st=statement(t,item,env,events,depth);if st!=0{return st;}}
 }return 0;
}
recursive fn statement(t:mixed_core::Tree&,id:i64,env:Env&,events:mixed_fact_core::Evidence[>..]&,depth:i64)->i64 {
 if depth>64 || id<1 || id>t.nodes.len{return 2;}let n=t.nodes[id-1];
 if n.tag==16 {
  if n.a<1 || n.a>t.nodes.len || n.b<1 || n.b>=257 {return 1;}
  let child=t.nodes[n.a-1];if child.tag==15 {let status=statement(t,n.a,env,events,depth+1);if status!=0{return status;}env.aliases[n.b]=n.b;return 0;}
  let status=value(t,n.a,env,events,0);if status!=0{return status;}let root=ref(t,n.a,env);env.aliases[n.b]=if root==0 {n.b} else {root};return 0;
 }
 if n.tag==15 {
  let lo=value(t,n.a,env,events,0);if lo!=0{return lo;}let hi=value(t,n.b,env,events,0);if hi!=0{return hi;}
  if n.c!=0 {let carry=t.nodes[n.c-1];let st=value(t,carry.a,env,events,0);if st!=0{return st;}}
  var inside=fresh();return walk(t,n.e,inside,events,depth+1);
 }
 if n.tag==14 {
  let st=value(t,n.a,env,events,0);if st!=0{return st;}
  var yes=env;var no=env;var cond=n.a;var steps:i64=0;
  while cond>0 && cond<=t.nodes.len && t.nodes[cond-1].tag==20 {steps+=1;if steps>128{return 2;}cond=t.nodes[cond-1].a;}
  if cond>0 && cond<=t.nodes.len && t.nodes[cond-1].tag==22 {
   let g=t.nodes[cond-1];let a=ref(t,g.a,env);let b=ref(t,g.b,env);
   if a>0 && yes.facts[a]==0 {yes.facts[a]=cond;yes.truth[a]=true;}
   let s=edge(yes,a,b,cond,true);if s!=0{return s;}let z=edge(no,b,a,cond,false);if z!=0{return z;}
  } else if cond>0 && cond<=t.nodes.len && t.nodes[cond-1].tag==28 {
   let g=t.nodes[cond-1];let a=ref(t,g.a,env);let bound,ok=literal(t,g.b);
   if ok && bound==4294967294 && a>0 && yes.facts[a]==0 {yes.facts[a]=cond;yes.truth[a]=true;}
  }
  let y=walk(t,n.b,yes,events,depth+1);if y!=0{return y;}if n.c!=0 {return walk(t,n.c,no,events,depth+1);}return 0;
 }
 if n.tag==13 || n.tag==9 || n.tag==10 {return value(t,n.a,env,events,0);}
 if n.tag==11 || n.tag==12 {return 0;}
 return 1;
}
fn build(t:mixed_core::Tree&)->mixed_fact_core::Result {
 if t.root<1 || t.root>t.nodes.len {return mixed_fact_core::Result {status:1};}let root=t.nodes[t.root-1];if root.tag!=18{return mixed_fact_core::Result {status:1};}
 var e=fresh();var events:mixed_fact_core::Evidence[>..]=[];let s=walk(t,root.a,e,events,0);if s!=0{return mixed_fact_core::Result {status:s};}return mixed_fact_core::Result {events:copy(events)};
}
