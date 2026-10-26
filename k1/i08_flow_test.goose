import std;
import i08_header_parse;
import i08_flow_completion;
import i08_flow_build;
import i08_flow_verify;
import i08_flow_core;
fn source(body:u8[:])->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n");s.append(body);return s;}
fn with_edges(p:i08_flow_core::Plan&,edges:i08_flow_core::Edge[:])->i08_flow_core::Plan {
 var owned:i08_flow_core::Edge[>..]=[];owned.append(edges);return i08_flow_core::Plan {initial:p.initial,view:p.view,nat:p.nat,capacity:p.capacity,loop_id:p.loop_id,index:p.index,carry_id:p.carry_id,result:p.result,carry_node:p.carry_node,invariant_id:p.invariant_id,freeze:p.freeze,return_node:p.return_node,root:p.root,edges:copy(owned)};
}
fn yes(body:u8[:],edges:i64) {let s=source(body);var tree,st=i08_header_parse::parse(s);if st!=0 {print("parse ",st," ",body);}assert(st==0);var p=i08_flow_build::build(tree,s);if p.status!=0 {print("flow ",p.status," completion ",i08_flow_completion::check(tree,s)," ",body);}assert(p.status==0 && p.plan.edges.len==edges && i08_flow_verify::verify(tree,s,p.plan));
 for i in p.plan.edges.len {let old=p.plan.edges[i];p.plan.edges[i].next_node=999999;assert(!i08_flow_verify::verify(tree,s,p.plan));p.plan.edges[i]=old;p.plan.edges[i].append=999999;assert(!i08_flow_verify::verify(tree,s,p.plan));p.plan.edges[i]=old;p.plan.edges[i].row=999999;assert(!i08_flow_verify::verify(tree,s,p.plan));p.plan.edges[i]=old;}

 for f in 13 {var q=copy(p.plan);if f==0 {q.initial=99999;}else if f==1 {q.view=99999;}else if f==2 {q.nat=99999;}else if f==3 {q.capacity=99999;}else if f==4 {q.loop_id=99999;}else if f==5 {q.index=99999;}else if f==6 {q.carry_id=99999;}else if f==7 {q.result=99999;}else if f==8 {q.carry_node=99999;}else if f==9 {q.invariant_id=99999;}else if f==10 {q.freeze=99999;}else if f==11 {q.return_node=99999;}else {q.root=99999;}assert(!i08_flow_verify::verify(tree,s,q));}
 {var q=with_edges(p.plan,p.plan.edges[..p.plan.edges.len-1]);assert(!i08_flow_verify::verify(tree,s,q));}
 {var extra:i08_flow_core::Edge[>..]=[];extra.append(p.plan.edges);extra.push(p.plan.edges[0]);var q=with_edges(p.plan,extra);assert(!i08_flow_verify::verify(tree,s,q));}
 for i in tree.nodes.len {for f in 11 {let old=tree.nodes[i];if f==0 {tree.nodes[i].tag=999999;}else if f==1 {tree.nodes[i].start=-1;}else if f==2 {tree.nodes[i].end=999999;}else if f==3 {tree.nodes[i].a=999999;}else if f==4 {tree.nodes[i].b=999999;}else if f==5 {tree.nodes[i].c=999999;}else if f==6 {tree.nodes[i].d=999999;}else if f==7 {tree.nodes[i].e=999999;}else if f==8 {tree.nodes[i].f=999999;}else if f==9 {tree.nodes[i].g=999999;}else {tree.nodes[i].target=999999;}assert(!i08_flow_verify::verify(tree,s,p.plan));tree.nodes[i]=old;}}
 for i in tree.bindings.len {for f in 4 {let old=tree.bindings[i];if f==0 {tree.bindings[i].start=-1;}else if f==1 {tree.bindings[i].end=999999;}else if f==2 {tree.bindings[i].kind=999999;}else {tree.bindings[i].scope=999999;}assert(!i08_flow_verify::verify(tree,s,p.plan));tree.bindings[i]=old;}}
 for i in tree.source.len {let old=tree.source[i];tree.source[i]=if old=='?' {'!'} else {'?'};assert(!i08_flow_verify::verify(tree,s,p.plan));tree.source[i]=old;}
 assert(!i08_flow_verify::verify(tree,"wrong",p.plan));}
fn no(body:u8[:]) {let s=source(body);var t,st=i08_header_parse::parse(s);if st==0 {let p=i08_flow_build::build(t,s);if p.status==0 {print("bad accepted ",body);}assert(p.status!=0);}}
fn main() {
 yes("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if i < 2:\n        next (builder.append(b,{x:source[i].x,y:source[i].y}))\n      else:\n        next (builder.append(b,{x:source[i].vx,y:source[i].vy}))\n  return builder.freeze(built)\n",2);
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if #False:\n        stop (b)\n      next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if #False:\n        return builder.freeze(b)\n      next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 yes("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if i < 2:\n        next (builder.append(b,{x:source[i].x,y:source[i].y}))\n      next (builder.append(b,{x:source[i].vx,y:source[i].vy}))\n  return builder.freeze(built)\n",2);
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if i < 2:\n        stop (b)\n      else:\n        next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if i < 2:\n        return builder.freeze(b)\n      else:\n        next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if i < 2:\n        next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 no("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      if #False:\n        return builder.freeze(initial)\n      next (builder.append(b,{x:source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 print("branch-aware source builder/completion controls passed");
}
