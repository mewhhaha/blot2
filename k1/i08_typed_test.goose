import std;
import i08_header_parse;
import i08_header_verify;
import i08_typed_shape;
import i08_bound_shape;
fn src(body:u8[:])->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n");s.append(body);return s;}
fn typed(body:u8[:],want:bool) {let s=src(body);var t,st=i08_header_parse::parse(s);if st!=0 {print("parse error ",st," ",body);}assert(st==0 && i08_header_verify::verify(t,s));let got=i08_typed_shape::verify(t,s);if got!=want {print("type mismatch expected ",want," ",body);}assert(got==want);}
fn main() {
 typed("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x + source[i].vx * dt, y: source[i].y}))\n  return builder.freeze(built)\n",true);
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (1)\n  return builder.freeze(built)\n",false);
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[i].x, y: i}))\n  return builder.freeze(built)\n",false);
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[dt].x, y: source[i].y}))\n  return builder.freeze(built)\n",false);
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[i].x * i, y: source[i].y}))\n  return builder.freeze(built)\n",false);
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(source,{x: source[i].x, y: source[i].y}))\n  return builder.freeze(built)\n",false);
 // Even when this shape type-checks, the index is unproved and no backend or
 // semantic admission exists: consumers must establish the read obligation.
 typed("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[4294967295].x, y: source[i].y}))\n  return builder.freeze(built)\n",true);

 let proven=src("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[i].x, y: source[i].y}))\n  return builder.freeze(built)\n");
 var p,ps=i08_header_parse::parse(proven);assert(ps==0 && i08_bound_shape::verify(p,proven));
 let missing=src("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[4294967295].x, y: source[i].y}))\n  return builder.freeze(built)\n");
 var q,qs=i08_header_parse::parse(missing);assert(qs==0 && i08_typed_shape::verify(q,missing) && !i08_bound_shape::verify(q,missing));
 let wrong=src("  let built = for i in 0..c carry (b=initial) do:\n    next (builder.append(b,{x: source[i].x, y: source[i].y}))\n  return builder.freeze(built)\n");
 var w,ws=i08_header_parse::parse(wrong);assert(ws==0 && i08_typed_shape::verify(w,wrong) && !i08_bound_shape::verify(w,wrong));
 let outside=src("  let a = builder.append(initial,{x: source[0].x, y: source[0].y})\n  return builder.freeze(a)\n");
 var x,xs=i08_header_parse::parse(outside);assert(xs==0 && i08_typed_shape::verify(x,outside) && !i08_bound_shape::verify(x,outside));
 let a=src("  let built = for i in 0..n carry (b=initial) do:\n    next (builder.append(b,{x: source[i].x, y: source[i].y}))\n  return builder.freeze(built)\n");
 var qtree,ok=i08_header_parse::parse(a);assert(ok==0 && i08_bound_shape::verify(qtree,a));
 for i in qtree.nodes.len {for f in 11 {let old=qtree.nodes[i];if f==0 {qtree.nodes[i].tag=999999;}else if f==1 {qtree.nodes[i].start=-1;}else if f==2 {qtree.nodes[i].end=999999;}else if f==3 {qtree.nodes[i].a=999999;}else if f==4 {qtree.nodes[i].b=999999;}else if f==5 {qtree.nodes[i].c=999999;}else if f==6 {qtree.nodes[i].d=999999;}else if f==7 {qtree.nodes[i].e=999999;}else if f==8 {qtree.nodes[i].f=999999;}else if f==9 {qtree.nodes[i].g=999999;}else {qtree.nodes[i].target=999999;}assert(!i08_bound_shape::verify(qtree,a));qtree.nodes[i]=old;}}
 print("bounded I08 type shapes and numerical read obligations checked; loan and affine obligations remain unadmitted");
}
