// Private source→target gate. Its result is used only inside the private
// Wasm authority fixture; actual K1 capabilities/loans and ABI remain absent.
import os;
import i08_link_build;
import i08_link_verify;
import i08_link_affine;
import i08_same_wasm;
import i08_same_target;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
 var linked,status=i08_link_build::build(text);assert(status==0 && i08_link_verify::verify(linked,text));
 let affine=i08_link_affine::build(linked,text);assert(affine.status==0 && i08_link_affine::verify(linked,text,affine.plan));
 var forged=affine.plan;forged.append+=1;assert(!i08_link_affine::verify(linked,text,forged));
 let target=i08_same_wasm::emit(linked.cap.job.core,text,linked.cap.job.core.context);
 assert(target.len>0 && i08_same_target::verify(linked.cap.job.core,text,linked.cap.job.core.context,target));
 assert(write_file("live-worker.wasm",target));
 print("private source/capability trace to live Wasm target passed");
}
