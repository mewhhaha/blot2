import std;import os;
import typed_canonical_frontend;import typed_canonical_wasm;
import leaf_resource_build;import leaf_runtime_emit;import leaf_runtime_verify;
fn one(source:u8[:],index:i64){var p=typed_canonical_frontend::parse(source);assert(p.status==0);let target=typed_canonical_wasm::emit(source,p.program);var summary=leaf_resource_build::build(source,p.program,target);assert(summary.status==0);let bytes=leaf_runtime_emit::emit(source,p.program,summary.summary);if bytes.len==0 {print("empty runtime wrapper ",index);}assert(bytes.len>0 && leaf_runtime_verify::verify(source,p.program,summary.summary,bytes));
 for j in bytes.len {var x=copy(bytes);x[j]^=1;assert(!leaf_runtime_verify::verify(source,p.program,summary.summary,x));assert(!leaf_runtime_verify::verify(source,p.program,summary.summary,bytes[..j]));}
 var forged=copy(summary.summary);forged.declared_frame^=1;assert(leaf_runtime_emit::emit(source,p.program,forged).len==0);assert(!leaf_runtime_verify::verify("wrong",p.program,summary.summary,bytes));assert(write_file(str("leaf-runtime-",index,".wasm"),bytes));}
fn main(){
 one("pub let f: U32 -> U32 ! {} resources {depth: 3, frame: 12} = fn x => do:\n  return x\n",0);
 one("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    let small = i < 5\n    if small:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n",1);
 one("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 4294967295} = fn x => do:\n  return x\n",2);
 one("pub let f: U32 -> U32 ! {} resources {depth: 128, frame: 0} = fn x => do:\n  return x\n",3);
 print("source-bound leaf runtime reservation/restore target checked");
}
