import std;
import os;
import unified_frontend;
import unified_guard;
import unified_check;
import unified_wasm;

fn accepted(s:u8[:], i:i64) {
    var p=unified_frontend::parse(s);
    if p.status!=0 {print("unexpected rejection ",p.status," ",s);}
    assert(p.status==0 && unified_guard::check(s,p.program).status==0);
    let out=unified_wasm::emit(s,p.program);
    assert(out.len>0 && write_file(str("cache_audit_",i,".wasm"),out));
    // A source-bound recognizer must reject changed parameter identities and
    // altered graph fields, not just a forged evidence record.
    for n in p.program.nodes.len {
        let before=p.program.nodes[n];
        if before.tag==1 {p.program.nodes[n].a=128;assert(!unified_check::verify(s,p.program));}
        else if before.tag==14 {p.program.nodes[n].b=0;assert(!unified_check::verify(s,p.program));}
        else if before.tag==16 {p.program.nodes[n].a=0;assert(!unified_check::verify(s,p.program));}
        p.program.nodes[n]=before;
    }
    let first=p.program.source[0];p.program.source[0]^=1;
    assert(!unified_check::verify(s,p.program));p.program.source[0]=first;
}
fn rejected(s:u8[:]) {
    let result=unified_frontend::parse(s);
    if result.status==0 {print("unexpected acceptance ",s);}
    assert(result.status!=0 && result.program.nodes.len==0);
}
fn main() {
    accepted("let f: U32 -> U32 = fn x => do:\n  let a = x\n  let b = a\n  if b < 4294967295:\n    return 1 + a\n  return x\n",0);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = x\n    if y < 4294967295:\n      return 1 + y\n    else:\n      return x\n  return x\n",1);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = U32.wrapping_add(x,1)\n    if y < 4294967295:\n      return y + 1\n    return x\n  return x\n",2);
    accepted("let f: U32 -> U32 = fn x => do:\n  return 4294967294 + 1\n",3);
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  else:\n    return x + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = x\n    return y + 1\n  else:\n    let y = U32.wrapping_add(x,1)\n    return y + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = U32.wrapping_add(x,1)\n    return y + 1\n  return x\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295 || #True:\n    return x + 1\n  return x\n");
    accepted("let f: U32 -> U32 = fn x => do:\n  if #False && x < 4294967295:\n    return x + 1\n  return x\n",4);
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let y = x\n    return y\n  return y + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  return 4294967295 + 1\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  return 4294967296\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  return 18446744073709551616\n");
    print("independent unified branch and exact-value audit passed");
}
