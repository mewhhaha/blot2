import os;
import joined_public_frontend;
import joined_public_verify;
import joined_public_wasm;
fn accepted(source:u8[:],index:i64,variant:i64) {
 var result=joined_public_frontend::parse(source);if result.status!=0 {print("status ",result.status," ",source);}assert(result.status==0 && result.program.body.variant==variant);
 assert(joined_public_verify::verify(source,result.program));let bytes=joined_public_wasm::emit(source,result.program);assert(bytes.len>0 && write_file(str("joined_",index,".wasm"),bytes));
 for i in source.len {var bad:u8[>..]=[];bad.append(source);bad[i]^=1;assert(!joined_public_verify::verify(bad,result.program) && joined_public_wasm::emit(bad,result.program).len==0);}
 let old=result.program.head;result.program.head.depth=0;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 result.program.head.frame^=1;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 result.program.head.effect_start=-1;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 result.program.head.let_start=-1;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 result.program.head.resources_end=9223372036854775807;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 result.program.head.ok=false;assert(!joined_public_verify::verify(source,result.program));result.program.head=old;
 let original=result.program.body.source[0];result.program.body.source[0]^=1;assert(!joined_public_verify::verify(source,result.program));result.program.body.source[0]=original;
 let prior=result.program.body.variant;result.program.body.variant=9;assert(!joined_public_verify::verify(source,result.program) && joined_public_wasm::emit(source,result.program).len==0);result.program.body.variant=prior;
}
fn rejected(source:u8[:]) {let r=joined_public_frontend::parse(source);if r.status==0 {print("unexpected acceptance: ",source);}assert(r.status!=0 && r.program.source.len==0);}
fn main() {
 accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",0,1);
 accepted("pub let f: U32 -> U32 ! {} resources {depth: 2, frame: 32} = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n",1,2);
 accepted("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,1))\n  return out\n",2,3);
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 129, frame: 0} = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4294967296} = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0, frame: 0} = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 0, frame: 0} = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {read r} resources {depth: 1, frame: 0} = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x + 1\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\nlet extra: U32 -> U32 = fn x => return x\n");
 rejected("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return missing\n");
 print("joined public-shaped source-bound compiler passed");
}
