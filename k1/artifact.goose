// Experimental bounded serialization for the scalar fixture, not a K1
// CheckedFunction or structural certificate. No executable bytes are trusted.
namespace artifact;
import validate;
import catalog;

// Magic plus edition, semantic policy, optimization policy and ABI label.
// The labels are checked before any payload offset is interpreted.
fn header() -> u8[>..] {
    var bytes: u8[>..] = [];
    bytes.append("BLK1SC01|");
    bytes.append(catalog::edition()); bytes.push('|');
    bytes.append(catalog::semantic_policy()); bytes.push('|');
    bytes.append(catalog::optimization_policy()); bytes.push('|');
    bytes.append(catalog::wasm_abi()); bytes.push('|');
    return bytes;
}
fn put32(out: u8[>..]&, value: u32) {
    out.push((value & 255) as u8);
    out.push(((value >> 8) & 255) as u8);
    out.push(((value >> 16) & 255) as u8);
    out.push(((value >> 24) & 255) as u8);
}
fn get32(bytes: u8[:], p: i64) -> u32 {
    return bytes[p] | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
struct Decoded {
    status: i64 = 1, // 0 valid, 1 malformed, 2 incompatible header
    source_start: i64 = 0,
    source_end: i64 = 0,
    name_start: i64 = 0,
    name_end: i64 = 0,
    operand_start: i64 = 0,
    operand_end: i64 = 0,
    kind: i64 = 0,
    literal: u32 = 0
}

// Every span is source-relative. The object is limited to 16 MiB, including
// header and metadata. Invalid candidates return an empty byte array.
fn encode(source: u8[:], start: i64, end: i64, name_start: i64,
          name_end: i64, kind: i64, literal: u32) -> u8[>..] {
    var out: u8[>..] = [];
    let h = header();
    if source.len > 16777216 - h.len - 28 { return out; }
    if validate::scalar(source, start, end, name_start, name_end, kind, literal,
       catalog::edition(), catalog::semantic_policy(), catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return out; }
    out.append(h);
    put32(out, source.len as u32);
    put32(out, start as u32);
    put32(out, end as u32);
    put32(out, name_start as u32);
    put32(out, name_end as u32);
    put32(out, kind as u32);
    put32(out, literal);
    out.append(source);
    return out;
}

// Does not allocate. All lengths and spans are checked before following
// them; the independent scalar validator then checks source correspondence.
fn decode(bytes: u8[:]) -> Decoded {
    var result = Decoded {};
    let h = header();
    if bytes.len > 16777216 || bytes.len < h.len + 28 { return result; }
    if bytes[0..8] != h[0..8] { return result; }
    if bytes[8..h.len] != h[8..h.len] { result.status = 2; return result; }
    var p = h.len;
    let length = get32(bytes, p) as i64; p += 4;
    let start = get32(bytes, p) as i64; p += 4;
    let end = get32(bytes, p) as i64; p += 4;
    let name_start = get32(bytes, p) as i64; p += 4;
    let name_end = get32(bytes, p) as i64; p += 4;
    let kind = get32(bytes, p) as i64; p += 4;
    let literal = get32(bytes, p);
    p += 4;
    if length != bytes.len - p { return result; }
    let source = bytes[p..];
    if validate::scalar(source, start, end, name_start, name_end, kind, literal,
       catalog::edition(), catalog::semantic_policy(), catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return result; }
    result.status = 0;
    result.source_start = p; result.source_end = bytes.len;
    result.name_start = name_start; result.name_end = name_end;
    result.operand_start = start; result.operand_end = end;
    result.kind = kind; result.literal = literal;
    return result;
}
