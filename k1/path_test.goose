import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_fact_build;
import short_fact_verify;
fn yes(s:u8[:],i:i64,events:i64){var p=short_frontend::parse(s);if p.status!=0 {print("rejected ",p.status," ",s);}assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && write_file(str("path-",i,".wasm"),b));let e=short_fact_build::build(p.program.tree);assert(e.status==0 && e.events.len==events && short_fact_verify::verify(p.program.tree,p.program.tree.source,e.events,1,2));if events>0 {for f in 5 {var q=copy(e.events);if f==0 {q[0].guard_id+=1;}else if f==1 {q[0].truth=!q[0].truth;}else if f==2 {q[0].subject+=1;}else if f==3 {q[0].addition+=1;}else {q[0].reference+=1;}assert(!short_fact_verify::verify(p.program.tree,p.program.tree.source,q,1,2));}}}
fn no(s:u8[:]){let p=short_frontend::parse(s);if p.status==0 {print("unexpected accepted ",s);}assert(p.status!=0 && p.program.source.len==0);}
fn main(){
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 4294967295 && (x + 1) < 5\n",0,1);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return 4294967294 < x || (x + 1) < 5\n",1,1);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False && (x + 1) < 5\n",2,0);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #True || (x + 1) < 5\n",3,0);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  if y < 4294967295 && (x + 1) < 5:\n    return (y + 1) < 4\n  return #False\n",4,2);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x <= 4294967294 && x + 1 < 5\n",5,1);
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 4294967295 || (x + 1) < 5\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False || (x + 1) < 5\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295 || #True:\n    return (x + 1) < 5\n  return #False\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False && missing < 5\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #True || x\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    let y = for i in 0..2 carry (a=x) do:\n      next (x + 1)\n    return y\n  return x\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  return x < 4294967295 && (y + 1) < 5\n");
 let loop_source="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = for i in 0..x carry (a=0) do:\n    if i < 4294967295 && (i + 1) < 5:\n      next (i + 1)\n    else:\n      stop (a)\n  return y\n";var p=short_frontend::parse(loop_source);assert(p.status==0 && short_check::verify(loop_source,p.program));let b=short_emit::emit(loop_source,p.program);assert(b.len>0 && write_file("path-loop.wasm",b));
 print("source-bound short-circuit predecessor proofs passed");
}
