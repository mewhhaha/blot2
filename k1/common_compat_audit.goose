import std;
import common_frontend;
import common_wasm;
import unified_frontend;
import unified_wasm;
import predflow_frontend;
import predflow_wasm;
fn main(){for i in 120 {let k=(i*7919)%300000;for form in 4 {var s:u8[>..]=[];
 if form==0 {format(s,"let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y < 4294967295:\n    return y + 1\n  return y\n");}
 else if form==1 {format(s,"let f: U32 -> U32 = fn x => do:\n  let y = x\n  return y + 1\n");}
 else if form==2 {format(s,"let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && y + 1 < ",k,"\n");}
 else {format(s,"let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 || y + 1 < ",k,"\n");}
 var actual=common_frontend::parse(s);var old=if form<2 {unified_frontend::parse(s)} else {predflow_frontend::parse(s)};assert(actual.status==old.status);if old.status==0 {let b=common_wasm::emit(s,actual.program);let c=if form<2 {unified_wasm::emit(s,old.program)} else {predflow_wasm::emit(s,old.program)};assert(b.len>0 && b[..]==c[..]);}
 }}print("independent common-Core legacy compatibility controls passed");}
