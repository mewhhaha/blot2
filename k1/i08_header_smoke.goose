import std;
import i08_header_parse;
import i08_header_verify;
fn main() {
 let s="pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";
 var t,status=i08_header_parse::parse(s);if status!=0 {print("status ",status);}assert(status==0 && t.source[..]==s && t.bindings.len==11 && i08_header_verify::verify(t,s));
 assert(t.bindings[0].kind==6 && t.bindings[1].kind==6 && t.bindings[2].kind==5 && t.bindings[3].kind==5 && t.bindings[4].kind==7);
 for i in t.bindings.len {for f in 4 {let old=t.bindings[i];if f==0 {t.bindings[i].start=-1;}else if f==1 {t.bindings[i].end=999999;}else if f==2 {t.bindings[i].kind=999999;}else {t.bindings[i].scope=999999;}assert(!i08_header_verify::verify(t,s));t.bindings[i]=old;}}
 for i in t.nodes.len {for f in 11 {let old=t.nodes[i];if f==0 {t.nodes[i].tag=999999;}else if f==1 {t.nodes[i].start=-1;}else if f==2 {t.nodes[i].end=999999;}else if f==3 {t.nodes[i].a=999999;}else if f==4 {t.nodes[i].b=999999;}else if f==5 {t.nodes[i].c=999999;}else if f==6 {t.nodes[i].d=999999;}else if f==7 {t.nodes[i].e=999999;}else if f==8 {t.nodes[i].f=999999;}else if f==9 {t.nodes[i].g=999999;}else {t.nodes[i].target=999999;}assert(!i08_header_verify::verify(t,s));t.nodes[i]=old;}}
 for i in t.source.len {let old=t.source[i];t.source[i]=if old=='?' {'!'} else {'?'};assert(!i08_header_verify::verify(t,s));t.source[i]=old;}
 assert(!i08_header_verify::verify(t,"other"));print("full source syntactic header binding passed");
}
