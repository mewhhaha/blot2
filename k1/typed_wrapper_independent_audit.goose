import std;
import os;
import common_decl_dispatch;
import typed_dispatch;
import typed_canonical_frontend;
import typed_canonical_target;
fn make(n:i64)->u8[] {return str("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for j in 0..x carry (a=0) do:\n    let flag = j < ",n,"\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n");}
fn main() {for n in 10 {let s=make(n);let old=common_decl_dispatch::compile(s);let next=typed_dispatch::compile(s);assert(old.status!=0 && next.status==0 && next.argument==1 && next.result==1);var p=typed_canonical_frontend::parse(s);assert(p.status==0 && typed_canonical_target::verify(s,p.program,next.wasm));let changed=make(n+1);assert(!typed_canonical_target::verify(changed,p.program,next.wasm));assert(write_file(str("wrapper-audit-",n,".wasm"),next.wasm));}print("wrapper independently checked ten new paths and source forgery");}
