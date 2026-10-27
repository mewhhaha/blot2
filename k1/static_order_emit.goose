// Private immutable static-data Wasm witness. Memory is unexported and no
// write instruction exists. The host test interface is not the K1 ABI.
namespace static_order_emit;
import wasm;
import pool_guest;
import static_publish_core;
fn export_fn(out:u8[>..]&,name:u8[:],index:i64){wasm::unsigned_leb(out,name.len);out.append(name);out.push(0);wasm::unsigned_leb(out,index);}
fn emit(image:static_publish_core::Image&)->u8[] {
 var out:u8[>..]=[0,97,115,109,1,0,0,0];
 let types:u8[11]=[2,0x60,2,0x7f,0x7f,1,0x7f,0x60,0,1,0x7f];pool_guest::section(out,1,types);
 let funcs:u8[4]=[3,0,1,1];pool_guest::section(out,3,funcs);
 var memory:u8[>..]=[1,1];let pages=(image.bytes as i64+65535)/65536;wasm::unsigned_leb(memory,pages);wasm::unsigned_leb(memory,pages);pool_guest::section(out,5,memory);
 var exports:u8[>..]=[3];export_fn(exports,"read",0);export_fn(exports,"length",1);export_fn(exports,"width",2);pool_guest::section(out,7,exports);
 var code:u8[>..]=[3];var read:u8[>..]=[0,0x20,0];pool_guest::constant(read,image.rows);read.append([0x4f,0x04,0x40,0,0x0b,0x20,1]);
 pool_guest::constant(read,image.width);read.append([0x4f,0x04,0x40,0,0x0b,0x20,0]);pool_guest::constant(read,image.width);
 read.append([0x6c,0x20,1,0x6a]);pool_guest::constant(read,4);read.append([0x6c,0x28,2,0,0x0b]);pool_guest::add_body(code,read);
 var count:u8[>..]=[0];pool_guest::constant(count,image.rows);count.push(0x0b);pool_guest::add_body(code,count);
 var width:u8[>..]=[0];pool_guest::constant(width,image.width);width.push(0x0b);pool_guest::add_body(code,width);pool_guest::section(out,10,code);
 var data:u8[>..]=[1,0,0x41,0,0x0b];wasm::unsigned_leb(data,image.bytes);data.append(image.data);pool_guest::section(out,11,data);
 return out;
}
