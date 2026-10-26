import os;
import m12_adapter_schema;
import m12_candidate_build;
import m12_candidate_verify;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let kernel=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");let adapter=m12_adapter_schema::source();let abi:u8[32]=[9;32];
 let manifest=m12_candidate_build::make(kernel,adapter,"pkg","project.blot",abi);
 assert(manifest.len>0 && m12_candidate_verify::verify(manifest,kernel,adapter,"pkg","project.blot",abi));
 assert(write_file("source-order-candidate.bin",manifest));print("private source-order candidate emitted");
}
