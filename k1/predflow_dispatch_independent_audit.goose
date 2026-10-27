import std;
import generic_callable;
import generic_callable_old;
fn check(s:u8[:]) {let a=generic_callable_old::compile(s);let b=generic_callable::compile(s);if a.status==0 {assert(b.status==0 && a.argument==b.argument && a.result==b.result && a.wasm[..]==b.wasm[..]);}else if b.status!=0 {assert(a.status==b.status && b.wasm.len==0);}else {assert(b.argument==1 && b.result==2 && b.wasm.len>0);}}
fn main() {for name in ["f","renamed"] {for n in ["0","1","7","4294967295"] {for prefix in ["U32 -> Bool","Fn[static,Many,U32,Bool]"] {for choice in 4 {let body=if choice==0 {str("  return x < ",n,"\n")} else if choice==1 {str("  let y = x\n  return y < ",n,"\n")} else if choice==2 {str("  return x + 1 < ",n,"\n")} else {str("  return y < 7\n")};check(str("pub let ",name,": ",prefix," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body));}}}}print("independent legacy dispatch compatibility matrix passed");}
