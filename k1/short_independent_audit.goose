import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_target;
fn main(){
 for i in 90 {let a=(i*7+2)%17;let b=(i*11+3)%17;let c=(i*13+4)%17;var s:u8[>..]=[];
  if i%3==0 {format(s,"pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let p = x < ",a,"\n  let q = x < ",b,"\n  let r = x < ",c,"\n  return p || q && r\n");}
  else if i%3==1 {format(s,"pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..8 carry (a=0) do:\n    let flag = j < ",a," && x < ",b," || x < ",c,"\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n");}
  else {s.append("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let a = x || #False\n  let b = x || #True\n  return a && b\n");}
  var p=short_frontend::parse(s);if p.status!=0 {print("rejected ",i," ",s);}assert(p.status==0 && short_check::verify(s,p.program));let out=short_emit::emit(s,p.program);assert(out.len>0 && short_target::verify(s,p.program,out));assert(write_file(str("ind-short-",i,".wasm"),out));
 }
 for s in ["pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return (x < 4294967295) && (x + 1) < 5\n", "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False && (x + 1) < 5\n", "pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x || 1\n"] {let p=short_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
 print("independent short-circuit nested precedence and conservative proof controls passed");
}
