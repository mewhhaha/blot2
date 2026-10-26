// Experimental public scalar semantic-interface envelope. This codec owns no
// source pointers, has no ABI realization or executable, and does not resolve
// packages or authenticate a producer. The caller must supply a producer tuple
// established by a trusted package resolver and separately qualify the ABI,
// semantic work, dependencies, body and lowering plan before K1 admission.
//
// Format: "K1PUBI01", u32 total bytes, u32 semantic byte count, then four
// length-prefixed edition/semantic/optimizer/ABI labels and a 32-byte expected
// ABI digest, canonical semantic bytes, and their 32-byte BLAKE3 digest.
// Integers are little-endian; strings are u32 byte count plus exact UTF-8 bytes. The semantic payload is
// "K1PUBSEM1", edition, semantic policy, package, module, declaration, then
// the 18 u32 fields listed in semantic(). No origins, source body, optimization
// policy, ABI realization or claimed executable are hashed into the interface.
// Entire object including digest is limited to 16 MiB; every input length and
// offset is checked before any candidate span is read or followed.
namespace public_artifact;
import public_frontend;
import public_interface;
import catalog;
import blake3;

struct Decoded {
    // 0 canonical, 1 malformed/producer mismatch, 2 incompatible identity,
    // 3 digest mismatch. None means the caller has authenticated a producer.
    status: i64 = 1, result_type: u32 = 0, declared_depth: u32 = 0,
    declared_frame: u32 = 0
}
fn put32(out: u8[>..]&, n: u32) {
    out.push((n & 255) as u8); out.push(((n >> 8) & 255) as u8);
    out.push(((n >> 16) & 255) as u8); out.push(((n >> 24) & 255) as u8);
}
fn putstr(out: u8[>..]&, s: u8[:]) { put32(out, s.len as u32); out.append(s); }
fn get32(bytes: u8[:], p: i64) -> u32 {
    if p < 0 || p > bytes.len - 4 { return 0; }
    return bytes[p] | ((bytes[p + 1] as u32) << 8) |
        ((bytes[p + 2] as u32) << 16) | ((bytes[p + 3] as u32) << 24);
}
// This checks the actual encoded length and bytes against the expected value,
// never a self-asserted length before proving it fits the remaining payload.
fn skip_expected(bytes: u8[:], p: i64, end: i64, expected: u8[:]) -> i64 {
    if p < 0 || end < p || end > bytes.len || end - p < 4 { return -1; }
    if get32(bytes, p) != expected.len { return -1; }
    let start = p + 4;
    if expected.len > end - start { return -1; }
    if bytes[start..start + expected.len] != expected { return -1; }
    return start + expected.len;
}
fn semantic(interface: public_interface::Interface&) -> u8[>..] {
    var out: u8[>..] = [];
    out.append("K1PUBSEM1");
    putstr(out, interface.edition); putstr(out, interface.semantic_policy);
    putstr(out, interface.package_identity); putstr(out, interface.module_path);
    putstr(out, interface.declaration);
    put32(out, interface.visibility as u32); put32(out, interface.parameter_type as u32);
    put32(out, interface.result_type as u32); put32(out, interface.parameter_count as u32);
    put32(out, interface.call_mode as u32); put32(out, interface.lifetime as u32);
    put32(out, interface.effect_bits as u32); put32(out, interface.binder_count as u32);
    put32(out, interface.capture_count as u32); put32(out, interface.precondition_count as u32);
    put32(out, interface.postcondition_count as u32); put32(out, interface.on_true_count as u32);
    put32(out, interface.on_false_count as u32); put32(out, interface.dictionary_count as u32);
    put32(out, interface.layout_premise_count as u32); put32(out, interface.data_identity_count as u32);
    put32(out, interface.declared_depth); put32(out, interface.declared_frame);
    return out;
}

// Candidate construction validates source before producing bytes. The bound
// includes envelope, digest and all metadata, not merely the producer tuple.
fn header_size() -> i64 {
    return 4 * 4 + catalog::edition().len + catalog::semantic_policy().len +
        catalog::optimization_policy().len + catalog::wasm_abi().len + 32;
}
fn encode(source: u8[:], candidate: public_frontend::Candidate, package: u8[:],
          module: u8[:], declaration: u8[:], abi_hash: u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    if abi_hash.len != 32 || !public_interface::identity_valid(package, module, declaration) { return out; }
    // Check the complete envelope size before building any owned candidate.
    let fixed = 9 + 5 * 4 + catalog::edition().len + catalog::semantic_policy().len + 18 * 4 + 16 + 32 + header_size();
    if package.len > 16777216 - fixed || module.len > 16777216 - fixed - package.len ||
       declaration.len > 16777216 - fixed - package.len - module.len { return out; }
    let built = public_interface::build(source, candidate, package, module, declaration);
    if built.status != 0 { return out; }
    let payload = semantic(built.interface);
    let digest = blake3::hash(payload);
    out.append("K1PUBI01"); put32(out, (16 + header_size() + payload.len + 32) as u32);
    put32(out, payload.len as u32);
    putstr(out, catalog::edition()); putstr(out, catalog::semantic_policy());
    putstr(out, catalog::optimization_policy()); putstr(out, catalog::wasm_abi());
    out.append(abi_hash); out.append(payload); out.append(digest);
    return out;
}

// Decode independently of semantic() and encode(). Fixed field checks ensure
// unsupported binders/effects/captures and forged scalar types never become a
// plausible interface. We do not decode any external executable bytes.
fn decode(bytes: u8[:], package: u8[:], module: u8[:], declaration: u8[:], abi_hash: u8[:]) -> Decoded {
    if abi_hash.len != 32 || !public_interface::identity_valid(package, module, declaration) ||
       bytes.len > 16777216 || bytes.len < 16 + header_size() + 9 + 5 * 4 + 18 * 4 + 32 ||
       bytes[0..8] != "K1PUBI01" { return Decoded {}; }
    if get32(bytes, 8) != bytes.len { return Decoded {}; }
    let payload_length: i64 = get32(bytes, 12);
    let start = 16 + header_size();
    if payload_length != bytes.len - start - 32 { return Decoded {}; }
    var p: i64 = 16;
    p = skip_expected(bytes, p, start, catalog::edition()); if p < 0 { return Decoded { status: 2 }; }
    p = skip_expected(bytes, p, start, catalog::semantic_policy()); if p < 0 { return Decoded { status: 2 }; }
    p = skip_expected(bytes, p, start, catalog::optimization_policy()); if p < 0 { return Decoded { status: 2 }; }
    p = skip_expected(bytes, p, start, catalog::wasm_abi()); if p < 0 { return Decoded { status: 2 }; }
    if start - p != 32 || bytes[p..start] != abi_hash { return Decoded { status: 2 }; }
    let end = start + payload_length;
    if payload_length < 9 || bytes[start..start + 9] != "K1PUBSEM1" { return Decoded {}; }
    p = start + 9;
    p = skip_expected(bytes, p, end, catalog::edition());
    if p < 0 { return Decoded { status: 2 }; }
    p = skip_expected(bytes, p, end, catalog::semantic_policy());
    if p < 0 { return Decoded { status: 2 }; }
    p = skip_expected(bytes, p, end, package); if p < 0 { return Decoded {}; }
    p = skip_expected(bytes, p, end, module); if p < 0 { return Decoded {}; }
    p = skip_expected(bytes, p, end, declaration); if p < 0 { return Decoded {}; }
    if end - p != 18 * 4 { return Decoded {}; }
    let result_type = get32(bytes, p + 8);
    let depth = get32(bytes, p + 64);
    let frame = get32(bytes, p + 68);
    if result_type != 1 && result_type != 2 { return Decoded {}; }
    if depth < 1 || depth > 128 { return Decoded {}; }
    let exact: u32[18] = [1, 1, result_type, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, depth, frame];
    for value in exact {
        if get32(bytes, p) != value { return Decoded {}; }
        p += 4;
    }
    if p != end { return Decoded {}; }
    let actual_digest = blake3::hash(bytes[start..end]);
    if actual_digest[..] != bytes[end..] { return Decoded { status: 3 }; }
    return Decoded { status: 0, result_type: result_type, declared_depth: depth, declared_frame: frame };
}

// Fresh source validation binds an artifact to the current declaration. The
// source verifier independently checks grammar, exit targets, scalar Core and
// exact declared bounds. No supplied digest, encoded producer or old candidate
// alone is a source proof. Body-only edits with the same interface can match.
fn verify_source(bytes: u8[:], source: u8[:], candidate: public_frontend::Candidate,
                 package: u8[:], module: u8[:], declaration: u8[:], abi_hash: u8[:]) -> i64 {
    let found = decode(bytes, package, module, declaration, abi_hash);
    if found.status != 0 { return found.status; }
    if !public_frontend::verify(source, candidate) { return 1; }
    if source[candidate.core.name_start..candidate.core.name_end] != declaration ||
       candidate.core.result_type != found.result_type ||
       candidate.declared_depth != found.declared_depth ||
       candidate.declared_frame != found.declared_frame { return 1; }
    return 0;
}
