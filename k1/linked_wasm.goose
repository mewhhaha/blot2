// Private two-function U32 linked-call emitter. No production host ABI,
// complete work receipt, artifact provenance or general compiler is claimed.
namespace linked_wasm;
import linked_program;
import linked_target;
import link_check;
import wasm;
import scalar_core;
fn section(out:u8[>..]&,id:u8,payload:u8[:]) {out.push(id);wasm::unsigned_leb(out,payload.len);out.append(payload);}
fn operand(out:u8[>..]&,value:scalar_core::ScalarValue) {
 if value.producer==1 {out.push(0x20);out.push(1);}else {out.push(0x41);wasm::signed_i32_leb(out,value.literal);}
}
fn emit(plan:linked_program::Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:]) -> u8[] {
 if !linked_program::verify(plan,package,entry,abi,probes) {return [];}
 let name=plan.graph.sources[plan.caller_start..plan.caller_end];
 if name.len<1 || name.len>4096 || !wasm::identifier(name) {return [];}
 let c=plan.provider.core;let value=c.values[c.result_id];var provider:u8[>..]=[0];
 if value.producer==3 {operand(provider,c.values[value.left_id]);operand(provider,c.values[value.right_id]);provider.push(plan.provider.opcode as u8);}
 else {operand(provider,value);}provider.push(0x0b);
 let caller:u8[8]=[0,0x20,0,0x20,1,0x10,0,0x0b];
 var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
 let types:u8[7]=[1,0x60,2,0x7f,0x7f,1,0x7f];section(out,1,types);
 let functions:u8[3]=[2,0,0];section(out,3,functions);
 var memory:u8[>..]=[1,1];wasm::unsigned_leb(memory,275);wasm::unsigned_leb(memory,275);section(out,5,memory);
 var exports:u8[>..]=[1];wasm::unsigned_leb(exports,name.len);exports.append(name);exports.push(0);exports.push(1);section(out,7,exports);
 var code:u8[>..]=[2];wasm::unsigned_leb(code,provider.len);code.append(provider);wasm::unsigned_leb(code,caller.len);code.append(caller);section(out,10,code);
 if !linked_target::verify(plan,package,entry,abi,probes,out) {return [];}
 return out;
}
