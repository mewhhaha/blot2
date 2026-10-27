import typed_canonical_frontend;
import typed_canonical_wasm;
import leaf_resource_build;
import leaf_resource_admit;
fn main(){
 let s="pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 12} = fn x => do:\n  return x\n";
 let other="pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 12} = fn x => do:\n  return U32.wrapping_add(x,1)\n";
 var p=typed_canonical_frontend::parse(s);var o=typed_canonical_frontend::parse(other);assert(p.status==0 && o.status==0);let b=typed_canonical_wasm::emit(s,p.program);let ob=typed_canonical_wasm::emit(other,o.program);var r=leaf_resource_build::build(s,p.program,b);var ro=leaf_resource_build::build(other,o.program,ob);assert(r.status==0 && ro.status==0);
 let nums:u32[]=[0,1,2,3,11,12,13,125,126,127,128,129,4294967294,4294967295];
 for used in nums {for lim in nums {let a=leaf_resource_admit::admit(s,p.program,b,r.summary,used,lim,0,12);let ok=lim<=128 && used<=lim && 3<=lim-used;assert(a.status==(if ok {0} else {2}));assert((a.wasm.len>0)==ok);}}
 for used in nums {for lim in nums {let a=leaf_resource_admit::admit(s,p.program,b,r.summary,0,3,used,lim);let ok=used<=lim && 12<=lim-used;assert(a.status==(if ok {0} else {3}));assert((a.wasm.len>0)==ok);}}
 let a=leaf_resource_admit::admit(s,p.program,ob,r.summary,0,128,0,4294967295);assert(a.status==1 && a.wasm.len==0);
 let c=leaf_resource_admit::admit(s,p.program,b,ro.summary,0,128,0,4294967295);assert(c.status==1 && c.wasm.len==0);
 let d=leaf_resource_admit::admit(s,o.program,ob,ro.summary,0,128,0,4294967295);assert(d.status==1 && d.wasm.len==0);
 let both=leaf_resource_admit::admit(s,p.program,b,r.summary,3,3,1,0);assert(both.status==2 && both.wasm.len==0);
 print("independent capacity matrix, exact cross-source/target rejection and failure priority passed");
}
