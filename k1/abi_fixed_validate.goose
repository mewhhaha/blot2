// Independent bounded parser for the proposed fixed-record component. This
// validates exact component framing and values; it grants no ABI authority.
// It deliberately does not call the encoder, derive offsets from its output,
// accept unknown records, or accept a complete profile under this magic.
namespace abi_fixed_validate;

fn read32(bytes: u8[:], p: i64) -> u32 {
    return bytes[p] | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
// Before any read, verify the enclosing header and complete payload bounds.
// The expected records are enumerated independently in canonical order.
fn expect(bytes: u8[:], p: i64&, section: u32, id: u32, words: u32[:]) -> bool {
    if p < 0 || p > bytes.len || bytes.len - p < 16 { return false; }
    if read32(bytes, p) != section || read32(bytes, p + 4) != id ||
       read32(bytes, p + 8) != 1 || read32(bytes, p + 12) != words.len * 4 { return false; }
    p += 16;
    if words.len * 4 > bytes.len - p { return false; }
    for n in words {
        if read32(bytes, p) != n { return false; }
        p += 4;
    }
    return true;
}
fn validate_component(bytes: u8[:]) -> bool {
    if bytes.len < 16 || bytes.len > 16777216 || bytes[0..8] != "K1FIX001" ||
       read32(bytes, 8) != 1 || read32(bytes, 12) != 34 { return false; }
    var p: i64 = 16;
    if !expect(bytes, p, 1, 1, [4, 1, 4, 0]) { return false; }
    if !expect(bytes, p, 1, 2, [0, 1, 0, 0]) { return false; }
    if !expect(bytes, p, 1, 3, [4, 4, 32, 1]) { return false; }
    if !expect(bytes, p, 1, 4, [4, 4, 2, 0, 1]) { return false; }
    if !expect(bytes, p, 1, 5, [4, 4, 32, 1]) { return false; }
    if !expect(bytes, p, 1, 6, [4, 4, 1, 1]) { return false; }
    if !expect(bytes, p, 1, 7, [1, 1, 1]) { return false; }
    if !expect(bytes, p, 1, 8, [4, 4, 4, 1, 1]) { return false; }
    if !expect(bytes, p, 1, 9, [1, 0, 1, 0, 0]) { return false; }
    if !expect(bytes, p, 1, 10, [4, 1, 0, 0]) { return false; }
    if !expect(bytes, p, 1, 11, [1, 0, 0]) { return false; }
    if !expect(bytes, p, 1, 12, [64, 32, 64, 32, 256, 256]) { return false; }
    if !expect(bytes, p, 2, 1, [2, 1, 2]) { return false; }
    if !expect(bytes, p, 2, 2, [2, 1, 3]) { return false; }
    if !expect(bytes, p, 2, 3, [2, 1, 4]) { return false; }
    if !expect(bytes, p, 2, 4, [3, 1, 2, 3]) { return false; }
    if !expect(bytes, p, 2, 5, [2, 5, 6]) { return false; }
    if !expect(bytes, p, 2, 6, [2, 5, 6]) { return false; }
    if !expect(bytes, p, 2, 7, [2, 5, 6]) { return false; }
    if !expect(bytes, p, 2, 8, [2, 5, 6]) { return false; }
    if !expect(bytes, p, 2, 9, [2, 7, 8]) { return false; }
    if !expect(bytes, p, 2, 10, [4, 9, 10, 11, 12]) { return false; }
    if !expect(bytes, p, 3, 1, [65536, 4096, 32, 256, 1073741824, 4096, 16777216, 128, 16777216, 256, 1048576, 65536, 65536]) { return false; }
    if !expect(bytes, p, 3, 2, [8, 1, 2, 3, 4, 5, 6, 7, 8]) { return false; }
    if !expect(bytes, p, 3, 3, [5, 0, 1, 2, 3, 4]) { return false; }
    if !expect(bytes, p, 3, 4, [4, 1, 2, 3, 4, 0, 0, 0, 0]) { return false; }
    if !expect(bytes, p, 4, 1, [4, 1, 2, 4, 0xfffffff8]) { return false; }
    if !expect(bytes, p, 4, 2, [5, 1, 2, 3, 4, 5]) { return false; }
    if !expect(bytes, p, 4, 3, [1, 0, 1, 0]) { return false; }
    if !expect(bytes, p, 4, 4, [1, 2, 1]) { return false; }
    if !expect(bytes, p, 4, 5, [1, 128, 1]) { return false; }
    if !expect(bytes, p, 6, 1, [0x4b310001, 32, 8, 1, 2, 3, 4, 5, 6, 7, 8]) { return false; }
    if !expect(bytes, p, 6, 2, [7, 0, 1, 2, 3, 4, 5, 6]) { return false; }
    if !expect(bytes, p, 6, 3, [2, 1, 2]) { return false; }
    return p == bytes.len;
}
