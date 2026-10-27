import std;
import os;
import predflow_frontend;
import predflow_shape;
import predflow_guard;
import predflow_proof;
import predflow_check;
import predflow_wasm;
import predflow_target;
fn yes(s:u8[:],i:i64) {var r=predflow_frontend::parse(s);if r.status!=0 {print("source status ",r.status," ",s);}assert(r.status==0 && predflow_shape::verify(s,r.program) && predflow_check::verify(s,r.program));let out=predflow_wasm::emit(s,r.program);assert(out.len>0 && predflow_target::verify(s,r.program,out) && write_file(str("predflow-",i,".wasm"),out));
 for j in out.len {var bad=copy(out);bad[j]^=1;assert(!predflow_target::verify(s,r.program,bad));assert(!predflow_target::verify(s,r.program,out[..j]));}
 if i==0 {var found:i64=0;for j in out.len-2 {if out[j]==0x41 && out[j+1]==0x7f && out[j+2]==0x49 {var bad=copy(out);bad[j+2]=0x4d;assert(!predflow_target::verify(s,r.program,bad) && write_file("predflow-mutant.wasm",bad));found+=1;}}assert(found==1);}
 let proof=predflow_guard::check(s,r.program);assert(proof.status==0 && predflow_proof::verify_evidence(s,r.program,proof.evidence));
 for n in r.program.nodes.len {var bad=copy(r.program);bad.nodes[n].start=-1;assert(!predflow_check::verify(s,bad) && predflow_wasm::emit(s,bad).len==0);}
 for n in r.program.bindings.len {var bad=copy(r.program);bad.bindings[n].start=-1;assert(!predflow_check::verify(s,bad));}
 assert(!predflow_check::verify("wrong",r.program) && !predflow_target::verify("wrong",r.program,out));}
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
 var long:u8[>..]=[];long.append("let f: U32 -> Bool = fn x => do:\n");for _ in 300 {long.append("  if #False:\n    return #False\n");}long.append("  return x < 1\n");var p=predflow_frontend::parse(long);assert(p.status==0);let b=predflow_wasm::emit(long,p.program);assert(b.len>0 && predflow_target::verify(long,p.program,b));
 print("private Bool-result source/proof/target decoding passed");}
