import os;
import generic_bool_frontend;
import generic_bool_verify;
import generic_bool_wasm;
import generic_callable;
fn main(){let source="pub let f: Fn[static, Many, Bool, U32] ! {} resources {depth: 2, frame: 64} = fn x => do:\n  if (#True && x) || #False:\n    if x:\n      return 11\n    else:\n      return 1\n  else:\n    return 42\n";
 var p=generic_bool_frontend::parse(source);assert(p.status==0 && generic_bool_verify::verify(source,p.program));let bytes=generic_bool_wasm::emit(source,p.program);assert(bytes.len>0 && write_file("bool-independent.wasm",bytes));
 for i in p.program.body.body.tree.nodes.len {for f in 6 {var b=copy(p.program);if f==0 {b.body.body.tree.nodes[i].tag=999;}else if f==1 {b.body.body.tree.nodes[i].start=-1;}else if f==2 {b.body.body.tree.nodes[i].end=9223372036854775807;}else if f==3 {b.body.body.tree.nodes[i].a=9223372036854775807;}else if f==4 {b.body.body.tree.nodes[i].b=-1;}else {b.body.body.tree.nodes[i].c=-1;}assert(!generic_bool_verify::verify(source,b) && generic_bool_wasm::emit(source,b).len==0);}}
 for i in p.program.body.body.types.len {var b=copy(p.program);b.body.body.types[i]^=1;assert(!generic_bool_verify::verify(source,b));}
 for i in p.program.body.body.literals.len {var b=copy(p.program);b.body.body.literals[i]^=1;assert(!generic_bool_verify::verify(source,b));}
 for s in ["pub let f: Fn[static, Many, Bool, U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if #False:\n    return x\n  return 1\n", "pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if #False:\n    return y\n  return 1\n", "pub let f: Bool -> U32 ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  return 1\n", "pub let f: Fn[static, Once, Bool, U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return 1\n"] {let r=generic_callable::compile(s);assert(r.status!=0 && r.argument==0 && r.wasm.len==0);}
 print("independent Bool callable node/header/type adversarial controls passed");}
