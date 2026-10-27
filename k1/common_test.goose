import std;
import os;
import common_frontend;
import common_check;
import common_wasm;
import unified_frontend;
import unified_wasm;
import predflow_frontend;
import predflow_wasm;
fn compare(source:u8[:],kind:i64,index:i64) {
 var r=common_frontend::parse(source);var before=if kind==1 {unified_frontend::parse(source)} else {predflow_frontend::parse(source)};
 assert(r.status==before.status);if r.status!=0 {assert(r.program.source.len==0);return;}
 assert(common_check::verify(source,r.program));let bytes=common_wasm::emit(source,r.program);let old=if kind==1 {unified_wasm::emit(source,before.program)} else {predflow_wasm::emit(source,before.program)};assert(bytes.len>0 && bytes[..]==old[..] && write_file(str("common-",index,".wasm"),bytes));
 for i in source.len {var wrong:u8[>..]=[];wrong.append(source);wrong[i]^=1;assert(!common_check::verify(wrong,r.program));}
 for i in r.program.nodes.len {for f in 8 {var bad=copy(r.program);if f==0 {bad.nodes[i].tag=999;}else if f==1 {bad.nodes[i].start= -1;}else if f==2 {bad.nodes[i].end=9223372036854775807;}else if f==3 {bad.nodes[i].a= -1;}else if f==4 {bad.nodes[i].b= -1;}else if f==5 {bad.nodes[i].c= -1;}else if f==6 {bad.nodes[i].literal^=1;}else {bad.nodes[i].ty^=1;}assert(!common_check::verify(source,bad) && common_wasm::emit(source,bad).len==0);}}
}
fn main(){
 compare("let f: U32 -> U32 = fn x => do:\n  let y = x\n  if y < 4294967295:\n    return y + 1\n  return y\n",1,0);
 compare("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return y < 4294967295 && (y + 1) < 100\n",2,1);
 compare("let f: U32 -> U32 = fn x => do:\n  return x + 1\n",1,2);
 compare("let f: U32 -> Bool = fn x => do:\n  return x < 4294967295 || (x + 1) < 5\n",2,3);
 compare("let f: U32 -> U32 = fn x => do:\n  return x < 5\n",1,4);
 compare("let f: U32 -> Bool = fn x => do:\n  return x\n",2,5);
 print("common scalar Core source/type/proof compatibility passed");
}
