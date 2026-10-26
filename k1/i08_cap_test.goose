import os;
import i08_cap_core;
import i08_cap_build;
import i08_cap_verify;
import i08_cap_wasm;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}
fn clone(p:i08_cap_core::Package&)->i08_cap_core::Package {return i08_cap_core::Package {job:copy(p.job),steps:copy(p.steps)};}
fn compile(x:u8[:],y:u8[:],path:u8[:])->u8[] {
    let source=source(x,y);var p,status=i08_cap_build::build(source);assert(status==0 && i08_cap_verify::verify(p,source));
    let out=i08_cap_wasm::emit(p,source);assert(out.len>0 && write_file(path,out));return out;
}
fn main() {
    let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
    var p,status=i08_cap_build::build(text);assert(status==0 && i08_cap_verify::verify(p,text));
    assert(p.steps.len>p.job.events.len);
    let a=compile("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt","particle-lower-a.wasm");
    let b=compile("(source[i].vx + source[i].x) * dt","source[i].y * dt + source[i].vy","particle-lower-b.wasm");
    let c=compile("source[i].vx","source[i].x","particle-lower-c.wasm");
    let d=compile("dt + source[i].x * source[i].vy","(source[i].vx + source[i].y) * (source[i].vy + dt)","particle-lower-d.wasm");
    assert(a[..]!=b[..] && a[..]!=c[..] && a[..]!=d[..]);
    for i in p.steps.len {for f in 5 {
        var bad=clone(p);
        if f==0 {bad.steps[i].kind+=1;} else if f==1 {bad.steps[i].event+=1;} else if f==2 {bad.steps[i].node+=1;}
        else if f==3 {bad.steps[i].site+=1;} else {bad.steps[i].proof+=1;}
        assert(!i08_cap_verify::verify(bad,text) && i08_cap_wasm::emit(bad,text).len==0);
    }}
    for i in p.steps.len-1 {
        var bad=clone(p);let old=bad.steps[i];bad.steps[i]=bad.steps[i+1];bad.steps[i+1]=old;
        assert(!i08_cap_verify::verify(bad,text));
    }
    var ms:i08_cap_core::Step[>..]=[];ms.append(p.steps[..p.steps.len-1]);var missing=i08_cap_core::Package {job:copy(p.job),steps:copy(ms)};assert(!i08_cap_verify::verify(missing,text));
    var s:i08_cap_core::Step[>..]=[];s.append(p.steps);s.push(p.steps[p.steps.len-1]);var extra=i08_cap_core::Package {job:copy(p.job),steps:copy(s)};
    assert(!i08_cap_verify::verify(extra,text));
    var mutated=clone(p);mutated.job.core.nodes[0].version+=1;assert(!i08_cap_verify::verify(mutated,text));
    var proof=clone(p);proof.job.core.proofs[3].dep2=0;assert(!i08_cap_verify::verify(proof,text));
    let other=source("source[i].vx","source[i].x");assert(!i08_cap_verify::verify(p,other));
    print("private source-scoped particle capability interpreter passed");
}
