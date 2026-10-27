import std;
import os;
import poly_canonical_frontend;
import poly_canonical_check;
import poly_canonical_wasm;
fn main(){
 for i in 80 {let limit=(i*7+3)%11;let k=(i*13+1)%64;var s:u8[>..]=[];
  if i%4==0 {s.append("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  for j in 0..5 do:\n    if x:\n      return #True\n    continue\n  return #False\n");}
  else if i%4==1 {format(s,"pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..5 carry (a=0) do:\n    if x:\n      next (U32.wrapping_add(a,",k,"))\n    else:\n      stop (a)\n  return total\n");}
  else if i%4==2 {format(s,"pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    if j < ",limit,":\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total < ",limit,"\n");}
  else {format(s,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    if j < ",limit,":\n      next (U32.wrapping_add(a,",k,"))\n    else:\n      stop (a)\n  return total\n");}
  var p=poly_canonical_frontend::parse(s);if p.status!=0 {print("rejected ",i," ",s);}assert(p.status==0 && poly_canonical_check::verify(s,p.program));let b=poly_canonical_wasm::emit(s,p.program);assert(b.len>0 && write_file(str("ind-poly-",i,".wasm"),b));
 }
 for s in ["pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    next (a)\n  return total\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=#True) do:\n    next (a)\n  return total\n", "pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return x + 1\n  return 0\n"] {let p=poly_canonical_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
 print("independent mixed-loop signature/type boundaries passed");
}
