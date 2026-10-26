import os;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
import source_wire_order;
import i08_same_wasm;
import i08_same_target;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let kernel=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");let adapter=m12_adapter_schema::source();
 var candidate,status=m12_adapter_build::build(kernel,adapter);assert(status==0);
 var all:u8[>..]=[];all.append(kernel);all.append(adapter);
 assert(m12_adapter_verify::verify(candidate,all) && source_wire_order::verify(candidate,all) && !m12_adapter_verify::public_eligible(candidate,all));
 var changed:u8[>..]=[];changed.append(all);changed[candidate.split]^=1;
 assert(!source_wire_order::verify(candidate,changed));
 let target=i08_same_wasm::emit(candidate.linked.cap.job.core,kernel,candidate.linked.cap.job.core.context);
 assert(target.len>0 && i08_same_target::verify(candidate.linked.cap.job.core,kernel,candidate.linked.cap.job.core.context,target));
 assert(write_file("live-worker.wasm",target));
 print("private adapter source field order and kernel target gate passed");
}
