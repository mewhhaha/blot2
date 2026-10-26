import std;
import os;
import unified_frontend;
import unified_check;
import unified_wasm;

fn accepted(source:u8[:],index:i64) {
    var r=unified_frontend::parse(source);
    if r.status!=0 {print("unexpected rejection ",r.status," for ",source);}
    assert(r.status==0 && unified_check::verify(source,r.program));
    let bytes=unified_wasm::emit(source,r.program);assert(bytes.len>0 && write_file(str("unified_",index,".wasm"),bytes));
    assert(unified_wasm::emit("different source",r.program).len==0);
    for i in r.program.nodes.len {
        let old=r.program.nodes[i];r.program.nodes[i].tag=999;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
        r.program.nodes[i].a=-1;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
        r.program.nodes[i].b=9999999;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
        r.program.nodes[i].c=-1;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
        r.program.nodes[i].ty=99;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
        r.program.nodes[i].literal ^= 1;assert(!unified_check::verify(source,r.program));r.program.nodes[i]=old;
    }
    for i in r.program.bindings.len {let old=r.program.bindings[i];r.program.bindings[i].start=-1;assert(!unified_check::verify(source,r.program));r.program.bindings[i]=old;}
}
fn reject(source:u8[:],status:i64) {let r=unified_frontend::parse(source);if r.status!=status {print("status ",r.status," expected ",status," for ",source);}assert(r.status==status && r.program.nodes.len==0);}
fn probe(source:u8[:],path:u8[:]) {
    var r=unified_frontend::parse(source);assert(r.status==0 && unified_check::verify(source,r.program));
    var rhs:i64=0;for n in r.program.nodes {if n.tag==12 || n.tag==13 {rhs=n.b;}}
    assert(rhs>0);let b=unified_wasm::probe(source,r.program,rhs);assert(b.len>0 && write_file(path,b));
}
fn main() {
    accepted("let f: U32 -> U32 = fn x => do:\n  let y = x + 0\n  return y\n",0);
    accepted("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 10 && #True:\n    let z = U32.wrapping_mul(y,2)\n    if z < 4:\n      return z\n    else:\n      return y\n  else:\n    let z = U32.wrapping_sub(y,1)\n    return z\n",1);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 10:\n    let t = 11\n    return t\n  else:\n    let t = 22\n    return t\n",2);
    accepted("let f: U32 -> U32 = fn x => do:\n  if #True:\n    return x\n",3);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 20:\n    let v = U32.wrapping_add(x,1)\n    if x < 5:\n      return v\n    return x\n  return 99\n",4);
    accepted("let f: U32 -> U32 = fn x => do:\n  if (x < 2 || x < 4) && #True:\n    return x & 15\n  else:\n    return 4294967295\n",5);
    reject("let f: U32 -> U32 = fn x => do:\n  if x < 10:\n    let t = 1\n  return t\n",3);
    reject("let f: U32 -> U32 = fn x => do:\n  let a = a\n  return a\n",3);
    reject("let f: U32 -> U32 = fn x => do:\n  let x = 1\n  return x\n",4);
    reject("let f: U32 -> U32 = fn x => do:\n  return x + 1\n",5);
    reject("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,1) + 1\n",5);
    reject("let f: U32 -> U32 = fn x => do:\n  if x:\n    return 1\n  else:\n    return 2\n",6);
    reject("let f: U32 -> U32 = fn x => do:\n  return #True\n",6);
    reject("let f: U32 -> U32 = fn x => do:\n  if x < 10:\n    return x\n",7);
    reject("let f: U32 -> U32 = fn x => do:\n  return x\n  return x\n",8);
    reject("let f: U32 -> U32 = fn x => do:\n  return 1.0\n",1);
    let a="let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,1)\n";
    let b="let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,2)\n";
    var owned=unified_frontend::parse(a);assert(owned.status==0 && a.len==b.len && !unified_check::verify(b,owned.program) && unified_wasm::emit(b,owned.program).len==0);
    probe("let f: U32 -> U32 = fn x => do:\n  if x < 10 && #True:\n    return 1\n  else:\n    return 2\n","unified_and_probe.wasm");
    probe("let f: U32 -> U32 = fn x => do:\n  if x < 10 || #False:\n    return 1\n  else:\n    return 2\n","unified_or_probe.wasm");
    print("private unified source/Core/flow laws passed");
}
