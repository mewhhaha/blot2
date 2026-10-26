import work;
import frontend;
import scalar_core;
import scalar_plan;
import scalar_wasm_metered;
import fixture_geometry;
import wasm_scalar_validation;
import wasm_scalar_validation_metered;

fn plan_for(source: u8[:]) -> scalar_plan::ScalarLoweringPlan {
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
fn exercise(source: u8[:]) {
    let plan = plan_for(source);
    var geometry, ok = fixture_geometry::build();
    assert(ok);
    var emission = work::Meter {};
    let emitted = scalar_wasm_metered::emit(source[plan.core.name_start..plan.core.name_end], plan, emission);
    assert(emitted.status == 0 && emitted.bytes.len > 0);
    var baseline = work::Meter {};
    assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, baseline) == 0);
    assert(baseline.semantic > 0 && baseline.phase_semantic[6] == baseline.semantic && baseline.target_visits > 0);
    let visits = baseline.semantic;
    var exact = work::Meter { semantic: 1048576 - visits };
    assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, exact) == 0 && exact.semantic == 1048576);
    for available in visits {
        var limited = work::Meter { semantic: 1048576 - available };
        assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, limited) == 3);
        assert(limited.semantic == 1048576);
    }
    var repeated = work::Meter {};
    assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, repeated) == 0);
    assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, repeated) == 0);
    assert(repeated.semantic == visits * 2 && repeated.target_visits == baseline.target_visits * 2);
    let maximum: u64 = ~(0 as u64);
    var telemetry = work::Meter { target_visits: maximum };
    assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes, telemetry) == 4);
    assert(telemetry.target_visits == maximum);

    // Compare the metered validator's acceptance to the independent unmetered
    // validator on every truncated prefix and every single-byte corruption.
    for n in emitted.bytes.len {
        var m = work::Meter {};
        assert(wasm_scalar_validation_metered::verify(source, plan, geometry, emitted.bytes[..n], m) != 0);
    }
    for i in emitted.bytes.len {
        var mutation: u8[>..] = []; mutation.append(emitted.bytes); mutation[i] ^= 0xff;
        let expected = wasm_scalar_validation::verify(source, plan, geometry, mutation);
        var m = work::Meter {};
        let actual = wasm_scalar_validation_metered::verify(source, plan, geometry, mutation, m);
        assert(actual == expected);
    }
    var bad_plan = plan; bad_plan.helper_count = 1;
    var invalid = work::Meter {};
    assert(wasm_scalar_validation_metered::verify(source, bad_plan, geometry, emitted.bytes, invalid) == 1);
    var bad_geometry = geometry; bad_geometry.maximum_pages += 1;
    var geometry_work = work::Meter {};
    assert(wasm_scalar_validation_metered::verify(source, plan, bad_geometry, emitted.bytes, geometry_work) == 1);
}
fn main() {
    exercise("let id: U32 -> U32 = fn x => return x\n");
    exercise("let max: U32 -> U32 = fn x => return 4294967295\n");
    exercise("let bits: U32 -> U32 = fn x => return x & 255\n");
    exercise("let less: U32 -> Bool = fn x => return x < 128\n");
    // The source ceiling is not a Wasm ceiling: a long legal export name
    // plus module framing exceeds 16 MiB without inventing a smaller input
    // limit. Raw byte scans remain bounded but are not semantic-node visits.
    let prefix = "let ";
    let suffix = ": U32 -> U32 = fn x => return x\n";
    var largest: u8[>..] = []; largest.append(prefix);
    for i in 16777216 - prefix.len - suffix.len { largest.push('n'); }
    largest.append(suffix);
    let large_plan = plan_for(largest);
    var large_geometry, ok = fixture_geometry::build();
    assert(ok);
    var emission = work::Meter {};
    let large_bytes = scalar_wasm_metered::emit(largest[large_plan.core.name_start..large_plan.core.name_end], large_plan, emission);
    assert(large_bytes.status == 0 && large_bytes.bytes.len > 16777216);
    var verification = work::Meter {};
    assert(wasm_scalar_validation_metered::verify(largest, large_plan, large_geometry, large_bytes.bytes, verification) == 0);
    assert(verification.semantic < 1048576);
    print("metered scalar Wasm validation laws passed");
}
