// A narrowly scoped encoder for the validated K1-00 scalar fixture.
// The exported callable uses the canonical K1-WASM32-ABI1 scalar convention:
// (environment: i32, argument: i32) -> i32.  This is an internal test
// interface, not the copy-only host bridge specified for later milestones.
namespace wasm;
import scalar_core;
import scalar_plan;

fn identifier(name: u8[:]) -> bool {
    if name.len == 0 { return false; }
    // Names passed to the encoder must also be legal declaration identifiers.
    if name == "import" || name == "as" || name == "pub" || name == "let" ||
       name == "static" || name == "local" || name == "type" || name == "fn" ||
       name == "in" || name == "do" || name == "return" || name == "break" ||
       name == "continue" || name == "next" || name == "stop" || name == "seal" ||
       name == "abort" || name == "if" || name == "else" || name == "case" ||
       name == "for" || name == "carry" || name == "invariant" || name == "forall" ||
       name == "exists" || name == "where" || name == "requires" || name == "ensures" ||
       name == "on_true" || name == "on_false" || name == "resources" ||
       name == "region" || name == "owned" || name == "pack" || name == "open" ||
       name == "space" || name == "dest" || name == "env" || name == "builder" ||
       name == "view" || name == "index" || name == "array" || name == "U32" ||
       name == "F32" || name == "Unit" || name == "Bool" || name == "RegionOwner" ||
       name == "Space" || name == "Dest" || name == "EnvDest" || name == "Builder" ||
       name == "View" || name == "Index" || name == "Fn" || name == "Owned" ||
       name == "Result" || name == "Many" || name == "Once" || name == "Append" ||
       name == "Resize" || name == "Type" || name == "Region" || name == "Nat" ||
       name == "Domain" || name == "Plain" || name == "Share" || name == "_" { return false; }
    for c, i in name {
        let letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
        if !letter && !(i > 0 && c >= '0' && c <= '9') { return false; }
    }
    return true;
}

fn unsigned_leb(out: u8[>..]&, number: i64) {
    var n = number;
    while n >= 128 {
        out.push(((n % 128) + 128) as u8);
        n = n / 128;
    }
    out.push(n as u8);
}

fn signed_i32_leb(out: u8[>..]&, literal: u32) {
    // Wasm's i32.const uses signed LEB, including for U32 bit patterns.
    var n: i64 = literal;
    if n >= 2147483648 { n -= 4294967296; }
    loop {
        // Masking gives the low seven bits for negative as well as positive n.
        let byte = (n & 127) as u8;
        n = n >> 7;
        if (n == 0 && byte < 64) || (n == -1 && byte >= 64) {
            out.push(byte);
            break;
        }
        out.push(byte + 128);
    }
}

// All constants below are nonnegative and bounded well below i64 maximum.
// Check contiguous geometry, region alignment, metadata sizes, and rounded
// memory extent before encoding the fixture. No dynamic layout is admitted.
fn fixture_geometry_valid() -> bool {
    let owners_end = 16 + 256 * 32;
    let bitmap_end = owners_end + 512;
    let frame_end = bitmap_end + 1048576;
    let ingress_end = frame_end + 65536;
    let egress_end = ingress_end + 65536;
    let pool_start = ((egress_end + 4095) / 4096) * 4096;
    let pool_end = pool_start + 16777216;
    let pages = (pool_end + 65535) / 65536;
    return owners_end == 8208 && bitmap_end == 8720 && frame_end == 1057296 &&
        ingress_end == 1122832 && egress_end == 1188368 && pool_start == 1191936 &&
        pool_end == 17969152 && pages == 275 && pages * 65536 == 18022400 &&
        pages * 65536 <= 1073741824 && (16777216 / 4096 + 7) / 8 == 512;
}

// kind 1 returns the argument; kind 2 returns literal.  Invalid input yields
// an empty array; caller must perform K1 completion and validation first.
fn emit_scalar(name: u8[:], kind: i64, literal: u32) -> u8[] {
    if !fixture_geometry_valid() || !identifier(name) || (kind != 1 && kind != 2) { return []; }
    var body: u8[>..] = [];
    body.push(0); // no locals
    if kind == 1 {
        body.push(0x20); // local.get argument (environment is local 0)
        body.push(1);
    } else {
        body.push(0x41); // i32.const
        signed_i32_leb(body, literal);
    }
    body.push(0x0b); // end

    return emit_body(name, body);
}

// Shared module wrapper for both fixture encoders. The caller provides a
// complete validated instruction body including its local declaration/end.
fn emit_body(name: u8[:], body: u8[:]) -> u8[] {
    if !fixture_geometry_valid() || !identifier(name) { return []; }
    var code: u8[>..] = [];
    code.push(1); // one function body
    unsigned_leb(code, body.len);
    for byte in body { code.push(byte); }

    var exports: u8[>..] = [];
    exports.push(1); // one export
    unsigned_leb(exports, name.len);
    for byte in name { exports.push(byte); }
    exports.push(0); // function
    exports.push(0); // function index

    var output: u8[>..] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    // type: one function (i32, i32) -> i32
    for byte in [1, 7, 1, 0x60, 2, 0x7f, 0x7f, 1, 0x7f] { output.push(byte as u8); }
    // function: one declaration of type 0
    for byte in [3, 2, 1, 0] { output.push(byte as u8); }
    // Private layout experiment: one fixed-size memory, initial == maximum.
    // The geometry is checked by wasm_test.mjs; the accompanying metadata is
    // deliberately not the versioned K1 ABI manifest or certificate.
    var memory: u8[>..] = [1, 1]; // one memory; limits include maximum
    unsigned_leb(memory, 275);
    unsigned_leb(memory, 275);
    output.push(5);
    unsigned_leb(output, memory.len);
    for byte in memory { output.push(byte); }
    output.push(7); // export section
    unsigned_leb(output, exports.len);
    for byte in exports { output.push(byte); }
    output.push(10); // code section
    unsigned_leb(output, code.len);
    for byte in code { output.push(byte); }

    // A deterministic, fixture-only description of the complete address map.
    // Static data and dictionaries have zero bytes in this scalar experiment.
    let metadata_name = "blot.k1.fixture.memory";
    let metadata = "{\"version\":1,\"page_bytes\":65536,\"pages\":275,\"granule_bytes\":4096,\"static_bytes\":0,\"dictionary_bytes\":0,\"control\":[0,16],\"owners\":[16,8192],\"owner_slots\":256,\"owner_stride\":32,\"bitmap\":[8208,512],\"frame\":[8720,1048576],\"ingress\":[1057296,65536],\"egress\":[1122832,65536],\"alignment_padding\":[1188368,3568],\"pool\":[1191936,16777216],\"page_padding\":[17969152,53248],\"memory_bytes\":18022400}";
    var custom: u8[>..] = [];
    unsigned_leb(custom, metadata_name.len);
    for byte in metadata_name { custom.push(byte); }
    for byte in metadata { custom.push(byte); }
    output.push(0);
    unsigned_leb(output, custom.len);
    for byte in custom { output.push(byte); }
    return output;
}

// Defensive, source-independent structural check. The caller must also run
// independent source/Core validation; this routine cannot authenticate spans.
fn empty_value(v: scalar_core::ScalarValue) -> bool {
    return v.producer == 0 && v.type_id == 0 && v.op_id == 0 && v.literal == 0 &&
        v.left_id == 0 && v.right_id == 0;
}

fn valid_v2(c: scalar_core::ScalarCore) -> bool {
    if c.value_count < 1 || c.value_count > 4 || c.terminator != 1 ||
       c.result_id < 0 || c.result_id >= c.value_count { return false; }
    let parameter = c.values[0];
    if parameter.producer != 1 || parameter.type_id != 1 || parameter.op_id != 0 ||
       parameter.literal != 0 || parameter.left_id != 0 || parameter.right_id != 0 { return false; }
    for i in c.value_count..4 { if !empty_value(c.values[i]) { return false; } }
    let result = c.values[c.result_id];
    if result.producer == 1 || result.producer == 2 {
        if c.result_type != 1 || c.result_id != c.value_count - 1 || c.value_count > 2 ||
           c.operator_start != 0 || c.operator_end != 0 || c.right_start != 0 || c.right_end != 0 { return false; }
        if result.producer == 1 { return c.value_count == 1; }
        return result.type_id == 1 && result.op_id == 0 && result.left_id == 0 && result.right_id == 0;
    }
    if result.producer != 3 || c.result_id != c.value_count - 1 || result.literal != 0 ||
       (result.op_id != 1 && result.op_id != 2) ||
       (result.op_id == 1 && (result.type_id != 1 || c.result_type != 1)) ||
       (result.op_id == 2 && (result.type_id != 2 || c.result_type != 2)) ||
       result.left_id < 0 || result.right_id < 0 ||
       result.left_id >= c.result_id || result.right_id >= c.result_id { return false; }
    // Every constant occurrence has its own record, allocated left-to-right.
    var next: i64 = 1;
    for id in [result.left_id, result.right_id] {
        let value = c.values[id];
        if id == 0 { continue; }
        if id != next || value.producer != 2 || value.type_id != 1 || value.op_id != 0 ||
           value.left_id != 0 || value.right_id != 0 { return false; }
        next += 1;
    }
    return next == c.result_id;
}

fn emit_operand(out: u8[>..]&, value: scalar_core::ScalarValue) {
    if value.producer == 1 { out.push(0x20); out.push(1); }
    else { out.push(0x41); signed_i32_leb(out, value.literal); }
}

// The ABI is (env:i32, arg:i32)->i32; lt_u yields canonical Bool 0 or 1.
fn emit_scalar_v2(name: u8[:], plan: scalar_plan::ScalarLoweringPlan) -> u8[] {
    if !identifier(name) || !fixture_geometry_valid() || !scalar_plan::validate(plan) || !valid_v2(plan.core) { return []; }
    let c = plan.core;
    var body: u8[>..] = [0];
    let result = c.values[c.result_id];
    if result.producer == 3 {
        emit_operand(body, c.values[result.left_id]);
        emit_operand(body, c.values[result.right_id]);
        body.push(plan.opcode as u8);
    } else { emit_operand(body, result); }
    body.push(0x0b);
    return emit_body(name, body);
}
