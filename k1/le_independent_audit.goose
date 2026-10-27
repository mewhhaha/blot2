import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
fn main(){
 for n in 1..13 {var s:u8[>..]=[];s.append("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n");
  for i in n {if i==0 {s.append("  let a0 = x\n");}else {format(s,"  let a",i," = a",i-1,"\n");}}
  format(s,"  if a",n-1," <= 4294967294:\n    return x + 1\n  return x\n");
  var p=short_frontend::parse(s);assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && write_file(str("ind-le-",n,".wasm"),b));
  let e=short_fact_build::build(p.program.tree);assert(e.status==0 && e.events.len==1 && short_fact_verify::verify(p.program.tree,p.program.tree.source,e.events,1,1));
  for f in 4 {var forged=copy(e.events);if f==0 {forged[0].count=1;}else if f==1 {forged[0].guards[15]=1;}else if f==2 {forged[0].edges[15]=true;}else {forged[0].truth=!forged[0].truth;}assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,forged,1,1));}
 }
 for s in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x & 255\n  if y <= 4294967294:\n    return x + 1\n  return 0\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967294:\n    let total = for i in 0..x carry (a=0) do:\n      next (x + 1)\n    return total\n  return 0\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967294:\n    return x\n  else:\n    return x + 1\n"] {let p=short_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
 print("independent alias identity, proof mutation and loop/false-edge controls passed");
}
