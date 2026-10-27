import generic_callable;
import predflow_decl_frontend;
import predflow_decl_verify;
import predflow_decl_wasm;
fn yes(s:u8[:]) {var p=predflow_decl_frontend::parse(s);assert(p.status==0 && predflow_decl_verify::verify(s,p.program));let out=predflow_decl_wasm::emit(s,p.program);assert(out.len>0);let common=generic_callable::compile(s);assert(common.status==0 && common.argument==1 && common.result==2 && common.wasm[..]==out[..]);
 for j in s.len {var q:u8[>..]=[];q.append(s);q[j]^=1;assert(!predflow_decl_verify::verify(q,p.program) && predflow_decl_wasm::emit(q,p.program).len==0);}
 for f in 9 {var q=copy(p.program);if f==0 {q.head.ok=false;}else if f==1 {q.head.let_start= -1;}else if f==2 {q.head.type_start= -1;}else if f==3 {q.head.type_end=9223372036854775807;}else if f==4 {q.head.effect_start= -1;}else if f==5 {q.head.resources_end=9223372036854775807;}else if f==6 {q.head.depth+=1;}else if f==7 {q.head.frame+=1;}else {q.head.form=3;}assert(!predflow_decl_verify::verify(s,q) && predflow_decl_wasm::emit(s,q).len==0);}
 for i in p.program.body.nodes.len {for f in 8 {var q=copy(p.program);if f==0 {q.body.nodes[i].tag=999;}else if f==1 {q.body.nodes[i].start= -1;}else if f==2 {q.body.nodes[i].end=9223372036854775807;}else if f==3 {q.body.nodes[i].a= -1;}else if f==4 {q.body.nodes[i].b= -1;}else if f==5 {q.body.nodes[i].c= -1;}else if f==6 {q.body.nodes[i].literal^=1;}else {q.body.nodes[i].ty^=1;}assert(!predflow_decl_verify::verify(s,q));}}
}
fn no(s:u8[:]) {let r=generic_callable::compile(s);assert(r.status!=0 && r.wasm.len==0);}
fn main(){
 yes("pub let f: Fn[static,Many,U32,Bool] ! {} resources {depth: 2, frame: 8} = fn x => do:\n  let y = x\n  return y < 4294967295 && (x + 1) < 7\n");
 yes("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return 4294967294 < y || (x + 1) < 20\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = U32.wrapping_add(x,1)\n  return x < 4294967295 && (y + 1) < 5\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  return x < 4294967295 || (x + 1) < 5\n");
 no("pub let f: U32 -> Bool ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x < 4294967295:\n    let y = x\n    return y < 5\n  return y < 5\n");
 no("pub let f: U32 -> Bool ! {reserve} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 5\n");
 no("pub let f: Fn[static,Once,U32,Bool] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  let y = x\n  return y < 5\n");
 print("independent lexical predicate declaration source, type, effects and scope passed");
}
