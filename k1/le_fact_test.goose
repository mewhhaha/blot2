import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
fn yes(s:u8[:],i:i64){var p=short_frontend::parse(s);if p.status!=0 {print("unexpected ",p.status," ",s);}assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && write_file(str("le-fact-",i,".wasm"),b));let ev=short_fact_build::build(p.program.tree);assert(ev.status==0 && ev.events.len==1 && short_fact_verify::verify(p.program.tree,p.program.tree.source,ev.events,1,1));for f in 5 {var q=copy(ev.events);if f==0 {q[0].guard_id+=1;}else if f==1 {q[0].truth=!q[0].truth;}else if f==2 {q[0].subject+=1;}else if f==3 {q[0].addition+=1;}else {q[0].reference+=1;}assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,q,1,1));}}
fn no(s:u8[:]) {let p=short_frontend::parse(s);if p.status==0 {print("unexpected acceptance ",s);}assert(p.status!=0);}
fn main(){yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  if y <= 4294967294:\n    return x + 1\n  return x\n",0);
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967295:\n    return x + 1\n  return x\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if 4294967294 <= x:\n    return x + 1\n  return x\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967294:\n    return x\n  return x + 1\n");
 let safe="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x <= 4294967294 && x + 1 < 5\n";var result=short_frontend::parse(safe);assert(result.status==0 && short_check::verify(safe,result.program) && short_emit::emit(safe,result.program).len>0);
 print("source-bound nonstrict guard successor evidence passed");}
