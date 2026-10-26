import std;
import os;
import compiler_frontend;
import compiler_validate;
import compiler_wasm;
import mixed_fact_build;
import mixed_fact_verify;
fn good(s:u8[:],i:i64,path:i64) {
 var p=compiler_frontend::parse(s);if p.status!=0 {print("unexpected rejection ",p.status," ",s);}assert(p.status==0 && p.program.variant==3 && compiler_validate::verify(s,p.program));
 let evidence=mixed_fact_build::build(p.program.mixed.body);assert(evidence.status==0 && evidence.events.len>0 && evidence.events[0].count==path);
 assert(mixed_fact_verify::verify(p.program.mixed.body,p.program.mixed.body.source,evidence.events));
 let data=compiler_wasm::emit(s,p.program);assert(data.len>0 && write_file(str("fact",i,".wasm"),data));
}
fn bad(s:u8[:]) {let p=compiler_frontend::parse(s);if p.status==0 {print("unexpected accept ",s);}assert(p.status!=0);}
fn main() {
 good("let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..3 carry (a=x) do:\n    if a < 4294967295:\n      next (a + 1)\n    else:\n      stop (a)\n  return r\n",0,0);
 good("let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..2 carry (a=x) do:\n    let b = U32.wrapping_add(a,4294967295)\n    if a < 4294967295:\n      if a < b:\n        stop (a)\n      else:\n        next (b + 1)\n    else:\n      stop (a)\n  return r\n",1,1);
 good("let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..2 carry (a=x) do:\n    let z = a\n    if z < 4294967295:\n      next (a + 1)\n    else:\n      stop (a)\n  return r\n",2,0);
 bad("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    let r = for i in 0..2 carry (a=x) do:\n      next (a + 1)\n    return r\n  else:\n    return x\n");
 bad("let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..2 carry (a=x) do:\n    if a < 4294967295:\n      stop (a)\n    else:\n      next (a + 1)\n  return r\n");
 bad("let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..2 carry (a=x) do:\n    if a < 4294967295:\n      let q = 1\n    else:\n      let q = 2\n    next (a + 1)\n  return r\n");
 print("source-bound loop guards and backedges passed");
}
