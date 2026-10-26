// Metered independent validation for the private scalar Wasm fixture.
// This is not the full K1 M13 certificate, ABI hash, or host bridge.
// Raw Wasm byte scans are input-bounded; byte-read telemetry remains pending.
namespace wasm_scalar_validation_metered;
import wasm_scalar_validation;
import fixture_geometry;
import manifest;
import scalar_plan;
import scalar_plan_metered;
import validate;
import catalog;
import work;

// status: 0 valid, 1 invalid, 3 semantic limit, 4 internal accounting.
fn selected_geometry(g: manifest::Geometry&, meter: work::Meter&) -> i64 {
    let validated = manifest::validate_with_work(g, meter, 7);
    if validated != 0 { return validated; }
    var expected, status = fixture_geometry::build_with_work(meter, 7);
    if status != 0 { return status; }
    let header = work::charge(meter, 7, 10);
    if header.status != 0 { return if header.status == 1 { 3 } else { 4 }; }
    let expected_header = work::charge(meter, 7, 10);
    if expected_header.status != 0 { return if expected_header.status == 1 { 3 } else { 4 }; }
    if g.page_bytes != expected.page_bytes || g.initial_pages != expected.initial_pages ||
       g.maximum_pages != expected.maximum_pages || g.owner_slots != expected.owner_slots ||
       g.owner_entry_bytes != expected.owner_entry_bytes || g.granule_bytes != expected.granule_bytes ||
       g.root_capsule_bytes != expected.root_capsule_bytes || g.padding_count != expected.padding_count { return 1; }
    for i in 9 {
        let actual_visit = work::charge(meter, 7, 10);
        if actual_visit.status != 0 { return if actual_visit.status == 1 { 3 } else { 4 }; }
        let actual = g.regions[i];
        let expected_visit = work::charge(meter, 7, 10);
        if expected_visit.status != 0 { return if expected_visit.status == 1 { 3 } else { 4 }; }
        let reference = expected.regions[i];
        if actual.tag != reference.tag || actual.start != reference.start || actual.length != reference.length { return 1; }
    }
    for i in 10 {
        let actual_visit = work::charge(meter, 7, 10);
        if actual_visit.status != 0 { return if actual_visit.status == 1 { 3 } else { 4 }; }
        let actual = g.padding[i];
        let expected_visit = work::charge(meter, 7, 10);
        if expected_visit.status != 0 { return if expected_visit.status == 1 { 3 } else { 4 }; }
        let reference = expected.padding[i];
        if actual.tag != reference.tag || actual.start != reference.start || actual.length != reference.length { return 1; }
    }
    return 0;
}
fn target(meter: work::Meter&) -> bool { return work::target_visit(meter).status == 0; }

// The emitter's target is regenerated from the validated source-bound plan;
// this verifier consumes the actual bytes and does not trust metadata/hash.
fn verify(source: u8[:], plan: scalar_plan::ScalarLoweringPlan,
          geometry: manifest::Geometry&, bytes: u8[:], meter: work::Meter&) -> i64 {
    if source.len > 16777216 || bytes.len > source.len + 4096 { return 1; }
    let checked = scalar_plan_metered::validate(plan, meter, 7);
    if checked.status != 0 { return if checked.status == 2 { 3 } else if checked.status == 4 { 4 } else { 1 }; }
    let geometry_status = selected_geometry(geometry, meter);
    if geometry_status != 0 { return geometry_status; }
    let geometry_header = work::charge(meter, 7, 10);
    if geometry_header.status != 0 { return if geometry_header.status == 1 { 3 } else { 4 }; }
    let plan_header = work::charge(meter, 7, 12);
    if plan_header.status != 0 { return if plan_header.status == 1 { 3 } else { 4 }; }
    let initial_pages = geometry.initial_pages;
    let maximum_pages = geometry.maximum_pages;
    let opcode = plan.opcode;
    if initial_pages != plan.memory_initial_pages || maximum_pages != plan.memory_maximum_pages { return 1; }
    let plan_edge = work::charge(meter, 7, 13);
    if plan_edge.status != 0 { return if plan_edge.status == 1 { 3 } else { 4 }; }
    let core = plan.core;
    let association = validate::scalar_v2_with_work_at_phase(source, core, catalog::edition(), catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi(), meter, 7);
    if association != 0 { return if association == 3 { 3 } else if association == 4 { 4 } else { 1 }; }
    if !target(meter) { return 4; }
    let magic: u8[8] = [0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
    if bytes.len < 8 || bytes[..8] != magic[..] { return 1; }
    var root = wasm_scalar_validation::Reader { at: 8, end: bytes.len };
    if !target(meter) { return 4; }
    let ty = wasm_scalar_validation::section(bytes, root, 1);
    if !wasm_scalar_validation::equal_payload(bytes, ty, [1, 0x60, 2, 0x7f, 0x7f, 1, 0x7f]) { return 1; }
    if !target(meter) { return 4; }
    let functions = wasm_scalar_validation::section(bytes, root, 3);
    if !wasm_scalar_validation::equal_payload(bytes, functions, [1, 0]) { return 1; }
    if !target(meter) { return 4; }
    var memory = wasm_scalar_validation::section(bytes, root, 5);
    if wasm_scalar_validation::byte(bytes, memory) != 1 || wasm_scalar_validation::byte(bytes, memory) != 1 ||
       wasm_scalar_validation::u32_leb(bytes, memory) != initial_pages ||
       wasm_scalar_validation::u32_leb(bytes, memory) != maximum_pages || !wasm_scalar_validation::done(memory) { return 1; }
    if !target(meter) { return 4; }
    var exports = wasm_scalar_validation::section(bytes, root, 7);
    if wasm_scalar_validation::u32_leb(bytes, exports) != 1 { return 1; }
    let name_size = wasm_scalar_validation::u32_leb(bytes, exports);
    if name_size < 0 || name_size > exports.end - exports.at { return 1; }
    let name_start = exports.at;
    exports.at += name_size;
    let name_core = work::charge(meter, 7, 4);
    if name_core.status != 0 { return if name_core.status == 1 { 3 } else { 4 }; }
    let source_name_start = core.name_start;
    let source_name_end = core.name_end;
    if bytes[name_start..exports.at] != source[source_name_start..source_name_end] ||
       wasm_scalar_validation::byte(bytes, exports) != 0 || wasm_scalar_validation::u32_leb(bytes, exports) != 0 ||
       !wasm_scalar_validation::done(exports) { return 1; }
    if !target(meter) { return 4; }
    var code = wasm_scalar_validation::section(bytes, root, 10);
    if wasm_scalar_validation::u32_leb(bytes, code) != 1 { return 1; }
    let body_size = wasm_scalar_validation::u32_leb(bytes, code);
    if body_size < 0 || body_size > code.end - code.at { return 1; }
    var body = wasm_scalar_validation::Reader { at: code.at, end: code.at + body_size };
    code.at += body_size;
    if wasm_scalar_validation::byte(bytes, body) != 0 { return 1; }
    let result_edge = work::charge(meter, 7, 5);
    if result_edge.status != 0 { return if result_edge.status == 1 { 3 } else { 4 }; }
    let result_visit = work::charge(meter, 7, 4);
    if result_visit.status != 0 { return if result_visit.status == 1 { 3 } else { 4 }; }
    let result = core.values[core.result_id];
    if result.producer == 3 {
        let left_edge = work::charge(meter, 7, 5);
        if left_edge.status != 0 { return if left_edge.status == 1 { 3 } else { 4 }; }
        let left_visit = work::charge(meter, 7, 4);
        if left_visit.status != 0 { return if left_visit.status == 1 { 3 } else { 4 }; }
        if !target(meter) { return 4; }
        if !wasm_scalar_validation::operand(bytes, body, core.values[result.left_id]) { return 1; }
        let right_edge = work::charge(meter, 7, 5);
        if right_edge.status != 0 { return if right_edge.status == 1 { 3 } else { 4 }; }
        let right_visit = work::charge(meter, 7, 4);
        if right_visit.status != 0 { return if right_visit.status == 1 { 3 } else { 4 }; }
        if !target(meter) { return 4; }
        if !wasm_scalar_validation::operand(bytes, body, core.values[result.right_id]) { return 1; }
        if !target(meter) { return 4; }
        if wasm_scalar_validation::byte(bytes, body) != opcode { return 1; }
    } else {
        let operand_visit = work::charge(meter, 7, 4);
        if operand_visit.status != 0 { return if operand_visit.status == 1 { 3 } else { 4 }; }
        if !target(meter) { return 4; }
        if !wasm_scalar_validation::operand(bytes, body, result) { return 1; }
    }
    if !target(meter) { return 4; }
    if wasm_scalar_validation::byte(bytes, body) != 0x0b || !wasm_scalar_validation::done(body) ||
       !wasm_scalar_validation::done(code) { return 1; }
    if !target(meter) { return 4; }
    var custom = wasm_scalar_validation::section(bytes, root, 0);
    let length = wasm_scalar_validation::u32_leb(bytes, custom);
    if length < 0 || length > custom.end - custom.at ||
       bytes[custom.at..custom.at + length] != "blot.k1.fixture.memory" { return 1; }
    custom.at = custom.end;
    if !wasm_scalar_validation::done(custom) || !wasm_scalar_validation::done(root) { return 1; }
    return 0;
}
