import std;import generic_fn_frontend;import generic_bool_frontend;import predicate_frontend;import predflow_decl_frontend;import common_decl_frontend;import typed_canonical_frontend;import typed_dispatch;import primary_dispatch;
fn main(){for s,i in [
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n",
 "pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 11\n  return 42\n",
 "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n",
 "pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n",
 "pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return x\n  return #False\n",
 "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    let flag = j < 5\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n"] {
 let accepted=if i==0 {generic_fn_frontend::parse(s).status==0} else if i==1 {generic_bool_frontend::parse(s).status==0} else if i==2 {predicate_frontend::parse(s).status==0} else if i==3 {predflow_decl_frontend::parse(s).status==0} else if i==4 {common_decl_frontend::parse(s).status==0} else {typed_canonical_frontend::parse(s).status==0};assert(accepted && primary_dispatch::previous_recognizes(s));let old=typed_dispatch::compile(s);let normal=primary_dispatch::compile(s);assert(old.status==0 && normal.status==0 && old.argument==normal.argument && old.result==normal.result && old.wasm[..]==normal.wasm[..]);let failed=primary_dispatch::compile_with_fault(s,7);assert(failed.status!=0 && failed.wasm.len==0 && failed.argument==0 && failed.result==0);
 }
 let new="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n";assert(!primary_dispatch::previous_recognizes(new) && typed_dispatch::compile(new).status!=0 && primary_dispatch::compile_with_fault(new,7).status==0);
 let invalid="pub let f: U32 -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => return 7\n";assert(!primary_dispatch::previous_recognizes(invalid));let failed=primary_dispatch::compile(invalid);assert(failed.status!=0 && failed.wasm.len==0);
 print("independent all-six replay and old-failure boundary passed");}
