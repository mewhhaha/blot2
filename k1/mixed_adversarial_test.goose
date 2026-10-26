import mixed_frontend;
import mixed_validate;
import mixed_wasm;
fn main() {
 let s="let f: U32 -> U32 = fn x => do:\n  let sum = for i in 0..x carry (a=0) do:\n    let inner = for j in 0..2 carry (b=a) do:\n      if j < 1:\n        next (U32.wrapping_add(b, i))\n      else:\n        stop (b + 0)\n    next (inner)\n  return sum\n";
 var p=mixed_frontend::parse(s);assert(p.status==0 && mixed_validate::verify(s,p.program));
 for i in p.program.body.nodes.len {for f in 11 {for v in [-1,999999] {
  let old=p.program.body.nodes[i];
  if f==0 {p.program.body.nodes[i].tag=v;} else if f==1 {p.program.body.nodes[i].start=v;} else if f==2 {p.program.body.nodes[i].end=v;}
  else if f==3 {p.program.body.nodes[i].a=v;} else if f==4 {p.program.body.nodes[i].b=v;} else if f==5 {p.program.body.nodes[i].c=v;}
  else if f==6 {p.program.body.nodes[i].d=v;} else if f==7 {p.program.body.nodes[i].e=v;} else if f==8 {p.program.body.nodes[i].f=v;}
  else if f==9 {p.program.body.nodes[i].g=v;} else {p.program.body.nodes[i].target=v;}
  assert(!mixed_validate::verify(s,p.program) && mixed_wasm::emit(s,p.program).len==0);p.program.body.nodes[i]=old;
 }}}
 for i in p.program.body.bindings.len {for f in 4 {for v in [-1,999999] {
  let old=p.program.body.bindings[i];if f==0 {p.program.body.bindings[i].start=v;} else if f==1 {p.program.body.bindings[i].end=v;} else if f==2 {p.program.body.bindings[i].kind=v;} else {p.program.body.bindings[i].scope=v;}
  assert(!mixed_validate::verify(s,p.program));p.program.body.bindings[i]=old;
 }}}
 for bad in [
 "let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    let t = 1\n    next (t)\n  return t\n",
 "let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    let z = for j in 0..2 carry (b=a) do:\n      next (a)\n    next (b)\n  return r\n",
 "let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    if i < 2:\n      let t = i\n      next (t)\n    else:\n      next (t)\n  return r\n",
 "let f: U32 -> U32 = fn x => do:\n  let r = for i in 0..x carry (a=0) do:\n    next (a + 1)\n  return r\n"
 ] {let z=mixed_frontend::parse(bad);assert(z.status!=0);}
 print("mixed independent forged-tree and scope audit passed");
}
