import std;
import typed_dispatch;
import short_frontend;
import short_emit;
fn main(){for n in ["0","1","3","7","4294967294"] {for body in ["x < 4294967295 && (x + 1) < ","4294967294 < x || (x + 1) < "] {let s=str("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return ",body,n,"\n");let old=typed_dispatch::compile(s);var now=short_frontend::parse(s);if old.status!=0 || now.status!=0 {print("status ",old.status," ",now.status," ",s);}assert(old.status==0 && now.status==0);let out=short_emit::emit(s,now.program);assert(out.len>0 && out[..]==old.wasm[..]);}}print("short-circuit proof path prior-target byte compatibility passed");}
