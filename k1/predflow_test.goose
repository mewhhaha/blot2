import std;
import os;
import predflow_frontend;
import predflow_shape;
import predflow_guard;
import predflow_proof;
import predflow_check;
import predflow_wasm;
fn yes(s:u8[:],i:i64) {var r=predflow_frontend::parse(s);if r.status!=0 {print("source status ",r.status," ",s);}assert(r.status==0 && predflow_shape::verify(s,r.program) && predflow_check::verify(s,r.program));let out=predflow_wasm::emit(s,r.program);assert(out.len>0 && write_file(str("predflow-",i,".wasm"),out));
 let proof=predflow_guard::check(s,r.program);assert(proof.status==0 && predflow_proof::verify_evidence(s,r.program,proof.evidence));
 for n in r.program.nodes.len {var bad=copy(r.program);bad.nodes[n].start=-1;assert(!predflow_check::verify(s,bad) && predflow_wasm::emit(s,bad).len==0);}
 for n in r.program.bindings.len {var bad=copy(r.program);bad.bindings[n].start=-1;assert(!predflow_check::verify(s,bad));}
 assert(!predflow_check::verify("wrong",r.program));}
fn no(s:u8[:]) {let r=predflow_frontend::parse(s);if r.status==0 {print("unexpected acceptance ",s);}assert(r.status!=0 && r.program.source.len==0);}
fn main(){
 yes("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n",0);
 yes("let f: U32 -> Bool = fn x => do:\n  if x <= 4294967294:\n    return (x + 1) < 100\n  return #False\n",1);
 yes("let f: U32 -> Bool = fn x => do:\n  return #False && (x + 1) < 100\n",2);
 yes("let f: U32 -> Bool = fn x => do:\n  return #True || (x + 1) < 100\n",3);
 no("let f: U32 -> Bool = fn x => do:\n  return (x + 1) < 100\n");
 no("let f: U32 -> Bool = fn x => do:\n  return x < 4294967295 || (x + 1) < 100\n");
 no("let f: U32 -> Bool = fn x => do:\n  return #False || (x + 1) < 100\n");
 no("let f: U32 -> Bool = fn x => do:\n  return x\n");
 no("let f: U32 -> Bool = fn x => do:\n  let y = x < 1\n  return #True\n");
 no("let f: U32 -> Bool = fn x => do:\n  if #False:\n    return missing < 1\n  return #True\n");
 print("private Bool-result lexical scalar source/proof passed");}
