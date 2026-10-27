import os;
import std;
import common_frontend;
import common_check;
import common_wasm;
import common_target;
import common_guard;
import common_proof;
fn yes(s:u8[:],i:i64) {var p=common_frontend::parse(s);if p.status!=0 {print("status ",p.status," ",s);}assert(p.status==0 && common_check::verify(s,p.program));let b=common_wasm::emit(s,p.program);assert(b.len>0 && common_target::verify(s,p.program,b) && write_file(str("common-independent-",i,".wasm"),b));
 for j in s.len {var x:u8[>..]=[];x.append(s);x[j]^=1;assert(!common_check::verify(x,p.program) && !common_target::verify(x,p.program,b));}
 for j in p.program.nodes.len {for k in 8 {var q=copy(p.program);if k==0 {q.nodes[j].tag=999;}else if k==1 {q.nodes[j].start= -1;}else if k==2 {q.nodes[j].end=9223372036854775807;}else if k==3 {q.nodes[j].a= -1;}else if k==4 {q.nodes[j].b= -1;}else if k==5 {q.nodes[j].c= -1;}else if k==6 {q.nodes[j].literal^=1;}else {q.nodes[j].ty^=1;}assert(!common_check::verify(s,q) && !common_target::verify(s,q,b));}}
 for j in b.len {var x=copy(b);x[j]^=1;assert(!common_target::verify(s,p.program,x));}
 let proof_result=common_guard::check(s,p.program);assert(proof_result.status==0 && common_proof::verify_evidence(s,p.program,proof_result.evidence));}
fn no(s:u8[:]){let p=common_frontend::parse(s);if p.status==0 {print("unexpected ",s);}assert(p.status!=0 && p.program.source.len==0);}
fn main(){yes("let f: Bool -> Bool = fn b => do:\n  return b\n",0);
 yes("let f: Bool -> U32 = fn b => do:\n  let y = 4294967294\n  if b && (y < 4294967295):\n    return y + 1\n  return 9\n",1);
 yes("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 7\n",2);
 yes("let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y < 4294967295:\n    return y + 1\n  return y\n",3);
 no("let f: Bool -> U32 = fn b => do:\n  return b + 1\n");
 no("let f: Bool -> Bool = fn b => do:\n  return b < 1\n");
 no("let f: Bool -> Bool = fn b => do:\n  let y = 4294967295\n  return b || (y + 1) < 1\n");
 no("let f: Bool -> U32 = fn b => do:\n  let y = 4294967295\n  if b:\n    return 1\n  return y + 1\n");
 no("let f: U32 -> Bool = fn x => do:\n  return x < 4294967295 || (x + 1) < 1\n");
 no("let f: Bool -> Bool = fn b => do:\n  if #False:\n    return missing\n  return b\n");
 print("independent common typed-Core and target controls passed");}
