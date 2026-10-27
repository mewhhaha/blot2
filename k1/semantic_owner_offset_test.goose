import std;
import os;
import semantic_owner;
fn main() {
 let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    return x + 5\n  return x\n";
 var r=semantic_owner::build("pkg","src/main.blot","f",s);assert(r.status==0);
 let output=semantic_owner::emit("pkg","src/main.blot","f",s,r.owner,0,1,0,0);assert(output.status==0 && semantic_owner::verify("pkg","src/main.blot","f",s,r.owner,output.wasm));
 assert(write_file("semantic-owner-offset.wasm",output.wasm));
 let bad="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967291:\n    return x + 5\n  return x\n";
 assert(semantic_owner::build("pkg","src/main.blot","f",bad).status!=0);
 assert(!semantic_owner::verify("pkg","src/main.blot","f",bad,r.owner,output.wasm));
 print("semantic owner guarded offset cross-check passed");
}
