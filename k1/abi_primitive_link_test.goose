import os;
import abi_primitive_link;
import abi_primitive_schema;
import abi_primitive_check;
fn main(){
 let source="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return x\n";
 let wrong="pub let identity: forall [T: Type] => Fn[static, Many, T, T] ! {} resources {depth: 1, frame: 256} = fn x => return y\n";
 assert(abi_primitive_schema::canonical(0).len==0 && abi_primitive_schema::canonical(5).len==0);
 for code in 1..5 {let typ=code as u32;var c=abi_primitive_link::make(source,typ);assert(c.status==0 && abi_primitive_link::verify(c,source,typ) && !abi_primitive_link::public_eligible(c));
  for other in 1..5 {if other!=code {assert(!abi_primitive_link::verify(c,source,other as u32));}}
  assert(!abi_primitive_link::verify(c,wrong,typ));
  for i in c.schema.len {var forged=copy(c);forged.schema[i]^=1;assert(!abi_primitive_link::verify(forged,source,typ));assert(!abi_primitive_check::verify(c.schema[..i],typ));}
  for i in c.source.len {var forged=copy(c);forged.source[i]^=1;assert(!abi_primitive_link::verify(forged,source,typ));}
  for i in c.dictionary.schema.len {var forged=copy(c);forged.dictionary.schema[i]^=1;assert(!abi_primitive_link::verify(forged,source,typ));}
  for i in c.target.len {var forged=copy(c);forged.target[i]^=1;assert(!abi_primitive_link::verify(forged,source,typ));}
  for i in 32 {var forged=copy(c);forged.policy_hash[i]^=1;assert(!abi_primitive_link::verify(forged,source,typ));}
  var forged=copy(c);forged.dictionary.dictionary.size+=1;assert(!abi_primitive_link::verify(forged,source,typ));
  var forged2=copy(c);forged2.dictionary.dictionary.alignment+=1;assert(!abi_primitive_link::verify(forged2,source,typ));
  var forged3=copy(c);forged3.dictionary.dictionary.flags^=1;assert(!abi_primitive_link::verify(forged3,source,typ));
  var forged4=copy(c);forged4.dictionary.dictionary.schema_id+=1;assert(!abi_primitive_link::verify(forged4,source,typ));
  assert(write_file(if typ==1 {"abi-unit.wasm"} else if typ==2 {"abi-u32.wasm"} else if typ==3 {"abi-f32.wasm"} else {"abi-bool.wasm"},c.target));
 }
 print("private builtin ABI schemas bind generic source, dictionary and exact target");
}
