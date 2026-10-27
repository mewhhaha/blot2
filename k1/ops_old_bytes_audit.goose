import std;
import typed_dispatch;
import short_frontend;
import short_emit;
fn main(){for name in ["f","other"] {for value in ["0","1","7","255","4294967295"] {for op in 4 {
 let body=if op==0 {str("  return U32.wrapping_sub(x,",value,")\n")} else if op==1 {str("  return U32.wrapping_mul(x,",value,")\n")} else if op==2 {str("  return x & ",value,"\n")} else {str("  return x <= ",value,"\n")};
 let result=if op==3 {"Bool"} else {"U32"};let s=str("pub let ",name,": U32 -> ",result," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body);
 let old=typed_dispatch::compile(s);var new=short_frontend::parse(s);assert(old.status==0 && new.status==0);let bytes=short_emit::emit(s,new.program);assert(bytes.len>0 && bytes[..]==old.wasm[..]);
 }}}print("independent old dispatcher operation bytes unchanged");}
