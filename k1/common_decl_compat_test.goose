import std;
import common_decl_dispatch;
import generic_callable;
fn main(){for arg in ["U32","Bool"] {for result in ["U32","Bool"] {for form in 2 {for n in ["0","1","7","4294967295"] {for choice in 4 {var sig:u8[>..]=[];if form==0 {format(sig,arg," -> ",result);}else {format(sig,"Fn[static,Many,",arg,",",result,"]");}var body:u8[>..]=[];if choice==0 {body.append("  return x\n");}else if choice==1 {format(body,"  return x < ",n,"\n");}else if choice==2 {body.append("  if x:\n    return 1\n  return 7\n");}else {format(body,"  let y = x\n  return y < ",n,"\n");}let s=str("pub let f: ",sig," ! {} resources {depth: 1, frame: 0} = fn x => do:\n",body);let old=generic_callable::compile(s);let now=common_decl_dispatch::compile(s);
 if old.status==0 {assert(now.status==0 && now.argument==old.argument && now.result==old.result && now.wasm[..]==old.wasm[..]);}
 else if now.status!=0 {assert(now.status==old.status && now.wasm.len==0);}
 else {assert(now.argument==(if arg=="U32" {1} else {2}) && now.result==(if result=="U32" {1} else {2}) && now.wasm.len>0);}
 }}}}}print("common declaration old/new status and byte compatibility passed");}
