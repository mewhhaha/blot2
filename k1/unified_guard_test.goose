import std;
import os;
import unified_frontend;
import unified_guard;
import unified_wasm;
fn accepted(s:u8[:],i:i64) {
    var r=unified_frontend::parse(s);if r.status!=0 {print("unexpected status ",r.status," ",s);}assert(r.status==0);
    let q=unified_guard::check(s,r.program);assert(q.status==0 && q.evidence.len>0);
    let bytes=unified_wasm::emit(s,r.program);assert(bytes.len>0 && write_file(str("guard_",i,".wasm"),bytes));
    for k in r.program.nodes.len {
        let old=r.program.nodes[k];r.program.nodes[k].tag=999;
        assert(unified_guard::check(s,r.program).status!=0 && unified_wasm::emit(s,r.program).len==0);r.program.nodes[k]=old;
    }
}
fn rejected(s:u8[:]) {let r=unified_frontend::parse(s);if r.status!=5 {print("unexpected status ",r.status," ",s);}assert(r.status==5 && r.program.nodes.len==0);}
fn main() {
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",0);
    accepted("let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y < 4294967295:\n    return x + 1\n  else:\n    return x\n",1);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = x\n    return y + 1\n  else:\n    return x\n",2);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    if x < 10:\n      return x + 1\n    return x + 1\n  return x\n",3);
    accepted("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 4294967295:\n    return y + 1\n  return x\n",4);
    rejected("let f: U32 -> U32 = fn x => do:\n  return x + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x\n  else:\n    return x + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x\n  return x + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = U32.wrapping_add(x,1)\n    return y + 1\n  else:\n    return x\n");
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 && #True:\n    return x + 1\n  return x\n",5);
    let a="let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n";
    let b="let f: U32 -> U32 = fn x => do:\n  if x < 4294967294:\n    return x + 1\n  return x\n";
    var r=unified_frontend::parse(a);assert(r.status==0 && a.len==b.len && unified_guard::check(b,r.program).status!=0 && unified_wasm::emit(b,r.program).len==0);
    print("scoped successor proof source and aliases passed");
}
