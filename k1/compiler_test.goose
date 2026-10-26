import std;
import os;
import compiler_frontend;
import compiler_validate;
import compiler_wasm;

fn accepted(source:u8[:],i:i64,variant:i64) {
    var r=compiler_frontend::parse(source);if r.status!=0 {print("status ",r.status," for ",source);}
    assert(r.status==0 && r.program.variant==variant && compiler_validate::verify(source,r.program));
    let out=compiler_wasm::emit(source,r.program);assert(out.len>0 && write_file(str("compiler_",i,".wasm"),out));
    assert(compiler_wasm::emit("not source",r.program).len==0);
    if variant==2 {
        for j in r.program.body.nodes.len {
            let old=r.program.body.nodes[j];r.program.body.nodes[j].tag=999;
            assert(!compiler_validate::verify(source,r.program) && compiler_wasm::emit(source,r.program).len==0);
            r.program.body.nodes[j]=old;r.program.body.nodes[j].target=-1;
            assert(!compiler_validate::verify(source,r.program));r.program.body.nodes[j]=old;
        }
        for j in r.program.body.bindings.len {
            let old=r.program.body.bindings[j];r.program.body.bindings[j].scope=-1;
            assert(!compiler_validate::verify(source,r.program));r.program.body.bindings[j]=old;
        }
        let old=r.program.fn_start;r.program.fn_start=-1;assert(!compiler_validate::verify(source,r.program));r.program.fn_start=old;
    }
}
fn rejected(source:u8[:]) {let r=compiler_frontend::parse(source);if r.status==0 {print("unexpected accepted source ",source);}assert(r.status!=0 && r.program.source.len==0);}
fn main() {
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",0,1);
    accepted("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    next (i)\n  return out\n",1,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=17) do:\n    stop (x)\n  return out\n",2,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    continue\n  return x\n",3,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    break\n  return x\n",4,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  let outer = for i in 0..x carry (a=7) do:\n    let inner = for j in 0..2 carry (b=a) do:\n      next (j)\n    next (inner)\n  return outer\n",5,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=4) do:\n    if #True:\n      if #False:\n        stop (x)\n      else:\n        next (i)\n    else:\n      stop (a)\n  return out\n",6,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=9) do:\n    for j in 0..3 do:\n      if #True:\n        break\n      else:\n        continue\n    next (i)\n  return out\n",7,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    return i\n  return 99\n",8,2);
    accepted("let f: U32 -> U32 = fn x => do:\n  let out = for i in 1..3 carry (a=9) do:\n    next (i)\n  return out\n",9,2);
    rejected("let f: U32 -> U32 = fn (x) => do:\n  for i in 0..x do:\n    continue\n  return x\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  return x + 1\n");
    let missing=compiler_frontend::parse("let f: U32 -> U32 = fn x => do:\n  if x < missing:\n    return x\n  else:\n    return 0\n");
    assert(missing.status==3 && missing.program.source.len==0);
    let unproved=compiler_frontend::parse("let f: U32 -> U32 = fn x => do:\n  return x + 1\n");
    assert(unproved.status==5 && unproved.program.source.len==0);
    let bad_target=compiler_frontend::parse("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    next (i)\n  return x\n");
    assert(bad_target.status==1 && bad_target.program.source.len==0);
    rejected("let f: U32 -> U32 = fn x => do:\n  let out = for i in x..x carry (a=1) do:\n    next (a)\n  return out\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  let out = for i in 2..1 carry (a=1) do:\n    next (a)\n  return out\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=1) invariant [Le(i,x)] do:\n    next (a)\n  return out\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x carry (a=1,b=2) do:\n    next (a,b)\n  return out\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  let out = for i in 0..x do:\n    continue\n  return out\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    continue\n  return i\n");
    rejected("let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    if x:\n      continue\n    else:\n      break\n  return x\n");
    print("tagged source/Core and finite-loop lowering passed");
}
