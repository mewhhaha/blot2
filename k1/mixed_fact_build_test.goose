import std;
import mixed_parse;
import mixed_verify;
import mixed_fact_build;
fn good(s:u8[:],paths:i64) {var t,status=mixed_parse::parse(s);assert(status==0 && mixed_verify::verify(t,s));let r=mixed_fact_build::build(t);if r.status!=0 {print("unexpected reject ",r.status," ",s);}assert(r.status==0 && r.events.len>0 && r.events[0].count==paths);}
fn bad(s:u8[:]) {var t,status=mixed_parse::parse(s);assert(status==0 && mixed_verify::verify(t,s));let r=mixed_fact_build::build(t);if r.status==0 {print("unexpected accept ",s);}assert(r.status==5);}
fn main() {
 good("fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    if a < 4294967295:\n      next (a + 1)\n    else:\n      stop (a)\n  return r\n",0);
 good("fn x => do:\n  let r = for i in 0..x carry (a=x) do:\n    let b = U32.wrapping_add(a,1)\n    if a < 4294967295:\n      if a < b:\n        stop (a)\n      else:\n        next (b + 1)\n    else:\n      stop (a)\n  return r\n",1);
 bad("fn x => do:\n  if x < 4294967295:\n    let r = for i in 0..2 carry (a=x) do:\n      next (a + 1)\n    return r\n  else:\n    return x\n");
 bad("fn x => do:\n  let r = for i in 0..x carry (a=x) do:\n    if a < 4294967295:\n      stop (a)\n    else:\n      next (a + 1)\n  return r\n");
 print("loop fact producer path and reset passed");
}
