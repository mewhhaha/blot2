import os;
import joined_public_frontend;
import joined_public_wasm;
import joined_target_scalar;
fn yes(source:u8[:],index:i64) {
 var p=joined_public_frontend::parse(source);if p.status!=0 {print("source status ",p.status);}assert(p.status==0 && p.program.body.variant==1);let b=joined_public_wasm::emit(source,p.program);assert(b.len>0 && joined_target_scalar::verify(source,p.program,b) && write_file(str("joined_target_",index,".wasm"),b));
 if index==0 {let signature:u8[6]=[0x20,1,0x41,1,0x6a,0x0f];var found:i64=0;for j in b.len-5 {if b[j..j+6]==signature[..] {var mutation=copy(b);mutation[j+4]=0x6b;assert(!joined_target_scalar::verify(source,p.program,mutation));assert(write_file("joined_valid_mutation.wasm",mutation));found+=1;}}assert(found==1);}
 for i in b.len {var x=copy(b);x[i]^=1;assert(!joined_target_scalar::verify(source,p.program,x));assert(!joined_target_scalar::verify(source,p.program,b[..i]));}
 var extra:u8[>..]=[];extra.append(b);extra.push(0);assert(!joined_target_scalar::verify(source,p.program,extra));
 assert(!joined_target_scalar::verify("wrong",p.program,b));let old=p.program.head;p.program.head.depth=0;assert(!joined_target_scalar::verify(source,p.program,b));p.program.head=old;
}
fn loop_case(body:u8[:],i:i64) {var source:u8[>..]=[];source.append("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n");source.append(body);var p=joined_public_frontend::parse(source);assert(p.status==0 && p.program.body.variant==2);let b=joined_public_wasm::emit(source,p.program);assert(joined_target_scalar::verify(source,p.program,b) && write_file(str("jt_loop_",i,".wasm"),b));for j in b.len {var bad=copy(b);bad[j]^=1;assert(!joined_target_scalar::verify(source,p.program,bad));}}
fn mixed_case(body:u8[:],i:i64) {var source:u8[>..]=[];source.append("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n");source.append(body);var p=joined_public_frontend::parse(source);assert(p.status==0 && p.program.body.variant==3);let b=joined_public_wasm::emit(source,p.program);assert(joined_target_scalar::verify(source,p.program,b) && write_file(str("jt_mixed_",i,".wasm"),b));for j in b.len {var bad=copy(b);bad[j]^=1;assert(!joined_target_scalar::verify(source,p.program,bad));}}
fn main(){
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",0);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = U32.wrapping_add(x,3)\n  if x < 2 && y <= 1:\n    return y\n  else:\n    return U32.wrapping_mul(y,7)\n",1);
 yes("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if #False || (x < 7):\n    return x & 15\n  return U32.wrapping_sub(x,1)\n",2);
 let loop_source="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n";var p=joined_public_frontend::parse(loop_source);assert(p.status==0 && p.program.body.variant==2);let t=joined_public_wasm::emit(loop_source,p.program);assert(t.len>0 && joined_target_scalar::verify(loop_source,p.program,t));for i in t.len {var x=copy(t);x[i]^=1;assert(!joined_target_scalar::verify(loop_source,p.program,x));}
 loop_case("  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n",0);
 loop_case("  let out = for i in 0..x carry (a=17) do:\n    stop (x)\n  return out\n",1);
 loop_case("  for i in 0..x do:\n    continue\n  return x\n",2);
 loop_case("  let outer = for i in 0..x carry (a=7) do:\n    let inner = for j in 0..2 carry (b=a) do:\n      next (j)\n    next (inner)\n  return outer\n",3);
 loop_case("  let out = for i in 0..x carry (a=4) do:\n    if #True:\n      if #False:\n        stop (x)\n      else:\n        next (i)\n    else:\n      stop (a)\n  return out\n",4);
 loop_case("  let out = for i in 0..x carry (a=9) do:\n    for j in 0..3 do:\n      if #True:\n        break\n      else:\n        continue\n    next (i)\n  return out\n",5);
 mixed_case("  let sum = for i in 0..x carry (a=0) do:\n    next (U32.wrapping_add(a,i))\n  return sum\n",0);
 mixed_case("  let sum = for i in 0..x carry (a=0) do:\n    let part = for j in 0..2 carry (b=a) do:\n      next (U32.wrapping_add(b,i))\n    next (part)\n  return sum + 0\n",1);
 mixed_case("  let sum = for i in 0..x carry (a=0) do:\n    if i < 4294967295:\n      next (i + 1)\n    else:\n      next (a)\n  return sum\n",2);
 print("independent joined scalar/finite-loop Wasm semantic decoding passed");}
