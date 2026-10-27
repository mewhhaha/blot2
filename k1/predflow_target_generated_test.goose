import std;
import os;
import predflow_frontend;
import predflow_check;
import predflow_wasm;
import predflow_target;
fn main(){for i in 80 {let kind=i%4;let limit=(i*7919)%300000;var s:u8[>..]=[];s.append("let f: U32 -> Bool = fn x => do:\n  let y = x\n  return ");
 if kind==0 {format(s,"y < 4294967295 && (y + 1) < ",limit,"\n");}
 else if kind==1 {format(s,"y <= 4294967294 && (y + 1) <= ",limit,"\n");}
 else if kind==2 {format(s,"y < ",limit," || #False\n");}
 else {format(s,"4294967294 < y || (y + 1) < ",limit,"\n");}
 var p=predflow_frontend::parse(s);if p.status!=0 {print("case ",i," ",s," status ",p.status);}assert(p.status==0 && predflow_check::verify(s,p.program));let out=predflow_wasm::emit(s,p.program);assert(out.len>0 && predflow_target::verify(s,p.program,out) && write_file(str("predgen-",i,".wasm"),out));}
 print("generated Bool-return proof cases passed");}
