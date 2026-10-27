import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
fn main(){for source,i in [
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    return x + 5\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967291:\n    return 5 + x\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967290 < x:\n    return x\n  else:\n    return x + 5\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967291 <= x:\n    return x\n  else:\n    return 5 + x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  if y < 100:\n    return x + 4294967196\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 0:\n    return x + 4294967295\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290 && x < 4294967295:\n    return x + 5\n  return x\n"
] {
 var p=short_frontend::parse(source);if p.status!=0 {print("rejected good ",i," status ",p.status);}assert(p.status==0 && short_check::verify(source,p.program));let proof=short_fact_build::build(p.program.tree);assert(proof.status==0 && proof.events.len>0 && short_fact_verify::verify(p.program.tree,p.program.tree.source,proof.events,p.program.head.argument,p.program.head.result));
 for f in 5 {var bad=copy(proof.events);if f==0 {bad[0].guard_id=0;}else if f==1 {bad[0].truth=!bad[0].truth;}else if f==2 {bad[0].subject=0;}else if f==3 {bad[0].one=0;}else {bad[0].addition=0;}assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,bad,p.program.head.argument,p.program.head.result));}
 let out=short_emit::emit(source,p.program);assert(out.len>0 && write_file(str("offset-",i,".wasm"),out));
 }
 for source in [
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967291:\n    return x + 5\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967292:\n    return 5 + x\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967291 < x:\n    return x\n  else:\n    return x + 5\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967292 <= x:\n    return x\n  else:\n    return 5 + x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 10:\n    return x + 4294967286\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290:\n    let z = for i in 0..x carry (a=0) do:\n      next (x + 5)\n    return z\n  return x\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967290 || #True:\n    return x + 5\n  return x\n"
] {let p=short_frontend::parse(source);assert(p.status!=0);}
 print("guarded U32 offsets and proof mutation controls passed");
}
