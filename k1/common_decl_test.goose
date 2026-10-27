import std;
import os;
import common_decl_frontend;
import common_decl_verify;
import common_decl_wasm;
import common_decl_dispatch;
import generic_callable;
import common_decl_header;
import common_target;
fn yes(s:u8[:],i:i64,arg:i64,res:i64,form:i64){var p=common_decl_frontend::parse(s);if p.status!=0 {print("status ",p.status," ",s);}assert(p.status==0 && p.program.header.argument==arg && p.program.header.result==res && p.program.header.form==form && common_decl_verify::verify(s,p.program));let b=common_decl_wasm::emit(s,p.program);assert(b.len>0 && write_file(str("common-decl-",i,".wasm"),b));
 let prior=generic_callable::compile(s);let out=common_decl_dispatch::compile(s);assert(out.status==0 && out.argument==arg && out.result==res);if prior.status==0 {assert(prior.wasm[..]==out.wasm[..]);}else {assert(out.wasm[..]==b[..]);}
 for j in s.len {var changed:u8[>..]=[];changed.append(s);changed[j]^=1;assert(!common_decl_verify::verify(changed,p.program) && common_decl_wasm::emit(changed,p.program).len==0);}
 let flat=common_decl_header::project(s,p.program.header);assert(common_target::verify(flat,p.program.body,b));
 for j in p.program.body.nodes.len {for f in 8 {var q=copy(p.program);if f==0 {q.body.nodes[j].tag=999;}else if f==1 {q.body.nodes[j].start= -1;}else if f==2 {q.body.nodes[j].end=9223372036854775807;}else if f==3 {q.body.nodes[j].a= -1;}else if f==4 {q.body.nodes[j].b= -1;}else if f==5 {q.body.nodes[j].c= -1;}else if f==6 {q.body.nodes[j].literal^=1;}else {q.body.nodes[j].ty^=1;}assert(!common_decl_verify::verify(s,q) && common_decl_wasm::emit(s,q).len==0);}}
 for j in b.len {var changed=copy(b);changed[j]^=1;assert(!common_target::verify(flat,p.program.body,changed));}
 for f in 11 {var q=copy(p.program);if f==0 {q.header.ok=false;}else if f==1 {q.header.let_start= -1;}else if f==2 {q.header.type_start= -1;}else if f==3 {q.header.type_end=9223372036854775807;}else if f==4 {q.header.effect_start= -1;}else if f==5 {q.header.resources_end=9223372036854775807;}else if f==6 {q.header.argument=3;}else if f==7 {q.header.result=3;}else if f==8 {q.header.depth=0;}else if f==9 {q.header.form=3;}else {q.body.root= -1;}assert(!common_decl_verify::verify(s,q) && common_decl_wasm::emit(s,q).len==0);}
}
fn no(s:u8[:]) {let p=common_decl_frontend::parse(s);let old=generic_callable::compile(s);let result=common_decl_dispatch::compile(s);assert(p.status!=0 && p.program.source.len==0);if old.status!=0 {assert(result.status==old.status && result.wasm.len==0);}else {assert(result.status==0 && result.wasm[..]==old.wasm[..]);}}
fn main(){for arg in 1..3 {for res in 1..3 {for form in 1..3 {let a=if arg==1 {"U32"} else {"Bool"};let z=if res==1 {"U32"} else {"Bool"};let sig=if form==1 {str(a," -> ",z)} else {str("Fn[static,Many,",a,",",z,"]")};let body=if arg==1 && res==1 {"  let y = x\n  if y < 4294967295:\n    return y + 1\n  return y\n"} else if arg==1 {"  let y = x\n  return y < 4294967295 && y + 1 < 100\n"} else if res==1 {"  let y = 7\n  if x:\n    return y\n  return 42\n"} else {"  if x:\n    return x\n  return #False\n"};let source=str("pub let f: ",sig," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body);yes(source,(arg-1)*4+(res-1)*2+form-1,arg,res,form);}}}
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x + 1\n");
 no("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 1\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 4294967295 || x + 1 < 1\n");
 no("pub let f: Fn[static,Once,Bool,Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: Bool -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 no("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x\nlet x = 1\n");
 print("private common public-shaped declaration source and dispatch passed");}
