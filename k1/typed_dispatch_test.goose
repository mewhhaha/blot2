import std;
import os;
import common_decl_dispatch;
import typed_canonical_frontend;
import typed_canonical_target;
import typed_dispatch;
fn prior(s:u8[:]) {let a=common_decl_dispatch::compile(s);let b=typed_dispatch::compile(s);if a.status==0 {assert(b.status==0 && a.argument==b.argument && a.result==b.result && a.wasm[..]==b.wasm[..]);}else if b.status!=0 {assert(a.status==b.status && b.wasm.len==0);}}
fn main(){
 for arg in ["U32","Bool"] {for result in ["U32","Bool"] {for form in 2 {for n in ["0","1","7","4294967295"] {for choice in 4 {
  var sig:u8[>..]=[];if form==0 {format(sig,arg," -> ",result);}else {format(sig,"Fn[static,Many,",arg,",",result,"]");}
  var body:u8[>..]=[];if choice==0 {body.append("  return x\n");}else if choice==1 {format(body,"  return x < ",n,"\n");}else if choice==2 {body.append("  if x:\n    return 1\n  return 7\n");}else {format(body,"  let y = x\n  return y < ",n,"\n");}
  let s=str("pub let f: ",sig," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body);prior(s);
 }}}}}
 for s in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x + 1\n", "pub let f: U32 -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return missing\n"] {prior(s);assert(typed_dispatch::compile(s).status!=0);}
 for s,i in ["pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    let flag = j < 5\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n", "pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    let flag = j < 4\n    if flag:\n      next (U32.wrapping_add(a,2))\n    else:\n      stop (a)\n  return total\n"] {
  let old=common_decl_dispatch::compile(s);if old.status==0 {print("old unexpectedly accepts canonical source");}assert(old.status!=0);
  var parsed=typed_canonical_frontend::parse(s);assert(parsed.status==0);let built=typed_dispatch::compile(s);assert(built.status==0 && built.argument==1 && built.result==1 && typed_canonical_target::verify(s,parsed.program,built.wasm));
  for k in built.wasm.len {var bad=copy(built.wasm);bad[k]^=1;assert(!typed_canonical_target::verify(s,parsed.program,bad));}
  assert(write_file(str("typed-dispatch-",i,".wasm"),built.wasm));
 }
 print("private old-first typed-loop dispatch compatibility and target checks passed");
}
