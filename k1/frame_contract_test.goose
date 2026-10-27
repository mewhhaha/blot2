import os;
import m12_adapter_schema;
import m12_adapter_build;
import m12_internal_emit;
import frame_contract;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}

fn main() {
 let source=kernel();let adapter=m12_adapter_schema::source();var module:u8[>..]=[];module.append(source);module.append(adapter);
 var p,status=m12_adapter_build::build(source,adapter);assert(status==0);
 let target=m12_internal_emit::emit(p,module);assert(target.len>0);
 let plan,ok=frame_contract::create(p,module,target);assert(ok && frame_contract::verify(p,module,target,plan));
 assert(plan.kernel_frame==256 && plan.adapter_frame==512 && plan.wrapper_span+plan.adapter_frame==688 && plan.reserved==768 && plan.machine_path==6 && !plan.qualified);
 for f in 8 {var bad=plan;if f==0 {bad.kernel_depth+=1;}else if f==1 {bad.kernel_frame+=1;}else if f==2 {bad.adapter_depth+=1;}else if f==3 {bad.adapter_frame+=1;}
  else if f==4 {bad.wrapper_depth+=1;}else if f==5 {bad.wrapper_span+=1;}else if f==6 {bad.adapter_local+=1;}else {bad.reserved-=1;}
  assert(!frame_contract::verify(p,module,target,bad));}
 for i in 5 {var bad=plan;bad.slots[i].offset=4294967295;assert(!frame_contract::verify(p,module,target,bad));
  var bad2=plan;bad2.slots[i].size=4294967295;assert(!frame_contract::verify(p,module,target,bad2));}
 var ranges=frame_contract::slots();ranges[0].size=4294967295;assert(!frame_contract::geometry(ranges,4294967295));
 ranges=frame_contract::slots();ranges[1].offset=20;assert(!frame_contract::geometry(ranges,768));
 // Zero-sized Unit slots are empty even inside a nonempty neighbor.
 var units=frame_contract::slots();units[1].offset=4;units[1].size=0;assert(frame_contract::geometry(units,768));

 for top in [0 as u32,1,3328,3329,4096,4294967295] {let next,good=frame_contract::reserve(4096,top,768);
  assert(good==(top<=3328));if good {assert(next==top+768);}else {assert(next==top);}}
 let x,ok1=frame_contract::reserve(4294967295,4294967295,1);assert(!ok1 && x==4294967295);
 let y,ok2=frame_contract::reserve(4294967295,4294967294,1);assert(ok2 && y==4294967295);
 assert(!frame_contract::verify(p,"wrong",target,plan));var bad=copy(target);bad[bad.len-1]^=1;assert(!frame_contract::verify(p,module,bad,plan));
 assert(write_file("private-invoke.wasm",target));print("conditional exact-source fixed frame plan passed");
}
