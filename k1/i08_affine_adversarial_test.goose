import std;
import i08_header_parse;
import i08_bound_shape;
import i08_affine_build;
import i08_affine_core;
import i08_affine_verify;
fn source(body:u8[:])->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n");s.append(body);return s;}
fn bad(body:u8[:]) {let s=source(body);var t,st=i08_header_parse::parse(s);if st==0 {let p=i08_affine_build::build(t,s);if p.status==0 {print("unexpected success ",body);}assert(p.status!=0);}}
fn main(){
 let s=source("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 var t,st=i08_header_parse::parse(s);assert(st==0);let p=i08_affine_build::build(t,s);assert(p.status==0 && i08_affine_verify::verify(t,s,p.plan));
 for f in 16 {for v in [-1,0,999999] {var q=p.plan;if f==0 {q.initial=v;}else if f==1 {q.view=v;}else if f==2 {q.nat=v;}else if f==3 {q.capacity=v;}else if f==4 {q.loop_id=v;}else if f==5 {q.index=v;}else if f==6 {q.carry_id=v;}else if f==7 {q.result=v;}else if f==8 {q.carry_node=v;}else if f==9 {q.invariant_id=v;}else if f==10 {q.next_node=v;}else if f==11 {q.append=v;}else if f==12 {q.row=v;}else if f==13 {q.freeze=v;}else if f==14 {q.return_node=v;}else {q.root=v;}assert(!i08_affine_verify::verify(t,s,q));}}
 for i in t.nodes.len {for f in 11 {let old=t.nodes[i];if f==0 {t.nodes[i].tag+=1;}else if f==1 {t.nodes[i].start+=1;}else if f==2 {t.nodes[i].end+=1;}else if f==3 {t.nodes[i].a+=1;}else if f==4 {t.nodes[i].b+=1;}else if f==5 {t.nodes[i].c+=1;}else if f==6 {t.nodes[i].d+=1;}else if f==7 {t.nodes[i].e+=1;}else if f==8 {t.nodes[i].f+=1;}else if f==9 {t.nodes[i].g+=1;}else {t.nodes[i].target+=1;}assert(!i08_affine_verify::verify(t,s,p.plan));t.nodes[i]=old;}}
 for i in t.bindings.len {for f in 4 {let old=t.bindings[i];if f==0 {t.bindings[i].start+=1;}else if f==1 {t.bindings[i].end+=1;}else if f==2 {t.bindings[i].kind+=1;}else {t.bindings[i].scope+=1;}assert(!i08_affine_verify::verify(t,s,p.plan));t.bindings[i]=old;}}
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      let save = b\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (b)\n  return builder.freeze(built)\n");
 bad("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[0].x,y:source[i].y}))\n  return builder.freeze(built)\n");
 print("independent I08 affine forged identity and double-use controls passed");}
