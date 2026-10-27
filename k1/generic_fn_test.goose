import os;
import generic_fn_frontend;
import generic_fn_verify;
import generic_fn_wasm;
fn accepted(s:u8[:],index:i64,form:i64) {
 var p=generic_fn_frontend::parse(s);if p.status!=0 {print("status ",p.status," ",s);}assert(p.status==0 && p.program.head.form==form);assert(generic_fn_verify::verify(s,p.program));let bytes=generic_fn_wasm::emit(s,p.program);assert(bytes.len>0 && write_file(str("generic-fn-",index,".wasm"),bytes));
 for i in s.len {var bad:u8[>..]=[];bad.append(s);bad[i]^=1;assert(!generic_fn_verify::verify(bad,p.program) && generic_fn_wasm::emit(bad,p.program).len==0);}
 for f in 9 {var b=copy(p.program);if f==0 {b.head.ok=false;}else if f==1 {b.head.let_start= -1;}else if f==2 {b.head.type_start= -1;}else if f==3 {b.head.type_end=9223372036854775807;}else if f==4 {b.head.effect_start= -1;}else if f==5 {b.head.resources_end=9223372036854775807;}else if f==6 {b.head.depth+=1;}else if f==7 {b.head.frame+=1;}else {b.head.form=3;}assert(!generic_fn_verify::verify(s,b) && generic_fn_wasm::emit(s,b).len==0);}
 var b=copy(p.program);b.body.variant=9;assert(!generic_fn_verify::verify(s,b));
}
fn bad(s:u8[:]) {let p=generic_fn_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
fn main() {
 accepted("pub let f: Fn[static, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",0,2);
 accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",1,1);
 accepted("pub let f: Fn[static,Many,U32,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return out\n",2,2);
 bad("pub let f: Fn[static, Once, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
 bad("pub let f: Fn[r, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
 bad("pub let f: Fn[static, Many, U32, Bool] ! {} resources {depth: 1, frame: 0} = fn x => return x\n");
 bad("pub let f: Fn[static, Many, U32, U32] ! {read r} resources {depth: 1, frame: 0} = fn x => return x\n");
 bad("pub let f: Fn[static, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => return x + 1\n");
 bad("pub let f: Fn[static, Many, U32, U32] ! {} resources {depth: 1, frame: 0} = fn x => return missing\n");
 print("private callable signature source-binding controls passed");
}
