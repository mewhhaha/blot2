import std;
import os;
import predicate_frontend;
import predicate_verify;
import predicate_wasm;
import generic_callable;
fn yes(s:u8[:],i:i64) {var p=predicate_frontend::parse(s);assert(p.status==0 && predicate_verify::verify(s,p.program));let b=predicate_wasm::emit(s,p.program);assert(b.len>0 && write_file(str("predicate-independent-",i,".wasm"),b));let r=generic_callable::compile(s);assert(r.status==0 && r.argument==1 && r.result==2 && r.wasm[..]==b[..]);
 for k in 8 {var q=copy(p.program);if k==0 {q.body.core.name_start= -1;}else if k==1 {q.body.core.parameter_start= -1;}else if k==2 {q.body.core.left_start= -1;}else if k==3 {q.body.core.operator_start=9223372036854775807;}else if k==4 {q.body.core.right_end=9223372036854775807;}else if k==5 {q.body.core.values[0].literal^=1;}else if k==6 {q.body.core.result_id= -1;}else {q.body.core.result_type=1;}assert(!predicate_verify::verify(s,q) && predicate_wasm::emit(s,q).len==0);}}
fn main(){yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return 7 < x\n",0);yes("pub let f: Fn[static,Many,U32,Bool] ! {} resources {depth: 2, frame: 3} = fn x => return x < 4294967295\n",1);yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < x\n",2);
 for s in ["pub let f: Fn[static,Many,U32,Bool] ! {} resources {depth: 1, frame: 0} = fn x => return y < x\n", "pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 0} = fn x => return x < 1\n", "pub let f: U32 -> Bool ! {} resources {depth: 0, frame: 0} = fn x => return x < 1\n", "pub let f: U32 -> Bool ! {reserve} resources {depth: 1, frame: 0} = fn x => return x < 1\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 1\nlet other = 1\n"] {let r=predicate_frontend::parse(s);assert(r.status!=0 && r.program.source.len==0);let d=generic_callable::compile(s);assert(d.status!=0 && d.wasm.len==0);}
 print("independent predicate original/header/Core/dispatch controls passed");}
