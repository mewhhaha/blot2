// Independent source-bound verifier for a bounded mixed-loop proof fixture.
// It reconstructs active value identities and branch edges without using the
// producer's graph or route search. Each loop body starts with fresh facts and
// aliases; no body fact crosses a backedge or leaves its lexical loop. This is
// not general K1 SSA, invariant checking, a portable certificate or C09 work.
namespace mixed_fact_verify;
import mixed_core;
import mixed_verify;
import mixed_completion;
import mixed_fact_core;

struct Relation {left:i64=0,right:i64=0,guard_id:i64=0,truth:bool=false}
struct State {alias:i64[257]=[0;257],origin:i64[257]=[0;257],polarity:bool[257]=[false;257],relations:Relation[64]=[Relation {};64],count:i64=0}
struct Reader {at:i64=0}
fn fresh()->State {var s=State {};for i in 257 {s.alias[i]=i;}return s;}
fn type_at(types:u8[:],id:i64)->u8 {if id<1 || id>types.len {return 0;}return types[id-1];}
// Re-establish enough typing to justify comparison edges. Syntax and binding
// order were independently re-recognized before this pass.
fn typed(t:mixed_core::Tree&)->bool {
 var types:u8[>..]=[];
 for n in t.nodes {
  var ty:u8=0;
  if n.tag==1 {if n.a<1 || n.a>t.bindings.len {return false;}let k=t.bindings[n.a-1].kind;if k<1 || k>4{return false;}ty=1;}
  else if n.tag==2 {ty=1;}
  else if n.tag==3 || n.tag==4 {ty=2;}
  else if n.tag==6 {if type_at(types,n.a)!=1 || n.b<1 || n.b>t.bindings.len || t.bindings[n.b-1].kind!=3{return false;}ty=4;}
  else if n.tag==9 || n.tag==10 {if n.b!=1 || type_at(types,n.a)!=1{return false;}ty=3;}
  else if n.tag==11 || n.tag==12 {ty=3;}
  else if n.tag==13 {if type_at(types,n.a)!=1{return false;}ty=3;}
  else if n.tag==14 {if type_at(types,n.a)!=2 || type_at(types,n.b)!=3 || (n.c!=0 && type_at(types,n.c)!=3){return false;}ty=3;}
  else if n.tag==15 {if n.g<0 || n.g>1 || n.d!=0 || type_at(types,n.a)!=1 || type_at(types,n.b)!=1 || type_at(types,n.e)!=3 || n.f<1 || n.f>t.bindings.len || t.bindings[n.f-1].kind!=2{return false;}
   if n.g==0 {if n.c!=0{return false;}ty=3;}else {if type_at(types,n.c)!=4{return false;}ty=1;}}
  else if n.tag==16 {if type_at(types,n.a)!=1 || n.b<1 || n.b>t.bindings.len || t.bindings[n.b-1].kind!=4{return false;}ty=3;}
  else if n.tag==17 {if type_at(types,n.a)!=3 || type_at(types,n.b)!=3{return false;}ty=3;}
  else if n.tag==18 {if n.b!=1 || type_at(types,n.a)!=3{return false;}ty=3;}
  else if n.tag==19 || n.tag==21 {if type_at(types,n.a)!=1 || type_at(types,n.b)!=1{return false;}ty=1;}
  else if n.tag==20 {ty=type_at(types,n.a);if ty!=1 && ty!=2{return false;}}
  else if n.tag==22 {if type_at(types,n.a)!=1 || type_at(types,n.b)!=1{return false;}ty=2;}
  else {return false;}
  types.push(ty);
 }
 return t.root>0 && t.root<=t.nodes.len && t.nodes[t.root-1].tag==18 && type_at(types,t.root)==3;
}
fn literal(t:mixed_core::Tree&,id:i64)->u64,bool {
 if id<1 || id>t.nodes.len{return 0,false;}let n=t.nodes[id-1];if n.tag!=2 || n.start<0 || n.end<=n.start || n.end>t.source.len{return 0,false;}
 var x:u64=0;for c in t.source[n.start..n.end] {if c<'0' || c>'9'{return 0,false;}let d=(c-'0') as u64;if x>(4294967295-d)/10{return 0,false;}x=x*10+d;}return x,true;
}
fn reference(t:mixed_core::Tree&,id:i64,s:State)->i64 {
 var cur=id;var steps:i64=0;while cur>0 && cur<=t.nodes.len && t.nodes[cur-1].tag==20 {steps+=1;if steps>128{return 0;}cur=t.nodes[cur-1].a;}
 if cur<1 || cur>t.nodes.len{return 0;}let n=t.nodes[cur-1];if n.tag!=1 || n.a<1 || n.a>=257{return 0;}return s.alias[n.a];
}
fn add_edge(s:State&,left:i64,right:i64,guard_id:i64,truth:bool)->bool {
 if left==0 || right==0 || left==right{return true;}if left<0 || left>=257 || right<0 || right>=257 || guard_id<1 || s.count>=64{return false;}
 s.relations[s.count]=Relation {left:left,right:right,guard_id:guard_id,truth:truth};s.count+=1;return true;
}
recursive fn expression(t:mixed_core::Tree&,id:i64,s:State,events:mixed_fact_core::Evidence[:],r:Reader&,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag>=1 && n.tag<=4{return true;}
 if n.tag==20{return expression(t,n.a,s,events,r,depth+1);}
 if n.tag!=19 && n.tag!=21 && n.tag!=22{return false;}
 if !expression(t,n.a,s,events,r,depth+1) || !expression(t,n.b,s,events,r,depth+1){return false;}
 if n.tag!=21{return true;}
 let a,aok=literal(t,n.a);let b,bok=literal(t,n.b);
 if (aok && a==0) || (bok && b==0) || (aok && bok && a+b<=4294967295){return true;}
 var subject:i64=0;var ref:i64=0;var one:i64=0;
 if bok && b==1 {subject=reference(t,n.a,s);ref=n.a;one=n.b;}else if aok && a==1 {subject=reference(t,n.b,s);ref=n.b;one=n.a;}
 if subject<1 || subject>=257 || r.at<0 || r.at>=events.len{return false;}let e=events[r.at];r.at+=1;
 if e.subject!=subject || e.reference!=ref || e.one!=one || e.addition!=id || e.count<0 || e.count>16{return false;}
 var current=subject;
 for j in e.count {var found=false;for k in s.count {let edge=s.relations[k];if edge.left==current && edge.guard_id==e.guards[j] && edge.truth==e.edges[j] {current=edge.right;found=true;break;}}
  if !found || current<1 || current>=257{return false;}}
 for j in e.count..16 {if e.guards[j]!=0 || e.edges[j]{return false;}}
 return s.origin[current]>0 && e.guard_id==s.origin[current] && e.truth==s.polarity[current];
}
recursive fn walk(t:mixed_core::Tree&,id:i64,s:State&,events:mixed_fact_core::Evidence[:],r:Reader&,depth:i64)->bool {
 if depth>64 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag==17 {
  var pending:i64[2048]=[0;2048];var count:i64=1;pending[0]=id;
  while count>0 {
   count-=1;let next=pending[count];if next<1 || next>t.nodes.len{return false;}
   let part=t.nodes[next-1];
   if part.tag==17 {if count+2>2048{return false;}pending[count]=part.b;pending[count+1]=part.a;count+=2;}
   else if !walk(t,next,s,events,r,depth) {return false;}
  }
  return true;
 }
 if n.tag==16 {
  if n.a<1 || n.a>t.nodes.len || n.b<1 || n.b>=257{return false;}
  if t.nodes[n.a-1].tag==15 {if !walk(t,n.a,s,events,r,depth+1){return false;}s.alias[n.b]=n.b;return true;}
  if !expression(t,n.a,s,events,r,0){return false;}let root=reference(t,n.a,s);s.alias[n.b]=if root==0 {n.b} else {root};return true;
 }
 if n.tag==15 {
  if !expression(t,n.a,s,events,r,0) || !expression(t,n.b,s,events,r,0){return false;}
  if n.c!=0 {if n.c<1 || n.c>t.nodes.len{return false;}let carry=t.nodes[n.c-1];if carry.tag!=6 || !expression(t,carry.a,s,events,r,0){return false;}}
  var inside=fresh();return walk(t,n.e,inside,events,r,depth+1);
 }
 if n.tag==14 {
  if !expression(t,n.a,s,events,r,0){return false;}var yes=s;var no=s;var id=n.a;var count:i64=0;
  while id>0 && id<=t.nodes.len && t.nodes[id-1].tag==20 {id=t.nodes[id-1].a;count+=1;if count>128{return false;}}
  if id>0 && id<=t.nodes.len && t.nodes[id-1].tag==22 {
   let comparison=t.nodes[id-1];let left=reference(t,comparison.a,s);let right=reference(t,comparison.b,s);
   if left>0 && yes.origin[left]==0 {yes.origin[left]=id;yes.polarity[left]=true;}
   if !add_edge(yes,left,right,id,true) || !add_edge(no,right,left,id,false){return false;}
  }
  if !walk(t,n.b,yes,events,r,depth+1){return false;}if n.c!=0 && !walk(t,n.c,no,events,r,depth+1){return false;}return true;
 }
 if n.tag==9 || n.tag==10 || n.tag==13 {return expression(t,n.a,s,events,r,0);}
 return n.tag==11 || n.tag==12;
}
fn verify(t:mixed_core::Tree&,expected:u8[:],events:mixed_fact_core::Evidence[:])->bool {
 if !mixed_verify::verify(t,expected) || mixed_completion::check(t,expected)!=0 || !typed(t) || events.len>t.nodes.len{return false;}
 var s=fresh();var r=Reader {};let root=t.nodes[t.root-1];return walk(t,root.a,s,events,r,0) && r.at==events.len;
}
