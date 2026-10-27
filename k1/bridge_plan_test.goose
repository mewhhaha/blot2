import std;
import m12_adapter_schema;
import m12_adapter_build;
import m12_adapter_verify;
fn kernel()->u8[] {return "pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n";}
fn replace(s:u8[:],a:u8[:],b:u8[:])->u8[] {var out:u8[>..]=[];var i:i64=0;var found=false;while i<s.len {if !found && a.len<=s.len-i && s[i..i+a.len]==a {out.append(b);i+=a.len;found=true;}else {out.push(s[i]);i+=1;}}assert(found);return out;}
import os; import m12_internal_emit; import m12_internal_target;
import bridge_plan_affine;
import bridge_plan_build; import bridge_plan_verify; import bridge_plan_emit;
fn main(){let k=kernel();let a=m12_adapter_schema::source();var p,status=m12_adapter_build::build(k,a);assert(status==0);var src:u8[>..]=[];src.append(k);src.append(a);var plan=bridge_plan_build::build(p,src);assert(plan.status==0 && bridge_plan_verify::verify(p,src,plan.plan));assert(!bridge_plan_verify::public_eligible(p,src,plan.plan));
 let b=bridge_plan_emit::emit(p,src,plan.plan);let reference=m12_internal_emit::emit(p,src);assert(b.len>0 && b==reference && write_file("private-invoke.wasm",b));
 for i in 7 {for j in 4 {let old=plan.plan.branches[i];if j==0 {plan.plan.branches[i].kind+=1;}else if j==1 {plan.plan.branches[i].status^=1;}else if j==2 {plan.plan.branches[i].cleanup+=1;}else {plan.plan.branches[i].phase+=1;}assert(bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.branches[i]=old;}}
 for i in 13 {plan.plan.ops[i]+=1;assert(!bridge_plan_verify::verify(p,src,plan.plan) && bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.ops[i]-=1;}
 plan.plan.ops[10]=12;plan.plan.ops[11]=11;assert(bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.ops[10]=11;plan.plan.ops[11]=12;
 for i in 9 {for k in 8 {let old=plan.plan.cases[i];if k==0 {plan.plan.cases[i].count+=1;}else if k==1 {plan.plan.cases[i].input_start+=1;}else if k==2 {plan.plan.cases[i].input_end+=1;}else if k==3 {plan.plan.cases[i].output_start+=1;}else if k==4 {plan.plan.cases[i].output_end+=1;}else if k==5 {plan.plan.cases[i].result_end+=1;}else if k==6 {plan.plan.cases[i].capacity+=1;}else {plan.plan.cases[i].frontier+=1;}assert(bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.cases[i]=old;}}
 plan.plan.source[0]^=1;assert(bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.source[0]^=1;
 for i in 5 {plan.plan.source_sites[i]+=1;assert(bridge_plan_emit::emit(p,src,plan.plan).len==0);plan.plan.source_sites[i]-=1;}
 assert(bridge_plan_emit::emit(p,"wrong",plan.plan).len==0);
 var st=bridge_plan_affine::State {};assert(!bridge_plan_affine::transition(st,2));assert(bridge_plan_affine::transition(st,1));assert(bridge_plan_affine::transition(st,2));assert(!bridge_plan_affine::transition(st,12));assert(!bridge_plan_affine::transition(st,11));
 var reservation=bridge_plan_affine::State {frame:true};assert(bridge_plan_affine::reserve_failure(reservation));assert(!bridge_plan_affine::reserve_failure(reservation));
 var live=bridge_plan_affine::State {frame:true,owner:true,space:1};assert(!bridge_plan_affine::reserve_failure(live));
 var forged=copy(b);forged[forged.len-1]^=1;assert(!m12_internal_target::verify(p,src,forged));
 let alt=replace(k,"source[i].x + source[i].vx * dt","source[i].vx + source[i].x * dt");var p2,code=m12_adapter_build::build(alt,a);assert(code==0);var src2:u8[>..]=[];src2.append(alt);src2.append(a);let b2=m12_internal_emit::emit(p2,src2);assert(b2.len>0);assert(bridge_plan_emit::emit(p2,src2,plan.plan).len==0);var altplan=bridge_plan_build::build(p2,src2);assert(altplan.status==0 && bridge_plan_emit::emit(p2,src2,altplan.plan)==b2);
 print("source-bound bridge Core drives checked caller emission");}
