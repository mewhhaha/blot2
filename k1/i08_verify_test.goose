import std;
import i08_parse;
import i08_verify;
fn main() {
 let src="fn (source,dt,initial) => do:\n  let built = for i in 0..source.length carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";
 var t,status=i08_parse::parse(src);assert(status==0 && i08_verify::verify(t,src));
 for i in t.nodes.len {for f in 11 {let old=t.nodes[i];
 if f==0 {t.nodes[i].tag=999999;} else if f==1 {t.nodes[i].start=-1;}else if f==2 {t.nodes[i].end=999999;}else if f==3 {t.nodes[i].a=999999;}
 else if f==4 {t.nodes[i].b=999999;}else if f==5 {t.nodes[i].c=999999;}else if f==6 {t.nodes[i].d=999999;}else if f==7 {t.nodes[i].e=999999;}
 else if f==8 {t.nodes[i].f=999999;}else if f==9 {t.nodes[i].g=999999;}else {t.nodes[i].target=999999;}
 assert(!i08_verify::verify(t,src));t.nodes[i]=old;}}
 for i in t.bindings.len {for f in 4 {let old=t.bindings[i];if f==0 {t.bindings[i].start=-1;}else if f==1 {t.bindings[i].end=999999;}else if f==2 {t.bindings[i].kind=999999;}else {t.bindings[i].scope=999999;}assert(!i08_verify::verify(t,src));t.bindings[i]=old;}}
 for i in t.source.len {let old=t.source[i];t.source[i]=if old=='?' {'!'} else {'?'};assert(!i08_verify::verify(t,src));t.source[i]=old;}
 let src2="fn (source,dt,initial) => do:\n  return 1.25 * dt + source[0].vx\n";var t2,st=i08_parse::parse(src2);assert(st==0 && i08_verify::verify(t2,src2));
 assert(!i08_verify::verify(t,"wrong"));print("independent I08 lexical syntax replay passed");
}
