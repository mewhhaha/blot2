import std;
import joined_public_frontend;
import joined_public_wasm;
import joined_driver_gate;
fn run(s:u8[:],variant:i64) {
 var p=joined_public_frontend::parse(s);if p.status!=0 {print("status ",p.status);}assert(p.status==0 && p.program.body.variant==variant);let b=joined_public_wasm::emit(s,p.program);assert(b.len>0 && joined_driver_gate::matches(s,p.program,b));
 var changes:i64=0;
 for i in b.len-1 {if b[i]==0x20 || b[i]==0x21 || b[i]==0x0c || b[i]==0x0d {for v in 8 {if v!=b[i+1] {var bad=copy(b);bad[i+1]=v as u8;assert(!joined_driver_gate::matches(s,p.program,bad));changes+=1;}}}}
 assert(changes>0);
 for i in s.len {var bad:u8[>..]=[];bad.append(s);bad[i]^=1;assert(!joined_driver_gate::matches(bad,p.program,b));}
 var pbad=copy(p.program);pbad.head.frame+=1;assert(!joined_driver_gate::matches(s,pbad,b));
}
fn main(){
 run("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = U32.wrapping_add(x,4)\n  if x < 2 && y < 7:\n    return y\n  return x\n",1);
 run("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=7) do:\n    for j in 0..2 do:\n      if #True:\n        break\n      else:\n        continue\n    if #False:\n      stop (a)\n    else:\n      next (i)\n  return out\n",2);
 run("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=7) do:\n    for j in 0..2 do:\n      if #True:\n        break\n      else:\n        continue\n    if i < 4294967295:\n      next (i + 1)\n    else:\n      stop (U32.wrapping_add(a,1))\n  return out\n",3);
 print("independent slot/branch/source mutation controls passed");
}
