// Standalone unkeyed BLAKE3, 32-byte output only. Digests locate candidates;
// equality of digests never replaces artifact or source validation.
// No keyed, derive-key, incremental or extended-output API is provided.
namespace blake3;

struct Output {
    cv: u32[8] = [0; 8],
    message: u32[16] = [0; 16],
    counter: u64 = 0,
    length: u32 = 0,
    flags: u32 = 0
}

fn iv() -> u32[8] {
    return [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
}
fn rotate(x: u32, n: u32) -> u32 { return (x >> n) | (x << (32 - n)); }
fn mix(s: u32[16]&, a: i64, b: i64, c: i64, d: i64, x: u32, y: u32) {
    s[a] = s[a] + s[b] + x;
    s[d] = rotate(s[d] ^ s[a], 16);
    s[c] = s[c] + s[d];
    s[b] = rotate(s[b] ^ s[c], 12);
    s[a] = s[a] + s[b] + y;
    s[d] = rotate(s[d] ^ s[a], 8);
    s[c] = s[c] + s[d];
    s[b] = rotate(s[b] ^ s[c], 7);
}
fn compress(o: Output, extra_flags: u32, counter: u64) -> u32[8] {
    var state: u32[16] = [0; 16];
    let initial = iv();
    for i in 8 { state[i] = o.cv[i]; }
    for i in 4 { state[i + 8] = initial[i]; }
    state[12] = counter as! u32;
    state[13] = (counter >> 32) as! u32;
    state[14] = o.length;
    state[15] = o.flags | extra_flags;
    var m = o.message;
    let permutation: i64[16] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
    for round in 7 {
        mix(state, 0, 4, 8, 12, m[0], m[1]);
        mix(state, 1, 5, 9, 13, m[2], m[3]);
        mix(state, 2, 6, 10, 14, m[4], m[5]);
        mix(state, 3, 7, 11, 15, m[6], m[7]);
        mix(state, 0, 5, 10, 15, m[8], m[9]);
        mix(state, 1, 6, 11, 12, m[10], m[11]);
        mix(state, 2, 7, 8, 13, m[12], m[13]);
        mix(state, 3, 4, 9, 14, m[14], m[15]);
        if round != 6 {
            var next: u32[16] = [0; 16];
            for i in 16 { next[i] = m[permutation[i]]; }
            m = next;
        }
    }
    var result: u32[8] = [0; 8];
    for i in 8 { result[i] = state[i] ^ state[i + 8]; }
    return result;
}
fn words(bytes: const u8[:]) -> u32[16] {
    // Internal helper contract: the final/complete compression message is at
    // most 64 bytes. Never truncate or index beyond the 16-word message.
    assert(bytes.len <= 64);
    var result: u32[16] = [0; 16];
    for b, i in bytes { result[i / 4] |= (b as u32) << ((i % 4) * 8); }
    return result;
}
// Input is one chunk of at most 1024 bytes. Leave its final message uncompressed
// so the caller can set ROOT on the final output, including for empty input.
fn chunk(input: const u8[:], counter: u64) -> Output {
    assert(input.len <= 1024);
    var cv = iv();
    var offset: i64 = 0;
    var blocks: i64 = 0;
    while input.len - offset > 64 {
        let o = Output { cv: cv, message: words(input[offset..offset + 64]), counter: counter,
                         length: 64, flags: if blocks == 0 { 1 } else { 0 } };
        cv = compress(o, 0, counter);
        offset += 64; blocks += 1;
    }
    return Output { cv: cv, message: words(input[offset..]), counter: counter,
                    length: (input.len - offset) as u32, flags: (if blocks == 0 { 3 } else { 2 }) as u32 };
}
fn parent(left: u32[8], right: u32[8]) -> Output {
    var message: u32[16] = [0; 16];
    for i in 8 { message[i] = left[i]; message[i + 8] = right[i]; }
    return Output { cv: iv(), message: message, length: 64, flags: 4 };
}
recursive fn subtree(input: const u8[:], counter: u64) -> Output {
    // `counter` names the first chunk. All chunk counters in this subtree
    // must fit u64; public one-shot hash starts at zero and always satisfies
    // this for a Goose slice. Reject invalid internal use before recursing.
    let chunks = if input.len == 0 { 1 } else { (input.len - 1) / 1024 + 1 };
    let max_counter: u64 = 18446744073709551615;
    assert(counter <= max_counter - ((chunks - 1) as u64));
    if input.len <= 1024 { return chunk(input, counter); }
    var left_chunks: i64 = 1;
    while left_chunks * 2 < chunks { left_chunks *= 2; }
    let cut = left_chunks * 1024;
    let left = subtree(input[..cut], counter);
    let right = subtree(input[cut..], counter + (left_chunks as u64));
    return parent(compress(left, 0, left.counter), compress(right, 0, right.counter));
}
fn hash(input: const u8[:]) -> u8[32] {
    let root = subtree(input, 0);
    let result = compress(root, 8, 0);
    var bytes: u8[32] = [0; 32];
    for word, i in result {
        for j in 4 { bytes[i * 4 + j] = ((word >> (j * 8)) & 255) as u8; }
    }
    return bytes;
}
