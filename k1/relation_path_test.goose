import std;
import os;
import unified_frontend;
import unified_guard;
import refinement_guard_verify;
import unified_check;
import unified_wasm;
fn main(){
 let accepted=[
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x <= y && y < 4294967295:\n    return x + 1\n  else:\n    return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < x:\n    return x\n  else:\n    if y < 4294967295:\n      return x + 1\n    else:\n      return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  let z = U32.wrapping_add(y,1)\n  if x <= y && y <= z && z < 4294967295:\n    return x + 1\n  else:\n    return x\n"
 ];
 for source,i in accepted {
   var p=unified_frontend::parse(source);if p.status!=0 {print(str("unexpected path rejection ",i," status ",p.status));}assert(p.status==0 && unified_check::verify(source,p.program));
   let evidence=unified_guard::check(source,p.program);assert(evidence.status==0 && evidence.evidence.len>0 && evidence.evidence[0].path_count==(if i==2 {2} else {1}));
   assert(refinement_guard_verify::verify_evidence(source,p.program,evidence.evidence));
   for field in 4 {var e:unified_guard::Evidence[>..]=[];e.append(evidence.evidence);if field==0 {e[0].path_guard[0]+=1;} else if field==1 {e[0].path_true[0]=!e[0].path_true[0];} else if field==2 {e[0].path_count=0;} else {e[0].path_guard[15]=1;} assert(!refinement_guard_verify::verify_evidence(source,p.program,e));}
   let bytes=unified_wasm::emit(source,p.program);assert(bytes.len>0 && write_file(str("relation-path-",i,".wasm"),bytes));
 }
 for source in [
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,0)\n  if x <= y:\n    return x + 1\n  else:\n    return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if y < 4294967295:\n    return x + 1\n  return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x <= y || y < 4294967295:\n    return x + 1\n  else:\n    return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  if x <= y:\n    let a = 0\n  else:\n    let b = 0\n  if y < 4294967295:\n    return x + 1\n  else:\n    return x\n"
 ] {let p=unified_frontend::parse(source);if p.status!=5 {print(str("unexpected unsafe acceptance/status ",p.status," ",source));}assert(p.status==5 && p.program.nodes.len==0);}
 print("source-bound transitive relation paths passed");
}
