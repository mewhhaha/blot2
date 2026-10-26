import m12_adapter_schema;
import m12_candidate_build;
import m12_candidate_verify;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


fn main() {
 let source_a=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
 let adapter=m12_adapter_schema::source();
 let source_b=source("source[i].vx","source[i].x");let abi:u8[32]=[9;32];let wrongabi:u8[32]=[8;32];
 let a=m12_candidate_build::make(source_a,adapter,"pkg","project.blot",abi);
 let b=m12_candidate_build::make(source_b,adapter,"pkg","project.blot",abi);
 assert(a.len>0 && b.len>0 && a[..]!=b[..]);
 assert(m12_candidate_verify::verify(a,source_a,adapter,"pkg","project.blot",abi));
 assert(!m12_candidate_verify::verify(a,source_b,adapter,"pkg","project.blot",abi));
 var altered_adapter:u8[>..]=[];altered_adapter.append(adapter);altered_adapter[0]^=1;
 assert(!m12_candidate_verify::verify(a,source_a,altered_adapter,"pkg","project.blot",abi));
 assert(m12_candidate_build::make(source_a,altered_adapter,"pkg","project.blot",abi).len==0);
 assert(!m12_candidate_verify::verify(a,source_a,adapter,"badpkg","project.blot",abi));
 assert(!m12_candidate_verify::verify(a,source_a,adapter,"pkg","other.blot",abi));
 assert(!m12_candidate_verify::verify(a,source_a,adapter,"pkg","project.blot",wrongabi));
 for i in a.len {var changed:u8[>..]=[];changed.append(a);changed[i]^=1;
  assert(!m12_candidate_verify::verify(changed,source_a,adapter,"pkg","project.blot",abi));}
 for i in a.len {assert(!m12_candidate_verify::verify(a[..i],source_a,adapter,"pkg","project.blot",abi));}
 var extra:u8[>..]=[];extra.append(a);extra.push(0);assert(!m12_candidate_verify::verify(extra,source_a,adapter,"pkg","project.blot",abi));
 assert(m12_candidate_build::make(source_a,adapter,"pkg","../escape",abi).len==0);
 print("private canonical source/target/window candidate corruption checks passed");
}
