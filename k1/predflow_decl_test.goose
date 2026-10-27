import os;
import generic_callable;
import predicate_frontend;
import predicate_wasm;
import predflow_decl_frontend;
import predflow_decl_verify;
import predflow_decl_wasm;
fn yes(s:u8[:],i:i64){var p=predflow_decl_frontend::parse(s);if p.status!=0 {print("status ",p.status);}assert(p.status==0 && predflow_decl_verify::verify(s,p.program));let bytes=predflow_decl_wasm::emit(s,p.program);assert(bytes.len>0 && write_file(str("preddecl-",i,".wasm"),bytes));let r=generic_callable::compile(s);assert(r.status==0 && r.argument==1 && r.result==2 && r.wasm[..]==bytes[..]);
 for j in s.len {var x:u8[>..]=[];x.append(s);x[j]^=1;assert(!predflow_decl_verify::verify(x,p.program) && predflow_decl_wasm::emit(x,p.program).len==0);}
 for f in 6 {var b=copy(p.program);if f==0 {b.head.type_start= -1;}else if f==1 {b.head.type_end=9223372036854775807;}else if f==2 {b.head.depth=0;}else if f==3 {b.head.form=3;}else if f==4 {b.body.root= -1;}else {b.body.nodes[0].tag=999;}assert(!predflow_decl_verify::verify(s,b) && predflow_decl_wasm::emit(s,b).len==0);}}
fn no(s:u8[:]) {let r=generic_callable::compile(s);assert(r.status!=0 && r.wasm.len==0);}
fn main(){yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n",0);
 yes("pub let f: Fn[static, Many, U32, Bool] ! {} resources {depth: 2, frame: 64} = fn x => do:\n  if x <= 4294967294:\n    return (x + 1) < 100\n  return #False\n",1);
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #True || (x + 1) < 1\n",2);
 let old="pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => return x < 7\n";var p=predicate_frontend::parse(old);assert(p.status==0);let b=predicate_wasm::emit(old,p.program);let c=generic_callable::compile(old);assert(c.status==0 && c.wasm[..]==b[..]);
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return #False || (x + 1) < 100\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: U32 -> Bool ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 1\n");
 print("source-bound lexical predicate dispatch passed");}
