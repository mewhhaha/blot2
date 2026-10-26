// Private scalar interface envelope experiment, per ARTIFACT_SCHEMA proposal.
// This only checks exact canonical bytes for a caller-selected tuple and hash;
// it authenticates neither package identity, source semantics, ABI hash, work
// receipt nor executable bytes. Public declarations and K1 admission are not
// supported. The caller must independently establish all such authority.
namespace interface_candidate;
import catalog;
import lexer;
import wasm;

fn put16(out: u8[>..]&, n: u32) {
    out.push((n & 255) as u8); out.push(((n >> 8) & 255) as u8);
}
fn put32(out: u8[>..]&, n: u32) {
    out.push((n & 255) as u8); out.push(((n >> 8) & 255) as u8);
    out.push(((n >> 16) & 255) as u8); out.push(((n >> 24) & 255) as u8);
}
fn string(out: u8[>..]&, text: u8[:]) { put32(out, text.len as u32); out.append(text); }
fn entry(out: u8[>..]&, id: u32, offset: i64, length: i64) {
    put16(out, id); put16(out, 0); put32(out, offset as u32); put32(out, length as u32);
}
fn text_ok(s: u8[:]) -> bool {
    if s.len == 0 || s.len > 16777216 || lexer::invalid_utf8(s) >= 0 { return false; }
    for c in s { if c < 32 || c == 127 { return false; } }
    return true;
}
fn path_ok(path: u8[:]) -> bool {
    if !text_ok(path) || path[0] == '/' || path[path.len - 1] == '/' { return false; }
    if path.len >= 2 && ((path[0] >= 'a' && path[0] <= 'z') ||
       (path[0] >= 'A' && path[0] <= 'Z')) && path[1] == ':' { return false; }
    var start: i64 = 0;
    for c, i in path {
        if c == '\\' { return false; }
        if c == '/' {
            if i == start || path[start..i] == "." || path[start..i] == ".." { return false; }
            start = i + 1;
        }
    }
    return path[start..] != "." && path[start..] != "..";
}

// Scalar semantic data is fixed: private, monomorphic U32->U32, Many,
// no effects, binders, captures, pre/postconditions, dictionaries, layout or
// nominal payloads, depth=1/frame=0. No source has yet been admitted here.
fn encode(package: u8[:], path: u8[:], declaration: u8[:], abi: u8[:]) -> u8[] {
    if abi.len != 32 || !text_ok(package) || !path_ok(path) ||
       declaration.len > 16777216 || !wasm::identifier(declaration) { return []; }
    // All lengths are independently bounded before addition/allocation.
    let producer_length = 16 + package.len + path.len + declaration.len;
    let version_length = 16 + catalog::edition().len + catalog::semantic_policy().len +
        catalog::optimization_policy().len + catalog::wasm_abi().len + 32;
    let total = 72 + version_length + producer_length + 56 + 4;
    if total > 16777216 { return []; }
    let version_offset: i64 = 72;
    let producer_offset = version_offset + version_length;
    let contract_offset = producer_offset + producer_length;
    let observations_offset = contract_offset + 56;

    var out: u8[>..] = [];
    out.append("K1ART001"); put16(out, 1); out.push(1); out.push(0); // interface
    put32(out, total as u32); put16(out, 4); put16(out, 0); put32(out, 48);
    entry(out, 1, version_offset, version_length);
    entry(out, 2, producer_offset, producer_length);
    entry(out, 3, contract_offset, 56);
    entry(out, 7, observations_offset, 4);
    string(out, catalog::edition()); string(out, catalog::semantic_policy());
    string(out, catalog::optimization_policy()); string(out, catalog::wasm_abi()); out.append(abi);
    string(out, package); string(out, path); put32(out, 1); string(out, declaration);
    // The fourteen fixed u32 words follow ARTIFACT_SCHEMA's interface record.
    for word in [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0] { put32(out, word as u32); }
    put32(out, 0); // zero external observation entries in this closed subset
    if out.len != total { return []; }
    return out;
}

// These bounded readers are defined separately from the encoder. Callers
// must not infer success from the zero returned for an invalid offset.
fn get16(bytes: u8[:], p: i64) -> u32 {
    if p < 0 || p > bytes.len - 2 { return 0; }
    return bytes[p] | ((bytes[p + 1] as u32) << 8);
}
fn get32(bytes: u8[:], p: i64) -> u32 {
    if p < 0 || p > bytes.len - 4 { return 0; }
    return bytes[p] | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
fn entry_is(bytes: u8[:], p: i64, id: u32, offset: i64, length: i64) -> bool {
    if p < 0 || p > bytes.len - 12 { return false; }
    return get16(bytes, p) == id && get16(bytes, p + 2) == 0 &&
        get32(bytes, p + 4) == offset && get32(bytes, p + 8) == length;
}
fn field_is(bytes: u8[:], p: i64, expected: u8[:]) -> bool {
    if p < 0 || p > bytes.len - 4 || get32(bytes, p) != expected.len { return false; }
    let start = p + 4;
    if expected.len > bytes.len - start { return false; }
    return bytes[start..start + expected.len] == expected;
}

// Status: 0 canonical match, 1 malformed/not the expected producer or scalar
// schema, 2 incompatible encoded edition/policies/ABI. The expected tuple/hash
// come from the caller and are not established by this API. Decode and check
// the actual header, directory, fields and contract independently of encode;
// never use an offset from the input before validating it.
fn validate(bytes: u8[:], package: u8[:], path: u8[:], declaration: u8[:], abi: u8[:]) -> i64 {
    if bytes.len < 72 || bytes.len > 16777216 || bytes[0..8] != "K1ART001" ||
       abi.len != 32 || !text_ok(package) || !path_ok(path) ||
       declaration.len > 16777216 || !wasm::identifier(declaration) { return 1; }
    let versions_len = 16 + catalog::edition().len + catalog::semantic_policy().len +
        catalog::optimization_policy().len + catalog::wasm_abi().len + 32;
    let producer_len = 16 + package.len + path.len + declaration.len;
    let total = 72 + versions_len + producer_len + 56 + 4;
    if get16(bytes, 8) != 1 || bytes[10] != 1 { return 2; }
    if total > 16777216 || bytes.len != total ||
       bytes[11] != 0 || get32(bytes, 12) != total ||
       get16(bytes, 16) != 4 || get16(bytes, 18) != 0 || get32(bytes, 20) != 48 { return 1; }
    let producer_offset = 72 + versions_len;
    let contract_offset = producer_offset + producer_len;
    let observations_offset = contract_offset + 56;
    if !entry_is(bytes, 24, 1, 72, versions_len) ||
       !entry_is(bytes, 36, 2, producer_offset, producer_len) ||
       !entry_is(bytes, 48, 3, contract_offset, 56) ||
       !entry_is(bytes, 60, 7, observations_offset, 4) { return 1; }
    var p: i64 = 72;
    if !field_is(bytes, p, catalog::edition()) { return 2; }
    p += 4 + catalog::edition().len;
    if !field_is(bytes, p, catalog::semantic_policy()) { return 2; }
    p += 4 + catalog::semantic_policy().len;
    if !field_is(bytes, p, catalog::optimization_policy()) { return 2; }
    p += 4 + catalog::optimization_policy().len;
    if !field_is(bytes, p, catalog::wasm_abi()) { return 2; }
    p += 4 + catalog::wasm_abi().len;
    if p > bytes.len - 32 || bytes[p..p + 32] != abi { return 2; }
    p += 32;
    if p != producer_offset || !field_is(bytes, p, package) { return 1; }
    p += 4 + package.len;
    if !field_is(bytes, p, path) { return 1; }
    p += 4 + path.len;
    if p > bytes.len - 4 || get32(bytes, p) != 1 { return 1; }
    p += 4;
    if !field_is(bytes, p, declaration) { return 1; }
    p += 4 + declaration.len;
    if p != contract_offset { return 1; }
    let contract: u32[14] = [1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0];
    for value in contract {
        if p > bytes.len - 4 || get32(bytes, p) != value { return 1; }
        p += 4;
    }
    if p != observations_offset || p > bytes.len - 4 || get32(bytes, p) != 0 { return 1; }
    p += 4;
    if p != bytes.len { return 1; }
    return 0;
}
