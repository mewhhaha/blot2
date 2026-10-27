import typed_canonical_frontend;
import typed_canonical_check;
import typed_canonical_target;
import typed_canonical_wasm;
fn main(){let s="pub let f: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let total = for i in 0..x carry (a=0) do:\n    let flag = i < 5\n    if flag:\n      next (U32.wrapping_add(a,1))\n    else:\n      stop (a)\n  return total\n";var p=typed_canonical_frontend::parse(s);assert(p.status==0 && typed_canonical_check::verify(s,p.program));let bytes=typed_canonical_wasm::emit(s,p.program);assert(bytes.len>0 && typed_canonical_target::verify(s,p.program,bytes));
 for i in bytes.len {var bad=copy(bytes);bad[i]^=1;assert(!typed_canonical_target::verify(s,p.program,bad));assert(!typed_canonical_target::verify(s,p.program,bytes[..i]));}
 for i in bytes.len-1 {if bytes[i]==0x20 || bytes[i]==0x21 || bytes[i]==0x0c || bytes[i]==0x0d || bytes[i]==0x04 {for k in 8 {if k!=bytes[i+1] {var bad=copy(bytes);bad[i+1]=k as u8;assert(!typed_canonical_target::verify(s,p.program,bad));}}}}
 for i in p.program.tree.bindings.len {for f in 4 {var q=copy(p.program);if f==0 {q.tree.bindings[i].start= -1;}else if f==1 {q.tree.bindings[i].end=9223372036854775807;}else if f==2 {q.tree.bindings[i].kind=999;}else {q.tree.bindings[i].scope= -1;}assert(!typed_canonical_check::verify(s,q));}}
 print("typed canonical lexical/loop target and binding forgery controls passed");}
