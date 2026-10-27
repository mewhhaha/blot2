import std;
import typed_dispatch;
import primary_dispatch;
fn check(source:u8[:]) {
 var recognized=true;let actual=typed_dispatch::compile_record(source,recognized);let prior=typed_dispatch::compile(source);
 assert(actual.status==prior.status && actual.argument==prior.argument && actual.result==prior.result && actual.wasm[..]==prior.wasm[..]);
 assert(recognized==primary_dispatch::previous_recognizes(source));
 if actual.status==0 {assert(recognized);let failure=primary_dispatch::compile_with_fault(source,7);assert(failure.status!=0 && failure.wasm.len==0);}
}
fn main(){for source in [
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n",
 "pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 11\n  return 42\n",
 "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n",
 "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n",
 "pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return x\n  return #False\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    let flag = j < 5\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n"] {
 check(source);for i in source.len {var changed:u8[>..]=[];changed.append(source);changed[i]^=1;check(changed);}for i in source.len {check(source[..i]);}
 }
 print("owned disposition matches independent source replay across mutations and truncations");
}
