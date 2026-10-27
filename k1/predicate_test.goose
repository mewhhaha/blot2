import std;
import os;
import predicate_frontend;
import predicate_verify;
import predicate_wasm;
import generic_callable;
fn yes(s:u8[:],i:i64,form:i64) {
 var p=predicate_frontend::parse(s);if p.status!=0 {print("predicate status ",p.status," ",s);}assert(p.status==0 && p.program.head.form==form && predicate_verify::verify(s,p.program));
 let b=predicate_wasm::emit(s,p.program);assert(b.len>0 && write_file(str("predicate-",i,".wasm"),b));let d=generic_callable::compile(s);assert(d.status==0 && d.argument==1 && d.result==2 && d.wasm[..]==b[..]);
 for j in s.len {var q:u8[>..]=[];q.append(s);q[j]^=1;assert(!predicate_verify::verify(q,p.program) && predicate_wasm::emit(q,p.program).len==0);}
 for k in 11 {var q=copy(p.program);if k==0 {q.head.ok=false;}else if k==1 {q.head.let_start= -1;}else if k==2 {q.head.type_start= -1;}else if k==3 {q.head.type_end=9223372036854775807;}else if k==4 {q.head.effect_start= -1;}else if k==5 {q.head.resources_end=9223372036854775807;}else if k==6 {q.head.depth+=1;}else if k==7 {q.head.frame+=1;}else if k==8 {q.head.form=3;}else if k==9 {q.body.core.result_type=1;}else {q.body.core.values[0].type_id=2;}assert(!predicate_verify::verify(s,q) && predicate_wasm::emit(s,q).len==0);}
}
fn no(s:u8[:]) {let p=generic_callable::compile(s);assert(p.status!=0 && p.wasm.len==0);}
fn main(){
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n",0,1);
 yes("pub let f: Fn[static, Many, U32, Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 7\n",1,2);
 no("pub let f: U32 -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => return x < 7\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
 no("pub let f: Fn[static,Once,U32,Bool] ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n");
 {let s="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 7\n";let legacy=predicate_frontend::parse(s);let compiled=generic_callable::compile(s);assert(legacy.status!=0 && compiled.status==0 && compiled.argument==1 && compiled.result==2 && compiled.wasm.len>0);}
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return y < 7\n");
 print("private predicate callable source and type controls passed");
}
