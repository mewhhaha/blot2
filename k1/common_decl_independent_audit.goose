import common_decl_frontend;
import common_decl_verify;
import common_decl_wasm;
import common_decl_dispatch;
import common_decl_header;
import common_target;
fn yes(s:u8[:]) {var p=common_decl_frontend::parse(s);assert(p.status==0 && common_decl_verify::verify(s,p.program));let bytes=common_decl_wasm::emit(s,p.program);assert(bytes.len>0);let flat=common_decl_header::project(s,p.program.header);assert(common_target::verify(flat,p.program.body,bytes));
 for i in s.len {var x:u8[>..]=[];x.append(s);x[i]^=1;assert(!common_decl_verify::verify(x,p.program));}
 for f in 11 {var q=copy(p.program);if f==0 {q.header.ok=false;}else if f==1 {q.header.let_start= -1;}else if f==2 {q.header.type_start= -1;}else if f==3 {q.header.type_end=9223372036854775807;}else if f==4 {q.header.effect_start= -1;}else if f==5 {q.header.resources_end=9223372036854775807;}else if f==6 {q.header.argument^=3;}else if f==7 {q.header.result^=3;}else if f==8 {q.header.depth+=1;}else if f==9 {q.header.frame+=1;}else {q.header.form=3;}assert(!common_decl_verify::verify(s,q) && common_decl_wasm::emit(s,q).len==0);}
 for i in bytes.len-1 {if bytes[i]==0x20 || bytes[i]==0x21 || bytes[i]==0x04 || bytes[i]==0x05 || bytes[i]==0x41 {for k in 8 {if k!=bytes[i+1] {var q=copy(bytes);q[i+1]=k as u8;assert(!common_target::verify(flat,p.program.body,q));}}}}
}
fn no(s:u8[:]) {let c=common_decl_dispatch::compile(s);assert(c.status!=0 && c.wasm.len==0);}
fn main(){
 yes("pub let f: Fn[static,Many,U32,Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 4294967295 && (x + 1) < 7\n");
 yes("pub let f: Fn[static,Many,Bool,Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return x || #False\n  return #True\n");
 no("pub let f: Bool -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 1\n");
 no("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x + 1\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  return x < 4294967295 && y + 1 < 7\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 4294967295 || x + 1 < 7\n");
 no("pub let f: Bool -> Bool ! {host} resources {depth: 1, frame: 0} = fn x => do:\n  return x\n");
 print("independent common declaration types, source, proof and target controls passed");
}
