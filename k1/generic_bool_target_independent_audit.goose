import generic_bool_frontend;
import generic_bool_wasm;
import generic_bool_target;
fn main() {
 let s="pub let select: Fn[static, Many, Bool, U32] ! {} resources {depth: 3, frame: 64} = fn b => do:\n  if (#True && b) || (#False && b):\n    if b && (#True || b):\n      return 4294967295\n    else:\n      return 0\n  else:\n    return 2147483648\n";
 var p=generic_bool_frontend::parse(s);assert(p.status==0);let bytes=generic_bool_wasm::emit(s,p.program);assert(bytes.len>0 && generic_bool_target::verify(s,p.program,bytes));
 for i in s.len {var changed:u8[>..]=[];changed.append(s);changed[i]^=1;assert(!generic_bool_target::verify(changed,p.program,bytes));}
 for i in bytes.len-1 {if bytes[i]==0x20 || bytes[i]==0x04 || bytes[i]==0x05 || bytes[i]==0x41 {for v in 8 {if v!=bytes[i+1] {var changed=copy(bytes);changed[i+1]=v as u8;assert(!generic_bool_target::verify(s,p.program,changed));}}}}
 for i in p.program.body.body.tree.nodes.len {for field in 6 {var changed=copy(p.program);if field==0 {changed.body.body.tree.nodes[i].tag=999;}else if field==1 {changed.body.body.tree.nodes[i].start= -1;}else if field==2 {changed.body.body.tree.nodes[i].end=9223372036854775807;}else if field==3 {changed.body.body.tree.nodes[i].a= -1;}else if field==4 {changed.body.body.tree.nodes[i].b= -1;}else {changed.body.body.tree.nodes[i].c= -1;}assert(!generic_bool_target::verify(s,changed,bytes));}}
 for i in p.program.body.body.types.len {var changed=copy(p.program);changed.body.body.types[i]^=1;assert(!generic_bool_target::verify(s,changed,bytes));}
 for i in p.program.body.body.literals.len {var changed=copy(p.program);changed.body.body.literals[i]^=1;assert(!generic_bool_target::verify(s,changed,bytes));}
 print("independent Bool source, tree, local and control mutation checks passed");
}
