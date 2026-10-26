namespace multilink_wasm;
import multilink_program;
import multilink_target;
import link_check;
import linked_wasm;
import wasm;
fn emit(plan:multilink_program::Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:])->u8[] {
 if !multilink_program::verify(plan,package,entry,abi,probes) {return [];}
 let count=plan.entries.len;
 var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
 let types:u8[7]=[1,0x60,2,0x7f,0x7f,1,0x7f];linked_wasm::section(out,1,types);
 var funcs:u8[>..]=[];wasm::unsigned_leb(funcs,count*2);for i in count*2 {funcs.push(0);}linked_wasm::section(out,3,funcs);
 var memory:u8[>..]=[1,1];wasm::unsigned_leb(memory,275);wasm::unsigned_leb(memory,275);linked_wasm::section(out,5,memory);
 var exports:u8[>..]=[];wasm::unsigned_leb(exports,count);
 for e,i in plan.entries {let name=plan.graph.sources[e.name_start..e.name_end];
  if name.len<1 || name.len>4096 || !wasm::identifier(name) {return [];}
  wasm::unsigned_leb(exports,name.len);exports.append(name);exports.push(0);wasm::unsigned_leb(exports,count+i);
 }linked_wasm::section(out,7,exports);
 var code:u8[>..]=[];wasm::unsigned_leb(code,count*2);
 for e in plan.entries {
  var body:u8[>..]=[0];let c=e.provider.core;let v=c.values[c.result_id];
  if v.producer==3 {linked_wasm::operand(body,c.values[v.left_id]);linked_wasm::operand(body,c.values[v.right_id]);body.push(e.provider.opcode as u8);}
  else {linked_wasm::operand(body,v);}body.push(0x0b);wasm::unsigned_leb(code,body.len);code.append(body);
 }
 for i in count {var body:u8[>..]=[0,0x20,0,0x20,1,0x10];wasm::unsigned_leb(body,i);body.push(0x0b);wasm::unsigned_leb(code,body.len);code.append(body);}
 linked_wasm::section(out,10,code);
 if !multilink_target::verify(plan,package,entry,abi,probes,out) {return [];}
 return out;
}
