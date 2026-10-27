import typed_canonical_frontend;
import typed_canonical_check;
import typed_canonical_target;
import typed_canonical_wasm;
fn no(source:u8[:]) {let r=typed_canonical_frontend::parse(source);assert(r.status!=0);}
fn main() {
 let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    if i < 4294967295:\n      next (i + 1)\n    else:\n      next (a)\n  return total\n";
 var p=typed_canonical_frontend::parse(s);assert(p.status==0 && typed_canonical_check::verify(s,p.program));
 let b=typed_canonical_wasm::emit(s,p.program);assert(b.len>0 && typed_canonical_target::verify(s,p.program,b));
 for i in b.len {var q:u8[>..]=[];q.append(b);q[i]^=1;assert(!typed_canonical_target::verify(s,p.program,q));}
 for i in b.len {assert(!typed_canonical_target::verify(s,p.program,b[..i]));}
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let flag = x < 7\n  return flag\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let flag = x < 7\n  return U32.wrapping_add(flag, 1)\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let flag = x < 7\n  let total = for i in 0..flag carry (a=0) do:\n    next (a)\n  return total\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let flag = x < 7\n  let total = for i in 0..x carry (a=flag) do:\n    next (a)\n  return total\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 1\n  return 0\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    let total = for i in 0..2 carry (a=x) do:\n      next (a + 1)\n    return total\n  else:\n    return x\n");
 print("typed scalar target mutation/truncation and Bool/backedge audits passed");
}
