// Private unoptimized particle Wasm fixture. This is hand-emitted code, NOT a
// source compiler, checked Core, a host bridge, an ownership proof or an M13
// certificate. Tests initialize raw memory directly. The guest assumes the
// fixed pool's slots/bitmap are globally disjoint and the caller ends every
// source/output loan before reusing or closing a region. The exposed integer
// handles and descriptors cannot manufacture K1 authority.
// Input descriptor records are 256..320; output records 320..384. Pool
// metadata and backing use the existing pool_guest layout.
namespace particle_guest;
import wasm;
import pool_guest;
import pool_builder_guest;

fn b(out: u8[>..]&, v: u8) { pool_guest::byte(out, v); }
fn c(out: u8[>..]&, v: u32) { pool_guest::constant(out, v); }
fn get(out: u8[>..]&, n: i64) { pool_guest::get(out, n); }
fn set(out: u8[>..]&, n: i64) { pool_guest::set(out, n); }
fn call(out: u8[>..]&, n: i64) { pool_guest::call(out, n); }
fn store(out: u8[>..]&, n: i64) { pool_guest::store(out, n); }
fn field(out: u8[>..]&, p: i64, n: i64) { pool_guest::field(out, p, n); }
fn field_const(out: u8[>..]&, p: i64, n: i64, value: u32) { pool_guest::field_const(out, p, n, value); }
fn field_local(out: u8[>..]&, p: i64, n: i64, i: i64) { pool_guest::field_local(out, p, n, i); }
fn fail_if(out: u8[>..]&, n: u32) { pool_guest::return_if(out, n); }
fn descriptor(out: u8[>..]&, slot: i64, base: u32) {
    c(out, base); get(out, slot); c(out, 1); b(out, 0x6b); c(out, 16); b(out, 0x6c); b(out, 0x6a);
}
fn load_f32(out: u8[>..]&, offset: i64) { b(out, 0x2a); b(out, 2); wasm::unsigned_leb(out, offset); }
fn store_f32(out: u8[>..]&, offset: i64) { b(out, 0x38); b(out, 2); wasm::unsigned_leb(out, offset); }

// (slot,generation,count)->0 or -1 SizeOverflow, -2 NoSpace, -4 fault.
// Reserve exactly count*16 bytes in the owner's requested extent. The caller
// initializes all rows before input_freeze; raw memory exports do not prove it.
fn input_alloc() -> u8[>..] {
    var out: u8[>..] = [1, 3, 0x7f]; // owner 3, descriptor 4, bytes 5
    get(out, 0); get(out, 1); call(out, 4); set(out, 3);
    get(out, 3); b(out, 0x45); fail_if(out, 4294967292);
    descriptor(out, 0, 256); set(out, 4);
    field(out, 4, 0); b(out, 0x45); b(out, 0x45);
    field(out, 4, 4); get(out, 1); b(out, 0x46); b(out, 0x71); fail_if(out, 4294967292);
    field(out, 3, 12); b(out, 0x45); b(out, 0x45); fail_if(out, 4294967292);
    get(out, 2); c(out, 268435455); b(out, 0x4b); fail_if(out, 4294967295);
    get(out, 2); c(out, 16); b(out, 0x6c); set(out, 5);
    get(out, 5); field(out, 3, 4); b(out, 0x4b); fail_if(out, 4294967294);
    field_local(out, 3, 12, 5); field_const(out, 4, 0, 1); field_local(out, 4, 4, 1);
    get(out, 4); get(out, 2); b(out, 0x45); b(out, 0x04); b(out, 0x7f);
      c(out, 0);
    b(out, 0x05);
      field(out, 3, 0);
    b(out, 0x0b); store(out, 8);
    field_local(out, 4, 12, 2); c(out, 0); b(out, 0x0b); return out;
}

// (slot,generation)->length or -4. The guest checks descriptor geometry;
// completed initialization and the mutable-to-immutable loan transition are
// externally established test preconditions, not established by these bits.
fn input_freeze() -> u8[>..] {
    var out: u8[>..] = [1, 3, 0x7f]; // owner 2 desc 3 count 4
    get(out, 0); get(out, 1); call(out, 4); set(out, 2);
    get(out, 2); b(out, 0x45); fail_if(out, 4294967292);
    descriptor(out, 0, 256); set(out, 3);
    field(out, 3, 0); c(out, 1); b(out, 0x47); fail_if(out, 4294967292);
    field(out, 3, 4); get(out, 1); b(out, 0x47); fail_if(out, 4294967292);
    field(out, 3, 12); set(out, 4);
    get(out, 4); c(out, 268435455); b(out, 0x4b); fail_if(out, 4294967292);
    get(out, 4); c(out, 16); b(out, 0x6c); field(out, 2, 12); b(out, 0x47); fail_if(out, 4294967292);
    get(out, 4); b(out, 0x45); b(out, 0x04); b(out, 0x40);
      field(out, 3, 8); b(out, 0x45); b(out, 0x45); fail_if(out, 4294967292);
    b(out, 0x05);
      field(out, 3, 8); field(out, 2, 0); b(out, 0x47); fail_if(out, 4294967292);
    b(out, 0x0b);
    field_const(out, 3, 0, 2); get(out, 4); b(out, 0x0b); return out;
}

fn indexed(out: u8[>..]&, base: i64, index: i64, stride: u32) {
    get(out, base); get(out, index); c(out, stride); b(out, 0x6c); b(out, 0x6a);
}
// (input slot, input gen, output slot, output gen, C, dt:f32)->n or negative.
// Input and output have separate owner records; global pool disjointness and
// absence of loans are caller invariants. All fallible checks precede writes.
// The live builder advances its initialized length after each complete row;
// its immutable view is published only after the loop completes.
// fault_after is a test-only row count, or -1 for the normal body. The
// injected unreachable simulates a trap after that many complete row writes;
// it is not an ordinary source-language failure or recoverable bridge call.
fn project(fault_after: i64) -> u8[>..] {
    var out: u8[>..] = [2, 9, 0x7f, 2, 0x7d]; // input owner 6, output owner 7, input descriptor 8, output descriptor 9, count 10, bytes 11, i 12, input data 13, output data 14
    get(out, 0); get(out, 1); call(out, 4); set(out, 6);
    get(out, 6); b(out, 0x45); fail_if(out, 4294967292);
    get(out, 2); get(out, 3); call(out, 4); set(out, 7);
    get(out, 7); b(out, 0x45); fail_if(out, 4294967292);
    get(out, 0); get(out, 2); b(out, 0x46); fail_if(out, 4294967292);
    descriptor(out, 0, 256); set(out, 8);
    field(out, 8, 0); c(out, 2); b(out, 0x47); fail_if(out, 4294967292);
    field(out, 8, 4); get(out, 1); b(out, 0x47); fail_if(out, 4294967292);
    field(out, 8, 12); set(out, 10);
    get(out, 10); c(out, 268435455); b(out, 0x4b); fail_if(out, 4294967292);
    get(out, 10); c(out, 16); b(out, 0x6c); field(out, 6, 12); b(out, 0x47); fail_if(out, 4294967292);
    get(out, 10); b(out, 0x45); b(out, 0x04); b(out, 0x40);
      field(out, 8, 8); b(out, 0x45); b(out, 0x45); fail_if(out, 4294967292);
    b(out, 0x05);
      field(out, 8, 8); field(out, 6, 0); b(out, 0x47); fail_if(out, 4294967292);
    b(out, 0x0b);
    descriptor(out, 2, 320); set(out, 9);
    field(out, 9, 0); b(out, 0x45); b(out, 0x45);
    field(out, 9, 4); get(out, 3); b(out, 0x46); b(out, 0x71); fail_if(out, 4294967292);
    field(out, 7, 12); b(out, 0x45); b(out, 0x45); fail_if(out, 4294967292);
    get(out, 4); c(out, 536870911); b(out, 0x4b); fail_if(out, 4294967295);
    get(out, 4); c(out, 8); b(out, 0x6c); set(out, 11);
    get(out, 11); field(out, 7, 4); b(out, 0x4b); fail_if(out, 4294967294);
    get(out, 10); get(out, 4); b(out, 0x4b); fail_if(out, 4294967293);
    field(out, 8, 8); set(out, 13); field(out, 7, 0); set(out, 14);
    // This placement advances the output frontier once; every subsequent
    // operation has a preflighted in-bounds address and cannot return an error.
    field_local(out, 7, 12, 11);
    field_const(out, 9, 0, 1); field_local(out, 9, 4, 3);
    field_local(out, 9, 8, 14); field_const(out, 9, 12, 0);
    if fault_after == 0 { b(out, 0x00); }
    c(out, 0); set(out, 12);
    b(out, 0x02); b(out, 0x40); b(out, 0x03); b(out, 0x40);
      get(out, 12); get(out, 10); b(out, 0x4f); b(out, 0x0d); wasm::unsigned_leb(out, 1);
      // x + vx * dt; Wasm f32.mul and f32.add are separate, never FMA.
      indexed(out, 13, 12, 16); load_f32(out, 0);
      indexed(out, 13, 12, 16); load_f32(out, 8); get(out, 5); b(out, 0x94); b(out, 0x92); set(out, 15);
      // Evaluate y before either store; locals retain separate F32 rounding.
      indexed(out, 13, 12, 16); load_f32(out, 4);
      indexed(out, 13, 12, 16); load_f32(out, 12); get(out, 5); b(out, 0x94); b(out, 0x92); set(out, 16);
      indexed(out, 14, 12, 8); get(out, 15); store_f32(out, 0);
      indexed(out, 14, 12, 8); get(out, 16); store_f32(out, 4);
      // Both fields are initialized before n := i+1 becomes observable.
      get(out, 9); get(out, 12); c(out, 1); b(out, 0x6a); store(out, 12);
      if fault_after > 0 {
          get(out, 12); c(out, (fault_after - 1) as u32); b(out, 0x46);
          b(out, 0x04); b(out, 0x40); b(out, 0x00); b(out, 0x0b);
      }
      get(out, 12); c(out, 1); b(out, 0x6a); set(out, 12);
      b(out, 0x0c); wasm::unsigned_leb(out, 0);
    b(out, 0x0b); b(out, 0x0b);
    get(out, 10); b(out, 0x45); b(out, 0x04); b(out, 0x40);
      field_const(out, 9, 8, 0);
    b(out, 0x0b);
    field_const(out, 9, 0, 2); get(out, 10); b(out, 0x0b); return out;
}

fn export_fn(out: u8[>..]&, name: u8[:], index: i64) {
    wasm::unsigned_leb(out, name.len); out.append(name); b(out, 0); wasm::unsigned_leb(out, index);
}
fn emit_test(fault_after: i64) -> u8[>..] {
    var out: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    // Types: 1, 2, 0 and 3 i32 parameters; 5 i32 and one f32 parameter.
    let types: u8[33] = [5, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 2, 0x7f, 0x7f, 1, 0x7f,
        0x60, 0, 1, 0x7f, 0x60, 3, 0x7f, 0x7f, 0x7f, 1, 0x7f,
        0x60, 6, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7d, 1, 0x7f];
    pool_guest::section(out, 1, types);
    let functions: u8[9] = [8, 0, 1, 2, 0, 1, 3, 1, 4];
    pool_guest::section(out, 3, functions);
    let memory: u8[4] = [1, 1, 1, 1]; pool_guest::section(out, 5, memory);
    var exports: u8[>..] = [6];
    export_fn(exports, "reserve", 0); export_fn(exports, "close", 1);
    export_fn(exports, "input_alloc", 5); export_fn(exports, "input_freeze", 6);
    export_fn(exports, "project", 7);
    exports.append([6, 'm', 'e', 'm', 'o', 'r', 'y', 2, 0]);
    pool_guest::section(out, 7, exports);
    var code: u8[>..] = [8];
    pool_guest::add_body(code, pool_guest::reserve()); pool_guest::add_body(code, pool_guest::close());
    pool_guest::add_body(code, pool_guest::find_slot()); pool_guest::add_body(code, pool_guest::find_run());
    pool_guest::add_body(code, pool_builder_guest::valid_owner());
    pool_guest::add_body(code, input_alloc()); pool_guest::add_body(code, input_freeze()); pool_guest::add_body(code, project(fault_after));
    pool_guest::section(out, 10, code); return out;
}
fn emit() -> u8[>..] { return emit_test(-1); }
