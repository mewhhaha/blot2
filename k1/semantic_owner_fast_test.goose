import std;
import semantic_owner;
import semantic_owner_fast;
import semantic_leaf;
fn compare(s:u8[:],o:semantic_owner::Owner&) {
 for depth in [0 as u32,125 as u32,126 as u32,128 as u32] {for frame in [0 as u32,7 as u32,4294967295 as u32] {
  let a=semantic_owner::emit("pkg","src/main.blot","f",s,o,depth,128,frame,4294967295);
  let b=semantic_owner_fast::emit("pkg","src/main.blot","f",s,o,depth,128,frame,4294967295);
  assert(a.status==b.status && a.wasm[..]==b.wasm[..]);if a.status!=0 {assert(a.wasm.len==0 && b.wasm.len==0);}
 }}
}
fn test(s:u8[:]) {
 var built=semantic_owner::build("pkg","src/main.blot","f",s);assert(built.status==0);compare(s,built.owner);
 let target=semantic_owner_fast::emit("pkg","src/main.blot","f",s,built.owner,0,128,0,4294967295);assert(target.status==0 && semantic_owner::verify("pkg","src/main.blot","f",s,built.owner,target.wasm));
 for k in target.wasm.len {var bad=copy(target.wasm);bad[k]^=1;assert(!semantic_owner::verify("pkg","src/main.blot","f",s,built.owner,bad));assert(!semantic_owner::verify("pkg","src/main.blot","f",s,built.owner,target.wasm[..k]));}
 for k in s.len {var bad:u8[>..]=[];bad.append(s);bad[k]^=1;compare(bad,built.owner);}
 for i in 13 {var bad=copy(built.owner);if i==0 {bad.origin.package[0]^=1;}else if i==1 {bad.origin.module[0]^=1;}else if i==2 {bad.origin.declaration[0]^=1;}else if i==3 {bad.origin.bytes[0]^=1;}else if i==4 {bad.origin.fingerprint[0]^=1;}else if i==5 {bad.core.effects=1;}else if i==6 {bad.core.declared_depth+=1;}else if i==7 {bad.core.declared_frame+=1;}else if i==8 {bad.core.actual_depth+=1;}else if i==9 {bad.core.actual_frame+=1;}else if i==10 {bad.core.loops+=1;}else if i==11 {bad.core.program.types[0]=9;}else {bad.core.program.tree.nodes[0].tag=999;}compare(s,bad);}
}
fn main() {
 test("pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  return x\n");
 test("pub let f: Bool -> U32 ! {} resources {depth: 3, frame: 7} = fn x => do:\n  let total = for i in 0..3 carry (a=0) do:\n    if x:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n");
 let a="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";
 let b="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return 0\n";
 var x=semantic_owner::build("pkg","src/main.blot","f",a);var y=semantic_owner::build("pkg","src/main.blot","f",b);assert(x.status==0 && y.status==0);
 compare(a,y.owner);compare(b,x.owner);
 let ax=semantic_owner_fast::emit("pkg","src/main.blot","f",a,x.owner,0,128,0,0);let by=semantic_owner_fast::emit("pkg","src/main.blot","f",b,y.owner,0,128,0,0);
 assert(ax.status==0 && by.status==0 && !semantic_owner::verify("pkg","src/main.blot","f",a,x.owner,by.wasm) && !semantic_owner::verify("pkg","src/main.blot","f",b,y.owner,ax.wasm));
 print("fused owner parity, forgery and complete target mutation passed");
}
