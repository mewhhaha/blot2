// Independent structural target checker against freshly rederived source plan.
namespace chain_target;
import chain_program;
import link_check;
import wasm_scalar_validation;
fn done(r:wasm_scalar_validation::Reader)->bool{return wasm_scalar_validation::done(r);}
fn call(bytes:u8[:],body:wasm_scalar_validation::Reader&,target:i64)->bool {
 let prefix:u8[6]=[0,0x20,0,0x20,1,0x10];for b in prefix {if wasm_scalar_validation::byte(bytes,body)!=b {return false;}}
 return wasm_scalar_validation::u32_leb(bytes,body)==target && wasm_scalar_validation::byte(bytes,body)==0x0b && done(body);
}
fn verify(plan:chain_program::Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:],bytes:u8[:])->bool {
 if !chain_program::verify(plan,package,entry,abi,probes) || bytes.len<8 || bytes.len>131072 {return false;}
 let magic:u8[8]=[0,0x61,0x73,0x6d,1,0,0,0];if bytes[..8]!=magic[..] {return false;}
 let count=plan.nodes.len+plan.entries.len;var root=wasm_scalar_validation::Reader {at:8,end:bytes.len};
 let ty=wasm_scalar_validation::section(bytes,root,1);
 if !wasm_scalar_validation::equal_payload(bytes,ty,[1,0x60,2,0x7f,0x7f,1,0x7f]) {return false;}
 var funcs=wasm_scalar_validation::section(bytes,root,3);if wasm_scalar_validation::u32_leb(bytes,funcs)!=count {return false;}
 for i in count {if wasm_scalar_validation::u32_leb(bytes,funcs)!=0 {return false;}}if !done(funcs) {return false;}
 var memory=wasm_scalar_validation::section(bytes,root,5);
 if wasm_scalar_validation::byte(bytes,memory)!=1 || wasm_scalar_validation::byte(bytes,memory)!=1 ||
  wasm_scalar_validation::u32_leb(bytes,memory)!=275 || wasm_scalar_validation::u32_leb(bytes,memory)!=275 || !done(memory) {return false;}
 var exports=wasm_scalar_validation::section(bytes,root,7);if wasm_scalar_validation::u32_leb(bytes,exports)!=plan.entries.len {return false;}
 for e,i in plan.entries {let name=plan.graph.sources[e.name_start..e.name_end];let n=wasm_scalar_validation::u32_leb(bytes,exports);
  if n!=name.len || n<0 || n>exports.end-exports.at {return false;}let start=exports.at;exports.at+=n;
  if bytes[start..exports.at]!=name || wasm_scalar_validation::byte(bytes,exports)!=0 ||
   wasm_scalar_validation::u32_leb(bytes,exports)!=plan.nodes.len+i {return false;}}
 if !done(exports) {return false;}
 var code=wasm_scalar_validation::section(bytes,root,10);if wasm_scalar_validation::u32_leb(bytes,code)!=count {return false;}
 for n in plan.nodes {
  let len=wasm_scalar_validation::u32_leb(bytes,code);if len<0 || len>code.end-code.at {return false;}
  var body=wasm_scalar_validation::Reader {at:code.at,end:code.at+len};code.at+=len;
  if n.kind==2 {if !call(bytes,body,n.target) {return false;}}
  else {if wasm_scalar_validation::byte(bytes,body)!=0 {return false;}let c=n.scalar.core;let v=c.values[c.result_id];
   if v.producer==3 {if !wasm_scalar_validation::operand(bytes,body,c.values[v.left_id]) || !wasm_scalar_validation::operand(bytes,body,c.values[v.right_id]) || wasm_scalar_validation::byte(bytes,body)!=n.scalar.opcode {return false;}}
   else if !wasm_scalar_validation::operand(bytes,body,v) {return false;}
   if wasm_scalar_validation::byte(bytes,body)!=0x0b || !done(body) {return false;}}
 }
 for e in plan.entries {let len=wasm_scalar_validation::u32_leb(bytes,code);if len<0 || len>code.end-code.at {return false;}
  var body=wasm_scalar_validation::Reader {at:code.at,end:code.at+len};code.at+=len;if !call(bytes,body,e.target) {return false;}}
 return done(code) && done(root);
}
