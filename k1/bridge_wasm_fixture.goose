// Private Wasm bridge integration fixture, generated directly in Goose. A
// single trusted U32-view XOR callable exercises a fixed ingress/egress window
// and one pool owner. This is not public K1 lowering, a host API, a full M12
// implementation, a resource certificate, or source/loan/domain authority.
// The sole builder descriptor is reused after freezing: its input bytes remain
// live in disjoint backing, but the source-level loan is a trusted precondition.
// Exported raw memory is test-only; a real host must keep memory private while
// Busy. Its arbitrary corruption is outside the trusted runtime invariant.
namespace bridge_wasm_fixture;
import wasm;
import pool_guest;
import pool_builder_guest;
fn byte(b: u8[>..]&, v: u8) { pool_guest::byte(b, v); }
fn c(b: u8[>..]&, v: u32) { pool_guest::constant(b, v); }
fn get(b: u8[>..]&, i: i64) { pool_guest::get(b, i); }
fn set(b: u8[>..]&, i: i64) { pool_guest::set(b, i); }
fn call(b: u8[>..]&, i: i64) { pool_guest::call(b, i); }
fn load(b: u8[>..]&, i: i64) { pool_guest::load(b, i); }
fn store(b: u8[>..]&, i: i64) { pool_guest::store(b, i); }
fn uleb(b: u8[>..]&, i: i64) { wasm::unsigned_leb(b, i); }
fn checked_status(b: u8[>..]&, status: u32) {
    // A true condition produces an empty error header, releases Busy, returns.
    byte(b, 0x04); byte(b, 0x40);
      c(b, status); c(b, 0); c(b, 0); c(b, 0); c(b, 0); call(b, 11); byte(b, 0x0f);
    byte(b, 0x0b);
}
fn require_zero(b: u8[>..]&, offset: u32) {
    c(b, 32768 + offset); load(b, 0); byte(b, 0x45); byte(b, 0x45); checked_status(b, 1);
}
fn expect_word(b: u8[>..]&, offset: u32, word: u32) {
    c(b, 32768 + offset); load(b, 0); c(b, word); byte(b, 0x47); checked_status(b, 1);
}
fn invariant(b: u8[>..]&) {
    // Trusted runtime failure is an engine trap; no invented wire status.
    byte(b, 0x04); byte(b, 0x40); byte(b, 0x00); byte(b, 0x0b);
}
// (status,payload,required,count,detail)->status. Header is written after
// payload; Busy is then released. Fixed ABI/export and reserved are explicit.
fn publish() -> u8[>..] {
    var b: u8[>..] = [0];
    for v, i in [0x4b310001 as u32, 17, 0, 0, 0, 0, 0, 0] {
        c(b, 33024 + i as u32 * 4); c(b, v); store(b, 0);
    }
    for i in 5 { c(b, 33032 + i as u32 * 4); get(b, i); store(b, 0); }
    c(b, 256); c(b, 0); store(b, 0);
    get(b, 0); byte(b, 0x0b); return b;
}
fn close_owner(b: u8[>..]&) {
    get(b, 6); get(b, 7); call(b, 1); byte(b, 0x45); byte(b, 0x45); invariant(b);
}
// (export_id,input_bytes,output_capacity)->status, all arguments U32.
// Local layout: payload=3, count=4, offset=5, slot=6, gen=7, inputptr=8,
// outputptr=9, i=10, data_end=11, mask=12, required=13, scratch=14.
fn invoke() -> u8[>..] {
    var b: u8[>..] = [1, 12, 0x7f];
    c(b, 256); load(b, 0); pool_guest::return_if(b, 4); // Busy makes no writes
    c(b, 256); c(b, 1); store(b, 0);
    get(b, 0); c(b, 17); byte(b, 0x47); checked_status(b, 1);
    get(b, 1); c(b, 32); byte(b, 0x49); checked_status(b, 1);
    get(b, 1); c(b, 128); byte(b, 0x4b); checked_status(b, 1);
    get(b, 2); c(b, 96); byte(b, 0x4b); checked_status(b, 1);
    get(b, 1); c(b, 32); byte(b, 0x6b); set(b, 3);
    get(b, 3); c(b, 12); byte(b, 0x49); checked_status(b, 1);
    expect_word(b, 0, 0x4b310001); expect_word(b, 4, 17);
    require_zero(b, 8); require_zero(b, 16); require_zero(b, 20); require_zero(b, 24); require_zero(b, 28);
    c(b, 32780); load(b, 0); get(b, 3); byte(b, 0x47); checked_status(b, 1);
    c(b, 32800); load(b, 0); set(b, 12);
    c(b, 32804); load(b, 0); set(b, 4);
    c(b, 32808); load(b, 0); set(b, 5);
    get(b, 4); c(b, 4); byte(b, 0x4b); checked_status(b, 1);
    get(b, 5); c(b, 3); byte(b, 0x71); checked_status(b, 1);
    get(b, 5); c(b, 12); byte(b, 0x49); checked_status(b, 1);
    get(b, 5); get(b, 3); byte(b, 0x4b); checked_status(b, 1);
    get(b, 4); c(b, 4); byte(b, 0x6c); get(b, 3); get(b, 5); byte(b, 0x6b); byte(b, 0x4b); checked_status(b, 1);
    get(b, 5); get(b, 4); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); set(b, 11);
    // Verify zero padding outside the single array range.
    c(b, 12); set(b, 10);
    byte(b, 0x02); byte(b, 0x40); byte(b, 0x03); byte(b, 0x40);
      get(b, 10); get(b, 3); byte(b, 0x4f); byte(b, 0x0d); uleb(b, 1);
      get(b, 10); get(b, 5); byte(b, 0x49); get(b, 10); get(b, 11); byte(b, 0x4f); byte(b, 0x72);
      byte(b, 0x04); byte(b, 0x40);
        c(b, 32800); get(b, 10); byte(b, 0x6a); byte(b, 0x2d); byte(b, 0); uleb(b, 0); checked_status(b, 1);
      byte(b, 0x0b);
      get(b, 10); c(b, 1); byte(b, 0x6a); set(b, 10); byte(b, 0x0c); uleb(b, 0);
    byte(b, 0x0b); byte(b, 0x0b);
    // Reserve one 32-byte requested region. A nonpositive slot indicates a
    // reservation failure; reservation's negative tag becomes detail.
    c(b, 32); call(b, 0); set(b, 6);
    get(b, 6); c(b, 0); byte(b, 0x4c); // i32.le_s
    byte(b, 0x04); byte(b, 0x40);
      c(b, 3); c(b, 0); c(b, 0); c(b, 0); c(b, 0); get(b, 6); byte(b, 0x6b); call(b, 11); byte(b, 0x0f);
    byte(b, 0x0b);
    // slot pointer = 16 + (slot-1)*32, then its generation word.
    c(b, 16); get(b, 6); c(b, 1); byte(b, 0x6b); c(b, 32); byte(b, 0x6c); byte(b, 0x6a); load(b, 16); set(b, 7);
    get(b, 6); get(b, 7); c(b, 4); call(b, 5); invariant(b);
    c(b, 0); set(b, 10);
    byte(b, 0x02); byte(b, 0x40); byte(b, 0x03); byte(b, 0x40);
      get(b, 10); get(b, 4); byte(b, 0x4f); byte(b, 0x0d); uleb(b, 1);
      get(b, 6); get(b, 7); c(b, 32800); get(b, 5); byte(b, 0x6a); get(b, 10); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); load(b, 0); call(b, 7); invariant(b);
      get(b, 10); c(b, 1); byte(b, 0x6a); set(b, 10); byte(b, 0x0c); uleb(b, 0);
    byte(b, 0x0b); byte(b, 0x0b);
    get(b, 6); get(b, 7); call(b, 8); get(b, 4); byte(b, 0x47); invariant(b);
    // Capture frozen input physical pointer before reusing descriptor. Empty
    // views are canonical zero and never dereferenced.
    c(b, 160); get(b, 6); c(b, 1); byte(b, 0x6b); c(b, 24); byte(b, 0x6c); byte(b, 0x6a); load(b, 8); set(b, 8);
    get(b, 6); get(b, 7); c(b, 4); call(b, 5); invariant(b);
    // Count one invocation in test-only telemetry (saturating).
    c(b, 260); load(b, 0); c(b, 4294967295); byte(b, 0x47);
    byte(b, 0x04); byte(b, 0x40); c(b, 260); c(b, 260); load(b, 0); c(b, 1); byte(b, 0x6a); store(b, 0); byte(b, 0x0b);
    c(b, 0); set(b, 10);
    byte(b, 0x02); byte(b, 0x40); byte(b, 0x03); byte(b, 0x40);
      get(b, 10); get(b, 4); byte(b, 0x4f); byte(b, 0x0d); uleb(b, 1);
      get(b, 6); get(b, 7); get(b, 8); get(b, 10); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); load(b, 0); get(b, 12); byte(b, 0x73); call(b, 7); invariant(b);
      get(b, 10); c(b, 1); byte(b, 0x6a); set(b, 10); byte(b, 0x0c); uleb(b, 0);
    byte(b, 0x0b); byte(b, 0x0b);
    get(b, 6); get(b, 7); call(b, 8); get(b, 4); byte(b, 0x47); invariant(b);
    c(b, 160); get(b, 6); c(b, 1); byte(b, 0x6b); c(b, 24); byte(b, 0x6c); byte(b, 0x6a); load(b, 8); set(b, 9);
    get(b, 4); c(b, 4); byte(b, 0x6c); c(b, 8); byte(b, 0x6a); set(b, 13);
    get(b, 13); get(b, 2); byte(b, 0x4b);
    byte(b, 0x04); byte(b, 0x40);
      close_owner(b); c(b, 2); c(b, 0); get(b, 13); get(b, 4); c(b, 0); call(b, 11); byte(b, 0x0f);
    byte(b, 0x0b);
    c(b, 33056); get(b, 4); store(b, 0); c(b, 33060); c(b, 8); store(b, 0);
    c(b, 0); set(b, 10);
    byte(b, 0x02); byte(b, 0x40); byte(b, 0x03); byte(b, 0x40);
      get(b, 10); get(b, 4); byte(b, 0x4f); byte(b, 0x0d); uleb(b, 1);
      c(b, 33064); get(b, 10); c(b, 4); byte(b, 0x6c); byte(b, 0x6a);
      get(b, 9); get(b, 10); c(b, 4); byte(b, 0x6c); byte(b, 0x6a); load(b, 0); store(b, 0);
      get(b, 10); c(b, 1); byte(b, 0x6a); set(b, 10); byte(b, 0x0c); uleb(b, 0);
    byte(b, 0x0b); byte(b, 0x0b);
    close_owner(b); c(b, 0); get(b, 13); get(b, 13); get(b, 4); c(b, 0); call(b, 11); byte(b, 0x0b);
    return b;
}
fn emit() -> u8[>..] {
    var out: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    let types: u8[32] = [5, 0x60, 1, 0x7f, 1, 0x7f, 0x60, 2, 0x7f, 0x7f, 1, 0x7f,
        0x60, 0, 1, 0x7f, 0x60, 3, 0x7f, 0x7f, 0x7f, 1, 0x7f,
        0x60, 5, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 1, 0x7f];
    pool_guest::section(out, 1, types);
    let functions: u8[13] = [12, 0, 1, 2, 0, 1, 3, 3, 3, 1, 3, 3, 4];
    pool_guest::section(out, 3, functions);
    let memory: u8[4] = [1, 1, 1, 1]; pool_guest::section(out, 5, memory);
    var exports: u8[>..] = [2];
    pool_builder_guest::export_fn(exports, "invoke", 10);
    exports.append([6, 'm', 'e', 'm', 'o', 'r', 'y', 2, 0]); pool_guest::section(out, 7, exports);
    var code: u8[>..] = [12];
    pool_guest::add_body(code, pool_guest::reserve()); pool_guest::add_body(code, pool_guest::close());
    pool_guest::add_body(code, pool_guest::find_slot()); pool_guest::add_body(code, pool_guest::find_run());
    pool_guest::add_body(code, pool_builder_guest::valid_owner()); pool_guest::add_body(code, pool_builder_guest::begin());
    pool_guest::add_body(code, pool_builder_guest::valid_descriptor()); pool_guest::add_body(code, pool_builder_guest::append());
    pool_guest::add_body(code, pool_builder_guest::freeze()); pool_guest::add_body(code, pool_builder_guest::read());
    pool_guest::add_body(code, invoke()); pool_guest::add_body(code, publish());
    pool_guest::section(out, 10, code); return out;
}
