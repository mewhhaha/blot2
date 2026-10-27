import predflow_frontend;
import predflow_guard;
import predflow_proof;
import predflow_check;
import predflow_wasm;
fn yes(s:u8[:]) {var r=predflow_frontend::parse(s);if r.status!=0 {print("rejected ",r.status," ",s);}assert(r.status==0 && predflow_check::verify(s,r.program) && predflow_wasm::emit(s,r.program).len>0);let ev=predflow_guard::check(s,r.program);assert(ev.status==0 && predflow_proof::verify_evidence(s,r.program,ev.evidence));for i in s.len {var b:u8[>..]=[];b.append(s);b[i]^=1;assert(!predflow_check::verify(b,r.program) && predflow_wasm::emit(b,r.program).len==0);}for i in r.program.nodes.len {for f in 8 {var b=copy(r.program);if f==0 {b.nodes[i].tag=999;}else if f==1 {b.nodes[i].start= -1;}else if f==2 {b.nodes[i].end=9223372036854775807;}else if f==3 {b.nodes[i].a= -1;}else if f==4 {b.nodes[i].b= -1;}else if f==5 {b.nodes[i].c= -1;}else if f==6 {b.nodes[i].literal^=1;}else {b.nodes[i].ty^=1;}assert(!predflow_check::verify(s,b));}}}
fn no(s:u8[:]) {let r=predflow_frontend::parse(s);assert(r.status!=0 && r.program.source.len==0);}
fn main() {
 yes("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && (x + 1) < y\n");
 yes("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return 4294967294 < y || (x + 1) < 20\n");
 yes("let f: U32 -> Bool = fn x => do:\n  let y = x\n  if y < 4294967295:\n    let z = x + 1\n    return z < 2\n  return #False\n");
 no("let f: U32 -> Bool = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  return x < 4294967295 && (y + 1) < 5\n");
 no("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 || (x + 1) < 5\n");
 no("let f: U32 -> Bool = fn x => do:\n  if x < 4294967295:\n    let y = x\n    if #True:\n      return y < 5\n  return (x + 1) < 5\n");
 no("let f: U32 -> Bool = fn x => do:\n  return #False && missing < 5\n");
 no("let f: U32 -> Bool = fn x => do:\n  return #False && x\n");
 print("independent Bool-return lexical scope, alias, branch and forgery controls passed");
}
