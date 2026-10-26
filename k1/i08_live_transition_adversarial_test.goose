// Private source→target gate. Its result is used only inside the private
// Wasm authority fixture; actual K1 capabilities/loans and ABI remain absent.
import os;
import i08_link_build;
import i08_link_verify;
import i08_link_affine;
import i08_link_core;
import i08_affine_core;
import i08_transition_core;
import i08_transition_build;
import i08_transition_verify;
import i08_same_wasm;
import i08_same_target;
fn source(x:u8[:],y:u8[:])->u8[] {
    var out:u8[>..]=[];
    out.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n  let built = for i in 0..n carry (b = initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b, {x: ");
    out.append(x);out.append(", y: ");out.append(y);out.append("}))\n  return builder.freeze(built)\n");return out;
}


// Private test gate. Numeric roles and conditional evidence are not a live
// loan, backend authority, host ABI or C09 receipt.
fn checked_emit(linked:i08_link_core::Program&,text:u8[:],plan:i08_affine_core::Plan,proof:i08_transition_core::Proof)->u8[] {
 if !i08_link_affine::verify(linked,text,plan) || !i08_transition_verify::verify(linked,text,plan,proof) {return [];}
 let target=i08_same_wasm::emit(linked.cap.job.core,text,linked.cap.job.core.context);
 if target.len==0 || !i08_same_target::verify(linked.cap.job.core,text,linked.cap.job.core.context,target) {return [];}
 return target;
}


fn main() {
 let text=source("source[i].x + source[i].vx * dt","source[i].y + source[i].vy * dt");
 var linked,status=i08_link_build::build(text);assert(status==0 && i08_link_verify::verify(linked,text));
 let affine=i08_link_affine::build(linked,text);assert(affine.status==0 && i08_link_affine::verify(linked,text,affine.plan));
 var forged=affine.plan;forged.append+=1;assert(!i08_link_affine::verify(linked,text,forged));
 let proof=i08_transition_build::build(linked,text,affine.plan);assert(proof.status==0 && i08_transition_verify::verify(linked,text,affine.plan,proof.proof));
 for i in 6 {for f in 13 {var bad=proof.proof;
  if f==0 {bad.steps[i].kind+=1;}else if f==1 {bad.steps[i].node+=1;}else if f==2 {bad.steps[i].site+=1;}
  else if f==3 {bad.steps[i].subject+=1;}else if f==4 {bad.steps[i].version+=1;}else if f==5 {bad.steps[i].result+=1;}else if f==6 {bad.steps[i].result_version+=1;}
  else if f==7 {bad.steps[i].index+=1;}else if f==8 {bad.steps[i].nat+=1;}else if f==9 {bad.steps[i].capacity+=1;}
  else if f==10 {bad.steps[i].dep1+=1;}else if f==11 {bad.steps[i].dep2+=1;}else {bad.steps[i].dep3+=1;}
  assert(checked_emit(linked,text,affine.plan,bad).len==0);
 }}
 assert(checked_emit(linked,"wrong",affine.plan,proof.proof).len==0);

 for f in 16 {for v in [-1,0,999999] {var bad=affine.plan;if f==0 {bad.initial=v;}else if f==1 {bad.view=v;}else if f==2 {bad.nat=v;}else if f==3 {bad.capacity=v;}else if f==4 {bad.loop_id=v;}else if f==5 {bad.index=v;}else if f==6 {bad.carry_id=v;}else if f==7 {bad.result=v;}else if f==8 {bad.carry_node=v;}else if f==9 {bad.invariant_id=v;}else if f==10 {bad.next_node=v;}else if f==11 {bad.append=v;}else if f==12 {bad.row=v;}else if f==13 {bad.freeze=v;}else if f==14 {bad.return_node=v;}else {bad.root=v;}assert(checked_emit(linked,text,bad,proof.proof).len==0);}}
 for i in linked.tree.nodes.len {for f in 4 {let old=linked.tree.nodes[i];if f==0 {linked.tree.nodes[i].start=-1;}else if f==1 {linked.tree.nodes[i].a=999999;}else if f==2 {linked.tree.nodes[i].b=999999;}else {linked.tree.nodes[i].target=999999;}assert(checked_emit(linked,text,affine.plan,proof.proof).len==0);linked.tree.nodes[i]=old;}}
 for i in linked.cap.steps.len {let old=linked.cap.steps[i];linked.cap.steps[i].kind+=1;assert(checked_emit(linked,text,affine.plan,proof.proof).len==0);linked.cap.steps[i]=old;}
 for i in linked.cap.job.events.len {let old=linked.cap.job.events[i];linked.cap.job.events[i].output_version+=1;assert(checked_emit(linked,text,affine.plan,proof.proof).len==0);linked.cap.job.events[i]=old;}
 let target=checked_emit(linked,text,affine.plan,proof.proof);assert(target.len>0);
 assert(write_file("live-worker.wasm",target));
 print("private source/capability trace to live Wasm target passed");
}
