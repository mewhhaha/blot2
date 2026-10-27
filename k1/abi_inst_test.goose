import os;
import std;
import abi_inst_source;
import abi_inst_check;
import abi_inst_compile;
fn make(typ:u8[:])->u8[]{var out:u8[>..]=[];out.append(abi_inst_source::generic());out.append(abi_inst_source::head());out.append(typ);out.append(", ");out.append(typ);out.append("] ! {} resources {depth: 2, frame: 256} = fn x => return identity@[");out.append(typ);out.append("](x)\n");return out;}
fn make_three(a:u8[:],b:u8[:],c:u8[:])->u8[]{var out:u8[>..]=[];out.append(abi_inst_source::generic());out.append(abi_inst_source::head());out.append(a);out.append(", ");out.append(b);out.append("] ! {} resources {depth: 2, frame: 256} = fn x => return identity@[");out.append(c);out.append("](x)\n");return out;}
fn main(){
 for n in 2..17 {var typ:u8[>..]=[];typ.push('(');for i in n {if i>0 {typ.push(',');}typ.append("U32");}typ.push(')');let source=make(typ);let info=abi_inst_source::parse(source);assert(info.count==n && abi_inst_source::verify(source,info));
  let target=abi_inst_compile::emit(source);assert(target.len==124 && abi_inst_check::verify(source,target) && !abi_inst_compile::public_eligible(source));
  for i in target.len {var bad=copy(target);bad[i]^=1;assert(!abi_inst_check::verify(source,bad));assert(!abi_inst_check::verify(source,target[..i]));}
  for i in source.len {var bad=copy(source);bad[i]^=1;assert(!abi_inst_check::verify(bad,target) && abi_inst_compile::emit(bad).len==0);}
  var filename:u8[>..]=[];format(filename,"abi-inst-",n,".wasm");assert(write_file(filename,target));
 }
 for bad in ["(U32,F32)","(U32)","(U32,)","(U32,U32)junk"] {let source=make(bad);assert(abi_inst_compile::emit(source).len==0);}
 let bad_result=make_three("(U32,U32)","(U32,U32,U32)","(U32,U32)");let bad_argument=make_three("(U32,U32)","(U32,U32)","(U32,U32,U32)");assert(abi_inst_compile::emit(bad_result).len==0 && abi_inst_compile::emit(bad_argument).len==0);
 let x=make("(U32,U32)");var split=copy(x);for i in split.len {if split[i]=='@' {split[i]='!';break;}}assert(abi_inst_compile::emit(split).len==0);
 print("explicit source tuple substitution bound to checked caller and generic target");
}
