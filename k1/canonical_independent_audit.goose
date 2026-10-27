import std;
import os;
import canonical_frontend;
import canonical_check;
import canonical_wasm;
fn main(){
 for i in 120 {let stop=(i*7+3)%11;let increment=(i*31+1)%257;var s:u8[>..]=[];
  format(s,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    if j < ",stop,":\n      next (U32.wrapping_add(a,",increment,"))\n    else:\n      stop (a)\n  return total\n");
  var p=canonical_frontend::parse(s);if p.status!=0 {print("unexpected status ",p.status," case ",i," ",s);}assert(p.status==0 && canonical_check::verify(s,p.program));
  let out=canonical_wasm::emit(s,p.program);assert(out.len>0 && write_file(str("ind-canonical-",i,".wasm"),out));
 }
 for s in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    let total = for i in 0..x carry (a=x) do:\n      next (a + 1)\n    return total\n  return 0\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    next (i + 1)\n  return total\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 1..x carry (a=0) do:\n    next (a)\n  return total\n"] {let p=canonical_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
 print("independent source/loop carry and fail-closed proof controls passed");
}
