import std;
import os;
import i08_job_wasm;
import i08_link_build;
import i08_link_verify;
import i08_affine_build;
import i08_affine_verify;
import i08_transition_build;
import i08_transition_verify;
fn source(body:u8[:])->u8[] {var s:u8[>..]=[];s.append("pub let project: forall [r: Region, s: Region, n: Nat, c: Nat, d: Domain] => Fn[static, Many, (View[r,{x:F32,y:F32,vx:F32,vy:F32},n,d], F32, Builder[s,{x:F32,y:F32},0,c,Append]), exists [e: Domain] => View[s,{x:F32,y:F32},n,e]] ! {read r, write s} requires [Le(n,c)] resources {depth: 2, frame: 256} = fn (source,dt,initial) => do:\n");s.append(body);return s;}
fn main() {
 let s=source("  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x + source[i].vx * dt, y: source[i].y + source[i].vy * dt}))\n  return builder.freeze(built)\n");
 var p,status=i08_link_build::build(s);if status!=0 {print("link status ",status);}assert(status==0 && i08_link_verify::verify(p,s));
 let a=i08_affine_build::build(p.tree,s);assert(a.status==0 && i08_affine_verify::verify(p.tree,s,a.plan));
 let e=i08_transition_build::build(p,s,a.plan);assert(e.status==0 && i08_transition_verify::verify(p,s,a.plan,e.proof));
 let wasm=i08_job_wasm::emit(p.cap.job,s);assert(wasm.len>0 && write_file("transition.wasm",wasm));
 for i in 6 {for f in 13 {var q=e.proof;let old=q.steps[i];
 if f==0 {q.steps[i].kind+=1;}else if f==1 {q.steps[i].node+=1;}else if f==2 {q.steps[i].site+=1;}
 else if f==3 {q.steps[i].subject+=1;}else if f==4 {q.steps[i].version+=1;}else if f==5 {q.steps[i].result+=1;}else if f==6 {q.steps[i].result_version+=1;}
 else if f==7 {q.steps[i].index+=1;}else if f==8 {q.steps[i].nat+=1;}else if f==9 {q.steps[i].capacity+=1;}
 else if f==10 {q.steps[i].dep1+=1;}else if f==11 {q.steps[i].dep2+=1;}else {q.steps[i].dep3+=1;}
 assert(!i08_transition_verify::verify(p,s,a.plan,q));q.steps[i]=old;}}
 for i in p.cap.job.events.len {for f in 5 {let old=p.cap.job.events[i];if f==0 {p.cap.job.events[i].symbol+=1;}else if f==1 {p.cap.job.events[i].version+=1;}else if f==2 {p.cap.job.events[i].output+=1;}else if f==3 {p.cap.job.events[i].output_version+=1;}else {p.cap.job.events[i].site+=1;}assert(!i08_transition_verify::verify(p,s,a.plan,e.proof));p.cap.job.events[i]=old;}}
 for i in 6 {for f in 9 {let old=p.cap.job.core.proofs[i];if f==0 {p.cap.job.core.proofs[i].rule+=1;}else if f==1 {p.cap.job.core.proofs[i].owner+=1;}
 else if f==2 {p.cap.job.core.proofs[i].left+=1;}else if f==3 {p.cap.job.core.proofs[i].right+=1;}else if f==4 {p.cap.job.core.proofs[i].version+=1;}
 else if f==5 {p.cap.job.core.proofs[i].dep1+=1;}else if f==6 {p.cap.job.core.proofs[i].dep2+=1;}else if f==7 {p.cap.job.core.proofs[i].dep3+=1;}else {p.cap.job.core.proofs[i].site+=1;}
 assert(!i08_transition_verify::verify(p,s,a.plan,e.proof));p.cap.job.core.proofs[i]=old;}}
 var wrong=a.plan;wrong.index+=1;assert(!i08_transition_verify::verify(p,s,wrong,e.proof));assert(!i08_transition_verify::verify(p,"other",a.plan,e.proof));
 for body in [
 "  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      stop (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n",
 "  let built = for i in 0..c carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n",
 "  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),0)] do:\n      next (builder.append(b,{x: source[i].x,y:source[i].y}))\n  return builder.freeze(built)\n",
 "  let built = for i in 0..n carry (b=initial)\n    invariant [Eq(Init(b),i)] do:\n      return builder.freeze(b)\n  return builder.freeze(built)\n"
 ] {let bad=source(body);var candidate,st=i08_link_build::build(bad);if st==0 {let badplan=i08_affine_build::build(candidate.tree,bad);assert(badplan.status!=0);}}
 print("source-linked conditional invariant and completion proof passed");
}
