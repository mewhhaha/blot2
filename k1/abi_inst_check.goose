// Independent exact target decoder for the single fixed direct call fixture;
// source, type, private dictionary and every target byte must match.
namespace abi_inst_check;
import abi_inst_source;
import abi_product_schema;
import abi_product_check;
fn verify(module:u8[:],bytes:u8[:])->bool {
 let t=abi_inst_source::parse(module);if !abi_inst_source::verify(module,t){return false;}
 let typ=module[t.start..t.end];let schema=abi_product_schema::canonical(typ);if !abi_product_check::verify(typ,schema){return false;}
 let prefix:u8[108]=[0,0x61,0x73,0x6d,1,0,0,0,1,14,2,0x60,4,0x7f,0x7f,0x7f,0x7f,0,0x60,3,0x7f,0x7f,0x7f,0,
  3,3,2,0,1,5,4,1,1,1,1,7,29,3,6,'m','e','m','o','r','y',2,0,8,'i','d','e','n','t','i','t','y',0,0,5,'a','p','p','l','y',0,1,
  10,31,2,15,0,0x20,1,0x20,3,0x20,2,0x28,2,0,0xfc,0x0a,0,0,0x0b,13,0,0x41,0,0x20,1,0x41,0x80,2,0x20,2,0x10,0,0x0b,
  11,23,1,0,0x41,0x80,2,0x0b,16];
 if bytes.len!=124 || bytes[..108]!=prefix[..]{return false;}
 let tail:u8[12]=[4,0,0,0,3,0,0,0,7,0,0,0];let n=t.count as u32;let size=n*4;return bytes[108]==size && bytes[109]==0 && bytes[110]==0 && bytes[111]==0 &&
 bytes[112..124]==tail[..];
}
