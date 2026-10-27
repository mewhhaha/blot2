// Private scheduled scalar fixture. The returned bytes remain candidate data
// until all required checks and phase transitions succeed. This is not public
// K1 admission or complete work-policy accounting.
namespace scalar_scheduled;
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

// Internal cache/receipt compatibility revision for this partial scalar
// traversal only; this is not a new normative K1 semantic policy.
fn private_visit_schedule() -> u32 { return 2; }

// 0 success, 1 invalid input/representation, 2 semantic limit,
// 3 Core limit, 4 internal accounting/phase failure.
struct Result {
    status: i64 = 0, bytes: u8[] = [],
    source_status: i64 = 0, source_start: i64 = 0, source_end: i64 = 0
}
fn stop(job: work::ScheduledWork&, status: i64) -> Result {
    job.failed = true;
    job.meter.gate = 9;
    return Result { status: status };
}
fn run(source: u8[:], job: work::ScheduledWork&) -> Result {
    if !work::schedule_begin(job, 1) { return stop(job, 4); }
    let p = frontend::parse_scalar_with_work(source, job.meter);
    if p.status != 0 {
        var failure = stop(job, if p.status == 12 { 2 } else if p.status == 13 { 4 } else { 1 });
        failure.source_status = p.status; failure.source_start = p.start; failure.source_end = p.end;
        return failure;
    }
    var tree, parse_status = parser::parse_candidate_with_work(source, job.meter);
    if parse_status != 0 { return stop(job, if parse_status == 12 { 2 } else { 4 }); }
    if tree.source[..] != source { return stop(job, 4); }
    if !work::schedule_end(job, 1) || !work::schedule_begin(job, 2) { return stop(job, 4); }
    // The compatibility parser performs the first of these checks inside
    // parse_with_work; the driver performs the second. Preserve both visits.
    for check in 2 {
        let syntax_status = parser::verify_with_work(tree, job.meter);
        if syntax_status != 0 { return stop(job, if syntax_status == 3 { 2 } else { 4 }); }
    }
    if !work::schedule_end(job, 2) || !work::schedule_begin(job, 3) { return stop(job, 4); }
    let made = scalar_core_metered::make(p.result_type, p.binary_op, p.kind, p.literal,
        p.right_kind, p.right_literal, job.meter);
    if made.status != 0 { return stop(job, made.status); }
    var core = made.core;
    core.name_start = p.name_start; core.name_end = p.name_end;
    core.parameter_start = p.parameter_start; core.parameter_end = p.parameter_end;
    core.left_start = p.start; core.left_end = p.end;
    core.operator_start = p.operator_start; core.operator_end = p.operator_end;
    core.right_start = p.right_start; core.right_end = p.right_end;
    if !work::schedule_end(job, 3) || !work::schedule_skip_proof(job) || !work::schedule_begin(job, 5) { return stop(job, 4); }
    let source_status = validate::scalar_v2_with_work_at_phase(source, core, catalog::edition(),
        catalog::semantic_policy(), catalog::optimization_policy(), catalog::wasm_abi(), job.meter, 5);
    if source_status != 0 { return stop(job, if source_status == 3 { 2 } else if source_status == 4 { 4 } else { 1 }); }
    if !work::schedule_end(job, 5) || !work::schedule_begin(job, 6) { return stop(job, 4); }
    let planned = scalar_plan_metered::make(core, job.meter);
    if planned.status != 0 { return stop(job, planned.status); }
    let checked = scalar_plan_metered::validate(planned.plan, job.meter, 6);
    if checked.status != 0 { return stop(job, checked.status); }
    if !work::schedule_end(job, 6) || !work::schedule_begin(job, 7) { return stop(job, 4); }
    let emitted = scalar_wasm_metered::emit(source[core.name_start..core.name_end], planned.plan, job.meter);
    if emitted.status != 0 { return stop(job, emitted.status); }
    var geometry, geometry_status = fixture_geometry::build_with_work(job.meter, 7);
    if geometry_status != 0 { return stop(job, if geometry_status == 3 { 2 } else if geometry_status == 4 { 4 } else { 1 }); }
    let verify_status = wasm_scalar_validation_metered::verify(source, planned.plan, geometry, emitted.bytes, job.meter);
    if verify_status != 0 { return stop(job, if verify_status == 3 { 2 } else if verify_status == 4 { 4 } else { 1 }); }
    if !work::schedule_end(job, 7) || !work::schedule_complete(job) { return stop(job, 4); }
    return Result { bytes: copy(emitted.bytes) };
}
