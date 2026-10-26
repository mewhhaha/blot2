import locals_frontend;
import locals_check;
import locals_wasm;
fn exercise(source: u8[:]) {
 var r = locals_frontend::parse(source); assert(r.status == 0 && locals_check::verify(source,r.program));
 for i in r.program.values.len {
  let old = r.program.values[i];
  for field in 5 {
   for val in [-1,0,1,2,2048,9999999,i+1,i+2] {
    r.program.values[i] = old;
    let before = if field==0 { old.kind } else if field==1 { old.start } else if field==2 { old.end } else if field==3 { old.a } else { old.b };
    if field==0 { r.program.values[i].kind=val; } else if field==1 { r.program.values[i].start=val; } else if field==2 { r.program.values[i].end=val; } else if field==3 { r.program.values[i].a=val; } else { r.program.values[i].b=val; }
    if val != before { assert(!locals_check::verify(source,r.program) && locals_wasm::emit(source,r.program).len == 0); }
   }
  }
  r.program.values[i] = old; r.program.values[i].literal ^= 1;
  assert(!locals_check::verify(source,r.program)); r.program.values[i] = old;
 }
 for i in r.program.bindings.len {
   let old = r.program.bindings[i];
   for field in 3 { for val in [-1,0,1,2,2048,9999999,i+1] {
     r.program.bindings[i]=old;
     let before=if field==0 {old.start} else if field==1 {old.end} else {old.value};
     if field==0 {r.program.bindings[i].start=val;} else if field==1 {r.program.bindings[i].end=val;} else {r.program.bindings[i].value=val;}
     if before!=val { assert(!locals_check::verify(source,r.program)); }
   } }
   r.program.bindings[i]=old;
 }
 let cond = r.program.cond_a; r.program.cond_a=-1; assert(!locals_check::verify(source,r.program)); r.program.cond_a=cond;
 let yes = r.program.yes; r.program.yes=-1; assert(!locals_check::verify(source,r.program)); r.program.yes=yes;
 var bytes: u8[>..] = []; bytes.append(source);
 for i in bytes.len {
   let old=bytes[i];
   for replacement in [0 as u8,' ', '\n', 'x', '0', '+', 255] {
     bytes[i]=replacement;
     let candidate=locals_frontend::parse(bytes);
     if candidate.status==0 { assert(locals_check::verify(bytes,candidate.program)); }
     if bytes[i]!=old { assert(!locals_check::verify(bytes,r.program) && locals_wasm::emit(bytes,r.program).len==0); }
   }
   bytes[i]=old;
 }
}
fn main() {
 exercise("let f: U32 -> U32 = fn x => do:\n  let a = U32.wrapping_add(x,4294967295)\n  let b: U32 = a + 0\n  if b < 10:\n    return U32.wrapping_mul(b,3)\n  else:\n    return b & 255\n");
 exercise("let result: U32 -> U32 = fn input => do:\n  return (1 + 2) & input\n");
 print("local syntax and Core mutation controls passed");
}
