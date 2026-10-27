// Private exact-source/target resource sidecar. This is not an M11
// certificate and never asserts helper frame or callable classification.
import os;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
import m12_internal_emit;
import m12_internal_target;
import frame_contract;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}


fn put(out:u8[>..]&,v:u32){for i in 4 {out.push(((v>>(8*i))&255) as u8);}}
fn main() {
 let source=kernel();let adapter=m12_adapter_schema::source();var full:u8[>..]=[];full.append(source);full.append(adapter);
 var p,status=m12_adapter_build::build(source,adapter);assert(status==0 && m12_adapter_verify::verify(p,full));
 let target=m12_internal_emit::emit(p,full);assert(target.len>0 && m12_internal_target::verify(p,full,target));
 let plan,ok=frame_contract::create(p,full,target);assert(ok && frame_contract::verify(p,full,target,plan) && !plan.qualified);
 var out:u8[>..]=[];out.append("I08RES01");
 for x in [plan.kernel_depth,plan.kernel_frame,plan.adapter_depth,plan.adapter_frame,plan.wrapper_depth,plan.wrapper_span,
  plan.adapter_local,plan.machine_path,plan.fixed_frontier,plan.reserved,if plan.qualified {1 as u32} else {0 as u32}] {put(out,x);}
 for slot in plan.slots {put(out,slot.offset);put(out,slot.size);}
 assert(write_file("private-invoke.wasm",target) && write_file("m11-source-resource.bin",out));
 assert(!m12_adapter_verify::public_eligible(p,full));print("private exact source/target resource sidecar passed");
}
