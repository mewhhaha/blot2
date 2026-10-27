import std;
import os;
import generic_bool_frontend;
import generic_bool_verify;
import generic_bool_wasm;
import generic_callable;
fn yes(s:u8[:],i:i64,form:i64) {
 var b=generic_bool_frontend::parse(s);if b.status!=0 {print("source status ",b.status);}assert(b.status==0 && b.program.head.form==form && generic_bool_verify::verify(s,b.program));
 let bytes=generic_bool_wasm::emit(s,b.program);assert(bytes.len>0 && write_file(str("bool-fn-",i,".wasm"),bytes));let combined=generic_callable::compile(s);assert(combined.status==0 && combined.argument==2 && combined.wasm[..]==bytes[..]);
 for k in s.len {var wrong:u8[>..]=[];wrong.append(s);wrong[k]^=1;assert(!generic_bool_verify::verify(wrong,b.program) && generic_bool_wasm::emit(wrong,b.program).len==0);}
 for f in 10 {var forged=copy(b.program);if f==0 {forged.head.ok=false;}else if f==1 {forged.head.let_start= -1;}else if f==2 {forged.head.type_start= -1;}else if f==3 {forged.head.type_end=9223372036854775807;}else if f==4 {forged.head.effect_start= -1;}else if f==5 {forged.head.resources_end=9223372036854775807;}else if f==6 {forged.head.depth+=1;}else if f==7 {forged.head.frame+=1;}else if f==8 {forged.head.form=3;}else {forged.body.body_start= -1;}assert(!generic_bool_verify::verify(s,forged) && generic_bool_wasm::emit(s,forged).len==0);}
}
fn no(s:u8[:]) {let r=generic_callable::compile(s);assert(r.status!=0 && r.wasm.len==0);}
fn main() {
 yes("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 11\n  return 42\n",0,1);
 yes("pub let f: Fn[static,Many,Bool,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x && #True:\n    return 11\n  return 42\n",1,2);
 let scalar="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";let r=generic_callable::compile(scalar);assert(r.status==0 && r.argument==1 && r.wasm.len>0);
 no("pub let f: Fn[static,Many,Bool,Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: Fn[static,Many,Bool,U32] ! {read r} resources {depth: 1, frame: 0} = fn x => do:\n  return 1\n");
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 1\n");
 no("pub let f: Fn[static,Once,Bool,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return 1\n");
 let unbound=generic_callable::compile("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return y\n");assert(unbound.status==13 && unbound.wasm.len==0);
 let mismatch=generic_callable::compile("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");assert(mismatch.status==14 && mismatch.wasm.len==0);
 let incomplete=generic_callable::compile("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 1\n");assert(incomplete.status==15 && incomplete.wasm.len==0);
 print("private U32/Bool callable typed source and effect controls passed");
}
