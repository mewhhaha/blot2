// Executed witness for the independently checked closed U32 carry-loop Core.
// Private fixture ABI: run(n,c) copies n initialized static U32 inputs into a
// separate fixed builder, and returns n; -1 means fixture preflight rejected
// before writes. length/capacity/at expose only the initialized result for
// tests. This is not a K1 Fn/View/Builder ABI, source/loan authority, frame
// arena implementation or M13 certificate. The non-exported memory prevents
// raw host mutation; each run assumes previous result loans have ended.
namespace loop_wasm;
import wasm;
import loop_core;
import loop_validate;
fn byte(out: u8[>..]&, v: u8) { out.push(v); }
fn leb(out: u8[>..]&, v: i64) { wasm::unsigned_leb(out,v); }
fn c(out: u8[>..]&, v: u32) { byte(out,0x41); wasm::signed_i32_leb(out,v); }
fn get(out: u8[>..]&, v: i64) { byte(out,0x20); leb(out,v); }
fn set(out: u8[>..]&, v: i64) { byte(out,0x21); leb(out,v); }
fn load(out: u8[>..]&, offset: i64) { byte(out,0x28); byte(out,2); leb(out,offset); }
fn store(out: u8[>..]&, offset: i64) { byte(out,0x36); byte(out,2); leb(out,offset); }
fn section(out: u8[>..]&, id: u8, data: u8[:]) { byte(out,id); leb(out,data.len); out.append(data); }
fn reject_if(out: u8[>..]&) { byte(out,0x04); byte(out,0x40); c(out,4294967295); byte(out,0x0f); byte(out,0x0b); }
fn addr(out: u8[>..]&, base: u32, local: i64) { c(out,base); get(out,local); c(out,4); byte(out,0x6c); byte(out,0x6a); }
// -1 emits normal code. Test-only values 0..128 trap after that many complete
// prefix publications; 129..256 trap between the corresponding element store
// and publication of that element's length. These are engine traps, not
// recoverable language failures; prefix tests discard the fixture instance.
fn run_body(input_len: u32, fault_after: i64) -> u8[>..] {
    var out: u8[>..] = [1,1,0x7f]; // one local: iteration i at index 2
    get(out,0); c(out,input_len); byte(out,0x4b); reject_if(out);
    get(out,1); c(out,128); byte(out,0x4b); reject_if(out);
    get(out,0); get(out,1); byte(out,0x4b); reject_if(out); // Le(n,c)
    c(out,16); c(out,0); store(out,0); c(out,20); get(out,1); store(out,0);
    if fault_after == 0 { byte(out,0x00); }
    c(out,0); set(out,2);
    byte(out,0x02); byte(out,0x40); byte(out,0x03); byte(out,0x40);
      get(out,2); get(out,0); byte(out,0x4f); byte(out,0x0d); leb(out,1); // i >= n exits
      addr(out,1024,2); addr(out,64,2); load(out,0); store(out,0); // complete scalar first
      if fault_after >= 129 {
          get(out,2); c(out,(fault_after-129) as u32); byte(out,0x46);
          byte(out,0x04); byte(out,0x40); byte(out,0x00); byte(out,0x0b);
      }
      c(out,16); get(out,2); c(out,1); byte(out,0x6a); store(out,0); // Init(next)=i+1
      if fault_after > 0 && fault_after <= 128 {
          get(out,2); c(out,(fault_after-1) as u32); byte(out,0x46);
          byte(out,0x04); byte(out,0x40); byte(out,0x00); byte(out,0x0b);
      }
      get(out,2); c(out,1); byte(out,0x6a); set(out,2);
      byte(out,0x0c); leb(out,0);
    byte(out,0x0b); byte(out,0x0b);
    get(out,0); byte(out,0x0b); return out;
}
fn at_body() -> u8[>..] {
    var out: u8[>..] = [0];
    get(out,0); c(out,16); load(out,0); byte(out,0x4f);
    byte(out,0x04); byte(out,0x40); byte(out,0x00); byte(out,0x0b);
    addr(out,1024,0); load(out,0); byte(out,0x0b); return out;
}
fn observation(offset: u32) -> u8[>..] { var out: u8[>..] = [0]; c(out,offset); load(out,0); byte(out,0x0b); return out; }
fn export_fn(out: u8[>..]&, name: u8[:], index: i64) { leb(out,name.len); out.append(name); byte(out,0); leb(out,index); }
fn add_body(code: u8[>..]&, body: u8[:]) { leb(code,body.len); code.append(body); }
fn emit_test(core: loop_core::Core&, source: u8[:], expected: loop_core::Context, values: u32[:], fault_after: i64) -> u8[] {
    if values.len > 128 || fault_after < -1 || fault_after > 256 || !loop_validate::verify(core,source,expected) { return []; }
    var out: u8[>..] = [0,0x61,0x73,0x6d,1,0,0,0];
    let types: u8[16] = [3,0x60,2,0x7f,0x7f,1,0x7f,0x60,1,0x7f,1,0x7f,0x60,0,1,0x7f]; section(out,1,types);
    let funcs: u8[5] = [4,0,1,2,2]; section(out,3,funcs);
    let memory: u8[4] = [1,1,1,1]; section(out,5,memory);
    var exports: u8[>..] = [4]; export_fn(exports,"run",0); export_fn(exports,"at",1); export_fn(exports,"length",2); export_fn(exports,"capacity",3); section(out,7,exports);
    var code: u8[>..] = [4]; add_body(code,run_body(values.len as u32,fault_after)); add_body(code,at_body());
    add_body(code,observation(16)); add_body(code,observation(20)); section(out,10,code);
    var data: u8[>..] = [1,0]; c(data,64); byte(data,0x0b); leb(data,values.len*4);
    for v in values { for k in 4 { byte(data,(v >> (8*k) & 255) as u8); } }
    section(out,11,data); return out;
}
fn emit(core: loop_core::Core&, source: u8[:], expected: loop_core::Context, values: u32[:]) -> u8[] {
    return emit_test(core,source,expected,values,-1);
}
