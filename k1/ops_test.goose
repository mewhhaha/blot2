import std;
import os;
import short_frontend;
import short_check;
import short_emit;
import short_target;
fn yes(s:u8[:],i:i64){var p=short_frontend::parse(s);if p.status!=0 {print("status ",p.status," ",s);}assert(p.status==0 && short_check::verify(s,p.program));let b=short_emit::emit(s,p.program);assert(b.len>0 && short_target::verify(s,p.program,b) && write_file(str("ops-",i,".wasm"),b));for k in s.len {var q:u8[>..]=[];q.append(s);q[k]^=1;assert(!short_check::verify(q,p.program));}for k in b.len {var q=copy(b);q[k]^=1;assert(!short_target::verify(s,p.program,q));assert(!short_target::verify(s,p.program,b[..k]));}}
fn no(s:u8[:]){let p=short_frontend::parse(s);assert(p.status!=0 && p.program.source.len==0);}
fn main(){
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return U32.wrapping_sub(x,1)\n",0);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return U32.wrapping_mul(x,7)\n",1);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x & 255\n",2);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x <= 7\n",3);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..3 carry (a=1) do:\n    next (U32.wrapping_mul(a,2))\n  return out\n",4);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x & 3 + 1 <= 2\n",5);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x <= 4294967295\n",6);
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return U32.wrapping_sub(x,1)\n");
 no("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let b = x < 5\n  return b & 1\n");
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x <= 4294967294:\n    return x + 1\n  return x\n",7);
 print("private typed scalar/loop operation parity controls passed");}
