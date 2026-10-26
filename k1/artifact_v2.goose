// Private SC02 scalar fixture container. This is not an authenticated K1
// CheckedFunction, cache, certificate, ABI manifest, or executable image.
//
// Byte format (no native struct layout, no padding):
//  * ASCII `BLK1SC02|` then exact edition, semantic policy, optimization policy,
//    and ABI labels, each terminated by `|`; all labels match catalog.
//  * 39 unsigned 32-bit words, little endian: source byte length; result_type,
//    value_count, terminator, result_id; name_start/end, parameter_start/end,
//    left_start/end, operator_start/end, right_start/end; then each of exactly
//    four value slots as producer, type_id, op_id, literal, left_id, right_id.
//  * The exact source bytes, whose length equals all remaining bytes.
// The source bytes are the source identity in this format; no external file or
// digest is accepted as a substitute. The entire object is at most 16 MiB.
// There are no machine-code bytes or trailing extension fields.
namespace artifact_v2;
import catalog;
import scalar_core;
import validate;

fn header() -> u8[>..] {
    var b: u8[>..] = [];
    b.append("BLK1SC02|");
    b.append(catalog::edition()); b.push('|');
    b.append(catalog::semantic_policy()); b.push('|');
    b.append(catalog::optimization_policy()); b.push('|');
    b.append(catalog::wasm_abi()); b.push('|');
    return b;
}
fn put32(out: u8[>..]&, value: u32) {
    out.push((value & 255) as u8);
    out.push(((value >> 8) & 255) as u8);
    out.push(((value >> 16) & 255) as u8);
    out.push(((value >> 24) & 255) as u8);
}
// The decoder proves the complete metadata window first. This guard also
// keeps direct helper calls from indexing a malformed span.
fn get32(bytes: u8[:], p: i64) -> u32 {
    if p < 0 || p > bytes.len - 4 { return 0; }
    return bytes[p] | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
struct Decoded {
    status: i64 = 1, // 0 valid, 1 malformed/inconsistent, 2 incompatible IDs
    source_start: i64 = 0,
    source_end: i64 = 0,
    core: scalar_core::ScalarCore = scalar_core::ScalarCore {}
}

fn encode(source: u8[:], core: scalar_core::ScalarCore) -> u8[>..] {
    var out: u8[>..] = [];
    let h = header();
    if source.len > 16777216 - h.len - 156 { return out; }
    if validate::scalar_v2(source, core, catalog::edition(), catalog::semantic_policy(),
                           catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return out; }
    out.append(h);
    put32(out, source.len as u32);
    put32(out, core.result_type as u32); put32(out, core.value_count as u32);
    put32(out, core.terminator as u32); put32(out, core.result_id as u32);
    put32(out, core.name_start as u32); put32(out, core.name_end as u32);
    put32(out, core.parameter_start as u32); put32(out, core.parameter_end as u32);
    put32(out, core.left_start as u32); put32(out, core.left_end as u32);
    put32(out, core.operator_start as u32); put32(out, core.operator_end as u32);
    put32(out, core.right_start as u32); put32(out, core.right_end as u32);
    for value in core.values {
        put32(out, value.producer as u32); put32(out, value.type_id as u32);
        put32(out, value.op_id as u32); put32(out, value.literal);
        put32(out, value.left_id as u32); put32(out, value.right_id as u32);
    }
    out.append(source);
    return out;
}

// No source bytes are copied and no candidate span is sliced until after the
// complete header, exact length, and independent source/Core validation pass.
fn decode(bytes: u8[:]) -> Decoded {
    var result = Decoded {};
    let h = header();
    if bytes.len > 16777216 || bytes.len < h.len + 156 { return result; }
    if bytes[0..8] != h[0..8] { return result; }
    if bytes[8..h.len] != h[8..h.len] { result.status = 2; return result; }
    var p = h.len;
    let length: i64 = get32(bytes, p); p += 4;
    var core = scalar_core::ScalarCore {};
    core.result_type = get32(bytes, p); p += 4;
    core.value_count = get32(bytes, p); p += 4;
    core.terminator = get32(bytes, p); p += 4;
    core.result_id = get32(bytes, p); p += 4;
    core.name_start = get32(bytes, p); p += 4;
    core.name_end = get32(bytes, p); p += 4;
    core.parameter_start = get32(bytes, p); p += 4;
    core.parameter_end = get32(bytes, p); p += 4;
    core.left_start = get32(bytes, p); p += 4;
    core.left_end = get32(bytes, p); p += 4;
    core.operator_start = get32(bytes, p); p += 4;
    core.operator_end = get32(bytes, p); p += 4;
    core.right_start = get32(bytes, p); p += 4;
    core.right_end = get32(bytes, p); p += 4;
    for i in 4 {
        core.values[i].producer = get32(bytes, p); p += 4;
        core.values[i].type_id = get32(bytes, p); p += 4;
        core.values[i].op_id = get32(bytes, p); p += 4;
        core.values[i].literal = get32(bytes, p); p += 4;
        core.values[i].left_id = get32(bytes, p); p += 4;
        core.values[i].right_id = get32(bytes, p); p += 4;
    }
    if length != bytes.len - p { return result; }
    if validate::scalar_v2(bytes[p..], core, catalog::edition(), catalog::semantic_policy(),
                           catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return result; }
    result.status = 0;
    result.source_start = p; result.source_end = bytes.len;
    result.core = core;
    return result;
}
