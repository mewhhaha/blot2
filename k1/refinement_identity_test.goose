import unified_frontend;
import unified_check;
import unified_guard;
import refinement_guard_verify;
fn reject(s:u8[:]) {let p=unified_frontend::parse(s);if p.status==0 {print("unexpected acceptance ",s);}assert(p.status!=0 && p.program.nodes.len==0);}
fn accept(s:u8[:]) {var p=unified_frontend::parse(s);if p.status!=0 {print("unexpected rejection ",p.status," ",s);}assert(p.status==0 && unified_check::verify(s,p.program) && refinement_guard_verify::check(s,p.program));}
fn main() {
 reject("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 4294967295:\n    return x + 1\n  return x\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_sub(x,1)\n  if y < 4294967295:\n    return x + 1\n  return x\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_mul(x,0)\n  if y < 4294967295:\n    return x + 1\n  return x\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 4294967295 || x < 4294967295:\n    return x + 1\n  return x\n");
 reject("let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x < 4294967295:\n    return y + 1\n  else:\n    return x\n");
 reject("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let z=x\n    return z + 1\n  else:\n    let z=U32.wrapping_add(x,1)\n    return z + 1\n");
 reject("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x\n  return x + 1\n");
 accept("let f: U32 -> U32 = fn x => do:\n  let a=x\n  let b=a\n  if b < 4294967295 && #True:\n    return a + 1\n  return x\n");
 accept("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let a=x\n    if a < 4294967295:\n      return 1 + a\n    else:\n      return x\n  return x\n");
 accept("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let a=x\n  else:\n    return x\n  return x + 1\n");
 accept("let f: U32 -> U32 = fn x => do:\n  if #False && x + 1 < 2:\n    return x + 1\n  return x\n");
 print("independent alias, wrapping, false-edge and join controls passed");
}
