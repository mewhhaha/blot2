import std;
import os;
import short_frontend;
import short_check;
import short_target;
import short_emit;
fn main(){
 for i in 100 {let k=(i*17+3)%257;let factor=(i*29+1)%511;let mask=(i*41+7)%65536;let limit=(i*19+9)%65536;var s:u8[>..]=[];
  if i%2==0 {format(s,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return U32.wrapping_mul(U32.wrapping_sub(x,",k,"),",factor,") & ",mask,"\n");}
  else {format(s,"pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x & ",mask," <= ",limit,"\n");}
  var p=short_frontend::parse(s);if p.status!=0 {print("unexpected rejection ",i," ",s);}assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && short_target::verify(s,p.program,b));assert(write_file(str("ind-ops-",i,".wasm"),b));
 }
 for s in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967295:\n    return x + 1\n  return 0\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967294 <= x:\n    return 0\n  return x + 1\n", "pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x <= #True\n"] {let p=short_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
 let safe="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return 0\n";var p=short_frontend::parse(safe);assert(p.status==0 && short_check::verify(safe,p.program));let b=short_emit::emit(safe,p.program);assert(b.len>0 && write_file("ind-safe.wasm",b));
 print("independent mixed operator, <= conservatism and proof controls passed");
}
