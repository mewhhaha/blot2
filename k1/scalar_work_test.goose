import work;
import frontend;
import scalar_core;
import validate;
import catalog;

fn core_from(p: frontend::ParseResult) -> scalar_core::ScalarCore {
    var c = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal,
                               p.right_kind, p.right_literal);
    c.name_start = p.name_start; c.name_end = p.name_end;
    c.parameter_start = p.parameter_start; c.parameter_end = p.parameter_end;
    c.left_start = p.start; c.left_end = p.end;
    c.operator_start = p.operator_start; c.operator_end = p.operator_end;
    c.right_start = p.right_start; c.right_end = p.right_end;
    return c;
}
fn check(source: u8[:], core: scalar_core::ScalarCore, m: work::Meter&) -> i64 {
    return validate::scalar_v2_with_work(source, core, catalog::edition(), catalog::semantic_policy(),
                                        catalog::optimization_policy(), catalog::wasm_abi(), m);
}
fn main() {
    let source = "let f: U32 -> Bool = fn x => return x < 4294967295\n";
    var initial = work::Meter {};
    let p = frontend::parse_scalar_with_work(source, initial);
    assert(p.status == 0);
    let parsed_visits = initial.semantic;
    let core = core_from(p);
    assert(check(source, core, initial) == 0);
    let validation_visits = initial.semantic - parsed_visits;
    assert(validation_visits > 0 && initial.phase_semantic[1] > 0 && initial.phase_semantic[4] > 0);
    let completed = initial.semantic;
    assert(check(source, core, initial) == 0);
    assert(initial.semantic == completed + validation_visits);

    // A single declaration budget includes both independent passes.
    var exact = work::Meter { semantic: 1048576 - completed };
    let q = frontend::parse_scalar_with_work(source, exact);
    assert(q.status == 0 && check(source, core_from(q), exact) == 0);
    assert(exact.semantic == 1048576);
    var short = work::Meter { semantic: 1048577 - completed };
    let s = frontend::parse_scalar_with_work(source, short);
    assert(s.status == 0 && check(source, core_from(s), short) == 3);
    assert(short.semantic == 1048576);

    // A mismatched artifact is rejected before any source/Core traversal.
    var incompatible = work::Meter {};
    assert(validate::scalar_v2_with_work(source, core, "legacy", catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi(), incompatible) == 2);
    assert(incompatible.semantic == 0);
    var emission = work::Meter {};
    assert(validate::scalar_v2_with_work_at_phase(source, core, catalog::edition(), catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi(), emission, 7) == 0);
    assert(emission.phase_semantic[6] == emission.semantic && emission.phase_semantic[1] == 0 && emission.phase_semantic[4] == 0);
    var bad_phase = work::Meter {};
    assert(validate::scalar_v2_with_work_at_phase(source, core, catalog::edition(), catalog::semantic_policy(),
        catalog::optimization_policy(), catalog::wasm_abi(), bad_phase, 1) == 4 && bad_phase.semantic == 0);
    var forged = core;
    forged.values[2].op_id = 1;
    var bad = work::Meter {};
    assert(check(source, forged, bad) == 1 && bad.semantic > 0);
    // A forged return edge is inspected only after its own visit charge. If
    // that last charge is unavailable, report the limit rather than the
    // malformed edge; with work available it is rejected as invalid.
    var bad_return = core; bad_return.result_id = 99;
    var bad_return_work = work::Meter {};
    assert(check(source, bad_return, bad_return_work) == 1 && bad_return_work.semantic > 0);
    var stopped = work::Meter { semantic: 1048577 - bad_return_work.semantic };
    assert(check(source, bad_return, stopped) == 3 && stopped.semantic == 1048576);
    var corrupt = work::Meter {};
    corrupt.phase_semantic[4] = 1;
    assert(check(source, core, corrupt) == 4 && corrupt.semantic == 0);
    print("shared frontend and validator work laws passed");
}
