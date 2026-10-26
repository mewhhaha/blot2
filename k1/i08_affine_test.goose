import std;
import i08_header_parse;
import i08_bound_shape;
import i08_affine_build;
import i08_affine_core;
import i08_affine_verify;
fn source(body:u8[:])->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n");s.append(body);return s;}
fn bad(body:u8[:]) {let s=source(body);var t,st=i08_header_parse::parse(s);if st==0 {let p=i08_affine_build::build(t,s);if p.status==0 {print("unexpected success ",body);}assert(p.status!=0);}}
fn main() {
 let s=source("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x + source[i].vx * dt,y:source[i].y}))\n  return builder.freeze(built)\n");
 var t,st=i08_header_parse::parse(s);assert(st==0 && i08_bound_shape::verify(t,s));let p=i08_affine_build::build(t,s);assert(p.status==0 && p.plan.initial==8 && p.plan.carry_id==10 && p.plan.result==11 && i08_affine_verify::verify(t,s,p.plan));
 for f in 16 {var q=p.plan;if f==0 {q.initial=9999;}else if f==1 {q.view=9999;}else if f==2 {q.nat=9999;}else if f==3 {q.capacity=9999;}else if f==4 {q.loop_id=9999;}else if f==5 {q.index=9999;}else if f==6 {q.carry_id=9999;}else if f==7 {q.result=9999;}else if f==8 {q.carry_node=9999;}else if f==9 {q.invariant_id=9999;}else if f==10 {q.next_node=9999;}else if f==11 {q.append=9999;}else if f==12 {q.row=9999;}else if f==13 {q.freeze=9999;}else if f==14 {q.return_node=9999;}else {q.root=9999;}assert(!i08_affine_verify::verify(t,s,q));}
 for i in t.source.len {let old=t.source[i];t.source[i]=if old=='?' {'!'} else {'?'};assert(!i08_affine_verify::verify(t,s,p.plan));t.source[i]=old;}
 for i in t.nodes.len {for f in 11 {for v in [-1,999999,9223372036854775807] {let old=t.nodes[i];
 if f==0 {t.nodes[i].tag=v;}else if f==1 {t.nodes[i].start=v;}else if f==2 {t.nodes[i].end=v;}else if f==3 {t.nodes[i].a=v;}else if f==4 {t.nodes[i].b=v;}else if f==5 {t.nodes[i].c=v;}else if f==6 {t.nodes[i].d=v;}else if f==7 {t.nodes[i].e=v;}else if f==8 {t.nodes[i].f=v;}else if f==9 {t.nodes[i].g=v;}else {t.nodes[i].target=v;}assert(!i08_affine_verify::verify(t,s,p.plan));t.nodes[i]=old;}}}
 for i in t.bindings.len {for f in 4 {let old=t.bindings[i];if f==0 {t.bindings[i].start=-1;}else if f==1 {t.bindings[i].end=999999;}else if f==2 {t.bindings[i].kind=999999;}else {t.bindings[i].scope=999999;}assert(!i08_affine_verify::verify(t,s,p.plan));t.bindings[i]=old;}}
 assert(!i08_affine_verify::verify(t,"other",p.plan));
 assert(i08_affine_build::build(t,"other").status!=0);
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(initial,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      stop (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),0)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..c carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(builder.append(b,{x: source[i].x,y:source[i].y}),{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(initial)\n");
 print("source builder affinity and completion controls passed");
}
