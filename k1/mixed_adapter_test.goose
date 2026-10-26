import std;
import os;
import compiler_frontend;
import compiler_validate;
import compiler_wasm;
fn accept(s:u8[:],id:i64) {
 var r=compiler_frontend::parse(s);if r.status!=0 {print("rejected ",r.status,": ",s);}assert(r.status==0 && r.program.variant==3 && compiler_validate::verify(s,r.program));
 let bytes=compiler_wasm::emit(s,r.program);assert(bytes.len>0 && write_file(str("mix",id,".wasm"),bytes));
 assert(!compiler_validate::verify("different",r.program) && compiler_wasm::emit("different",r.program).len==0);
 for i in r.program.mixed.body.nodes.len {for f in 11 {let save=r.program.mixed.body.nodes[i];
 if f==0 {r.program.mixed.body.nodes[i].tag+=1;}else if f==1 {r.program.mixed.body.nodes[i].start+=1;}else if f==2 {r.program.mixed.body.nodes[i].end+=1;}else if f==3 {r.program.mixed.body.nodes[i].a+=1;}else if f==4 {r.program.mixed.body.nodes[i].b+=1;}else if f==5 {r.program.mixed.body.nodes[i].c+=1;}else if f==6 {r.program.mixed.body.nodes[i].d+=1;}else if f==7 {r.program.mixed.body.nodes[i].e+=1;}else if f==8 {r.program.mixed.body.nodes[i].f+=1;}else if f==9 {r.program.mixed.body.nodes[i].g+=1;}else {r.program.mixed.body.nodes[i].target+=1;}
 assert(!compiler_validate::verify(s,r.program) && compiler_wasm::emit(s,r.program).len==0);r.program.mixed.body.nodes[i]=save;}}
 for i in r.program.mixed.body.bindings.len {for f in 4 {let save=r.program.mixed.body.bindings[i];if f==0 {r.program.mixed.body.bindings[i].start+=1;}else if f==1 {r.program.mixed.body.bindings[i].end+=1;}else if f==2 {r.program.mixed.body.bindings[i].kind+=1;}else {r.program.mixed.body.bindings[i].scope+=1;}assert(!compiler_validate::verify(s,r.program));r.program.mixed.body.bindings[i]=save;}}
}
fn reject(s:u8[:]) {let r=compiler_frontend::parse(s);if r.status==0 {print("unexpected accept: ",s);}assert(r.status!=0);}
fn main() {
 accept("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,i))\n  return sum\n",0);
 accept("let f: U32 -> U32 = fn x => do:\n  let z = 2 + 3\n  let sum = for i in 0..x carry (a=z) do:\n    let n = U32.wrapping_add(a, i)\n    if i < 2:\n      next (n)\n    else:\n      stop (U32.wrapping_add(n, 1))\n  return U32.wrapping_add(sum, x)\n",1);
 accept("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    let part = for j in 0..2 carry (b=a) do:\n      next (U32.wrapping_add(b, i))\n    next (part)\n  return sum + 0\n",2);
 reject("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    next (a + 1)\n  return sum\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    next (4294967295 + 1)\n  return sum\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=i) do:\n    next (a)\n  return sum\n");
 reject("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    continue\n  return i\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    if i:\n      next (a)\n    else:\n      stop (a)\n  return sum\n");
 print("mixed scalar and loop source/Core tests passed");
}
