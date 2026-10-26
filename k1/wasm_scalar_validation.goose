// Independent validation of the private scalar Wasm fixture. This is a closed
// structural and semantic check for one source-bound U32/Bool callable; it is
// not the general K1 M13 certificate, ABI profile/hash, or a host bridge.
// It accepts no imports, tables, globals, data, start function, helper calls,
// memory instructions, alternate encodings, or operations outside the closed
// scalar Core. A matching check is not authentication of an external artifact.
namespace wasm_scalar_validation;
import catalog;
import fixture_geometry;
import manifest;
import scalar_plan;
import scalar_core;
import validate;

struct Reader { at: i64 = 0, end: i64 = 0, ok: bool = true }

fn byte(bytes: const u8[:], r: Reader&) -> i64 {
    if !r.ok || r.at < 0 || r.end < r.at || r.end > bytes.len || r.at == r.end {
        r.ok = false; return -1;
    }
    let result = bytes[r.at]; r.at += 1; return result;
}

// Canonical U32 LEB; -1 means malformed. No addition or shift can overflow.
fn u32_leb(bytes: const u8[:], r: Reader&) -> i64 {
    var result: i64 = 0;
    for i in 5 {
        let b = byte(bytes, r);
        if b < 0 { return -1; }
        let payload = b & 127;
        if i == 4 && payload > 15 { r.ok = false; return -1; }
        result += payload << (7 * i);
        if b < 128 {
            if i > 0 && payload == 0 { r.ok = false; return -1; }
            return result;
        }
    }
    r.ok = false; return -1;
}

// Canonical signed i32 LEB, returned as the corresponding unsigned bit
// pattern. Reject overlong, unterminated and out-of-range immediates.
fn i32_leb_bits(bytes: const u8[:], r: Reader&) -> i64 {
    var result: i64 = 0;
    var previous: i64 = 0;
    for i in 5 {
        let b = byte(bytes, r);
        if b < 0 { return -1; }
        let payload = b & 127;
        result += payload << (7 * i);
        if b < 128 {
            if i > 0 && ((payload == 0 && (previous & 64) == 0) ||
                         (payload == 127 && (previous & 64) != 0)) {
                r.ok = false; return -1;
            }
            let shift = 7 * (i + 1);
            if (payload & 64) != 0 { result -= 1 << shift; }
            if result < -2147483648 || result > 2147483647 { r.ok = false; return -1; }
            if result < 0 { result += 4294967296; }
            return result;
        }
        previous = payload;
    }
    r.ok = false; return -1;
}

// Obtain a bounded section and advance its parent's cursor only after the
// complete section range has been checked using subtraction.
fn section(bytes: const u8[:], parent: Reader&, id: i64) -> Reader {
    if byte(bytes, parent) != id { parent.ok = false; return Reader { ok: false }; }
    let n = u32_leb(bytes, parent);
    if n < 0 || n > parent.end - parent.at { parent.ok = false; return Reader { ok: false }; }
    let start = parent.at;
    parent.at += n;
    return Reader { at: start, end: parent.at };
}
fn done(r: Reader) -> bool { return r.ok && r.at == r.end; }
fn equal_payload(bytes: const u8[:], r: Reader, expected: const u8[:]) -> bool {
    return r.ok && r.at >= 0 && r.end >= r.at && r.end <= bytes.len &&
           bytes[r.at..r.end] == expected;
}
fn operand(bytes: const u8[:], body: Reader&, value: scalar_core::ScalarValue) -> bool {
    if value.producer == 1 {
        return byte(bytes, body) == 0x20 && u32_leb(bytes, body) == 1;
    }
    if value.producer == 2 {
        if byte(bytes, body) != 0x41 { return false; }
        return i32_leb_bits(bytes, body) == value.literal;
    }
    return false;
}

// This validator supports one fixed private profile. Equal page counts alone
// do not identify its memory roles. Compare every geometry field with the
// independently constructed selected profile before considering any bytes.
fn selected_geometry(g: manifest::Geometry&) -> bool {
    let expected, ok = fixture_geometry::build();
    if !ok || manifest::validate(g) != 0 ||
       g.page_bytes != expected.page_bytes || g.initial_pages != expected.initial_pages ||
       g.maximum_pages != expected.maximum_pages || g.owner_slots != expected.owner_slots ||
       g.owner_entry_bytes != expected.owner_entry_bytes || g.granule_bytes != expected.granule_bytes ||
       g.root_capsule_bytes != expected.root_capsule_bytes || g.padding_count != expected.padding_count { return false; }
    for i in 9 {
        if g.regions[i].tag != expected.regions[i].tag || g.regions[i].start != expected.regions[i].start ||
           g.regions[i].length != expected.regions[i].length { return false; }
    }
    for i in 10 {
        if g.padding[i].tag != expected.padding[i].tag || g.padding[i].start != expected.padding[i].start ||
           g.padding[i].length != expected.padding[i].length { return false; }
    }
    return true;
}

// geometry must be the separately selected/validated fixture map, not a claim
// read from Wasm's custom metadata. Source validation precedes all source spans.
// Exact code semantics are checked against the source-bound Core, not its hash.
fn verify(source: const u8[:], plan: scalar_plan::ScalarLoweringPlan,
          geometry: manifest::Geometry&, bytes: const u8[:]) -> i64 {
    // C09's 16 MiB serialized-artifact limit is not a Wasm-output limit. This
    // closed emitter's module is at most the source byte length plus 4096
    // bytes of fixed section framing/metadata and its bounded scalar body.
    // A maximal source identifier can thus produce a module above 16 MiB.
    if source.len > 16777216 || bytes.len > source.len + 4096 ||
       !scalar_plan::validate(plan) || !selected_geometry(geometry) ||
       geometry.initial_pages != plan.memory_initial_pages ||
       geometry.maximum_pages != plan.memory_maximum_pages { return 1; }
    let core = plan.core;
    if validate::scalar_v2(source, core, catalog::edition(), catalog::semantic_policy(),
                           catalog::optimization_policy(), catalog::wasm_abi()) != 0 { return 1; }
    let magic: u8[8] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    if bytes.len < 8 || bytes[..8] != magic[..] { return 1; }
    var root = Reader { at: 8, end: bytes.len };
    let ty = section(bytes, root, 1);
    if !equal_payload(bytes, ty, [1, 0x60, 2, 0x7f, 0x7f, 1, 0x7f]) { return 1; }
    let functions = section(bytes, root, 3);
    if !equal_payload(bytes, functions, [1, 0]) { return 1; }
    var memory = section(bytes, root, 5);
    if byte(bytes, memory) != 1 || byte(bytes, memory) != 1 ||
       u32_leb(bytes, memory) != geometry.initial_pages ||
       u32_leb(bytes, memory) != geometry.maximum_pages || !done(memory) { return 1; }
    var exports = section(bytes, root, 7);
    if u32_leb(bytes, exports) != 1 { return 1; }
    let name_size = u32_leb(bytes, exports);
    if name_size < 0 || name_size > exports.end - exports.at { return 1; }
    let name_start = exports.at;
    exports.at += name_size;
    if bytes[name_start..exports.at] != source[core.name_start..core.name_end] ||
       byte(bytes, exports) != 0 || u32_leb(bytes, exports) != 0 || !done(exports) { return 1; }
    var code = section(bytes, root, 10);
    if u32_leb(bytes, code) != 1 { return 1; }
    let body_size = u32_leb(bytes, code);
    if body_size < 0 || body_size > code.end - code.at { return 1; }
    var body = Reader { at: code.at, end: code.at + body_size };
    code.at += body_size;
    if byte(bytes, body) != 0 { return 1; } // no local declaration groups
    let result = core.values[core.result_id];
    if result.producer == 3 {
        if !operand(bytes, body, core.values[result.left_id]) ||
           !operand(bytes, body, core.values[result.right_id]) ||
           byte(bytes, body) != plan.opcode { return 1; }
    } else if !operand(bytes, body, result) { return 1; }
    if byte(bytes, body) != 0x0b || !done(body) || !done(code) { return 1; }
    // This private emitter includes one non-executable custom section. Its
    // data is not used as evidence of geometry, identity, or code provenance.
    // All other sections (including imports, start and data) reject.
    var custom = section(bytes, root, 0);
    let length = u32_leb(bytes, custom);
    if length < 0 || length > custom.end - custom.at ||
       bytes[custom.at..custom.at + length] != "blot.k1.fixture.memory" { return 1; }
    custom.at = custom.end;
    if !done(custom) { return 1; }
    if !done(root) { return 1; }
    return 0;
}
