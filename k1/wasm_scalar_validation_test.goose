import std;
import frontend;
import scalar_core;
import scalar_plan;
import fixture_geometry;
import wasm;
import wasm_scalar_validation;

fn plan_for(source: const u8[:]) -> scalar_plan::ScalarLoweringPlan {
    let p = frontend::parse_scalar(source);
    assert(p.status == 0);
    var c = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal, p.right_kind, p.right_literal);
    c.name_start = p.name_start; c.name_end = p.name_end;
    c.parameter_start = p.parameter_start; c.parameter_end = p.parameter_end;
    c.left_start = p.start; c.left_end = p.end;
    c.operator_start = p.operator_start; c.operator_end = p.operator_end;
    c.right_start = p.right_start; c.right_end = p.right_end;
    return scalar_plan::make(c);
}
fn exercise(source: const u8[:]) {
    let plan = plan_for(source);
    var geometry, ok = fixture_geometry::build();
    assert(ok && scalar_plan::validate(plan));
    let name = source[plan.core.name_start..plan.core.name_end];
    let bytes = wasm::emit_scalar_v2(name, plan);
    assert(bytes.len > 0);
    assert(wasm_scalar_validation::verify(source, plan, geometry, bytes) == 0);
    // Every truncated prefix must fail, before any unchecked section access.
    for n in bytes.len {
        assert(wasm_scalar_validation::verify(source, plan, geometry, bytes[..n]) != 0);
    }
    // Decode section boundaries in the test rather than relying on an offset
    // in a particular export-name encoding.
    var r = wasm_scalar_validation::Reader { at: 8, end: bytes.len };
    let ty = wasm_scalar_validation::section(bytes, r, 1);
    let funcs = wasm_scalar_validation::section(bytes, r, 3);
    let mem = wasm_scalar_validation::section(bytes, r, 5);
    let exports = wasm_scalar_validation::section(bytes, r, 7);
    var code = wasm_scalar_validation::section(bytes, r, 10);
    assert(ty.ok && funcs.ok && mem.ok && exports.ok && code.ok);
    assert(wasm_scalar_validation::u32_leb(bytes, code) == 1);
    let body_size = wasm_scalar_validation::u32_leb(bytes, code);
    assert(body_size > 2);
    let instruction = code.at + 1; // skip local-group count
    var changed: u8[>..] = [];
    changed.append(bytes); changed[instruction] = 0x10; // helper call
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[instruction] = 0x40; // memory.grow
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[instruction] = bytes[instruction];
    // Substituting the environment for the parameter, or altering a literal,
    // remains well-formed Wasm but must not match the checked source Core.
    if changed[instruction] == 0x20 {
        changed[instruction + 1] = 0;
    } else {
        changed[instruction + 1] ^= 1;
    }
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[instruction + 1] = bytes[instruction + 1];
    changed[mem.at + 1] = 0; // no declared memory maximum
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[mem.at + 1] = bytes[mem.at + 1];
    changed[8] = 2; // import section instead of type
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[8] = bytes[8];
    changed[9] = 255; // invalid/overlong section length
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    changed[9] = bytes[9];
    changed.push(8); changed.push(1); changed.push(0); // appended start section
    assert(wasm_scalar_validation::verify(source, plan, geometry, changed) != 0);
    var bad_plan = plan; bad_plan.helper_count = 1;
    assert(wasm_scalar_validation::verify(source, bad_plan, geometry, bytes) != 0);
    var bad_geometry = geometry; bad_geometry.maximum_pages += 1;
    assert(wasm_scalar_validation::verify(source, plan, bad_geometry, bytes) != 0);
    // A distinct otherwise-valid layout with equal page counts is not the
    // selected fixture geometry, even if scalar instructions access no memory.
    var swapped = geometry;
    let ingress = swapped.regions[6].start;
    swapped.regions[6].start = swapped.regions[7].start;
    swapped.regions[7].start = ingress;
    assert(wasm_scalar_validation::verify(source, plan, swapped, bytes) != 0);
    var other: u8[>..] = []; other.append(source);
    other[plan.core.name_start] = if other[plan.core.name_start] == 'z' { 'y' } else { 'z' };
    assert(wasm_scalar_validation::verify(other, plan, geometry, bytes) != 0);
    // Exercise every byte position with deterministic corruption. Some custom
    // metadata mutations are allowed because metadata grants no authority;
    // every call must nevertheless remain bounded and safe on malformed bytes.
    for i in bytes.len {
        var mutation: u8[>..] = [];
        mutation.append(bytes);
        mutation[i] ^= 0xff;
        let result = wasm_scalar_validation::verify(source, plan, geometry, mutation);
        assert(result == 0 || result == 1);
    }
}
fn main() {
    exercise("let id: U32 -> U32 = fn x => return x\n");
    exercise("let z: U32 -> U32 = fn x => return 0\n");
    exercise("let n: U32 -> U32 = fn x => return 63\n");
    exercise("let n: U32 -> U32 = fn x => return 64\n");
    exercise("let n: U32 -> U32 = fn x => return 2147483647\n");
    exercise("let n: U32 -> U32 = fn x => return 2147483648\n");
    exercise("let n: U32 -> U32 = fn x => return 4294967295\n");
    exercise("let n: U32 -> U32 = fn x => return x & 4294967295\n");
    exercise("let less: U32 -> Bool = fn x => return x < 128\n");
    // Signed and unsigned LEB decoders must reject noncanonical or unsafe data.
    let long_zero: u8[2] = [128, 0];
    var a = wasm_scalar_validation::Reader { end: 2 };
    assert(wasm_scalar_validation::u32_leb(long_zero, a) < 0 && !a.ok);
    var b = wasm_scalar_validation::Reader { end: 2 };
    assert(wasm_scalar_validation::i32_leb_bits(long_zero, b) < 0 && !b.ok);
    let overflow: u8[5] = [255, 255, 255, 255, 127];
    var c = wasm_scalar_validation::Reader { end: 5 };
    assert(wasm_scalar_validation::u32_leb(overflow, c) < 0 && !c.ok);
    let truncated: u8[1] = [128];
    var d = wasm_scalar_validation::Reader { end: 1 };
    assert(wasm_scalar_validation::i32_leb_bits(truncated, d) < 0 && !d.ok);
    // The source limit is not a Wasm-output limit: an identifier taking
    // nearly the whole source can make export bytes exceed 16 MiB because
    // the module has section headers and fixture metadata of its own.
    let prefix = "let ";
    let suffix = ": U32 -> U32 = fn x => return x\n";
    var largest: u8[>..] = [];
    largest.append(prefix);
    for i in 16777216 - prefix.len - suffix.len { largest.push('n'); }
    largest.append(suffix);
    assert(largest.len == 16777216);
    let large_plan = plan_for(largest);
    var large_geometry, large_ok = fixture_geometry::build();
    assert(large_ok);
    let large_bytes = wasm::emit_scalar_v2(largest[large_plan.core.name_start..large_plan.core.name_end], large_plan);
    assert(large_bytes.len > 16777216);
    assert(wasm_scalar_validation::verify(largest, large_plan, large_geometry, large_bytes) == 0);
    print("private scalar Wasm structural validation passed");
}
