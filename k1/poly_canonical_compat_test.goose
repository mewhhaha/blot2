import std;
import typed_canonical_frontend;
import typed_canonical_wasm;
import poly_canonical_frontend;
import poly_canonical_wasm;
fn check(s:u8[:]) {var a=typed_canonical_frontend::parse(s);var b=poly_canonical_frontend::parse(s);if a.status!=b.status {print("status ",a.status," ",b.status," ",s);}assert(a.status==b.status);if a.status==0 {let x=typed_canonical_wasm::emit(s,a.program);let y=poly_canonical_wasm::emit(s,b.program);assert(x.len>0 && x[..]==y[..]);}}
fn main(){for name in ["f","value"] {for n in ["0","1","7","20"] {for choice in 6 {let body=if choice==0 {str("  let y = x\n  return y\n")} else if choice==1 {str("  let flag = x < ",n,"\n  if flag:\n    return 1\n  return 2\n")} else if choice==2 {str("  let total = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,",n,"))\n  return total\n")} else if choice==3 {str("  let total = for i in 0..x carry (a=0) do:\n    next (i + 1)\n  return total\n")} else if choice==4 {str("  if x < ",n,":\n    return x\n  return 0\n")} else {str("  return missing\n")};check(str("pub let ",name,": U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body));}}}print("polymorphic scalar/loop prior U32 compatibility passed");}
