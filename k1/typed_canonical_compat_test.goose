import std;
import canonical_frontend;
import canonical_wasm;
import typed_canonical_frontend;
import typed_canonical_wasm;
fn check(s:u8[:]) {var a=canonical_frontend::parse(s);var b=typed_canonical_frontend::parse(s);if a.status==0 {assert(b.status==0);let x=canonical_wasm::emit(s,a.program);let y=typed_canonical_wasm::emit(s,b.program);assert(x.len>0 && x[..]==y[..]);} else if b.status!=0 {assert(b.status==a.status);} }
fn main(){for name in ["f","value"] {for bound in ["0","1","7","20"] {for choice in 6 {let body=if choice==0 {str("  let y = x\n  return y\n")} else if choice==1 {str("  let flag = x < ",bound,"\n  if flag:\n    return 1\n  return 2\n")} else if choice==2 {str("  let total = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,",bound,"))\n  return total\n")} else if choice==3 {str("  let total = for i in 0..x carry (a=0) do:\n    next (i + 1)\n  return total\n")} else if choice==4 {str("  if x < ",bound,":\n    return x\n  return 0\n")} else {str("  return missing\n")};check(str("pub let ",name,": U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body));}}}print("typed canonical old/new status and target byte matrix passed");}
