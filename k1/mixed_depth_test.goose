import std;
import mixed_frontend;
import mixed_validate;
import mixed_wasm;
fn source(n:i64)->u8[] {
 var s:u8[>..]=[];s.append("let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..1 carry (a=0) do:\n    next (a");
 for i in n {s.append(" + 0");}s.append(")\n  return sum\n");return s;
}
fn main() {
 let good=source(127);var p=mixed_frontend::parse(good);assert(p.status==0 && mixed_validate::verify(good,p.program) && mixed_wasm::emit(good,p.program).len>0);
 let bad=source(128);let q=mixed_frontend::parse(bad);assert(q.status!=0 && q.program.source.len==0);
 print("mixed expression depth admission matches lowering");
}
