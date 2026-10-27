import joined_public_frontend;
import joined_public_wasm;
import joined_driver_gate;
fn main(){let a="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n";
 let b="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n";
 var x=joined_public_frontend::parse(a);var y=joined_public_frontend::parse(b);assert(x.status==0 && y.status==0);
 let at=joined_public_wasm::emit(a,x.program);let bt=joined_public_wasm::emit(b,y.program);assert(at.len>0 && bt.len>0 && at[..]!=bt[..]);
 assert(joined_driver_gate::matches(a,x.program,at));assert(!joined_driver_gate::matches(b,x.program,at));assert(!joined_driver_gate::matches(a,x.program,bt));assert(!joined_driver_gate::matches(b,y.program,at));
 for i in at.len {var bad=copy(at);bad[i]^=1;assert(!joined_driver_gate::matches(a,x.program,bad));}
 let old=x.program.head;x.program.head.depth=0;assert(!joined_driver_gate::matches(a,x.program,at));x.program.head=old;
 print("private joined driver exact source/target association passed");}
