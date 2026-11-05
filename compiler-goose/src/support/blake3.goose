// Portable BLAKE3 byte semantics used by dependency content/edge fingerprints.
namespace blot_support_blake3;
import std;
import support.bytes;

let iv: u32[8] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
let schedule: u8[16][7] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8],
    [3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1],
    [10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6],
    [12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4],
    [9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7],
    [11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13],
];
let CHUNK_START: u32 = 1;
let CHUNK_END: u32 = 2;
let PARENT: u32 = 4;
let ROOT: u32 = 8;
let KEYED: u32 = 16;
let DERIVE_CONTEXT: u32 = 32;
let DERIVE_MATERIAL: u32 = 64;

struct Output { cv: u32[8], block_: u32[16], counter: u64, length: u32, flags: u32 }
struct Chunk {
    cv: u32[8], counter: u64 = 0, block_: u8[64], length: i64 = 0,
    compressed: u8 = 0, flags: u32 = 0,
}
struct State {
    key: u32[8], chunk: Chunk, stack: u32[8][54], stack_len: i64 = 0,
    flags: u32 = 0,
}
fn rotate(value: u32, bits: u32) -> u32 { value >> bits | value << (32 - bits) }
fn g(state: u32[16]&, a: i64, b: i64, c: i64, d: i64, x: u32, y: u32) {
    state[a] += state[b] + x; state[d] = rotate(state[d] ^ state[a], 16);
    state[c] += state[d]; state[b] = rotate(state[b] ^ state[c], 12);
    state[a] += state[b] + y; state[d] = rotate(state[d] ^ state[a], 8);
    state[c] += state[d]; state[b] = rotate(state[b] ^ state[c], 7);
}
fn compress(cv: u32[8], block_: u32[16], counter: u64, length: u32, flags: u32) -> u32[16] {
    var state: u32[16] = default<u32[16]>();
    for index in 8 { state[index] = cv[index]; }
    for index in 4 { state[index + 8] = iv[index]; }
    state[12] = counter as! u32; state[13] = (counter >> 32) as u32;
    state[14] = length; state[15] = flags;
    for round in 7 {
        let s = schedule[round];
        g(state, 0, 4, 8, 12, block_[s[0]], block_[s[1]]);
        g(state, 1, 5, 9, 13, block_[s[2]], block_[s[3]]);
        g(state, 2, 6, 10, 14, block_[s[4]], block_[s[5]]);
        g(state, 3, 7, 11, 15, block_[s[6]], block_[s[7]]);
        g(state, 0, 5, 10, 15, block_[s[8]], block_[s[9]]);
        g(state, 1, 6, 11, 12, block_[s[10]], block_[s[11]]);
        g(state, 2, 7, 8, 13, block_[s[12]], block_[s[13]]);
        g(state, 3, 4, 9, 14, block_[s[14]], block_[s[15]]);
    }
    for index in 8 { state[index] ^= state[index + 8]; state[index + 8] ^= cv[index]; }
    return state;
}
fn chaining(output: Output) -> u32[8] {
    let words = compress(output.cv, output.block_, output.counter, output.length, output.flags);
    var result: u32[8] = default<u32[8]>();
    for index in 8 { result[index] = words[index]; }
    return result;
}
fn start_flag(chunk: Chunk) -> u32 {
    if chunk.compressed == 0 { return CHUNK_START; }
    return 0;
}
fn words(bytes: u8[64]) -> u32[16] {
    var result: u32[16] = default<u32[16]>();
    for index in 16 { result[index] = blot_bytes::get_u32(bytes, index * 4); }
    return result;
}
fn chunk_output(chunk: Chunk) -> Output {
    Output { chunk.cv, words(chunk.block_), chunk.counter, chunk.length as u32,
        chunk.flags | start_flag(chunk) | CHUNK_END }
}
fn parent_output(left: u32[8], right: u32[8], key: u32[8], flags: u32) -> Output {
    var block_: u32[16] = default<u32[16]>();
    for index in 8 { block_[index] = left[index]; block_[index + 8] = right[index]; }
    return Output { key, block_, 0, 64, flags | PARENT , ..};
}
fn make_chunk(key: u32[8], counter: u64, flags: u32) -> Chunk {
    Chunk { key, counter, default<u8[64]>(), 0, 0, flags }
}
fn init() -> State { State { iv, make_chunk(iv, 0, 0), default<u32[8][54]>(), 0, 0 } }
fn initKeyed(key: u8[32]) -> State {
    var words: u32[8] = default<u32[8]>();
    for index in 8 { words[index] = blot_bytes::get_u32(key, index * 4); }
    return State { words, make_chunk(words, 0, KEYED), default<u32[8][54]>(), 0, KEYED , ..};
}
fn update_chunk(chunk: Chunk&, bytes: const u8[:]) {
    var at: i64 = 0;
    while at < bytes.len {
        if chunk.length == 64 {
            let compressed = compress(chunk.cv, words(chunk.block_), chunk.counter, 64,
                chunk.flags | start_flag(chunk));
            for index in 8 { chunk.cv[index] = compressed[index]; }
            chunk.compressed++; chunk.length = 0; chunk.block_ = default<u8[64]>();
        }
        let count = min(64 - chunk.length, bytes.len - at);
        for index in count { chunk.block_[chunk.length + index] = bytes[at + index]; }
        chunk.length += count; at += count;
    }
}
fn add_chunk(state: State&, var cv: u32[8], var total: u64) {
    while total & 1 == 0 {
        state.stack_len--;
        cv = chaining(parent_output(state.stack[state.stack_len], cv, state.key, state.flags));
        total >>= 1;
    }
    state.stack[state.stack_len] = cv; state.stack_len++;
}
fn update(state: State&, bytes: const u8[:]) {
    var at: i64 = 0;
    while at < bytes.len {
        let length = state.chunk.compressed as i64 * 64 + state.chunk.length;
        if length == 1024 {
            let cv = chaining(chunk_output(state.chunk));
            let total = state.chunk.counter + 1;
            add_chunk(state, cv, total);
            state.chunk = make_chunk(state.key, total, state.flags);
        }
        let used = state.chunk.compressed as i64 * 64 + state.chunk.length;
        let count = min(1024 - used, bytes.len - at);
        update_chunk(state.chunk, bytes[at..at + count]); at += count;
    }
}
fn finalBytes(state: State, out: u8[:]) {
    var output = chunk_output(state.chunk);
    var index = state.stack_len;
    while index > 0 {
        index--; output = parent_output(state.stack[index], chaining(output), state.key, state.flags);
    }
    var at: i64 = 0;
    var counter: u64 = 0;
    while at < out.len {
        let block_ = compress(output.cv, output.block_, counter, output.length, output.flags | ROOT);
        var encoded: u8[64] = default<u8[64]>();
        for word in 16 { blot_bytes::put_u32(encoded, word * 4, block_[word]); }
        let count = min(64, out.len - at);
        for byte in count { out[at + byte] = encoded[byte]; }
        at += count; counter++;
    }
}
fn final(state: State) -> u8[32] {
    var digest: u8[32] = default<u8[32]>(); finalBytes(state, digest); return digest;
}
fn hash(bytes: const u8[:]) -> u8[32] { var state = init(); update(state, bytes); return final(state); }
fn initDerived(context: const u8[:]) -> State {
    var context_state = init(); context_state.flags = DERIVE_CONTEXT;
    context_state.chunk.flags = DERIVE_CONTEXT; update(context_state, context);
    let key = final(context_state);
    var words: u32[8] = default<u32[8]>();
    for index in 8 { words[index] = blot_bytes::get_u32(key, index * 4); }
    return State { words, make_chunk(words, 0, DERIVE_MATERIAL), default<u32[8][54]>(), 0, DERIVE_MATERIAL , ..};
}
