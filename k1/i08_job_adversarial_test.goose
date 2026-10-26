import i08_job_build;
import i08_job_wasm;
import particle_lower_target;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}
fn main() {
    let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
    var job,status=i08_job_build::build(text);assert(status==0);
    let target=i08_job_wasm::emit(job,text);assert(target.len>0);
    for i in target.len {
        var forged:u8[>..]=[];forged.append(target);forged[i] ^= 1;
        assert(!particle_lower_target::verify(job.core,text,job.core.context,forged));
        assert(!particle_lower_target::verify(job.core,text,job.core.context,target[..i]));
    }
    var extra:u8[>..]=[];extra.append(target);extra.push(0);
    assert(!particle_lower_target::verify(job.core,text,job.core.context,extra));
    print("private I08 target byte mutations and truncations rejected");
}
