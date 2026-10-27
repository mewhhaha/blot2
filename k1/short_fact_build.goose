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
// A recorded source guard provides an unsigned upper bound for its exact
// terminal alias. Variable-to-variable strict guards prove at least non-MAX.
fn guard_limit(t:mixed_core::Tree&,id:i64,truth:bool,subject:i64,e:Env)->u64,bool {
 if id<1 || id>t.nodes.len {return 0,false;}let n=t.nodes[id-1];
 if n.tag==22 && truth && ref(t,n.a,e)==subject {
  let v,ok=literal(t,n.b);if ok && v>0 {return v-1,true;}return 4294967294,true;
 }
 if n.tag==22 && !truth && ref(t,n.b,e)==subject {let v,ok=literal(t,n.a);if ok {return v,true;}}
 if n.tag==28 && truth && ref(t,n.a,e)==subject {let v,ok=literal(t,n.b);if ok {return v,true;}}
 if n.tag==28 && !truth && ref(t,n.b,e)==subject {let v,ok=literal(t,n.a);if ok && v>0 {return v-1,true;}}
 return 0,false;
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
recursive fn numeric(t:mixed_core::Tree&,id:i64,e:Env,events:mixed_fact_core::Evidence[>..]&,depth:i64)->i64 {
 if depth>=128 || id<1 || id>t.nodes.len {return 2;}let n=t.nodes[id-1];
 if n.tag>=1 && n.tag<=4 {return 0;}
 if n.tag==20 {return numeric(t,n.a,e,events,depth+1);}
 if n.tag==19 || n.tag==21 || n.tag==22 || n.tag==25 || n.tag==26 || n.tag==27 || n.tag==28 {
  let a=numeric(t,n.a,e,events,depth+1);if a!=0{return a;}let b=numeric(t,n.b,e,events,depth+1);if b!=0{return b;}
  if n.tag==21 {
   let x,xok=literal(t,n.a);let y,yok=literal(t,n.b);
   if (xok && x==0) || (yok && y==0) || (xok && yok && x+y<=4294967295) {return 0;}
   var subject:i64=0;var reference:i64=0;var one:i64=0;
   var offset:u64=0;
   if yok && y>0 {subject=ref(t,n.a,e);reference=n.a;one=n.b;offset=y;}else if xok && x>0 {subject=ref(t,n.b,e);reference=n.b;one=n.a;offset=x;}
   let route=path(e,subject);if route.status!=0{return route.status;}
   let bound,ok=guard_limit(t,e.facts[route.terminal],e.truth[route.terminal],route.terminal,e);if !ok || bound+offset>4294967295{return 5;}
   events.push(mixed_fact_core::Evidence {guard_id:e.facts[route.terminal],truth:e.truth[route.terminal],subject:subject,reference:reference,one:one,addition:id,count:route.count,guards:route.guards,edges:route.truth});
  }return 0;
 }
 return 1;
}
fn value(t:mixed_core::Tree&,id:i64,e:Env,events:mixed_fact_core::Evidence[>..]&,depth:i64)->i64 {
 var cur=id;var ndepth=depth;
 loop {if ndepth>=128 || cur<1 || cur>t.nodes.len {return 2;}let n=t.nodes[cur-1];
  if n.tag==20 {cur=n.a;ndepth+=1;continue;}
  if n.tag==23 || n.tag==24 {let c=condition(t,cur,e,events,ndepth+1);return c.status;}
  return numeric(t,cur,e,events,ndepth);
 }
}
// Two predecessor states retain only exact facts common to all live paths.
struct Cond {status:i64=0,yes:Env=Env {},no:Env=Env {},yes_live:bool=false,no_live:bool=false}
fn same_edge(a:Edge,b:Edge)->bool {return a.left==b.left && a.right==b.right && a.guard_id==b.guard_id && a.truth==b.truth;}
fn intersect(a:Env,b:Env)->Env {
 var out=a;for i in 257 {if a.aliases[i]!=b.aliases[i] {out.aliases[i]=i;}if a.facts[i]!=b.facts[i] || a.truth[i]!=b.truth[i] {out.facts[i]=0;out.truth[i]=false;}}
 out.count=0;for i in a.count {for j in b.count {if same_edge(a.edges[i],b.edges[j]) {out.edges[out.count]=a.edges[i];out.count+=1;break;}}}return out;
}
// Explicit heap-backed stack keeps long left-associated Bool chains bounded.
struct CondFrame {id:i64=0,phase:i64=0,env:Env=Env {},left:Cond=Cond {}}
fn condition(t:mixed_core::Tree&,id:i64,env:Env,events:mixed_fact_core::Evidence[>..]&,depth:i64)->Cond {
 if depth>=128 {return Cond {status:2};}
 var stack:CondFrame[>..]=[CondFrame {id:id,env:env}];var done=Cond {};var have=false;var steps:i64=0;
 while stack.len>0 {
  if steps>=32768 {return Cond {status:2};}steps+=1;
  if stack.len>128 {return Cond {status:2};}let pos=stack.len-1;let f=stack[pos];
  if f.id<1 || f.id>t.nodes.len {return Cond {status:1};}let n=t.nodes[f.id-1];
  if f.phase==0 {
   if n.tag==20 {stack[pos].id=n.a;continue;}
   if n.tag==23 || n.tag==24 {stack[pos].phase=1;stack.push(CondFrame {id:n.a,env:f.env});continue;}
   if n.tag==3 {done=Cond {yes:f.env,yes_live:true};}
   else if n.tag==4 {done=Cond {no:f.env,no_live:true};}
   else if n.tag==1 {done=Cond {yes:f.env,no:f.env,yes_live:true,no_live:true};}
   else if n.tag==22 || n.tag==28 {
    let status=numeric(t,f.id,f.env,events,0);if status!=0{return Cond {status:status};}
    var yes=f.env;var no=f.env;let a=ref(t,n.a,f.env);let b=ref(t,n.b,f.env);
    if n.tag==22 {
     if a>0 && yes.facts[a]==0 {yes.facts[a]=f.id;yes.truth[a]=true;}
     let x=edge(yes,a,b,f.id,true);if x!=0{return Cond {status:x};}let y=edge(no,b,a,f.id,false);if y!=0{return Cond {status:y};}
     let bound,ok=literal(t,n.a);if ok && bound<4294967295 && b>0 && no.facts[b]==0 {no.facts[b]=f.id;no.truth[b]=false;}
    } else {
     let bound,ok=literal(t,n.b);if ok && bound<4294967295 && a>0 && yes.facts[a]==0 {yes.facts[a]=f.id;yes.truth[a]=true;}
     let floor,valid=literal(t,n.a);if valid && floor>0 && b>0 && no.facts[b]==0 {no.facts[b]=f.id;no.truth[b]=false;}
    }done=Cond {yes:yes,no:no,yes_live:true,no_live:true};
   } else {return Cond {status:1};}
   stack.pop();have=true;continue;
  }
  if !have {return Cond {status:1};}
  if f.phase==1 {
   let left=done;if left.status!=0{return left;}stack[pos].left=left;have=false;
   if n.tag==23 && !left.yes_live {done=Cond {no:left.no,no_live:left.no_live};stack.pop();have=true;continue;}
   if n.tag==24 && !left.no_live {done=Cond {yes:left.yes,yes_live:left.yes_live};stack.pop();have=true;continue;}
   stack[pos].phase=2;stack.push(CondFrame {id:n.b,env:if n.tag==23 {left.yes} else {left.no}});continue;
  }
  if f.phase!=2 {return Cond {status:1};}let left=f.left;let right=done;if right.status!=0{return right;}
  if n.tag==23 {var no=left.no;var live=left.no_live;if right.no_live {if live {no=intersect(no,right.no);}else {no=right.no;live=true;}}done=Cond {yes:right.yes,yes_live:right.yes_live,no:no,no_live:live};}
  else if n.tag==24 {var yes=left.yes;var live=left.yes_live;if right.yes_live {if live {yes=intersect(yes,right.yes);}else {yes=right.yes;live=true;}}done=Cond {yes:yes,yes_live:live,no:right.no,no_live:right.no_live};}
  else {return Cond {status:1};}stack.pop();have=true;
 }
 return if have {done} else {Cond {status:1}};
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
  let c=condition(t,n.a,env,events,0);if c.status!=0{return c.status;}
  if c.yes_live {var yes=c.yes;let y=walk(t,n.b,yes,events,depth+1);if y!=0{return y;}}
  if n.c!=0 && c.no_live {var no=c.no;return walk(t,n.c,no,events,depth+1);}return 0;
 }
 if n.tag==13 || n.tag==9 || n.tag==10 {return value(t,n.a,env,events,0);}
 if n.tag==11 || n.tag==12 {return 0;}
 return 1;
}
fn build(t:mixed_core::Tree&)->mixed_fact_core::Result {
 if t.root<1 || t.root>t.nodes.len {return mixed_fact_core::Result {status:1};}let root=t.nodes[t.root-1];if root.tag!=18{return mixed_fact_core::Result {status:1};}
 var e=fresh();var events:mixed_fact_core::Evidence[>..]=[];let s=walk(t,root.a,e,events,0);if s!=0{return mixed_fact_core::Result {status:s};}return mixed_fact_core::Result {events:copy(events)};
}
