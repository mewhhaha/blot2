import os;
import std;
import generic_bool_frontend;
import generic_bool_wasm;
import generic_bool_target;
fn check(source:u8[:],i:i64){var p=generic_bool_frontend::parse(source);if p.status!=0 {print("parse ",p.status);}assert(p.status==0);let b=generic_bool_wasm::emit(source,p.program);assert(b.len>0 && generic_bool_target::verify(source,p.program,b) && write_file(str("bool-target-",i,".wasm"),b));
 for j in b.len {var x=copy(b);x[j]^=1;assert(!generic_bool_target::verify(source,p.program,x));assert(!generic_bool_target::verify(source,p.program,b[..j]));}
 var extra:u8[>..]=[];extra.append(b);extra.push(0);assert(!generic_bool_target::verify(source,p.program,extra));assert(!generic_bool_target::verify("wrong",p.program,b));
 if i==0 {var found:i64=0;for j in b.len-2 {if b[j]==0x41 && b[j+1]==11 && b[j+2]==0x0f {var x=copy(b);x[j+1]=12;assert(!generic_bool_target::verify(source,p.program,x) && write_file("bool-valid-mutation.wasm",x));found+=1;}}assert(found==1);}
}
fn main(){
 check("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x:\n    return 11\n  return 42\n",0);
 check("pub let f: Fn[static,Many,Bool,U32] ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if x && #True:\n    return 11\n  return 42\n",1);
 check("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n  if #False || (x && #True):\n    if x:\n      return 11\n    else:\n      return 7\n  else:\n    return 42\n",2);
 var long:u8[>..]=[];long.append("pub let f: Bool -> U32 ! {} resources {depth: 1, frame: 0} = fn x => do:\n");for _ in 250 {long.append("  if #False:\n    return 1\n");}long.append("  return 42\n");var p=generic_bool_frontend::parse(long);assert(p.status==0);let bytes=generic_bool_wasm::emit(long,p.program);assert(bytes.len>0 && generic_bool_target::verify(long,p.program,bytes));
 print("independent Bool target source and Wasm decoding passed");}
