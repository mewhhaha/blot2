// Integration law for the private scalar fixture. This test wires the opt-in
// measured components with one compiler-owned meter; it is not a public K1
// admission path or a complete K1-SEM-POLICY-1 work receipt.
import work;
import frontend;
import parser;
import scalar_core_metered;
import scalar_plan_metered;
import scalar_wasm_metered;
import wasm_scalar_validation_metered;
import validate;
import catalog;
import fixture_geometry;
import os;

struct Result { status: i64 = 0, bytes: u8[] = [] }
// status: 0 success, 1 invalid, 2 semantic limit, 3 Core limit, 4 internal.
fn run(source: u8[:], meter: work::Meter&) -> Result {
    let p = frontend::parse_scalar_with_work(source, meter);
    if p.status != 0 { return Result { status: if p.status == 12 { 2 } else if p.status == 13 { 4 } else { 1 } }; }
    var tree, parse_status = parser::parse_with_work(source, meter);
    if parse_status != 0 { return Result { status: if parse_status == 12 { 2 } else if parse_status == 13 { 4 } else { 1 } }; }
    let syntax_status = parser::verify_with_work(tree, meter);
    if syntax_status != 0 { return Result { status: if syntax_status == 3 { 2 } else if syntax_status == 4 { 4 } else { 1 } }; }
    let made = scalar_core_metered::make(p.result_type, p.binary_op, p.kind, p.literal,
        p.right_kind, p.right_literal, meter);
    if made.status != 0 { return Result { status: made.status }; }
    var core = made.core;
    core.name_start = p.name_start; core.name_end = p.name_end;
    core.parameter_start = p.parameter_start; core.parameter_end = p.parameter_end;
    core.left_start = p.start; core.left_end = p.end;
    core.operator_start = p.operator_start; core.operator_end = p.operator_end;
    core.right_start = p.right_start; core.right_end = p.right_end;
    let source_status = validate::scalar_v2_with_work_at_phase(source, core, catalog::edition(),
        catalog::semantic_policy(), catalog::optimization_policy(), catalog::wasm_abi(), meter, 5);
    if source_status != 0 { return Result { status: if source_status == 3 { 2 } else if source_status == 4 { 4 } else { 1 } }; }
    let planned = scalar_plan_metered::make(core, meter);
    if planned.status != 0 { return Result { status: planned.status }; }
    let checked = scalar_plan_metered::validate(planned.plan, meter, 6);
    if checked.status != 0 { return Result { status: checked.status }; }
    let emitted = scalar_wasm_metered::emit(source[core.name_start..core.name_end], planned.plan, meter);
    if emitted.status != 0 { return Result { status: emitted.status }; }
    var geometry, geometry_status = fixture_geometry::build_with_work(meter, 7);
    if geometry_status != 0 { return Result { status: if geometry_status == 3 { 2 } else if geometry_status == 4 { 4 } else { 1 } }; }
    let verify_status = wasm_scalar_validation_metered::verify(source, planned.plan, geometry, emitted.bytes, meter);
    if verify_status != 0 { return Result { status: if verify_status == 3 { 2 } else if verify_status == 4 { 4 } else { 1 } }; }
    return Result { bytes: copy(emitted.bytes) };
}
fn main() {
    let source = "let less: U32 -> Bool = fn x => return do:\n  break x < 7\n";
    var first = work::Meter {};
    let result = run(source, first);
    assert(result.status == 0 && result.bytes.len > 0 && first.target_visits > 0);
    assert(first.phase_semantic[0] > 0 && first.phase_semantic[1] > 0 && first.phase_semantic[2] > 0 &&
           first.phase_semantic[4] > 0 && first.phase_semantic[5] > 0 && first.phase_semantic[6] > 0);
    assert(first.phase_semantic[3] == 0);
    let visits = first.semantic;
    var second = work::Meter {};
    let again = run(source, second);
    assert(again.status == 0 && again.bytes[..] == result.bytes[..] && second.semantic == visits);
    assert(second.phase_semantic == first.phase_semantic && second.target_visits == first.target_visits);
    var exact = work::Meter { semantic: 1048576 - visits };
    assert(run(source, exact).status == 0 && exact.semantic == 1048576);
    for available in visits {
        var limited = work::Meter { semantic: 1048576 - available };
        let blocked = run(source, limited);
        assert(blocked.status == 2 && blocked.bytes.len == 0 && limited.semantic == 1048576);
    }
    var bad_source = work::Meter {};
    assert(run("let f: U32 -> U32 = fn x => return x + 1", bad_source).status == 1);
    assert(write_file("scalar_pipeline_work.wasm", result.bytes));
    print("private shared scalar pipeline work laws passed");
}
