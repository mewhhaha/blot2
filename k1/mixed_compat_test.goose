import std;
import compiler_frontend;
import compiler_validate;
import compiler_wasm;
fn same(s:u8[:]) {
 var a=compiler_frontend::legacy_parse(s);var b=compiler_frontend::parse(s);
 if a.status!=b.status {print("diagnostic mismatch ",a.status," ",b.status," ",s);}
 assert(a.status==b.status);
 if a.status==0 {assert(a.program.variant==b.program.variant && compiler_validate::verify(s,b.program));
  let x=compiler_wasm::emit(s,a.program);let y=compiler_wasm::emit(s,b.program);assert(x.len>0 && x[..]==y[..]);}
}
fn main() {
 for s in [
  "let f: U32 -> U32 = fn x => do:\n  return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  return y\n",
  "let f: U32 -> U32 = fn x => do:\n  if x < 4294967295:\n    return x + 1\n  return x\n",
  "let f: U32 -> U32 = fn x => do:\n  return x + 1\n",
  "let f: U32 -> U32 = fn x => do:\n  return absent\n",
  "let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    next (i)\n  return x\n",
  "let f: U32 -> U32 = fn x => do:\n  for i in 0..x do:\n    continue\n  return x\n",
  "let f: U32 -> U32 = fn x => do:\n  let v = for i in 0..x carry (b=9) do:\n    next (i)\n  return v\n",
  "let f: U32 -> U32 = fn x => do:\n  let v = for i in x..x carry (b=9) do:\n    next (i)\n  return v\n",
  "let f: U32 -> U32 = fn x => do:\n  let v = for i in 0..x carry (b=9) do:\n    next (b)\n  return i\n",
  "wrong text"] {same(s);}
 print("legacy compiler acceptance, diagnostics and Wasm preserved");
}
