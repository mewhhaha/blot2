import m12_adapter_schema;
import m12_adapter_build;
import m12_internal_emit;
import frame_contract;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}

fn oracle(a:frame_contract::Slot[5],limit:u32)->bool {
 for x,i in a {
  let x0=x.offset as u64;let x1=x0+x.size as u64;
  if x0>limit || x1>limit || x.offset%4!=0 || x.size%4!=0{return false;}
  for y,j in a {if j>=i || x.size==0 || y.size==0 {continue;}
   let y0=y.offset as u64;let y1=y0+y.size as u64;if x0<y1 && y0<x1{return false;}}
 }return true;
}
fn main(){
 var state:u64=1234567;
 for i in 10000 {var a:frame_contract::Slot[5]=[frame_contract::Slot {};5];
  for j in 5 {state=(state*1664525+1013904223)&4294967295;let at=((state%257)*4) as u32;
   state=(state*1664525+1013904223)&4294967295;let size=((state%17)*4) as u32;a[j]=frame_contract::Slot {offset:at,size:size};}
  assert(frame_contract::geometry(a,1024)==oracle(a,1024));
 }
 let k=kernel();let adapter=m12_adapter_schema::source();var source:u8[>..]=[];source.append(k);source.append(adapter);
 var p,status=m12_adapter_build::build(k,adapter);assert(status==0);let target=m12_internal_emit::emit(p,source);assert(target.len>0);
 let plan,valid=frame_contract::create(p,source,target);assert(valid && !plan.qualified);
 var q=plan;q.qualified=true;assert(!frame_contract::verify(p,source,target,q));
 var z=plan;z.fixed_frontier=4;assert(!frame_contract::verify(p,source,target,z));
 var n=plan;n.machine_path=5;assert(!frame_contract::verify(p,source,target,n));
 print("independent frame geometry and unqualified-bound controls passed");
}
