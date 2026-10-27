// BLAKE3's unkeyed 256-bit digest, encoded as eight little-endian words.
// Algorithm: https://github.com/BLAKE3-team/BLAKE3-specs/blob/master/blake3.pdf
// Fixed scratch: no input-dependent allocation or recursive tree walk.
namespace k1hash;

struct Digest { words: u32[8] }
struct Output { cv: u32[8], words: u32[16], counter: u64, size: u32, flags: u32 }

fn iv() -> u32[8] {
    return [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
}
fn rotate(x: u32, n: u32) -> u32 { return (x >> n) | (x << (32 - n)); }
fn mix(s: u32[16]&, a: i64, b: i64, c: i64, d: i64, x: u32, y: u32) {
    s[a] += s[b] + x;
    s[d] = rotate(s[d] ^ s[a], 16);
    s[c] += s[d];
    s[b] = rotate(s[b] ^ s[c], 12);
    s[a] += s[b] + y;
    s[d] = rotate(s[d] ^ s[a], 8);
    s[c] += s[d];
    s[b] = rotate(s[b] ^ s[c], 7);
}
fn compress(o: Output, root: bool) -> u32[16] {
    var s: u32[16] = [0; 16];
    let initial = iv();
    for i in 8 { s[i] = o.cv[i]; }
    for i in 4 { s[8 + i] = initial[i]; }
    s[12] = o.counter as! u32;
    s[13] = (o.counter >> 32) as! u32;
    s[14] = o.size;
    s[15] = o.flags;
    if root { s[12] = 0; s[13] = 0; s[15] |= 8; }
    var m = o.words;
    let permutation: u32[16] = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8];
    for round in 7 {
        mix(s, 0, 4, 8, 12, m[0], m[1]);
        mix(s, 1, 5, 9, 13, m[2], m[3]);
        mix(s, 2, 6, 10, 14, m[4], m[5]);
        mix(s, 3, 7, 11, 15, m[6], m[7]);
        mix(s, 0, 5, 10, 15, m[8], m[9]);
        mix(s, 1, 6, 11, 12, m[10], m[11]);
        mix(s, 2, 7, 8, 13, m[12], m[13]);
        mix(s, 3, 4, 9, 14, m[14], m[15]);
        if round < 6 {
            var next: u32[16] = [0; 16];
            for i in 16 { next[i] = m[permutation[i]]; }
            m = next;
        }
    }
    for i in 8 { s[i] ^= s[i + 8]; s[i + 8] ^= o.cv[i]; }
    return s;
}
fn chaining(o: Output) -> u32[8] {
    let words = compress(o, false);
    var out: u32[8] = [0; 8];
    for i in 8 { out[i] = words[i]; }
    return out;
}
fn parent(left: u32[8], right: u32[8]) -> Output {
    var words: u32[16] = [0; 16];
    for i in 8 { words[i] = left[i]; words[i + 8] = right[i]; }
    return Output { iv(), words, 0, 64, 4 };
}
fn chunk(data: const u8[:], counter: u64) -> Output {
    var cv = iv();
    var offset: i64 = 0;
    loop {
        var size = data.len - offset;
        if size > 64 { size = 64; }
        var words: u32[16] = [0; 16];
        for i in size { words[i / 4] |= data[offset + i] as u32 << ((i % 4) * 8); }
        var flags: u32 = 0;
        if offset == 0 { flags |= 1; }
        if offset + size == data.len { flags |= 2; }
        let out = Output { cv, words, counter, size as u32, flags };
        if flags & 2 != 0 { return out; }
        cv = chaining(out);
        offset += size;
    }
}
fn blake3(data: const u8[:]) -> Digest {
    var stack: u32[8][64] = [[0; 8]; 64];
    var used: i64 = 0;
    var offset: i64 = 0;
    var counter: u64 = 0;
    while data.len - offset > 1024 {
        var cv = chaining(chunk(data[offset..offset + 1024], counter));
        counter += 1;
        var total = counter;
        while total & 1 == 0 {
            used -= 1;
            cv = chaining(parent(stack[used], cv));
            total >>= 1;
        }
        stack[used] = cv;
        used += 1;
        offset += 1024;
    }
    var out = chunk(data[offset..], counter);
    while used > 0 { used -= 1; out = parent(stack[used], chaining(out)); }
    let words = compress(out, true);
    var result: u32[8] = [0; 8];
    for i in 8 { result[i] = words[i]; }
    return Digest { result };
}
fn equal(a: Digest, b: Digest) -> bool {
    var different: u32 = 0;
    for i in 8 { different |= a.words[i] ^ b.words[i]; }
    return different == 0;
}
fn hex(d: Digest) -> u8[64] {
    let alphabet = "0123456789abcdef";
    var out: u8[64] = [0; 64];
    for i in 32 {
        let byte = (d.words[i / 4] >> ((i % 4) * 8)) & 255;
        out[i * 2] = alphabet[byte >> 4];
        out[i * 2 + 1] = alphabet[byte & 15];
    }
    return out;
}
