import std;
import locals_frontend;
import locals_check;
import locals_wasm;
fn main() {
 var expr: u8[>..] = []; expr.append("let f: U32 -> U32 = fn x => do:\n  return x");
 for i in 1023 { expr.append(" & x"); }
 expr.append("\n");
 var a = locals_frontend::parse(expr); assert(a.status==0 && a.program.values.len==2047 && locals_check::verify(expr,a.program));
 assert(locals_wasm::emit(expr,a.program).len>0);
 var over: u8[>..] = []; over.append("let f: U32 -> U32 = fn x => do:\n  return x");
 for i in 1024 { over.append(" & x"); }
 over.append("\n");
 let b = locals_frontend::parse(over); assert(b.status==2 && b.program.values.len==0);
 var locals: u8[>..] = []; locals.append("let f: U32 -> U32 = fn x => do:\n");
 for i in 129 { locals.append(str("  let a",i," = x\n")); }
 locals.append("  return a128\n");
 let c = locals_frontend::parse(locals); assert(c.status==2 && c.program.values.len==0);
 var deep: u8[>..] = []; deep.append("let f: U32 -> U32 = fn x => do:\n  return ");
 for i in 63 { deep.append("("); } deep.append("x"); for i in 63 { deep.append(")"); } deep.append("\n");
 var d = locals_frontend::parse(deep); assert(d.status==0 && locals_check::verify(deep,d.program));
 var too_deep: u8[>..] = []; too_deep.append("let f: U32 -> U32 = fn x => do:\n  return ");
 for i in 64 { too_deep.append("("); } too_deep.append("x"); for i in 64 { too_deep.append(")"); } too_deep.append("\n");
 let e = locals_frontend::parse(too_deep); assert(e.status==2 && e.program.values.len==0);
 for rejected in ["let f: U32 -> U32 = fn x => do:\n  return x + U32.wrapping_sub(0,0)\n", "let f: U32 -> U32 = fn x => do:\n  return 1 + 2 + 3\n"] { let bad=locals_frontend::parse(rejected); assert(bad.status==5); }
 print("local value, binding, depth, and conservative proof limits passed");
}
