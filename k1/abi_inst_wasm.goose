// Actual private two-function module. The canonical concrete caller takes
// (environment,result-slot,argument-slot) and invokes the one generic body
// with a compiler-placed dictionary. Source/loan validity remains separate.
namespace abi_inst_wasm;
import abi_inst_source;
import abi_product_link;
import generic_identity_wasm;
import wasm;
fn emit(module:u8[:])->u8[] {
 let info=abi_inst_source::parse(module);if !abi_inst_source::verify(module,info){return [];}
 let typ=module[info.start..info.end];var product=abi_product_link::make(abi_inst_source::generic(),typ,7);if product.status!=0{return [];}
 var out:u8[>..]=[0,0x61,0x73,0x6d,1,0,0,0];
 let types:u8[14]=[2,0x60,4,0x7f,0x7f,0x7f,0x7f,0,0x60,3,0x7f,0x7f,0x7f,0];generic_identity_wasm::section(out,1,types);
 let functions:u8[3]=[2,0,1];generic_identity_wasm::section(out,3,functions);
 let memory:u8[4]=[1,1,1,1];generic_identity_wasm::section(out,5,memory);
 let exports:u8[29]=[3,6,'m','e','m','o','r','y',2,0,8,'i','d','e','n','t','i','t','y',0,0,5,'a','p','p','l','y',0,1];generic_identity_wasm::section(out,7,exports);
 var code:u8[>..]=[2,15,0,0x20,1,0x20,3,0x20,2,0x28,2,0,0xfc,0x0a,0,0,0x0b];
 let caller:u8[14]=[0,0x41,0,0x20,1,0x41,0x80,0x02,0x20,2,0x10,0,0x0b,0];
 // Body has 13 bytes: zero local groups, constants/locals/call/end.
 wasm::unsigned_leb(code,13);for i in 13 {code.push(caller[i]);}generic_identity_wasm::section(out,10,code);
 var data:u8[>..]=[1,0,0x41,0x80,0x02,0x0b,16];
 for x in [product.dictionary.dictionary.size,product.dictionary.dictionary.alignment,product.dictionary.dictionary.flags,product.dictionary.dictionary.schema_id] {data.push((x&255) as u8);data.push(((x>>8)&255) as u8);data.push(((x>>16)&255) as u8);data.push(((x>>24)&255) as u8);}
 generic_identity_wasm::section(out,11,data);return out;
}
