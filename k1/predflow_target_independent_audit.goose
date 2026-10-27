import predflow_frontend;
import predflow_wasm;
import predflow_target;
fn main() {
 let s="let f: U32 -> Bool = fn x => do:\n  let y = x\n  if y < 4294967295:\n    let z = y + 1\n    return z < 100 && (x < 2 || y <= 5)\n  return #False\n";
 var p=predflow_frontend::parse(s);assert(p.status==0);let bytes=predflow_wasm::emit(s,p.program);assert(bytes.len>0 && predflow_target::verify(s,p.program,bytes));
 for i in s.len {var bad:u8[>..]=[];bad.append(s);bad[i]^=1;assert(!predflow_target::verify(bad,p.program,bytes));}
 for i in bytes.len-1 {if bytes[i]==0x20 || bytes[i]==0x21 || bytes[i]==0x04 || bytes[i]==0x05 || bytes[i]==0x41 {for v in 8 {if v!=bytes[i+1] {var bad=copy(bytes);bad[i+1]=v as u8;assert(!predflow_target::verify(s,p.program,bad));}}}}
 for i in p.program.nodes.len {for f in 8 {var bad=copy(p.program);if f==0 {bad.nodes[i].tag=999;}else if f==1 {bad.nodes[i].start= -1;}else if f==2 {bad.nodes[i].end=9223372036854775807;}else if f==3 {bad.nodes[i].a= -1;}else if f==4 {bad.nodes[i].b= -1;}else if f==5 {bad.nodes[i].c= -1;}else if f==6 {bad.nodes[i].literal^=1;}else {bad.nodes[i].ty^=1;}assert(!predflow_target::verify(s,bad,bytes));}}
 for i in p.program.bindings.len {var bad=copy(p.program);bad.bindings[i].start= -1;assert(!predflow_target::verify(s,bad,bytes));}
 print("independent Bool-result target/source/slot/control mutations passed");
}
