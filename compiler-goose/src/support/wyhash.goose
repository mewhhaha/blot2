// The same byte stream and Wyhash variant as the pinned Zig oracle.
namespace blot_support_wyhash;
import support.bytes;

let secret: u64[4] = [0xa0761d6478bd642f, 0xe7037ed1a0b428db,
    0x8ebc6af09c88c6e3, 0x589965cc75374cc3];
struct Wyhash {
    a: u64 = 0, b: u64 = 0, state: u64[3], total_len: u64 = 0,
    buffer: u8[48], buffer_len: i64 = 0,
}
fn multiply(left: u64, right: u64) -> u64, u64 {
    let low_low = (left & 4294967295) * (right & 4294967295);
    let low_high = (left & 4294967295) * (right >> 32);
    let high_low = (left >> 32) * (right & 4294967295);
    let high_high = (left >> 32) * (right >> 32);
    let middle = (low_low >> 32) + (low_high & 4294967295) + (high_low & 4294967295);
    return (low_low & 4294967295) | (middle << 32),
        high_high + (low_high >> 32) + (high_low >> 32) + (middle >> 32);
}
fn mix(left: u64, right: u64) -> u64 {
    let low, high = multiply(left, right);
    return low ^ high;
}
fn init(seed: u64) -> Wyhash {
    let initial = seed ^ mix(seed ^ secret[0], secret[1]);
    return Wyhash { 0, 0, [initial, initial, initial], 0, default<u8[48]>(), 0 , ..};
}
fn round(hash: Wyhash&, bytes: const u8[:]) {
    for index in 3 {
        let left = blot_bytes::get_u64(bytes, 16 * index);
        let right = blot_bytes::get_u64(bytes, 16 * index + 8);
        hash.state[index] = mix(left ^ secret[index + 1], right ^ hash.state[index]);
    }
}
fn update(hash: Wyhash&, bytes: const u8[:]) {
    hash.total_len += bytes.len as u64;
    if bytes.len <= 48 - hash.buffer_len {
        for byte, index in bytes { hash.buffer[hash.buffer_len + index] = byte; }
        hash.buffer_len += bytes.len;
        return;
    }
    var at: i64 = 0;
    if hash.buffer_len > 0 {
        at = 48 - hash.buffer_len;
        for index in at { hash.buffer[hash.buffer_len + index] = bytes[index]; }
        round(hash, hash.buffer);
        hash.buffer_len = 0;
    }
    while at + 48 < bytes.len { round(hash, bytes[at..at + 48]); at += 48; }
    let remaining = bytes.len - at;
    if remaining < 16 && at >= 48 {
        let prefix = 16 - remaining;
        for index in prefix { hash.buffer[48 - prefix + index] = bytes[at - prefix + index]; }
    }
    for index in remaining { hash.buffer[index] = bytes[at + index]; }
    hash.buffer_len = remaining;
}
fn smallKey(hash: Wyhash&, bytes: const u8[:]) {
    if bytes.len >= 4 {
        let end = bytes.len - 4;
        let quarter = (bytes.len >> 3) << 2;
        hash.a = (blot_bytes::get_u32(bytes, 0) as u64 << 32) |
            blot_bytes::get_u32(bytes, quarter) as u64;
        hash.b = (blot_bytes::get_u32(bytes, end) as u64 << 32) |
            blot_bytes::get_u32(bytes, end - quarter) as u64;
    } else if bytes.len > 0 {
        hash.a = (bytes[0] as u64 << 16) | (bytes[bytes.len >> 1] as u64 << 8) |
            bytes[bytes.len - 1] as u64;
        hash.b = 0;
    } else { hash.a = 0; hash.b = 0; }
}
fn final1(hash: Wyhash&, bytes: const u8[:], start: i64) {
    var at = start;
    while at + 16 < bytes.len {
        hash.state[0] = mix(blot_bytes::get_u64(bytes, at) ^ secret[1],
            blot_bytes::get_u64(bytes, at + 8) ^ hash.state[0]);
        at += 16;
    }
    hash.a = blot_bytes::get_u64(bytes, bytes.len - 16);
    hash.b = blot_bytes::get_u64(bytes, bytes.len - 8);
}
fn final2(hash: Wyhash&) -> u64 {
    let low, high = multiply(hash.a ^ secret[1], hash.b ^ hash.state[0]);
    return mix(low ^ secret[0] ^ hash.total_len, high ^ secret[1]);
}
fn final(source: Wyhash) -> u64 {
    var hash = source;
    if hash.total_len <= 16 { smallKey(hash, source.buffer[..source.buffer_len]); }
    else {
        hash.state[0] ^= hash.state[1] ^ hash.state[2];
        if source.buffer_len < 16 {
            var scratch: u8[16] = default<u8[16]>();
            let prefix = 16 - source.buffer_len;
            for index in prefix { scratch[index] = source.buffer[48 - prefix + index]; }
            for index in source.buffer_len { scratch[prefix + index] = source.buffer[index]; }
            final1(hash, scratch, prefix);
        } else { final1(hash, source.buffer[..source.buffer_len], 0); }
    }
    return final2(hash);
}
fn hash(seed: u64, bytes: const u8[:]) -> u64 {
    var state = init(seed);
    update(state, bytes);
    return final(state);
}

fn value(state: Wyhash&, item: u8) { let bytes = [item]; update(state, bytes); }
fn value(state: Wyhash&, item: bool) {
    var byte: u8 = 0; if item { byte = 1; }
    value(state, byte);
}
fn value(state: Wyhash&, value: u16) {
    let bytes = [value as! u8, (value >> 8) as! u8]; update(state, bytes);
}
fn value(state: Wyhash&, value: u32) {
    var bytes: u8[4] = default<u8[4]>();
    blot_bytes::put_u32(bytes, 0, value); update(state, bytes);
}
fn value(state: Wyhash&, value: u64) {
    var bytes: u8[8] = default<u8[8]>();
    blot_bytes::put_u64(bytes, 0, value); update(state, bytes);
}
