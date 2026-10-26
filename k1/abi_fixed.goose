// Proposed fixed ABI records only. This is a reviewable component, NOT a
// complete K1-WASM32-ABI1 profile and MUST NOT be hashed or used as authority.
// Operations, helper contracts, complete type schemas and lifecycle rules are
// deliberately absent. See ABI_PROFILE_SCHEMA.md.
namespace abi_fixed;

fn put32(out: u8[>..]&, n: u32) {
    out.push((n & 255) as u8); out.push(((n >> 8) & 255) as u8);
    out.push(((n >> 16) & 255) as u8); out.push(((n >> 24) & 255) as u8);
}
fn record(out: u8[>..]&, section: u32, id: u32, words: u32[:]) {
    put32(out, section); put32(out, id); put32(out, 1);
    put32(out, (words.len * 4) as u32);
    for n in words { put32(out, n); }
}
fn encode_component() -> u8[>..] {
    var out: u8[>..] = [];
    out.append("K1FIX001"); put32(out, 1); put32(out, 34);
    record(out, 1, 1, [4, 1, 4, 0]);
    record(out, 1, 2, [0, 1, 0, 0]);
    record(out, 1, 3, [4, 4, 32, 1]);
    record(out, 1, 4, [4, 4, 2, 0, 1]);
    record(out, 1, 5, [4, 4, 32, 1]);
    record(out, 1, 6, [4, 4, 1, 1]);
    record(out, 1, 7, [1, 1, 1]);
    record(out, 1, 8, [4, 4, 4, 1, 1]);
    record(out, 1, 9, [1, 0, 1, 0, 0]);
    record(out, 1, 10, [4, 1, 0, 0]);
    record(out, 1, 11, [1, 0, 0]);
    record(out, 1, 12, [64, 32, 64, 32, 256, 256]);
    record(out, 2, 1, [2, 1, 2]);
    record(out, 2, 2, [2, 1, 3]);
    record(out, 2, 3, [2, 1, 4]);
    record(out, 2, 4, [3, 1, 2, 3]);
    record(out, 2, 5, [2, 5, 6]);
    record(out, 2, 6, [2, 5, 6]);
    record(out, 2, 7, [2, 5, 6]);
    record(out, 2, 8, [2, 5, 6]);
    record(out, 2, 9, [2, 7, 8]);
    record(out, 2, 10, [4, 9, 10, 11, 12]);
    record(out, 3, 1, [65536, 4096, 32, 256, 1073741824, 4096, 16777216, 128, 16777216, 256, 1048576, 65536, 65536]);
    record(out, 3, 2, [8, 1, 2, 3, 4, 5, 6, 7, 8]);
    record(out, 3, 3, [5, 0, 1, 2, 3, 4]);
    record(out, 3, 4, [4, 1, 2, 3, 4, 0, 0, 0, 0]);
    record(out, 4, 1, [4, 1, 2, 4, 0xfffffff8]);
    record(out, 4, 2, [5, 1, 2, 3, 4, 5]);
    record(out, 4, 3, [1, 0, 1, 0]);
    record(out, 4, 4, [1, 2, 1]);
    record(out, 4, 5, [1, 128, 1]);
    record(out, 6, 1, [0x4b310001, 32, 8, 1, 2, 3, 4, 5, 6, 7, 8]);
    record(out, 6, 2, [7, 0, 1, 2, 3, 4, 5, 6]);
    record(out, 6, 3, [2, 1, 2]);
    return out;
}
