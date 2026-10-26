// Private full-byte structure check: source-bound worker bodies come from the
// independently verified base; frame functions from the fixed frame fixture;
// the two canonical shim/adapter bodies are pinned. Not public ABI authority.
namespace m12_one_target;
import wasm;
import pool_guest;
import i08_same_wasm;
import i08_same_target;
import m12_adapter_core;
import m12_adapter_verify;
fn shim()->u8[] {return [0,32,0,69,69,4,64,0,11,32,1,65,160,128,3,71,4,64,0,11,32,2,65,128,128,3,71,4,64,0,11,65,16,40,2,0,65,128,32,71,4,64,0,11,65,20,40,2,0,65,192,1,71,4,64,0,11,65,24,40,2,0,65,128,32,71,4,64,0,11,65,36,40,2,0,65,1,71,4,64,0,11,65,144,1,40,2,0,65,1,71,4,64,0,11,65,128,2,40,2,0,65,2,71,4,64,0,11,65,192,2,40,2,0,65,1,71,4,64,0,11,65,204,2,40,2,0,65,0,71,4,64,0,11,65,128,3,40,2,0,65,8,71,4,64,0,11,65,32,40,2,0,69,4,64,0,11,65,132,2,40,2,0,65,32,40,2,0,71,4,64,0,11,65,196,2,40,2,0,65,32,40,2,0,71,4,64,0,11,32,2,40,2,4,65,8,75,4,64,0,11,65,140,2,40,2,0,32,2,40,2,4,71,4,64,0,11,32,2,40,2,4,65,16,108,65,192,0,106,65,28,40,2,0,71,4,64,0,11,32,2,40,2,4,65,16,108,65,128,32,106,65,200,2,40,2,0,71,4,64,0,11,32,2,40,2,4,69,4,64,65,136,2,40,2,0,69,69,4,64,0,11,5,65,136,2,40,2,0,65,128,32,71,4,64,0,11,11,32,2,40,2,0,65,136,2,40,2,0,71,4,64,0,11,32,2,40,2,4,65,140,2,40,2,0,71,4,64,0,11,32,2,40,2,12,65,200,2,40,2,0,71,4,64,0,11,32,2,40,2,16,65,204,2,40,2,0,71,4,64,0,11,32,2,40,2,20,65,128,3,40,2,0,71,4,64,0,11,65,1,65,32,40,2,0,65,1,65,32,40,2,0,32,2,42,2,8,16,15,32,2,40,2,4,71,4,64,0,11,32,1,32,2,40,2,4,69,4,127,65,0,5,32,2,40,2,12,11,54,2,0,32,1,32,2,40,2,4,54,2,4,11];}
fn adapter()->u8[] {return [0,32,0,69,69,4,64,0,11,65,156,3,40,2,0,65,1,71,4,64,0,11,65,152,3,40,2,0,69,69,4,64,0,11,65,148,3,40,2,0,65,128,6,71,4,64,0,11,65,144,3,40,2,0,65,128,6,73,4,64,0,11,65,144,3,40,2,0,65,128,32,75,4,64,0,11,32,2,65,236,133,3,75,4,64,0,11,32,2,65,3,113,4,64,0,11,32,2,65,168,128,3,73,4,64,0,11,32,1,65,240,133,3,75,4,64,0,11,32,1,65,3,113,4,64,0,11,32,1,65,168,128,3,73,4,64,0,11,32,1,65,16,106,32,2,77,32,2,65,20,106,32,1,77,114,69,4,64,0,11,32,2,40,2,4,32,2,40,2,16,75,4,64,0,11,65,128,128,3,32,2,40,2,0,54,2,0,65,128,128,3,32,2,40,2,4,54,2,4,65,128,128,3,32,2,40,2,8,54,2,8,65,128,128,3,32,2,40,2,12,54,2,12,65,128,128,3,32,2,40,2,16,54,2,20,65,128,128,3,65,0,54,2,16,65,0,65,160,128,3,65,128,128,3,16,20,65,160,128,3,40,2,4,32,2,40,2,4,71,4,64,0,11,32,2,40,2,4,69,4,64,65,160,128,3,40,2,0,69,69,4,64,0,11,5,65,160,128,3,40,2,0,32,2,40,2,12,71,4,64,0,11,11,32,1,65,0,54,2,0,32,1,65,160,128,3,40,2,4,54,2,4,32,1,65,160,128,3,40,2,0,54,2,8,32,1,65,160,128,3,40,2,4,54,2,12,11];}
fn verify(p:m12_adapter_core::Program&,source:u8[:],bytes:u8[:])->bool {
 if !m12_adapter_verify::verify(p,source) || bytes.len<8 || bytes[..8]!=[0 as u8,97,115,109,1,0,0,0] {return false;}
 let kernel=source[..p.split];let base=i08_same_wasm::emit(p.linked.cap.job.core,kernel,p.linked.cap.job.core.context);if base.len==0 {return false;}
 var at:i64=8;var bas:i64=8;
 let types=i08_same_target::section(bytes,at,1);if !types.ok {return false;}let expected_types:u8[48]=[7,0x60,1,0x7f,1,0x7f,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f,0x60,3,0x7f,0x7f,0x7f,1,0x7f,0x60,5,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f,0x60,6,0x7f,0x7f,0x7f,0x7f,0x7f,0x7d,1,0x7f,0x60,3,0x7f,0x7f,0x7f,0];
 if bytes[types.payload..types.end]!=expected_types[..] {return false;}at=types.end;
 let base_types=i08_same_target::section(base,bas,1);if !base_types.ok {return false;}bas=base_types.end;
 let fun=i08_same_target::section(bytes,at,3);let expected_fun:u8[23]=[22,0,1,2,0,1,3,1,3,3,4,5,1,1,1,1,4,0,2,2,2,6,6];if !fun.ok || bytes[fun.payload..fun.end]!=expected_fun[..] {return false;}at=fun.end;
 let bf=i08_same_target::section(base,bas,3);if !bf.ok {return false;}bas=bf.end;
 let mem=i08_same_target::section(bytes,at,5);let bm=i08_same_target::section(base,bas,5);
 if !mem.ok || !bm.ok || bytes[mem.start..mem.end]!=base[bm.start..bm.end] {return false;}at=mem.end;bas=bm.end;
 let ex=i08_same_target::section(bytes,at,7);if !ex.ok {return false;}var exports:u8[>..]=[16];
 for item in ["reserve","close","input_alloc","input_freeze","advance","builder_alloc","project","input_end","output_end","input_discard","frame_config","frame_top","frame_enter","frame_leave","adapter"] {
  let index=if item=="reserve" {0} else if item=="close" {11} else if item=="input_alloc" {5} else if item=="input_freeze" {6} else if item=="advance" {7} else if item=="builder_alloc" {8} else if item=="project" {15} else if item=="input_end" {12} else if item=="output_end" {13} else if item=="input_discard" {14} else if item=="frame_config" {16} else if item=="frame_top" {17} else if item=="frame_enter" {18} else if item=="frame_leave" {19} else {21};
  wasm::unsigned_leb(exports,item.len);exports.append(item);exports.push(0);wasm::unsigned_leb(exports,index);
 }
 exports.append([6,'m','e','m','o','r','y',2,0]);
 if bytes[ex.payload..ex.end]!=exports[..] {return false;}at=ex.end;
 let be=i08_same_target::section(base,bas,7);if !be.ok {return false;}bas=be.end;
 let code=i08_same_target::section(bytes,at,10);let bc=i08_same_target::section(base,bas,10);
 if !code.ok || !bc.ok || code.end!=bytes.len || bc.end!=base.len {return false;}
 let count=i08_same_target::read_leb(bytes,code.payload,code.end);let bcount=i08_same_target::read_leb(base,bc.payload,bc.end);
 if !count.ok || count.value!=22 || !bcount.ok || bcount.value!=15 {return false;}at=count.next;bas=bcount.next;
 for i in 15 {
  let a=i08_same_target::read_leb(bytes,at,code.end);let z=i08_same_target::read_leb(base,bas,bc.end);
  if !a.ok || !z.ok || a.value>code.end-a.next || z.value>bc.end-z.next {return false;}
  let ae=a.next+a.value;let ze=z.next+z.value;if bytes[at..ae]!=base[bas..ze] {return false;}at=ae;bas=ze;
 }
 if bas!=bc.end {return false;}
 let f15:u8[109]=[108,1,1,127,65,156,3,40,2,0,65,1,71,4,64,65,123,15,11,65,152,3,40,2,0,33,5,65,144,3,40,2,0,65,128,32,75,4,64,65,123,15,11,32,5,65,144,3,40,2,0,75,4,64,65,123,15,11,65,128,6,65,144,3,40,2,0,32,5,107,75,4,64,65,123,15,11,65,148,3,40,2,0,32,5,65,128,6,106,71,4,64,65,123,15,11,32,0,32,1,32,2,32,3,32,4,16,9,11];if at+f15.len>code.end || bytes[at..at+f15.len]!=f15[..] {return false;}at+=f15.len;
 let f16:u8[53]=[52,0,65,156,3,40,2,0,69,69,4,64,65,124,15,11,65,148,3,40,2,0,69,69,4,64,65,124,15,11,32,0,65,128,32,75,4,64,65,124,15,11,65,144,3,32,0,54,2,0,65,0,11];if at+f16.len>code.end || bytes[at..at+f16.len]!=f16[..] {return false;}at+=f16.len;
 let f17:u8[9]=[8,0,65,148,3,40,2,0,11];if at+f17.len>code.end || bytes[at..at+f17.len]!=f17[..] {return false;}at+=f17.len;
 let f18:u8[228]=[226,1,1,1,127,65,144,1,40,2,0,69,69,4,64,65,124,15,11,65,36,40,2,0,69,65,36,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,196,0,40,2,0,69,65,196,0,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,228,0,40,2,0,69,65,228,0,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,132,1,40,2,0,69,65,132,1,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,156,3,40,2,0,69,69,4,64,65,124,15,11,65,148,3,40,2,0,33,0,65,144,3,40,2,0,65,128,32,75,4,64,65,123,15,11,32,0,65,144,3,40,2,0,75,4,64,65,123,15,11,65,128,6,65,144,3,40,2,0,32,0,107,75,4,64,65,123,15,11,65,152,3,32,0,54,2,0,65,148,3,32,0,65,128,6,106,54,2,0,65,156,3,65,1,54,2,0,65,128,128,3,32,0,106,65,0,58,0,0,65,0,11];if at+f18.len>code.end || bytes[at..at+f18.len]!=f18[..] {return false;}at+=f18.len;
 let f19:u8[224]=[222,1,1,1,127,65,144,1,40,2,0,69,69,4,64,65,124,15,11,65,36,40,2,0,69,65,36,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,196,0,40,2,0,69,65,196,0,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,228,0,40,2,0,69,65,228,0,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,132,1,40,2,0,69,65,132,1,40,2,0,65,3,70,114,69,4,64,65,124,15,11,65,156,3,40,2,0,65,1,71,4,64,65,124,15,11,65,152,3,40,2,0,33,0,65,144,3,40,2,0,65,128,32,75,4,64,65,124,15,11,32,0,65,144,3,40,2,0,75,4,64,65,124,15,11,65,128,6,65,144,3,40,2,0,32,0,107,75,4,64,65,124,15,11,65,148,3,40,2,0,32,0,65,128,6,106,71,4,64,65,124,15,11,65,148,3,32,0,54,2,0,65,156,3,65,0,54,2,0,65,0,11];if at+f19.len>code.end || bytes[at..at+f19.len]!=f19[..] {return false;}at+=f19.len;
 let a=i08_same_target::read_leb(bytes,at,code.end);if !a.ok || a.value>code.end-a.next {return false;}let ae=a.next+a.value;let expected_shim=shim();if bytes[a.next..ae]!=expected_shim[..] {return false;}at=ae;
 let b=i08_same_target::read_leb(bytes,at,code.end);if !b.ok || b.value>code.end-b.next || b.next+b.value!=code.end {return false;}let expected_adapter=adapter();return bytes[b.next..code.end]==expected_adapter[..];
}
