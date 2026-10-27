// Independent closed Wasm decoder for the private Bool -> U32 fixture.
// Caller must supply canonical Bool 0/1. This is not public ABI or M13.
namespace generic_bool_target;
import generic_bool_core;
import generic_bool_verify;
import wasm_scalar_validation;
struct Action {kind:i64=0,value:i64=0}
fn verify(source:u8[:],p:generic_bool_core::Program&,bytes:u8[:])->bool {
 if !generic_bool_verify::verify(source,p) || bytes.len<8 || bytes.len>source.len+65536 || bytes[..8]!=[0 as u8,97,115,109,1,0,0,0] {return false;}
 var root=wasm_scalar_validation::Reader {at:8,end:bytes.len};
 let ty=wasm_scalar_validation::section(bytes,root,1);if !wasm_scalar_validation::equal_payload(bytes,ty,[1,0x60,2,0x7f,0x7f,1,0x7f]) {return false;}
 let f=wasm_scalar_validation::section(bytes,root,3);if !wasm_scalar_validation::equal_payload(bytes,f,[1,0]) {return false;}
 var mem=wasm_scalar_validation::section(bytes,root,5);if wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::byte(bytes,mem)!=1 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || wasm_scalar_validation::u32_leb(bytes,mem)!=275 || !wasm_scalar_validation::done(mem) {return false;}
 var ex=wasm_scalar_validation::section(bytes,root,7);if wasm_scalar_validation::u32_leb(bytes,ex)!=1 {return false;}let n=wasm_scalar_validation::u32_leb(bytes,ex);
 if n<0 || n>ex.end-ex.at {return false;}let a=ex.at;ex.at+=n;if bytes[a..ex.at]!=p.body.body.name || wasm_scalar_validation::byte(bytes,ex)!=0 || wasm_scalar_validation::u32_leb(bytes,ex)!=0 || !wasm_scalar_validation::done(ex) {return false;}
 var code=wasm_scalar_validation::section(bytes,root,10);if wasm_scalar_validation::u32_leb(bytes,code)!=1 {return false;}let size=wasm_scalar_validation::u32_leb(bytes,code);if size<0 || size>code.end-code.at {return false;}
 var body=wasm_scalar_validation::Reader {at:code.at,end:code.at+size};code.at+=size;if !wasm_scalar_validation::done(code) || wasm_scalar_validation::byte(bytes,body)!=0 {return false;}
 var todo:Action[>..]=[Action {kind:1,value:p.body.body.tree.root}];var steps:i64=0;
 while todo.len>0 {
  steps+=1;if steps>16384 || todo.len>16384 {return false;}let a=todo[todo.len-1];todo.pop();
  if a.kind==2 {if wasm_scalar_validation::byte(bytes,body)!=a.value{return false;}continue;}
  if a.kind==3 {if wasm_scalar_validation::byte(bytes,body)!=0x41 || wasm_scalar_validation::i32_leb_bits(bytes,body)!=a.value{return false;}continue;}
  if a.kind!=1 || a.value<1 || a.value>p.body.body.tree.nodes.len {return false;}let node=p.body.body.tree.nodes[a.value-1];
  if node.tag==1 {if wasm_scalar_validation::byte(bytes,body)!=0x20 || wasm_scalar_validation::u32_leb(bytes,body)!=1{return false;}}
  else if node.tag==2 {if wasm_scalar_validation::byte(bytes,body)!=0x41 || wasm_scalar_validation::i32_leb_bits(bytes,body)!=p.body.body.literals[a.value-1] {return false;}}
  else if node.tag==3 || node.tag==4 {if wasm_scalar_validation::byte(bytes,body)!=0x41 || wasm_scalar_validation::i32_leb_bits(bytes,body)!=(if node.tag==4 {1} else {0}) {return false;}}
  else if node.tag==5 {todo.push(Action {kind:1,value:node.a});}
  else if node.tag==7 || node.tag==8 {
   todo.push(Action {kind:2,value:0x0b});
   if node.tag==7 {todo.push(Action {kind:3,value:0});todo.push(Action {kind:2,value:0x05});todo.push(Action {kind:1,value:node.b});}
   else {todo.push(Action {kind:1,value:node.b});todo.push(Action {kind:2,value:0x05});todo.push(Action {kind:3,value:1});}
   todo.push(Action {kind:2,value:0x7f});todo.push(Action {kind:2,value:0x04});todo.push(Action {kind:1,value:node.a});
  } else if node.tag==9 {todo.push(Action {kind:2,value:0x0f});todo.push(Action {kind:1,value:node.a});}
  else if node.tag==10 {todo.push(Action {kind:2,value:0x0b});if node.c!=0 {todo.push(Action {kind:1,value:node.c});todo.push(Action {kind:2,value:0x05});}todo.push(Action {kind:1,value:node.b});todo.push(Action {kind:2,value:0x40});todo.push(Action {kind:2,value:0x04});todo.push(Action {kind:1,value:node.a});}
  else if node.tag==11 {todo.push(Action {kind:1,value:node.b});todo.push(Action {kind:1,value:node.a});}
  else {return false;}
 }
 if wasm_scalar_validation::byte(bytes,body)!=0 || wasm_scalar_validation::byte(bytes,body)!=0x0b || !wasm_scalar_validation::done(body) {return false;}
 var custom=wasm_scalar_validation::section(bytes,root,0);let key=wasm_scalar_validation::u32_leb(bytes,custom);if key<0 || key>custom.end-custom.at || bytes[custom.at..custom.at+key]!="blot.k1.fixture.memory" {return false;}custom.at+=key;
 let metadata="{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
 return custom.ok && bytes[custom.at..custom.end]==metadata && wasm_scalar_validation::done(root);
}
