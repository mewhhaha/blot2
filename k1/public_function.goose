// Private experiment for an owned, source-bound public scalar function. This
// is not a portable CheckedFunction, cache receipt or authority to emit Wasm.
// Expected producer and ABI are caller inputs, not authenticated by this file.
// Source, interface, ABI profile, required-work receipt, dependency and
// executable provenance must all be independently established for K1 admission.
//
// K1PUBF02: magic[8], total u32, semantic length u32, compatibility header
// (edition/semantic/optimizer/ABI labels + expected ABI hash), semantic bytes,
// 32-byte BLAKE3 of semantic bytes, and ten u32 source-origin offsets. Semantic
// bytes are "K1PUBFUN2", an explicit length and exact canonical interface
// semantic bytes, its 32-byte fingerprint, result type,
// value count, terminator, result ID, and four 6-word scalar value records.
// Origins and ABI realization are deliberately outside the semantic digest.
namespace public_function;
import catalog;
import blake3;
import scalar_core;
import public_frontend;
import public_artifact;

struct Decoded { status: i64 = 1, core: scalar_core::ScalarCore = scalar_core::ScalarCore {} }
// For v02 the function envelope is exactly interface_length + 197 bytes:
// it embeds the interface semantic bytes, omits the interface envelope and
// retains its digest. Subtraction avoids overflow for arbitrary caller sizes.
fn fits_interface(interface_length: i64) -> bool {
    return interface_length >= 0 && interface_length <= 16777216 - 197;
}
// Digests select a candidate only; exact canonical linked bytes are compared
// independently, including when two supplied digest values are identical.
fn same_link(a: u8[:], a_digest: u8[:], b: u8[:], b_digest: u8[:]) -> bool {
    return a_digest.len == 32 && b_digest.len == 32 && a_digest == b_digest && a == b;
}
fn header(out: u8[>..]&, abi: u8[:]) {
    public_artifact::putstr(out, catalog::edition());
    public_artifact::putstr(out, catalog::semantic_policy());
    public_artifact::putstr(out, catalog::optimization_policy());
    public_artifact::putstr(out, catalog::wasm_abi()); out.append(abi);
}
fn header_valid(bytes: u8[:], start: i64, abi: u8[:]) -> bool {
    if abi.len != 32 || start != 16 + public_artifact::header_size() || bytes.len < start { return false; }
    var p: i64 = 16;
    p = public_artifact::skip_expected(bytes, p, start, catalog::edition()); if p < 0 { return false; }
    p = public_artifact::skip_expected(bytes, p, start, catalog::semantic_policy()); if p < 0 { return false; }
    p = public_artifact::skip_expected(bytes, p, start, catalog::optimization_policy()); if p < 0 { return false; }
    p = public_artifact::skip_expected(bytes, p, start, catalog::wasm_abi()); if p < 0 { return false; }
    return start - p == 32 && bytes[p..start] == abi;
}
fn semantic(core: scalar_core::ScalarCore, interface_semantic: u8[:], interface_digest: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if interface_digest.len != 32 { return out; }
    out.append("K1PUBFUN2"); public_artifact::put32(out, interface_semantic.len as u32);
    out.append(interface_semantic); out.append(interface_digest);
    public_artifact::put32(out, core.result_type as u32);
    public_artifact::put32(out, core.value_count as u32);
    public_artifact::put32(out, core.terminator as u32);
    public_artifact::put32(out, core.result_id as u32);
    for v in core.values {
        public_artifact::put32(out, v.producer as u32); public_artifact::put32(out, v.type_id as u32);
        public_artifact::put32(out, v.op_id as u32); public_artifact::put32(out, v.literal);
        public_artifact::put32(out, v.left_id as u32); public_artifact::put32(out, v.right_id as u32);
    }
    return out;
}
fn origins(out: u8[>..]&, c: scalar_core::ScalarCore) {
    for p in [c.name_start, c.name_end, c.parameter_start, c.parameter_end,
              c.left_start, c.left_end, c.operator_start, c.operator_end,
              c.right_start, c.right_end] { public_artifact::put32(out, p as u32); }
}
fn encode(source: u8[:], candidate: public_frontend::Candidate, interface: u8[:],
          package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    // The output cannot fit even if the input later validates. Reject before
    // source revalidation or allocating any candidate/projection storage.
    if !fits_interface(interface.len) { return out; }
    if public_artifact::verify_source(interface, source, candidate, package, module, declaration, abi) != 0 { return out; }
    if !scalar_core::validate_structure(candidate.core) { return out; }
    let interface_start = 16 + public_artifact::header_size();
    let interface_end = interface.len - 32;
    let semantic_length = interface_end - interface_start;
    let overhead = 16 + public_artifact::header_size() + 157 + 32 + 40;
    if semantic_length > 16777216 - overhead { return out; }
    let payload = semantic(candidate.core, interface[interface_start..interface_end], interface[interface_end..]);
    if payload.len != 157 + semantic_length { return out; }
    let digest = blake3::hash(payload);
    let total = 16 + public_artifact::header_size() + payload.len + 32 + 40;
    out.append("K1PUBF02"); public_artifact::put32(out, total as u32);
    public_artifact::put32(out, payload.len as u32); header(out, abi);
    out.append(payload); out.append(digest); origins(out, candidate.core);
    return out;
}
fn decode(bytes: u8[:], interface: u8[:], package: u8[:], module: u8[:],
          declaration: u8[:], abi: u8[:]) -> Decoded {
    let expected = public_artifact::decode(interface, package, module, declaration, abi);
    if expected.status != 0 { return Decoded { status: expected.status }; }
    let start = 16 + public_artifact::header_size();
    if bytes.len > 16777216 || bytes.len < start + 157 + 32 + 40 ||
       bytes[0..8] != "K1PUBF02" || public_artifact::get32(bytes, 8) != bytes.len { return Decoded {}; }
    let payload_length: i64 = public_artifact::get32(bytes, 12);
    if payload_length != bytes.len - start - 32 - 40 || payload_length < 157 { return Decoded {}; }
    let end = start + payload_length;
    if !header_valid(bytes, start, abi) { return Decoded { status: 2 }; }
    if bytes[start..start + 9] != "K1PUBFUN2" { return Decoded {}; }
    let interface_start = 16 + public_artifact::header_size();
    let interface_end = interface.len - 32;
    let interface_length: i64 = public_artifact::get32(bytes, start + 9);
    if interface_length != interface_end - interface_start || interface_length != payload_length - 157 { return Decoded {}; }
    let link_start = start + 13;
    let digest_start = link_start + interface_length;
    if !same_link(bytes[link_start..digest_start], bytes[digest_start..digest_start + 32],
                  interface[interface_start..interface_end], interface[interface_end..]) { return Decoded {}; }
    if blake3::hash(bytes[start..end])[..] != bytes[end..end + 32] { return Decoded { status: 3 }; }
    var c = scalar_core::ScalarCore {};
    var p = digest_start + 32;
    c.result_type = public_artifact::get32(bytes, p); p += 4;
    c.value_count = public_artifact::get32(bytes, p); p += 4;
    c.terminator = public_artifact::get32(bytes, p); p += 4;
    c.result_id = public_artifact::get32(bytes, p); p += 4;
    for i in 4 {
        c.values[i].producer = public_artifact::get32(bytes, p); p += 4;
        c.values[i].type_id = public_artifact::get32(bytes, p); p += 4;
        c.values[i].op_id = public_artifact::get32(bytes, p); p += 4;
        c.values[i].literal = public_artifact::get32(bytes, p); p += 4;
        c.values[i].left_id = public_artifact::get32(bytes, p); p += 4;
        c.values[i].right_id = public_artifact::get32(bytes, p); p += 4;
    }
    if p != end { return Decoded {}; }
    p += 32;
    c.name_start = public_artifact::get32(bytes, p); p += 4; c.name_end = public_artifact::get32(bytes, p); p += 4;
    c.parameter_start = public_artifact::get32(bytes, p); p += 4; c.parameter_end = public_artifact::get32(bytes, p); p += 4;
    c.left_start = public_artifact::get32(bytes, p); p += 4; c.left_end = public_artifact::get32(bytes, p); p += 4;
    c.operator_start = public_artifact::get32(bytes, p); p += 4; c.operator_end = public_artifact::get32(bytes, p); p += 4;
    c.right_start = public_artifact::get32(bytes, p); p += 4; c.right_end = public_artifact::get32(bytes, p); p += 4;
    if p != bytes.len || c.result_type != expected.result_type || !scalar_core::validate_structure(c) { return Decoded {}; }
    for o in [c.name_start, c.name_end, c.parameter_start, c.parameter_end, c.left_start, c.left_end,
              c.operator_start, c.operator_end, c.right_start, c.right_end] {
        if o < 0 || o > 16777216 { return Decoded {}; }
    }
    return Decoded { status: 0, core: c };
}
fn same(a: scalar_core::ScalarCore, b: scalar_core::ScalarCore) -> bool {
    if a.result_type != b.result_type || a.value_count != b.value_count ||
       a.terminator != b.terminator || a.result_id != b.result_id ||
       a.name_start != b.name_start || a.name_end != b.name_end ||
       a.parameter_start != b.parameter_start || a.parameter_end != b.parameter_end ||
       a.left_start != b.left_start || a.left_end != b.left_end ||
       a.operator_start != b.operator_start || a.operator_end != b.operator_end ||
       a.right_start != b.right_start || a.right_end != b.right_end { return false; }
    for i in 4 { if !scalar_core::same_value(a.values[i], b.values[i]) { return false; } }
    return true;
}
fn verify_source(bytes: u8[:], source: u8[:], candidate: public_frontend::Candidate,
                 interface: u8[:], package: u8[:], module: u8[:], declaration: u8[:], abi: u8[:]) -> i64 {
    if public_artifact::verify_source(interface, source, candidate, package, module, declaration, abi) != 0 { return 1; }
    let found = decode(bytes, interface, package, module, declaration, abi);
    if found.status != 0 { return found.status; }
    if !same(found.core, candidate.core) { return 1; }
    return 0;
}
