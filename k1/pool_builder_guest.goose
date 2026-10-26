// Private emitted-Wasm integration fixture: fixed pool -> one U32 destination
// per owner -> append builder -> frozen view. The host exports are test-only;
// source checking, affine capabilities, lexical loans and global bitmap/owner
// disjointness are NOT established by these raw integers or memory records.
// Pool slots occupy 16..144, bitmap 144, fixture descriptors 160..256, and
// the backing pool 4096..28672. Descriptor state is 1 live or 2 frozen.
namespace pool_builder_guest;
import pool_guest;
import wasm;

fn byte(b: u8[>..]&, v: u8) { pool_guest::byte(b, v); }
fn c(b: u8[>..]&, v: u32) { pool_guest::constant(b, v); }
fn get(b: u8[>..]&, i: i64) { pool_guest::get(b, i); }
fn set(b: u8[>..]&, i: i64) { pool_guest::set(b, i); }
fn call(b: u8[>..]&, i: i64) { pool_guest::call(b, i); }
fn load(b: u8[>..]&, i: i64) { pool_guest::load(b, i); }
fn store(b: u8[>..]&, i: i64) { pool_guest::store(b, i); }
fn fail_if(b: u8[>..]&, v: u32) { pool_guest::return_if(b, v); }
fn field(b: u8[>..]&, ptr: i64, offset: i64) { pool_guest::field(b, ptr, offset); }
fn field_const(b: u8[>..]&, ptr: i64, offset: i64, value: u32) { pool_guest::field_const(b, ptr, offset, value); }
fn field_local(b: u8[>..]&, ptr: i64, offset: i64, index: i64) { pool_guest::field_local(b, ptr, offset, index); }
fn descriptor(b: u8[>..]&, slot: i64) {
    c(b, 160); get(b, slot); c(b, 1); byte(b, 0x6b); c(b, 24); byte(b, 0x6c); byte(b, 0x6a);
}

// (slot,generation)->slot pointer or zero; validate local extent and bitmap
// before addressing backing bytes. Global disjointness remains a trusted pool
// invariant, as in pool_guest; a forged alias can still point at another run.
fn valid_owner() -> u8[>..] {
    var b: u8[>..] = [1, 4, 0x7f]; // ptr=2, first=3, count=4, mask=5
    get(b, 0); byte(b, 0x45); fail_if(b, 0);
    get(b, 0); c(b, 4); byte(b, 0x4b); fail_if(b, 0);
    get(b, 1); byte(b, 0x45); fail_if(b, 0);
    c(b, 16); get(b, 0); c(b, 1); byte(b, 0x6b); c(b, 32); byte(b, 0x6c); byte(b, 0x6a); set(b, 2);
    field(b, 2, 20); c(b, 1); byte(b, 0x47); fail_if(b, 0);
    field(b, 2, 16); get(b, 1); byte(b, 0x47); fail_if(b, 0);
    field(b, 2, 12); field(b, 2, 4); byte(b, 0x4b); fail_if(b, 0);
    field(b, 2, 4); c(b, 4294963200); byte(b, 0x4b); fail_if(b, 0);
    field(b, 2, 4); c(b, 4095); byte(b, 0x6a); c(b, 4294963200); byte(b, 0x71);
    field(b, 2, 8); byte(b, 0x47); fail_if(b, 0);
    field(b, 2, 8); byte(b, 0x45); byte(b, 0x04); byte(b, 0x40);
      field(b, 2, 0); byte(b, 0x45); byte(b, 0x45); fail_if(b, 0);
    byte(b, 0x05);
      field(b, 2, 0); c(b, 4096); byte(b, 0x49); fail_if(b, 0);
      field(b, 2, 0); c(b, 4096); byte(b, 0x6b); c(b, 4095); byte(b, 0x71);
      byte(b, 0x45); byte(b, 0x45); fail_if(b, 0);
      field(b, 2, 0); c(b, 4096); byte(b, 0x6b); c(b, 12); byte(b, 0x76); set(b, 3);
      field(b, 2, 8); c(b, 12); byte(b, 0x76); set(b, 4);
      get(b, 3); c(b, 6); byte(b, 0x4b); fail_if(b, 0);
      get(b, 4); c(b, 6); get(b, 3); byte(b, 0x6b); byte(b, 0x4b); fail_if(b, 0);
      c(b, 1); get(b, 4); byte(b, 0x74); c(b, 1); byte(b, 0x6b); get(b, 3); byte(b, 0x74); set(b, 5);
      c(b, 144); load(b, 0); get(b, 5); byte(b, 0x71); get(b, 5); byte(b, 0x47); fail_if(b, 0);
    byte(b, 0x0b);
    get(b, 2); byte(b, 0x0b); return b;
}

// (slot,generation,capacity)->0, -1 SizeOverflow, -2 NoSpace, -4 fault.
// The exclusive frontier and absence of live loans are caller preconditions.
// All failing branches precede every write to owner, descriptor or data.
fn begin() -> u8[>..] {
    var b: u8[>..] = [1, 5, 0x7f]; // owner=3 desc=4 aligned=5 bytes=6 data=7
    get(b, 0); get(b, 1); call(b, 4); set(b, 3);
    get(b, 3); byte(b, 0x45); fail_if(b, 4294967292);
    descriptor(b, 0); set(b, 4);
    field(b, 4, 0); c(b, 1); byte(b, 0x46); field(b, 4, 4); get(b, 1); byte(b, 0x46); byte(b, 0x71); fail_if(b, 4294967292);
    get(b, 2); c(b, 1073741823); byte(b, 0x4b); fail_if(b, 4294967295);
    get(b, 2); c(b, 4); byte(b, 0x6c); set(b, 6);
    field(b, 3, 12); c(b, 3); byte(b, 0x6a); c(b, 4294967292); byte(b, 0x71); set(b, 5);
    get(b, 5); field(b, 3, 4); byte(b, 0x4b); fail_if(b, 4294967294);
    get(b, 6); field(b, 3, 4); get(b, 5); byte(b, 0x6b); byte(b, 0x4b); fail_if(b, 4294967294);
    field(b, 3, 0); get(b, 5); byte(b, 0x6a); set(b, 7);
    get(b, 3); get(b, 5); get(b, 6); byte(b, 0x6a); store(b, 12);
    field_const(b, 4, 0, 1); field_local(b, 4, 4, 1);
    field_local(b, 4, 8, 7); field_local(b, 4, 12, 2); field_const(b, 4, 16, 0);
    c(b, 0); byte(b, 0x0b); return b;
}

// (owner pointer,desc pointer,state)->0 or 1. Ensure local descriptor range
// lies inside requested bytes before indexing. No pointer grants authority.
fn valid_descriptor() -> u8[>..] {
    var b: u8[>..] = [1, 1, 0x7f]; // offset=3
    field(b, 1, 0); get(b, 2); byte(b, 0x47); fail_if(b, 0);
    field(b, 1, 4); field(b, 0, 16); byte(b, 0x47); fail_if(b, 0);
    field(b, 1, 16); field(b, 1, 12); byte(b, 0x4b); fail_if(b, 0);
    // Frozen empty views use the canonical data pointer zero. They cannot
    // perform a load, even when the underlying destination had capacity.
    get(b, 2); c(b, 2); byte(b, 0x46); field(b, 1, 16); byte(b, 0x45); byte(b, 0x71);
    byte(b, 0x04); byte(b, 0x40);
      field(b, 1, 8); byte(b, 0x45); byte(b, 0x45); fail_if(b, 0);
      c(b, 1); byte(b, 0x0f);
    byte(b, 0x0b);
    field(b, 1, 8); field(b, 0, 0); byte(b, 0x49); fail_if(b, 0);
    field(b, 1, 8); field(b, 0, 0); byte(b, 0x6b); set(b, 3);
    get(b, 3); c(b, 3); byte(b, 0x71); byte(b, 0x45); byte(b, 0x45); fail_if(b, 0);
    get(b, 3); field(b, 0, 12); byte(b, 0x4b); fail_if(b, 0);
    field(b, 1, 12); field(b, 0, 12); get(b, 3); byte(b, 0x6b); c(b, 2); byte(b, 0x76); byte(b, 0x4b); fail_if(b, 0);
    c(b, 1); byte(b, 0x0b); return b;
}

// (slot,generation,value)->0, -3 full, -4 invalid. The value expression is
// already complete on entry: write the scalar first, then publish length.
fn append() -> u8[>..] {
    var b: u8[>..] = [1, 2, 0x7f]; // owner=3 desc=4
    get(b, 0); get(b, 1); call(b, 4); set(b, 3);
    get(b, 3); byte(b, 0x45); fail_if(b, 4294967292);
    descriptor(b, 0); set(b, 4);
    get(b, 3); get(b, 4); c(b, 1); call(b, 6); byte(b, 0x45); fail_if(b, 4294967292);
    field(b, 4, 16); field(b, 4, 12); byte(b, 0x46); fail_if(b, 4294967293);
    field(b, 4, 8); field(b, 4, 16); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); get(b, 2); store(b, 0);
    get(b, 4); field(b, 4, 16); c(b, 1); byte(b, 0x6a); store(b, 16);
    c(b, 0); byte(b, 0x0b); return b;
}

// (slot,generation)->length or -4; frozen data is unchanged, no copy.
fn freeze() -> u8[>..] {
    var b: u8[>..] = [1, 2, 0x7f]; // owner=2 desc=3
    get(b, 0); get(b, 1); call(b, 4); set(b, 2);
    get(b, 2); byte(b, 0x45); fail_if(b, 4294967292);
    descriptor(b, 0); set(b, 3);
    get(b, 2); get(b, 3); c(b, 1); call(b, 6); byte(b, 0x45); fail_if(b, 4294967292);
    field(b, 3, 16); byte(b, 0x45); byte(b, 0x04); byte(b, 0x40);
      field_const(b, 3, 8, 0);
    byte(b, 0x0b);
    field_const(b, 3, 0, 2); field(b, 3, 16); byte(b, 0x0b); return b;
}

// (slot,generation,index)->U32. Internal test boundary traps on invalid view
// or out-of-bounds access; normal K1 would require checked Index evidence.
fn read() -> u8[>..] {
    var b: u8[>..] = [1, 2, 0x7f]; // owner=3 desc=4
    get(b, 0); get(b, 1); call(b, 4); set(b, 3);
    get(b, 3); byte(b, 0x45); byte(b, 0x04); byte(b, 0x40); byte(b, 0x00); byte(b, 0x0b);
    descriptor(b, 0); set(b, 4);
    get(b, 3); get(b, 4); c(b, 2); call(b, 6); byte(b, 0x45); byte(b, 0x04); byte(b, 0x40); byte(b, 0x00); byte(b, 0x0b);
    get(b, 2); field(b, 4, 16); byte(b, 0x4f); byte(b, 0x04); byte(b, 0x40); byte(b, 0x00); byte(b, 0x0b);
    field(b, 4, 8); get(b, 2); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); load(b, 0); byte(b, 0x0b); return b;
}

fn export_fn(out: u8[>..]&, name: u8[:], index: i64) {
    wasm::unsigned_leb(out, name.len); out.append(name); byte(out, 0); wasm::unsigned_leb(out, index);
}
fn emit() -> u8[>..] {
    var out: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    // (i32)->i32; (i32,i32)->i32; ()->i32; (i32,i32,i32)->i32.
    let types: u8[23] = [4, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 2, 0x7f, 0x7f, 1, 0x7f,
                          0x60, 0, 1, 0x7f, 0x60, 3, 0x7f, 0x7f, 0x7f, 1, 0x7f];
    pool_guest::section(out, 1, types);
    let functions: u8[11] = [10, 0, 1, 2, 0, 1, 3, 3, 3, 1, 3];
    pool_guest::section(out, 3, functions);
    let memory: u8[4] = [1, 1, 1, 1]; pool_guest::section(out, 5, memory);
    var exports: u8[>..] = [7];
    export_fn(exports, "reserve", 0); export_fn(exports, "close", 1);
    export_fn(exports, "begin", 5); export_fn(exports, "append", 7);
    export_fn(exports, "freeze", 8); export_fn(exports, "read", 9);
    exports.append([6, 'm', 'e', 'm', 'o', 'r', 'y', 2, 0]);
    pool_guest::section(out, 7, exports);
    var code: u8[>..] = [10];
    pool_guest::add_body(code, pool_guest::reserve()); pool_guest::add_body(code, pool_guest::close());
    pool_guest::add_body(code, pool_guest::find_slot()); pool_guest::add_body(code, pool_guest::find_run());
    pool_guest::add_body(code, valid_owner()); pool_guest::add_body(code, begin());
    pool_guest::add_body(code, valid_descriptor()); pool_guest::add_body(code, append());
    pool_guest::add_body(code, freeze()); pool_guest::add_body(code, read());
    pool_guest::section(out, 10, code); return out;
}
