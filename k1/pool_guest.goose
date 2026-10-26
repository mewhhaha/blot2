// Private unoptimized Wasm allocator fixture, emitted directly by Goose.
// This is a deterministic test model, NOT the K1 runtime, compiler lowering,
// ownership validator, host bridge, or structural certificate. Its exported
// memory exists only for tests and may be forged by the test host.
// Slot/bitmap consistency and exclusive ownership are trusted invariants:
// a forged owner can point at another live owner's bitmap run. Local extent
// checks do not detect that alias or establish safe behavior under hostile
// memory corruption; the guest is not a validator for untrusted authority.
// Four owner records at 16..144, one bitmap word at 144, six granules at 4096.
namespace pool_guest;
import wasm;

fn byte(out: u8[>..]&, opcode: u8) { out.push(opcode); }
fn uleb(out: u8[>..]&, value: i64) { wasm::unsigned_leb(out, value); }
fn constant(out: u8[>..]&, value: u32) { byte(out, 0x41); wasm::signed_i32_leb(out, value); }
fn get(out: u8[>..]&, index: i64) { byte(out, 0x20); uleb(out, index); }
fn set(out: u8[>..]&, index: i64) { byte(out, 0x21); uleb(out, index); }
fn call(out: u8[>..]&, index: i64) { byte(out, 0x10); uleb(out, index); }
fn load(out: u8[>..]&, offset: i64) { byte(out, 0x28); byte(out, 2); uleb(out, offset); }
fn store(out: u8[>..]&, offset: i64) { byte(out, 0x36); byte(out, 2); uleb(out, offset); }
fn section(out: u8[>..]&, id: u8, payload: u8[:]) {
    byte(out, id); uleb(out, payload.len); out.append(payload);
}
fn return_if(out: u8[>..]&, value: u32) {
    byte(out, 0x04); byte(out, 0x40); // if void
    constant(out, value); byte(out, 0x0f); // return
    byte(out, 0x0b); // end
}
fn slot_address(out: u8[>..]&, index: i64) {
    constant(out, 16); get(out, index); constant(out, 32); byte(out, 0x6c); byte(out, 0x6a);
}
fn field(out: u8[>..]&, slot_ptr: i64, offset: i64) { get(out, slot_ptr); load(out, offset); }
fn field_const(out: u8[>..]&, slot_ptr: i64, offset: i64, value: u32) {
    get(out, slot_ptr); constant(out, value); store(out, offset);
}
fn field_local(out: u8[>..]&, slot_ptr: i64, offset: i64, index: i64) {
    get(out, slot_ptr); get(out, index); store(out, offset);
}
fn add_body(section_body: u8[>..]&, body: u8[:]) { uleb(section_body, body.len); section_body.append(body); }

// () -> i32: first reusable slot index, -1 if exhausted, -2 for a malformed
// encountered owner record. Linear scans and explicit branches are unoptimized.
fn find_slot() -> u8[>..] {
    var b: u8[>..] = [1, 1, 0x7f]; // one i32 local (index 0)
    constant(b, 0); set(b, 0);
    byte(b, 0x02); byte(b, 0x40); // block
    byte(b, 0x03); byte(b, 0x40); // loop
    get(b, 0); constant(b, 4); byte(b, 0x4f); // i32.ge_u
    byte(b, 0x0d); uleb(b, 1); // br_if block
    slot_address(b, 0); load(b, 20); constant(b, 4); byte(b, 0x4b); // state > 4
    return_if(b, 4294967294); // -2
    slot_address(b, 0); load(b, 20); byte(b, 0x45); // state == Free
    byte(b, 0x04); byte(b, 0x40);
      slot_address(b, 0); load(b, 16); constant(b, 4294967295); byte(b, 0x46);
      return_if(b, 4294967294); // free with max generation is malformed
      get(b, 0); byte(b, 0x0f);
    byte(b, 0x0b);
    get(b, 0); constant(b, 1); byte(b, 0x6a); set(b, 0);
    byte(b, 0x0c); uleb(b, 0); // br loop
    byte(b, 0x0b); byte(b, 0x0b);
    constant(b, 4294967295); byte(b, 0x0b); // -1
    return b;
}

// (needed:i32)->i32: ascending first-fit contiguous run, -1 on failure.
fn find_run() -> u8[>..] {
    var b: u8[>..] = [1, 3, 0x7f]; // locals i=1, run=2, begin=3
    get(b, 0); byte(b, 0x45); return_if(b, 0);
    get(b, 0); constant(b, 6); byte(b, 0x4b); return_if(b, 4294967295);
    constant(b, 0); set(b, 1); constant(b, 0); set(b, 2); constant(b, 0); set(b, 3);
    byte(b, 0x02); byte(b, 0x40);
    byte(b, 0x03); byte(b, 0x40);
    get(b, 1); constant(b, 6); byte(b, 0x4f); byte(b, 0x0d); uleb(b, 1);
    constant(b, 144); load(b, 0); constant(b, 1); get(b, 1); byte(b, 0x74); byte(b, 0x71); byte(b, 0x45);
    byte(b, 0x04); byte(b, 0x40); // if free
      get(b, 2); byte(b, 0x45);
      byte(b, 0x04); byte(b, 0x40); get(b, 1); set(b, 3); byte(b, 0x0b);
      get(b, 2); constant(b, 1); byte(b, 0x6a); set(b, 2);
      get(b, 2); get(b, 0); byte(b, 0x46);
      byte(b, 0x04); byte(b, 0x40); get(b, 3); byte(b, 0x0f); byte(b, 0x0b);
    byte(b, 0x05); // else occupied
      constant(b, 0); set(b, 2);
    byte(b, 0x0b);
    get(b, 1); constant(b, 1); byte(b, 0x6a); set(b, 1);
    byte(b, 0x0c); uleb(b, 0);
    byte(b, 0x0b); byte(b, 0x0b);
    constant(b, 4294967295); byte(b, 0x0b);
    return b;
}

// (bytes:i32)->i32: positive slot on success, -1 overflow, -2 no slot,
// -3 no contiguous space, -4 internal corruption. Mutations occur only after
// rounding and both searches succeed.
fn reserve() -> u8[>..] {
    var b: u8[>..] = [1, 5, 0x7f]; // slot=1, rounded=2, needed=3, begin=4, ptr=5
    get(b, 0); constant(b, 4294963200); byte(b, 0x4b); return_if(b, 4294967295);
    get(b, 0); constant(b, 4095); byte(b, 0x6a); constant(b, 4294963200); byte(b, 0x71); set(b, 2);
    call(b, 2); set(b, 1);
    get(b, 1); constant(b, 4294967294); byte(b, 0x46); return_if(b, 4294967292);
    get(b, 1); constant(b, 4294967295); byte(b, 0x46); return_if(b, 4294967294);
    get(b, 2); constant(b, 12); byte(b, 0x76); set(b, 3); // shr_u
    get(b, 3); call(b, 3); set(b, 4);
    get(b, 4); constant(b, 4294967295); byte(b, 0x46); return_if(b, 4294967293);
    // bitmap |= ((1 << needed) - 1) << begin; needed 0 gives zero.
    constant(b, 144); constant(b, 144); load(b, 0);
    constant(b, 1); get(b, 3); byte(b, 0x74); constant(b, 1); byte(b, 0x6b);
    get(b, 4); byte(b, 0x74); byte(b, 0x72); store(b, 0);
    slot_address(b, 1); set(b, 5);
    get(b, 5); get(b, 3); byte(b, 0x45);
    byte(b, 0x04); byte(b, 0x7f); // if (result i32)
      constant(b, 0);
    byte(b, 0x05);
      constant(b, 4096); get(b, 4); constant(b, 4096); byte(b, 0x6c); byte(b, 0x6a);
    byte(b, 0x0b); store(b, 0);
    field_local(b, 5, 4, 0); field_local(b, 5, 8, 2); field_const(b, 5, 12, 0);
    get(b, 5); field(b, 5, 16); constant(b, 1); byte(b, 0x6a); store(b, 16);
    field_const(b, 5, 20, 1); field_const(b, 5, 24, 0); field_const(b, 5, 28, 0);
    get(b, 1); constant(b, 1); byte(b, 0x6a); byte(b, 0x0b);
    return b;
}

// (slot:i32,generation:i32)->i32: 0 success, -4 invalid slot/handle/state or
// corrupt extent. Check the complete bitmap run before clearing any bit.
fn close() -> u8[>..] {
    var b: u8[>..] = [1, 4, 0x7f]; // ptr=2, first=3, count=4, mask=5
    get(b, 0); byte(b, 0x45); return_if(b, 4294967292);
    get(b, 0); constant(b, 4); byte(b, 0x4b); return_if(b, 4294967292);
    get(b, 1); byte(b, 0x45); return_if(b, 4294967292);
    constant(b, 16); get(b, 0); constant(b, 1); byte(b, 0x6b); constant(b, 32); byte(b, 0x6c); byte(b, 0x6a); set(b, 2);
    field(b, 2, 20); constant(b, 1); byte(b, 0x47); return_if(b, 4294967292); // state != Open
    field(b, 2, 16); get(b, 1); byte(b, 0x47); return_if(b, 4294967292);
    field(b, 2, 12); field(b, 2, 4); byte(b, 0x4b); return_if(b, 4294967292); // top > requested
    field(b, 2, 4); constant(b, 4294963200); byte(b, 0x4b); return_if(b, 4294967292);
    field(b, 2, 4); constant(b, 4095); byte(b, 0x6a); constant(b, 4294963200); byte(b, 0x71);
    field(b, 2, 8); byte(b, 0x47); return_if(b, 4294967292);
    field(b, 2, 8); byte(b, 0x45);
    byte(b, 0x04); byte(b, 0x40); // if zero rounded
      field(b, 2, 0); byte(b, 0x45); byte(b, 0x45); return_if(b, 4294967292);
    byte(b, 0x05); // nonzero extent
      field(b, 2, 0); constant(b, 4096); byte(b, 0x49); return_if(b, 4294967292); // base < pool start
      field(b, 2, 0); constant(b, 4096); byte(b, 0x6b); constant(b, 4095); byte(b, 0x71);
      byte(b, 0x45); byte(b, 0x45); return_if(b, 4294967292); // misaligned
      field(b, 2, 0); constant(b, 4096); byte(b, 0x6b); constant(b, 12); byte(b, 0x76); set(b, 3);
      field(b, 2, 8); constant(b, 12); byte(b, 0x76); set(b, 4);
      get(b, 3); constant(b, 6); byte(b, 0x4b); return_if(b, 4294967292);
      get(b, 4); constant(b, 6); get(b, 3); byte(b, 0x6b); byte(b, 0x4b); return_if(b, 4294967292);
      constant(b, 1); get(b, 4); byte(b, 0x74); constant(b, 1); byte(b, 0x6b); get(b, 3); byte(b, 0x74); set(b, 5);
      constant(b, 144); load(b, 0); get(b, 5); byte(b, 0x71); get(b, 5); byte(b, 0x47); return_if(b, 4294967292);
      constant(b, 144); constant(b, 144); load(b, 0); get(b, 5); constant(b, 4294967295); byte(b, 0x73); byte(b, 0x71); store(b, 0);
    byte(b, 0x0b);
    get(b, 2); get(b, 1); constant(b, 4294967295); byte(b, 0x46);
    byte(b, 0x04); byte(b, 0x7f); constant(b, 3); byte(b, 0x05); constant(b, 0); byte(b, 0x0b); store(b, 20);
    constant(b, 0); byte(b, 0x0b);
    return b;
}

fn emit() -> u8[>..] {
    var out: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    // Three types: (i32)->i32; (i32,i32)->i32; ()->i32.
    var types: u8[>..] = [3, 0x60, 1, 0x7f, 1, 0x7f,
                          0x60, 2, 0x7f, 0x7f, 1, 0x7f, 0x60, 0, 1, 0x7f];
    section(out, 1, types);
    // reserve type 0; close type 1; find_slot type 2; find_run type 0.
    var functions: u8[>..] = [4, 0, 1, 2, 0]; section(out, 3, functions);
    // Fixed one-page memory; zero imports and no memory.grow instruction.
    var memory: u8[>..] = [1, 1, 1, 1]; section(out, 5, memory);
    var exports: u8[>..] = [3];
    for byte_value in [7, 'r', 'e', 's', 'e', 'r', 'v', 'e', 0, 0,
                       5, 'c', 'l', 'o', 's', 'e', 0, 1,
                       6, 'm', 'e', 'm', 'o', 'r', 'y', 2, 0] { exports.push(byte_value as u8); }
    section(out, 7, exports);
    var code: u8[>..] = [4];
    add_body(code, reserve()); add_body(code, close()); add_body(code, find_slot()); add_body(code, find_run());
    section(out, 10, code);
    return out;
}
