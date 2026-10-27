import wasm;
import wasm_fast;
fn main() {
 for name_size in [1,2,126,127,128,129,16383,16384] {
  var name:u8[>..]=[];for i in name_size {name.push('a');}
  for body_size in [0,1,2,126,127,128,129,16383,16384] {
   var body:u8[>..]=[];for i in body_size {body.push((i%256) as u8);}
   let a=wasm::emit_body(name,body);let b=wasm_fast::emit_body(name,body);
   assert(a.len>0 && a[..]==b[..]);
  }
 }
 for s in ["", "_", "U32", "bad-name", "9bad"] {
  assert(wasm::emit_body(s,[]).len==0 && wasm_fast::emit_body(s,[]).len==0);
 }
 var long_name:u8[>..]=[];for i in 1048576 {long_name.push('a');}
 let reference=wasm::emit_body(long_name,[0 as u8,0x20,1,0x0b]);
 let direct=wasm_fast::emit_body(long_name,[0 as u8,0x20,1,0x0b]);
 assert(reference[..]==direct[..]);
 print("direct Wasm section encoding matches reference bytes at LEB boundaries");
}
