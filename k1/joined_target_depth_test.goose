import std;
import joined_public_frontend;
import joined_public_wasm;
import joined_target_scalar;
fn test(source:u8[:]) {var p=joined_public_frontend::parse(source);if p.status!=0 {print("source rejected ",p.status);}assert(p.status==0);let b=joined_public_wasm::emit(source,p.program);assert(b.len>0 && joined_target_scalar::verify(source,p.program,b));}
fn main(){var a:u8[>..]=[];a.append("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n");for _ in 300 {a.append("  if #False:\n    return 0\n");}a.append("  return x\n");test(a);
 var b:u8[>..]=[];b.append("pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x");for _ in 500 {b.append(" & 4294967295");}b.push('\n');test(b);print("independent long sequence and expression coverage passed");}
