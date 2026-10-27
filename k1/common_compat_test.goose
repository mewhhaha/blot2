import std;
import common_frontend;
import common_wasm;
import unified_frontend;
import unified_wasm;
import predflow_frontend;
import predflow_wasm;
fn check(s:u8[:],kind:i64) {var a=if kind==1 {unified_frontend::parse(s)} else {predflow_frontend::parse(s)};var b=common_frontend::parse(s);if a.status!=b.status {print("status mismatch ",a.status," ",b.status," ",s);}assert(a.status==b.status);if a.status==0 {let x=if kind==1 {unified_wasm::emit(s,a.program)} else {predflow_wasm::emit(s,a.program)};let y=common_wasm::emit(s,b.program);assert(x.len>0 && x[..]==y[..]);}}
fn main(){for name in ["f","value"] {for n in ["0","1","7","4294967295"] {for kind in 2 {for choice in 6 {let result=if kind==0 {"U32"} else {"Bool"};let body=if choice==0 {if kind==0 {str("  return x\n")} else {str("  return x < ",n,"\n")}} else if choice==1 {if kind==0 {str("  let y = x\n  return U32.wrapping_add(y,",n,")\n")} else {str("  let y = x\n  return y < ",n,"\n")}} else if choice==2 {if kind==0 {str("  return x + 1\n")} else {str("  return (x + 1) < ",n,"\n")}} else if choice==3 {if kind==0 {str("  return x < ",n,"\n")} else {str("  return x\n")}} else if choice==4 {if kind==0 {str("  if x < ",n,":\n    return 1\n  return 2\n")} else {str("  if x < ",n,":\n    return #True\n  return #False\n")}} else {str("  return missing\n")};let s=str("let ",name,": U32 -> ",result," = fn x => do:\n",body);check(s,kind+1);}}}}print("common scalar old/new status and byte matrix passed");}
