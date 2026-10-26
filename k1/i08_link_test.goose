import std;
import i08_link_build;
import i08_link_verify;
fn source()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var at:i64=0;var done=false;while at<s.len {if !done && a.len<=s.len-at && s[at..at+a.len]==a {out.append(b);at+=a.len;done=true;}else {out.push(s[at]);at+=1;}}assert(done);return out;}
fn main() {let s=source();var p,status=i08_link_build::build(s);if status!=0 {print("unexpected status ",status);}assert(status==0 && i08_link_verify::verify(p,s));let old=p.tree.nodes[0];p.tree.nodes[0].a+=1;assert(!i08_link_verify::verify(p,s));p.tree.nodes[0]=old;let event=p.cap.steps[0];p.cap.steps[0].kind+=1;assert(!i08_link_verify::verify(p,s));p.cap.steps[0]=event;let n=p.cap.job.core.nodes[0];p.cap.job.core.nodes[0].field+=1;assert(!i08_link_verify::verify(p,s));p.cap.job.core.nodes[0]=n;assert(!i08_link_verify::verify(p,"bad source"));
 for changed in ["(source[i].x + source[i].vx) * dt", "source[i].x * (source[i].vx + dt)", "source[i].vx + source[i].x * dt"] {
  let alt=replace(s,"source[i].x + source[i].vx * dt",changed);assert(!i08_link_verify::verify(p,alt));var q,code=i08_link_build::build(alt);if code!=0 {print("failed valid variant ",changed," ",code);}assert(code==0 && i08_link_verify::verify(q,alt));
 }
 var bytes:u8[>..]=[];bytes.append(s);for i in bytes.len {let save=bytes[i];bytes[i]=if save=='?' {'!'} else {'?'};assert(!i08_link_verify::verify(p,bytes));bytes[i]=save;}
 for i in p.tree.nodes.len {let save=p.tree.nodes[i];p.tree.nodes[i].start=-1;assert(!i08_link_verify::verify(p,s));p.tree.nodes[i]=save;}
 for i in p.cap.steps.len {let save=p.cap.steps[i];p.cap.steps[i].site+=1;assert(!i08_link_verify::verify(p,s));p.cap.steps[i]=save;}
 let bad=replace(s,"source[i].x","source[c].x");let _,bad_status=i08_link_build::build(bad);assert(bad_status!=0);
 print("I08 syntax, read bounds and source-local capability trace linked");}
