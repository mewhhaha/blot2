// Independent source-bound verifier for a bounded mixed-loop proof fixture.
// It reconstructs active value identities and branch edges without using the
// producer's graph or route search. Each loop body starts with fresh facts and
// aliases; no body fact crosses a backedge or leaves its lexical loop. This is
// not general K1 SSA, invariant checking, a portable certificate or C09 work.
namespace short_fact_verify;
import mixed_core;
import short_verify;
import short_completion;
import mixed_fact_core;

struct Relation {left:i64=0,right:i64=0,guard_id:i64=0,truth:bool=false}
struct State {alias:i64[257]=[0;257],origin:i64[257]=[0;257],polarity:bool[257]=[false;257],relations:Relation[64]=[Relation {};64],count:i64=0}
struct Reader {at:i64=0}
fn fresh()->State {var s=State {};for i in 257 {s.alias[i]=i;}return s;}
fn type_at(types:u8[:],id:i64)->u8 {if id<1 || id>types.len {return 0;}return types[id-1];}
// Re-establish enough typing to justify comparison edges. Syntax and binding
// order were independently re-recognized before this pass.
fn typed(t:mixed_core::Tree&,argument:i64,result:i64)->bool {
 if (argument!=1 && argument!=2) || (result!=1 && result!=2) {return false;}
 var types:u8[>..]=[];var bindings:u8[256]=[0;256];for binding,i in t.bindings {if binding.kind==1 {bindings[i]=argument as u8;} else if binding.kind==2 || binding.kind==3 {bindings[i]=1;}}
 for n in t.nodes {
  var ty:u8=0;
  if n.tag==1 {if n.a<1 || n.a>t.bindings.len {return false;}let k=t.bindings[n.a-1].kind;if k<1 || k>4 || bindings[n.a-1]==0{return false;}ty=bindings[n.a-1];}
  else if n.tag==2 {ty=1;}
  else if n.tag==3 || n.tag==4 {ty=2;}
  else if n.tag==6 {if type_at(types,n.a)!=1 || n.b<1 || n.b>t.bindings.len || t.bindings[n.b-1].kind!=3{return false;}ty=4;}
  else if n.tag==9 || n.tag==10 {if n.b!=1 || type_at(types,n.a)!=1{return false;}ty=3;}
  else if n.tag==11 || n.tag==12 {ty=3;}
  else if n.tag==13 {if type_at(types,n.a)!=result{return false;}ty=3;}
  else if n.tag==14 {if type_at(types,n.a)!=2 || type_at(types,n.b)!=3 || (n.c!=0 && type_at(types,n.c)!=3){return false;}ty=3;}
  else if n.tag==15 {if n.g<0 || n.g>1 || n.d!=0 || type_at(types,n.a)!=1 || type_at(types,n.b)!=1 || type_at(types,n.e)!=3 || n.f<1 || n.f>t.bindings.len || t.bindings[n.f-1].kind!=2{return false;}
   if n.g==0 {if n.c!=0{return false;}ty=3;}else {if type_at(types,n.c)!=4{return false;}ty=1;}}
  else if n.tag==16 {let value=type_at(types,n.a);if (value!=1 && value!=2) || n.b<1 || n.b>t.bindings.len || t.bindings[n.b-1].kind!=4{return false;}bindings[n.b-1]=value;ty=3;}
  else if n.tag==17 {if type_at(types,n.a)!=3 || type_at(types,n.b)!=3{return false;}ty=3;}
  else if n.tag==18 {if n.b!=1 || type_at(types,n.a)!=3{return false;}ty=3;}
  else if n.tag==19 || n.tag==21 || n.tag==25 || n.tag==26 || n.tag==27 {if type_at(types,n.a)!=1 || type_at(types,n.b)!=1{return false;}ty=1;}
  else if n.tag==20 {ty=type_at(types,n.a);if ty!=1 && ty!=2{return false;}}
  else if (n.tag==22 || n.tag==28) {if type_at(types,n.a)!=1 || type_at(types,n.b)!=1{return false;}ty=2;}
  else if n.tag==23 || n.tag==24 {if type_at(types,n.a)!=2 || type_at(types,n.b)!=2{return false;}ty=2;}
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
// Independently reconstruct the terminal upper bound from its active source
// comparison and polarity; the evidence does not carry a trusted number.
fn terminal_limit(t:mixed_core::Tree&,guard_id:i64,polarity:bool,slot:i64,s:State)->u64,bool {
 if guard_id<1 || guard_id>t.nodes.len{return 0,false;}let g=t.nodes[guard_id-1];
 if g.tag==22 && polarity && reference(t,g.a,s)==slot {let limit,ok=literal(t,g.b);if ok && limit>0{return limit-1,true;}return 4294967294,true;}
 if g.tag==22 && !polarity && reference(t,g.b,s)==slot {let limit,ok=literal(t,g.a);if ok{return limit,true;}}
 if g.tag==28 && polarity && reference(t,g.a,s)==slot {let limit,ok=literal(t,g.b);if ok{return limit,true;}}
 if g.tag==28 && !polarity && reference(t,g.b,s)==slot {let limit,ok=literal(t,g.a);if ok && limit>0{return limit-1,true;}}
 return 0,false;
}
fn add_edge(s:State&,left:i64,right:i64,guard_id:i64,truth:bool)->bool {
 if left==0 || right==0 || left==right{return true;}if left<0 || left>=257 || right<0 || right>=257 || guard_id<1 || s.count>=64{return false;}
 s.relations[s.count]=Relation {left:left,right:right,guard_id:guard_id,truth:truth};s.count+=1;return true;
}
recursive fn numeric(t:mixed_core::Tree&,id:i64,s:State,events:mixed_fact_core::Evidence[:],r:Reader&,depth:i64)->bool {
 if depth>=128 || id<1 || id>t.nodes.len{return false;}let n=t.nodes[id-1];
 if n.tag>=1 && n.tag<=4{return true;}
 if n.tag==20{return numeric(t,n.a,s,events,r,depth+1);}
 if n.tag!=19 && n.tag!=21 && n.tag!=22 && n.tag!=25 && n.tag!=26 && n.tag!=27 && n.tag!=28{return false;}
 if !numeric(t,n.a,s,events,r,depth+1) || !numeric(t,n.b,s,events,r,depth+1){return false;}
 if n.tag!=21{return true;}
 let a,aok=literal(t,n.a);let b,bok=literal(t,n.b);
 if (aok && a==0) || (bok && b==0) || (aok && bok && a+b<=4294967295){return true;}
 var subject:i64=0;var ref:i64=0;var one:i64=0;
 var offset:u64=0;
 if bok && b>0 {subject=reference(t,n.a,s);ref=n.a;one=n.b;offset=b;}else if aok && a>0 {subject=reference(t,n.b,s);ref=n.b;one=n.a;offset=a;}
 if subject<1 || subject>=257 || r.at<0 || r.at>=events.len{return false;}let e=events[r.at];r.at+=1;
 if e.subject!=subject || e.reference!=ref || e.one!=one || e.addition!=id || e.count<0 || e.count>16{return false;}
 var current=subject;
 for j in e.count {var found=false;for k in s.count {let edge=s.relations[k];if edge.left==current && edge.guard_id==e.guards[j] && edge.truth==e.edges[j] {current=edge.right;found=true;break;}}
  if !found || current<1 || current>=257{return false;}}
 for j in e.count..16 {if e.guards[j]!=0 || e.edges[j]{return false;}}
 if s.origin[current]<=0 || e.guard_id!=s.origin[current] || e.truth!=s.polarity[current] {return false;}
 let limit,valid=terminal_limit(t,e.guard_id,e.truth,current,s);return valid && limit+offset<=4294967295;
}
fn expression(t:mixed_core::Tree&,id:i64,s:State,events:mixed_fact_core::Evidence[:],r:Reader&,depth:i64)->bool {
 var cur=id;var ndepth=depth;
 loop {if ndepth>=128 || cur<1 || cur>t.nodes.len {return false;}let n=t.nodes[cur-1];
  if n.tag==20 {cur=n.a;ndepth+=1;continue;}
  if n.tag==23 || n.tag==24 {let c=branch(t,cur,s,events,r,ndepth+1);return c.valid;}
  return numeric(t,cur,s,events,r,ndepth);
 }
}
// Rebuild reachable predecessor facts independently; intersections require the
// same subject, source-origin node and polarity on both paths.
struct Split {valid:bool=false,yes:State=State {},no:State=State {},yes_live:bool=false,no_live:bool=false}
fn identical(a:Relation,b:Relation)->bool {return a.left==b.left && a.right==b.right && a.guard_id==b.guard_id && a.truth==b.truth;}
fn common(a:State,b:State)->State {
 var out=a;for i in 257 {if a.alias[i]!=b.alias[i] {out.alias[i]=i;}if a.origin[i]!=b.origin[i] || a.polarity[i]!=b.polarity[i] {out.origin[i]=0;out.polarity[i]=false;}}
 out.count=0;for i in a.count {for j in b.count {if identical(a.relations[i],b.relations[j]) {out.relations[out.count]=a.relations[i];out.count+=1;break;}}}return out;
}
// Independent iterative predecessor replay avoids recursion on long chains.
struct BranchFrame {id:i64=0,phase:i64=0,state:State=State {},left:Split=Split {}}
fn branch(t:mixed_core::Tree&,id:i64,s:State,events:mixed_fact_core::Evidence[:],r:Reader&,depth:i64)->Split {
 if depth>=128 {return Split {};}var stack:BranchFrame[>..]=[BranchFrame {id:id,state:s}];var done=Split {};var have=false;var steps:i64=0;
 while stack.len>0 {
  if steps>=32768 {return Split {};}steps+=1;
  if stack.len>128 {return Split {};}let pos=stack.len-1;let f=stack[pos];if f.id<1 || f.id>t.nodes.len{return Split {};}let n=t.nodes[f.id-1];
  if f.phase==0 {
   if n.tag==20 {stack[pos].id=n.a;continue;}
   if n.tag==23 || n.tag==24 {stack[pos].phase=1;stack.push(BranchFrame {id:n.a,state:f.state});continue;}
   if n.tag==3 {done=Split {valid:true,yes:f.state,yes_live:true};}
   else if n.tag==4 {done=Split {valid:true,no:f.state,no_live:true};}
   else if n.tag==1 {done=Split {valid:true,yes:f.state,no:f.state,yes_live:true,no_live:true};}
   else if n.tag==22 || n.tag==28 {
    if !numeric(t,f.id,f.state,events,r,0){return Split {};}
    var yes=f.state;var no=f.state;let left=reference(t,n.a,f.state);let right=reference(t,n.b,f.state);
    if n.tag==22 {
     if left>0 && yes.origin[left]==0 {yes.origin[left]=f.id;yes.polarity[left]=true;}
     if !add_edge(yes,left,right,f.id,true) || !add_edge(no,right,left,f.id,false){return Split {};}
     let bound,ok=literal(t,n.a);if ok && bound<4294967295 && right>0 && no.origin[right]==0 {no.origin[right]=f.id;no.polarity[right]=false;}
    } else {
     let bound,ok=literal(t,n.b);if ok && bound<4294967295 && left>0 && yes.origin[left]==0 {yes.origin[left]=f.id;yes.polarity[left]=true;}
     let floor,valid=literal(t,n.a);if valid && floor>0 && right>0 && no.origin[right]==0 {no.origin[right]=f.id;no.polarity[right]=false;}
    }done=Split {valid:true,yes:yes,no:no,yes_live:true,no_live:true};
   }else {return Split {};}stack.pop();have=true;continue;
  }
  if !have {return Split {};}
  if f.phase==1 {
   let left=done;if !left.valid{return left;}stack[pos].left=left;have=false;
   if n.tag==23 && !left.yes_live {done=Split {valid:true,no:left.no,no_live:left.no_live};stack.pop();have=true;continue;}
   if n.tag==24 && !left.no_live {done=Split {valid:true,yes:left.yes,yes_live:left.yes_live};stack.pop();have=true;continue;}
   stack[pos].phase=2;stack.push(BranchFrame {id:n.b,state:if n.tag==23 {left.yes} else {left.no}});continue;
  }
  if f.phase!=2{return Split {};}let left=f.left;let right=done;if !right.valid{return right;}
  if n.tag==23 {var no=left.no;var live=left.no_live;if right.no_live {if live {no=common(no,right.no);}else {no=right.no;live=true;}}done=Split {valid:true,yes:right.yes,yes_live:right.yes_live,no:no,no_live:live};}
  else if n.tag==24 {var yes=left.yes;var live=left.yes_live;if right.yes_live {if live {yes=common(yes,right.yes);}else {yes=right.yes;live=true;}}done=Split {valid:true,yes:yes,yes_live:live,no:right.no,no_live:right.no_live};}
  else {return Split {};}stack.pop();have=true;
 }
 return if have {done} else {Split {}};
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
  let c=branch(t,n.a,s,events,r,0);if !c.valid{return false;}
  if c.yes_live {var yes=c.yes;if !walk(t,n.b,yes,events,r,depth+1){return false;}}
  if n.c!=0 && c.no_live {var no=c.no;if !walk(t,n.c,no,events,r,depth+1){return false;}}return true;
 }
 if n.tag==9 || n.tag==10 || n.tag==13 {return expression(t,n.a,s,events,r,0);}
 return n.tag==11 || n.tag==12;
}
fn verify(t:mixed_core::Tree&,expected:u8[:],events:mixed_fact_core::Evidence[:],argument:i64,result:i64)->bool {
 if !short_verify::verify(t,expected) || short_completion::check(t,expected)!=0 || !typed(t,argument,result) || events.len>t.nodes.len{return false;}
 var s=fresh();var r=Reader {};let root=t.nodes[t.root-1];return walk(t,root.a,s,events,r,0) && r.at==events.len;
}
