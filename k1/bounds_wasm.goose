// Private executable proof witness. A fixed unexported one-page memory holds
// U32 values; host supplies (initialized_prefix_length,index). The preflight
// rejects a prefix larger than the actual fixed data. The guarded read itself
// uses the source's i < v.length fact, with no capacity-as-initialization or
// endpoint inference. This is not a K1 View ABI, public wrapper or certificate.
namespace bounds_wasm;
import bounds_core;
import bounds_validate;
import wasm;
fn byte(out: u8[>..]&, value: u8) { out.push(value); }
fn leb(out: u8[>..]&, value: i64) { wasm::unsigned_leb(out,value); }
fn c(out: u8[>..]&, value: u32) { byte(out,0x41); wasm::signed_i32_leb(out,value); }
fn get(out: u8[>..]&, local: i64) { byte(out,0x20); leb(out,local); }
fn section(out: u8[>..]&, id: u8, data: u8[:]) { byte(out,id); leb(out,data.len); out.append(data); }
fn emit(program: bounds_core::Program&, expected_source: u8[:], expected: bounds_core::Context, values: u32[:]) -> u8[] {
    if values.len > 256 || !bounds_validate::verify(program,expected_source,expected) { return []; }
    var body: u8[>..] = [0];
    // The raw host fixture may choose only an initialized prefix of the
    // embedded backing. A real K1 caller must establish its own View authority.
    get(body,0); c(body,values.len as u32); byte(body,0x4b); // n > backing
    byte(body,0x04); byte(body,0x40); byte(body,0x00); byte(body,0x0b);
    get(body,1); get(body,0); byte(body,0x49); // exact source guard i < n
    byte(body,0x04); byte(body,0x7f); // if result i32
      c(body,64); get(body,1); c(body,4); byte(body,0x6c); byte(body,0x6a);
      byte(body,0x28); byte(body,2); leb(body,0); // guarded view.read
    byte(body,0x05); c(body,program.fallback); byte(body,0x0b); byte(body,0x0b);
    var out: u8[>..] = [0,0x61,0x73,0x6d,1,0,0,0];
    let types: u8[7] = [1,0x60,2,0x7f,0x7f,1,0x7f]; section(out,1,types);
    let functions: u8[2] = [1,0]; section(out,3,functions);
    let memory: u8[4] = [1,1,1,1]; section(out,5,memory);
    let exports: u8[8] = [1,4,'r','e','a','d',0,0]; section(out,7,exports);
    var code: u8[>..] = [1]; leb(code,body.len); code.append(body); section(out,10,code);
    var data: u8[>..] = [1,0]; c(data,64); byte(data,0x0b); leb(data,values.len*4);
    for value in values { for k in 4 { data.push((value >> (8*k) & 255) as u8); } }
    section(out,11,data); return out;
}
