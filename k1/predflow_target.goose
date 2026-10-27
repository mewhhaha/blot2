// Independently decode private lexical U32->Bool Wasm from exact checked Core.
// This is not M13, C09 or public ABI admission.
namespace predflow_target;
import unified_core;
import predflow_check;
import wasm_scalar_validation;
struct State {r:wasm_scalar_validation::Reader=wasm_scalar_validation::Reader {},steps:i64=0}
fn op(b:u8[:],s:State&,v:i64)->bool{return wasm_scalar_validation::byte(b,s.r)==v;}
struct Expected {kind:i64=0,value:i64=0}
// Explicit traversal avoids imposing a new recursion bound on left-associative
// source expressions. Actions describe expected instructions, not output.
fn expression(b:u8[:],s:State&,p:unified_core::Program&,id:i64,depth:i64)->bool {
 if depth>128 {return false;}var pending:Expected[>..]=[Expected {kind:1,value:id}];
 while pending.len>0 {
  if pending.len>32768 || s.steps>=32768 {return false;}let a=pending[pending.len-1];pending.pop();s.steps+=1;
  if a.kind==2 {if !op(b,s,a.value){return false;}continue;}
  if a.kind==3 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=a.value {return false;}continue;}
  if a.kind!=1 || a.value<1 || a.value>p.nodes.len {return false;}let n=p.nodes[a.value-1];
  if n.tag==1 {if !op(b,s,0x20) || wasm_scalar_validation::u32_leb(b,s.r)!=n.a+1 {return false;}}
  else if n.tag==2 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=n.literal {return false;}}
  else if n.tag==10 || n.tag==11 {if !op(b,s,0x41) || wasm_scalar_validation::i32_leb_bits(b,s.r)!=(if n.tag==10 {1} else {0}) {return false;}}
  else if n.tag==8 {pending.push(Expected {kind:1,value:n.a});}
  else if n.tag==3 || n.tag==4 || n.tag==5 || n.tag==6 || n.tag==7 || n.tag==9 || n.tag==18 {
   let code=if n.tag==3 || n.tag==4 {0x6a} else if n.tag==5 {0x6b} else if n.tag==6 {0x6c} else if n.tag==7 {0x71} else if n.tag==9 {0x49} else {0x4d};
   pending.push(Expected {kind:2,value:code});pending.push(Expected {kind:1,value:n.b});pending.push(Expected {kind:1,value:n.a});
  } else if n.tag==12 || n.tag==13 {
   pending.push(Expected {kind:2,value:0x0b});
   if n.tag==12 {pending.push(Expected {kind:3,value:0});pending.push(Expected {kind:2,value:0x05});pending.push(Expected {kind:1,value:n.b});}
   else {pending.push(Expected {kind:1,value:n.b});pending.push(Expected {kind:2,value:0x05});pending.push(Expected {kind:3,value:1});}
   pending.push(Expected {kind:2,value:0x7f});pending.push(Expected {kind:2,value:0x04});pending.push(Expected {kind:1,value:n.a});
  } else {return false;}
 }
 return true;
}
recursive fn statement(b:u8[:],s:State&,p:unified_core::Program&,id:i64,depth:i64)->bool {
 if depth>128 || id<1 || id>p.nodes.len || s.steps>=32768 {return false;}s.steps+=1;let n=p.nodes[id-1];
 if n.tag==17 {var pending:i64[2048]=[0;2048];pending[0]=id;var count:i64=1;while count>0 {count-=1;let q=pending[count];if q<1 || q>p.nodes.len {return false;}let x=p.nodes[q-1];if x.tag==17 {if count+2>2048{return false;}pending[count]=x.b;pending[count+1]=x.a;count+=2;}else if !statement(b,s,p,q,depth+1){return false;}}return true;}
 if n.tag==14 {return expression(b,s,p,n.a,depth+1) && op(b,s,0x21) && wasm_scalar_validation::u32_leb(b,s.r)==n.b+1;}
 if n.tag==15 {return expression(b,s,p,n.a,depth+1) && op(b,s,0x0f);}
 if n.tag==16 {if !expression(b,s,p,n.a,depth+1) || !op(b,s,0x04) || !op(b,s,0x40) || !statement(b,s,p,n.b,depth+1) {return false;}
  if n.c!=0 && (!op(b,s,0x05) || !statement(b,s,p,n.c,depth+1)) {return false;}return op(b,s,0x0b);}
 return false;
}
fn verify(source:u8[:],p:unified_core::Program&,bytes:u8[:])->bool {
 if !predflow_check::verify(source,p) || bytes.len<8 || bytes.len>source.len+65536 || bytes[..8]!=[0 as u8,97,115,109,1,0,0,0] {return false;}
 let c=p;let name=source[p.name_start..p.name_end];var root=wasm_scalar_validation::Reader {at:8,end:bytes.len};
 let ty=wasm_scalar_validation::section(bytes,root,1);if !wasm_scalar_validation::equal_payload(bytes,ty,[1,0x60,2,0x7f,0x7f,1,0x7f]) {return false;}
 let f=wasm_scalar_validation::section(bytes,root,3);if !wasm_scalar_validation::equal_payload(bytes,f,[1,0]) {return false;}
 var mem=wasm_scalar_validation::section(bytes,root,5);if wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || !wasm_scalar_validation::done(mem) {return false;}
 var ex=wasm_scalar_validation::section(bytes,root,7);if wasm_scalar_validation::u32_leb(bytes,ex)!=1 {return false;}let n=wasm_scalar_validation::u32_leb(bytes,ex);
 if n<0 || n>ex.end-ex.at {return false;}let a=ex.at;ex.at+=n;if bytes[a..ex.at]!=name || wasm_scalar_validation::byte(bytes,ex)!=0 || wasm_scalar_validation::u32_leb(bytes,ex)!=0 || !wasm_scalar_validation::done(ex) {return false;}
 var code=wasm_scalar_validation::section(bytes,root,10);if wasm_scalar_validation::u32_leb(bytes,code)!=1 {return false;}let size=wasm_scalar_validation::u32_leb(bytes,code);if size<0 || size>code.end-code.at {return false;}
 var s=State {r:wasm_scalar_validation::Reader {at:code.at,end:code.at+size}};code.at+=size;if !wasm_scalar_validation::done(code) {return false;}
 if c.bindings.len==0 {if !op(bytes,s,0){return false;}}else {if !op(bytes,s,1) || wasm_scalar_validation::u32_leb(bytes,s.r)!=c.bindings.len || !op(bytes,s,0x7f){return false;}}
 if !statement(bytes,s,c,c.root,0){return false;}
 if !op(bytes,s,0) || !op(bytes,s,0x0b) || !wasm_scalar_validation::done(s.r) {return false;}
 var custom=wasm_scalar_validation::section(bytes,root,0);let key=wasm_scalar_validation::u32_leb(bytes,custom);if key<0 || key>custom.end-custom.at || bytes[custom.at..custom.at+key]!="blot.k1.fixture.memory" {return false;}custom.at+=key;
 let metadata="{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
 return custom.ok && bytes[custom.at..custom.end]==metadata && wasm_scalar_validation::done(root);
}
