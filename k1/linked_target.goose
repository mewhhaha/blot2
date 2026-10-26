// Independent closed target checker for the private linked scalar fixture.
// It authenticates neither arbitrary artifacts nor filesystem provenance.
namespace linked_target;
import linked_program;
import link_check;
import scalar_core;
import wasm_scalar_validation;

fn done(r:wasm_scalar_validation::Reader)->bool {return wasm_scalar_validation::done(r);}
fn verify(plan:linked_program::Plan&,package:u8[:],entry:u8[:],abi:u8[:],probes:link_check::Probe[:],bytes:u8[:])->bool {
 if !linked_program::verify(plan,package,entry,abi,probes) || bytes.len<8 || bytes.len>8192 {return false;}
 let magic:u8[8]=[0,0x61,0x73,0x6d,1,0,0,0];if bytes[..8]!=magic[..]{return false;}
 let name=plan.graph.sources[plan.caller_start..plan.caller_end];if name.len<1 || name.len>4096{return false;}
 var root=wasm_scalar_validation::Reader {at:8,end:bytes.len};
 let ty=wasm_scalar_validation::section(bytes,root,1);
 if !wasm_scalar_validation::equal_payload(bytes,ty,[1,0x60,2,0x7f,0x7f,1,0x7f]) {return false;}
 let functions=wasm_scalar_validation::section(bytes,root,3);
 if !wasm_scalar_validation::equal_payload(bytes,functions,[2,0,0]) {return false;}
 var memory=wasm_scalar_validation::section(bytes,root,5);
 if wasm_scalar_validation::byte(bytes,memory)!=1 || wasm_scalar_validation::byte(bytes,memory)!=1 ||
    wasm_scalar_validation::u32_leb(bytes,memory)!=275 || wasm_scalar_validation::u32_leb(bytes,memory)!=275 || !done(memory) {return false;}
 var exports=wasm_scalar_validation::section(bytes,root,7);
 if wasm_scalar_validation::u32_leb(bytes,exports)!=1 {return false;}
 let n=wasm_scalar_validation::u32_leb(bytes,exports);
 if n!=name.len || n<0 || n>exports.end-exports.at {return false;}
 let start=exports.at;exports.at+=n;
 if bytes[start..exports.at]!=name || wasm_scalar_validation::byte(bytes,exports)!=0 ||
    wasm_scalar_validation::u32_leb(bytes,exports)!=1 || !done(exports) {return false;}
 var code=wasm_scalar_validation::section(bytes,root,10);
 if wasm_scalar_validation::u32_leb(bytes,code)!=2 {return false;}
 let plen=wasm_scalar_validation::u32_leb(bytes,code);
 if plen<0 || plen>code.end-code.at {return false;}
 var provider=wasm_scalar_validation::Reader {at:code.at,end:code.at+plen};code.at+=plen;
 if wasm_scalar_validation::byte(bytes,provider)!=0 {return false;}
 let c=plan.provider.core;let value=c.values[c.result_id];
 if value.producer==3 {
  if !wasm_scalar_validation::operand(bytes,provider,c.values[value.left_id]) ||
     !wasm_scalar_validation::operand(bytes,provider,c.values[value.right_id]) ||
     wasm_scalar_validation::byte(bytes,provider)!=plan.provider.opcode {return false;}
 } else if !wasm_scalar_validation::operand(bytes,provider,value) {return false;}
 if wasm_scalar_validation::byte(bytes,provider)!=0x0b || !done(provider) {return false;}
 let clen=wasm_scalar_validation::u32_leb(bytes,code);
 if clen<0 || clen>code.end-code.at {return false;}
 let caller:u8[8]=[0,0x20,0,0x20,1,0x10,0,0x0b];
 if clen!=caller.len || bytes[code.at..code.at+clen]!=caller[..] {return false;}
 code.at+=clen;return done(code) && done(root);
}
