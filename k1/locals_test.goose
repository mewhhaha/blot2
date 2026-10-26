import std;
import os;
import locals_frontend;
import locals_check;
import locals_wasm;

fn accepted(source: u8[:], index: i64) {
    var r = locals_frontend::parse(source);
    if r.status != 0 { print("unexpected source rejection ",r.status," for ",source); }
    assert(r.status == 0 && locals_check::verify(source,r.program));
    let bytes = locals_wasm::emit(source,r.program);
    assert(bytes.len > 0 && write_file(str("locals_",index,".wasm"),bytes));
    assert(locals_wasm::emit("different source",r.program).len == 0);
    for i in r.program.values.len {
        let old = r.program.values[i]; r.program.values[i].kind = 99;
        assert(!locals_check::verify(source,r.program) && locals_wasm::emit(source,r.program).len == 0);
        r.program.values[i] = old; r.program.values[i].a = -1;
        assert(!locals_check::verify(source,r.program)); r.program.values[i] = old;
        r.program.values[i].b = 9999999; assert(!locals_check::verify(source,r.program)); r.program.values[i] = old;
        r.program.values[i].literal ^= 1; assert(!locals_check::verify(source,r.program)); r.program.values[i] = old;
    }
    for i in r.program.bindings.len {
        let old = r.program.bindings[i]; r.program.bindings[i].value = -1;
        assert(!locals_check::verify(source,r.program)); r.program.bindings[i] = old;
        r.program.bindings[i].start = -1; assert(!locals_check::verify(source,r.program)); r.program.bindings[i] = old;
    }
    let old = r.program.source[0]; r.program.source[0] = 'x';
    assert(!locals_check::verify(source,r.program)); r.program.source[0] = old;
}
fn rejected(source: u8[:], status: i64) {
    let r = locals_frontend::parse(source);
    if r.status != status { print("unexpected status ",r.status," expected ",status," for ",source); }
    assert(r.status == status && r.program.values.len == 0);
}
fn main() {
    accepted("let f: U32 -> U32 = fn x => do:\n  return x\n",0);
    accepted("let f: U32 -> U32 = fn x => do:\n  let y: U32 = x + 0\n  let z = U32.wrapping_add(y,1)\n  return z\n",1);
    accepted("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,4294967295)\n",2);
    accepted("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_sub(0,x)\n",3);
    accepted("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_mul(x,3)\n",4);
    accepted("let f: U32 -> U32 = fn x => do:\n  return 4294967294 + 1\n",5);
    accepted("let f: U32 -> U32 = fn x => do:\n  let y = x & 255\n  if y < 10:\n    return U32.wrapping_add(y,1)\n  else:\n    return y\n",6);
    accepted("let f: U32 -> U32 = fn x => do:\n  if x < 5:\n    return x\n  return 0\n",7);
    accepted("let f: U32 -> U32 = fn x => do:\n  return x & 15 + 0\n",8);
    accepted("let f: U32 -> U32 = fn x => do:\n  return 0 + x\n",9);
    rejected("let f: U32 -> U32 = fn x => do:\n  return x + 1\n",5);
    rejected("let f: U32 -> U32 = fn x => do:\n  return 4294967295 + 1\n",5);
    rejected("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,1) + 1\n",5);
    rejected("let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(4294967295,1) + 1\n",5);
    rejected("let f: F32 -> F32 = fn x => do:\n  return x\n",1);
    rejected("let f: U32 -> U32 = fn x => do:\n  return 1.0\n",1);
    rejected("let f: U32 -> U32 = fn x => do:\n  return F32.wrapping_add(x,1)\n",1);
    rejected("let f: U32 -> U32 = fn x => do:\n  let y = y\n  return y\n",3);
    rejected("let f: U32 -> U32 = fn x => do:\n  let y = x\n  let y = x\n  return y\n",4);
    rejected("let f: U32 -> U32 = fn x => do:\n  let x = 0\n  return x\n",4);
    rejected("let f: U32 -> U32 = fn x => do:\n  if x < 1:\n    return 1\n",1);
    rejected("let f: U32 -> U32 = fn x => do:\n  return x\n  return x\n",1);
    let original = "let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,1)\n";
    let other = "let f: U32 -> U32 = fn x => do:\n  return U32.wrapping_add(x,2)\n";
    var bound = locals_frontend::parse(original);
    assert(bound.status == 0 && original.len == other.len && !locals_check::verify(other,bound.program));
    assert(locals_wasm::emit(other,bound.program).len == 0);
    var long: u8[>..] = []; long.append("let f: U32 -> U32 = fn x => do:\n");
    for i in 128 { long.append(str("  let a",i," = x\n")); }
    long.append("  return a127\n"); accepted(long,10);
    print("private U32 local source/Core/lowering laws passed");
}
