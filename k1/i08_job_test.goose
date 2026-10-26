import os;
import i08_job_core;
import i08_job_build;
import i08_job_verify;
import i08_job_wasm;
import particle_lower_target;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}
fn clone(j:i08_job_core::Job&)->i08_job_core::Job {return i08_job_core::Job {source:copy(j.source),core:copy(j.core),events:copy(j.events)};}
fn compile(x:u8[:],y:u8[:],path:u8[:])->u8[] {
    let text=source(x,y);var job,status=i08_job_build::build(text);assert(status==0 && i08_job_verify::verify(job,text));
    let bytes=i08_job_wasm::emit(job,text);assert(bytes.len>0 && write_file(path,bytes));return bytes;
}
fn main() {
    let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
    var job,status=i08_job_build::build(text);assert(status==0 && i08_job_verify::verify(job,text));
    assert(job.events.len==job.core.nodes.len+6 && job.events[0].kind==1);
    let last=job.events.len;assert(job.events[last-5].kind==6 && job.events[last-4].kind==7 && job.events[last-3].kind==8 && job.events[last-2].kind==9 && job.events[last-1].kind==10);
    let a=compile("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt","particle-lower-a.wasm");
    let b=compile("(source[i].vx + source[i].x) * dt","source[i].y * dt + source[i].vy","particle-lower-b.wasm");
    let c=compile("source[i].vx","source[i].x","particle-lower-c.wasm");
    let d=compile("dt + source[i].x * source[i].vy","(source[i].vx + source[i].y) * (source[i].vy + dt)","particle-lower-d.wasm");
    assert(a[..]!=b[..] && a[..]!=c[..] && a[..]!=d[..]);
    // All source-owned ordering, SSA IDs, version and proof links are checked
    // against the independently reconstructed symbolic job before emission.
    for i in job.events.len {for field in 13 {
        var bad=clone(job);
        if field==0 {bad.events[i].kind+=1;} else if field==1 {bad.events[i].node+=1;}
        else if field==2 {bad.events[i].site+=1;} else if field==3 {bad.events[i].symbol+=1;}
        else if field==4 {bad.events[i].version+=1;} else if field==5 {bad.events[i].region+=1;}
        else if field==6 {bad.events[i].domain+=1;} else if field==7 {bad.events[i].index+=1;}
        else if field==8 {bad.events[i].a+=1;} else if field==9 {bad.events[i].b+=1;}
        else if field==10 {bad.events[i].output+=1;} else if field==11 {bad.events[i].output_version+=1;}
        else {bad.events[i].proof+=1;}
        assert(!i08_job_verify::verify(bad,text) && i08_job_wasm::emit(bad,text).len==0);
    }}
    var no_events=i08_job_core::Job {source:copy(job.source),core:copy(job.core),events:[]};assert(!i08_job_verify::verify(no_events,text));
    var shuffled=clone(job);let first=shuffled.events[0];shuffled.events[0]=shuffled.events[1];shuffled.events[1]=first;assert(!i08_job_verify::verify(shuffled,text));
    var changed_ctx=clone(job);changed_ctx.core.context.input_version+=1;assert(!i08_job_verify::verify(changed_ctx,text));
    var wrong_domain=clone(job);wrong_domain.core.context.result_domain+=1;assert(!i08_job_verify::verify(wrong_domain,text));
    var wrong_node=clone(job);wrong_node.core.nodes[0].field+=1;assert(!i08_job_verify::verify(wrong_node,text));
    var wrong_proof=clone(job);wrong_proof.core.proofs[3].dep1=0;assert(!i08_job_verify::verify(wrong_proof,text));
    for i in text.len {var bad=clone(job);bad.source[i]='?';assert(!i08_job_verify::verify(bad,text));}
    let other=source("source[i].vx","source[i].x");assert(!i08_job_verify::verify(job,other));
    assert(!particle_lower_target::verify(job.core,text,job.core.context,c));
    var caller:u8[>..]=[];caller.append(text);var owned,os=i08_job_build::build(caller);assert(os==0);caller[0]='?';assert(i08_job_verify::verify(owned,text));
    let unsupported=source("source[i+1].x","source[i].y");let _,bad=i08_job_build::build(unsupported);assert(bad!=0);
    var huge:u8[>..]=[32;65537];let _,limit=i08_job_build::build(huge);assert(limit==2);
    print("private compiler-owned I08 job/Core/event linkage passed");
}
