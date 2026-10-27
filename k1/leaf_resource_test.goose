import std;import os;
import typed_canonical_frontend;import typed_canonical_wasm;import leaf_resource_core;import leaf_resource_build;import leaf_resource_verify;import leaf_resource_admit;
fn check(source:u8[:],which:i64,depth:u32,frame:u32,loops:u32) {
 var p=typed_canonical_frontend::parse(source);assert(p.status==0);let target=typed_canonical_wasm::emit(source,p.program);assert(target.len>0);
 var r=leaf_resource_build::build(source,p.program,target);assert(r.status==0 && r.summary.declared_depth==depth && r.summary.declared_frame==frame && r.summary.body_depth==1 && r.summary.body_frame==0 && r.summary.loops==loops);assert(leaf_resource_verify::verify(source,p.program,target,r.summary));assert(!leaf_resource_verify::public_eligible(source,p.program,target,r.summary));
 let ok=leaf_resource_admit::admit(source,p.program,target,r.summary,0,depth,0,frame);assert(ok.status==0 && ok.wasm[..]==target);
 var changed=copy(target);let owned=leaf_resource_admit::admit(source,p.program,changed,r.summary,0,depth,0,frame);assert(owned.status==0);changed[0]^=1;assert(owned.wasm[..]==target && owned.wasm[..]!=changed[..]);
 var forged_tree=copy(p.program);forged_tree.tree.nodes[0].tag=999;let ft=leaf_resource_admit::admit(source,forged_tree,target,r.summary,0,128,0,4294967295);assert(ft.status==1 && ft.wasm.len==0);
 let exact=leaf_resource_admit::admit(source,p.program,target,r.summary,128-depth,128,4294967295-frame,4294967295);assert(exact.status==0 && exact.wasm[..]==target);
 let short=leaf_resource_admit::admit(source,p.program,target,r.summary,129-depth,128,0,frame);assert(short.status==2 && short.wasm.len==0);
 let d=leaf_resource_admit::admit(source,p.program,target,r.summary,0,depth-1,0,frame);assert(d.status==2 && d.wasm.len==0);
 let d2=leaf_resource_admit::admit(source,p.program,target,r.summary,4294967295,128,0,frame);assert(d2.status==2 && d2.wasm.len==0);
 let d3=leaf_resource_admit::admit(source,p.program,target,r.summary,0,129,0,frame);assert(d3.status==2 && d3.wasm.len==0);
 if frame>0 {let f=leaf_resource_admit::admit(source,p.program,target,r.summary,0,depth,0,frame-1);assert(f.status==3 && f.wasm.len==0);}
 let f2=leaf_resource_admit::admit(source,p.program,target,r.summary,0,depth,4294967295,0);assert(f2.status==3 && f2.wasm.len==0);
 let f3=leaf_resource_admit::admit(source,p.program,target,r.summary,0,depth,1,4294967295);if frame==4294967295 {assert(f3.status==3 && f3.wasm.len==0);}else {assert(f3.status==0);}
 for k in 6 {var forged=copy(r.summary);if k==0 {forged.source[0]^=1;}else if k==1 {forged.declared_depth+=1;}else if k==2 {forged.declared_frame^=1;}else if k==3 {forged.body_depth+=1;}else if k==4 {forged.body_frame+=1;}else {forged.loops+=1;}let bad=leaf_resource_admit::admit(source,p.program,target,forged,0,128,0,4294967295);assert(bad.status==1 && bad.wasm.len==0);}
 for k in target.len {var bad=copy(target);bad[k]^=1;let x=leaf_resource_admit::admit(source,p.program,bad,r.summary,0,128,0,4294967295);assert(x.status==1 && x.wasm.len==0);let y=leaf_resource_admit::admit(source,p.program,target[..k],r.summary,0,128,0,4294967295);assert(y.status==1 && y.wasm.len==0);}
 assert(leaf_resource_admit::admit("wrong",p.program,target,r.summary,0,128,0,4294967295).status==1);
 assert(write_file(str("leaf-resource-",which,".wasm"),ok.wasm));
}
fn main(){
 check("pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 12} = fn x => do:\n  return x\n",0,3,12,0);
 check("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    let small = i < 5\n    if small:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n",1,1,0,1);
 check("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4294967295} = fn x => do:\n  return x\n",2,1,4294967295,0);
 for invalid in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return call(x)\n","pub let f: U32 -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n","pub let f: U32 -> U32 ! {} resources {depth: 0, frame: 0} = fn x => do:\n  return x\n"] {let p=typed_canonical_frontend::parse(invalid);assert(p.status!=0);}
 print("source/target-bound scalar leaf resource preflight passed");
}
