// Private checked-add pipeline with one compiler-owned proof inventory/meter.
// The candidate and handles are trusted compiler scratch, not a portable proof
// receipt. A caller must validate source/Core before using it, keep the scope
// alive for each evidence consumer, and release it after the last consumer.
// This is only AddFits(x, 0); parser construction, full C09 event schedules,
// general term interning, artifact admission and allocation failure are absent.
namespace add_scoped;
import add_core;
import add_frontend;
import wasm;
import add_proof;
import add_proof_metered;
import add_source_metered;
import scalar_core;
import proof_scopes;
import work;

struct Job {
    attempted: bool = false,
    active: bool = false,
    scope: proof_scopes::Handle = proof_scopes::Handle {},
    first: proof_scopes::Handle = proof_scopes::Handle {},
    second: proof_scopes::Handle = proof_scopes::Handle {},
    conclusion: proof_scopes::Handle = proof_scopes::Handle {},
    graph: proof_scopes::Job = proof_scopes::Job {}
}
struct Candidate {
    status: u32 = 0,
    receipt: work::Receipt = work::Receipt {},
    checked: add_core::AddCoreV4 = add_core::AddCoreV4 {},
    scope: proof_scopes::Handle = proof_scopes::Handle {},
    first: proof_scopes::Handle = proof_scopes::Handle {},
    second: proof_scopes::Handle = proof_scopes::Handle {},
    conclusion: proof_scopes::Handle = proof_scopes::Handle {}
}
struct Check { status: u32 = 0, receipt: work::Receipt = work::Receipt {} }
fn poison(job: Job&, status: u32, receipt: work::Receipt) -> Candidate {
    job.graph.failed = true;
    return Candidate { status: status, receipt: receipt };
}
fn proof_failure(job: Job&, result: proof_scopes::Result) -> Candidate {
    if result.status == 2 { return poison(job, add_proof_metered::category(result.receipt), result.receipt); }
    return poison(job, 4, result.receipt);
}
fn shape(core: scalar_core::ScalarCore, meter: work::Meter&, phase: u32) -> Check {
    var r = work::charge(meter, phase, 4);
    if r.status != 0 { return Check { status: if r.status == 1 { 3 } else { 4 }, receipt: r }; }
    if core.result_type != 1 || core.value_count != 3 || core.terminator != 1 || core.result_id != 2 { return Check { status: 1 }; }
    for i in 4 {
        r = work::charge(meter, phase, 4);
        if r.status != 0 { return Check { status: if r.status == 1 { 3 } else { 4 }, receipt: r }; }
        let expected = if i == 0 { scalar_core::ScalarValue { producer: 1, type_id: 1 } }
            else if i == 1 { scalar_core::ScalarValue { producer: 2, type_id: 1 } }
            else if i == 2 { scalar_core::ScalarValue { producer: 3, type_id: 1, op_id: 3, left_id: 0, right_id: 1 } }
            else { scalar_core::ScalarValue {} };
        if !add_core::same(core.values[i], expected) { return Check { status: 1 }; }
    }
    return Check {};
}
// Core is an untrusted producer candidate here. Full independent source/Core
// validation happens before its consumer may use the proof. One attempt per
// job avoids pretending this fixture implements general distinct-term interning.
fn build(core: scalar_core::ScalarCore, job: Job&) -> Candidate {
    if job.graph.failed || job.attempted { return poison(job, 4, work::Receipt {}); }
    job.attempted = true;
    let subject = add_core::subject();
    var r = work::charge(job.graph.meter, 4, 20);
    if r.status != 0 { return poison(job, add_proof_metered::category(r), r); }
    let valid_core = shape(core, job.graph.meter, 4);
    if valid_core.status != 0 { return poison(job, valid_core.status, valid_core.receipt); }
    if !add_proof::valid_subject(subject) { return poison(job, 1, work::Receipt {}); }
    var p = add_proof::Proof { schema: 1, semantic_policy: 1, subject: subject };
    r = work::charge(job.graph.meter, 4, 21);
    if r.status != 0 { return poison(job, add_proof_metered::category(r), r); }
    p.terms[0] = add_proof::Term { kind: 1, owner: subject.owner, scope: subject.scope,
        value: subject.parameter, version: subject.parameter_version };
    r = work::charge(job.graph.meter, 4, 21);
    if r.status != 0 { return poison(job, add_proof_metered::category(r), r); }
    p.terms[1] = add_proof::Term { kind: 2, owner: subject.owner, scope: subject.scope,
        value: subject.zero, version: subject.zero_version, literal: 0 };
    r = work::charge(job.graph.meter, 4, 21);
    if r.status != 0 { return poison(job, add_proof_metered::category(r), r); }
    p.terms[2] = add_proof::Term { kind: 3, owner: subject.owner, scope: subject.scope, literal: 4294967295 };
    r = work::charge(job.graph.meter, 4, 21);
    if r.status != 0 { return poison(job, add_proof_metered::category(r), r); }
    p.terms[3] = add_proof::Term { kind: 4, owner: subject.owner, scope: subject.scope, base: 2 };
    let none = proof_scopes::Handle {};
    let scope = proof_scopes::open(job.graph, none);
    if scope.status != 0 { return proof_failure(job, scope); }
    let first = proof_scopes::add(job.graph, scope.handle, none, none);
    if first.status != 0 { return proof_failure(job, first); }
    p.nodes[0] = add_proof::Node { rule: 1, owner: subject.owner, scope: subject.scope, left: 1, right: 3 };
    let second = proof_scopes::add(job.graph, scope.handle, none, none);
    if second.status != 0 { return proof_failure(job, second); }
    p.nodes[1] = add_proof::Node { rule: 2, owner: subject.owner, scope: subject.scope, left: 4, right: 3 };
    let conclusion = proof_scopes::add(job.graph, scope.handle, first.handle, second.handle);
    if conclusion.status != 0 { return proof_failure(job, conclusion); }
    p.nodes[2] = add_proof::Node { rule: 3, owner: subject.owner, scope: subject.scope, left: 1, right: 2,
        prior1: 1, prior2: 2, operation_result: subject.result, operation_version: subject.result_version };
    p.term_count = 4; p.node_count = 3; p.conclusion = 3;
    job.active = true;
    job.scope = scope.handle; job.first = first.handle;
    job.second = second.handle; job.conclusion = conclusion.handle;
    return Candidate { checked: add_core::make_core(core, p), scope: scope.handle,
        first: first.handle, second: second.handle, conclusion: conclusion.handle };
}

// All reads of the live inventory are charged; the inventory itself is not
// proof authority. Source/Core and every field of the proof are separately
// validated below on the same meter. Handles must never cross jobs.
fn live(candidate: Candidate, job: Job&, phase: u32) -> Check {
    if job.graph.failed || !job.active || candidate.status != 0 || phase < 5 || phase > 7 { job.graph.failed = true; return Check { status: 4 }; }
    if !proof_scopes::same(job.scope, candidate.scope) || !proof_scopes::same(job.first, candidate.first) ||
       !proof_scopes::same(job.second, candidate.second) || !proof_scopes::same(job.conclusion, candidate.conclusion) {
        job.graph.failed = true; return Check { status: 1 };
    }
    for slot in 4 {
        let r = work::charge(job.graph.meter, phase, 20);
        if r.status != 0 { job.graph.failed = true; return Check { status: add_proof_metered::category(r), receipt: r }; }
        let valid = if slot == 0 { proof_scopes::scope_valid(job.graph, candidate.scope) }
            else if slot == 1 { proof_scopes::fact_valid(job.graph, candidate.first) }
            else if slot == 2 { proof_scopes::fact_valid(job.graph, candidate.second) }
            else { proof_scopes::fact_valid(job.graph, candidate.conclusion) };
        if !valid { job.graph.failed = true; return Check { status: 1 }; }
    }
    // One charge before each scope/edge handle read. The producer's arena is
    // private; these checks guard stale or accidentally mismatched handles.
    for slot in 5 {
        let r = work::charge(job.graph.meter, phase, 20);
        if r.status != 0 { job.graph.failed = true; return Check { status: add_proof_metered::category(r), receipt: r }; }
        let ok = if slot == 0 { proof_scopes::same(job.graph.entries[candidate.first.index - 1].fact.scope, candidate.scope) }
            else if slot == 1 { proof_scopes::same(job.graph.entries[candidate.second.index - 1].fact.scope, candidate.scope) }
            else if slot == 2 { proof_scopes::same(job.graph.entries[candidate.conclusion.index - 1].fact.scope, candidate.scope) }
            else if slot == 3 { proof_scopes::same(job.graph.entries[candidate.conclusion.index - 1].fact.first, candidate.first) }
            else { proof_scopes::same(job.graph.entries[candidate.conclusion.index - 1].fact.second, candidate.second) };
        if !ok { job.graph.failed = true; return Check { status: 1 }; }
    }
    return Check {};
}
fn validate_core(source: u8[:], candidate: Candidate, job: Job&, phase: u32) -> Check {
    let active = live(candidate, job, phase);
    if active.status != 0 { return active; }
    let c = candidate.checked;
    if c.schema != 4 || c.owner != 1 || c.scope != 1 { job.graph.failed = true; return Check { status: 1 }; }
    let valid_core = shape(c.core, job.graph.meter, phase);
    if valid_core.status != 0 { job.graph.failed = true; return valid_core; }
    let checked = add_source_metered::validate_source_at_phase(source, c.core, job.graph.meter, phase);
    if checked != 0 {
        job.graph.failed = true;
        let receipt = if checked == 3 { work::Receipt { status: 1, quantity: 1, measured: job.graph.meter.semantic, limit: 1048576 } }
            else { work::Receipt {} };
        return Check { status: checked as u32, receipt: receipt };
    }
    let proof = add_proof_metered::validate_meter(c.evidence, add_core::subject(), job.graph.meter, phase);
    if proof.status != 0 { job.graph.failed = true; return Check { status: proof.status, receipt: proof.receipt }; }
    return Check {};
}
// The caller must first discard all uses of the candidate evidence, and must
// not publish the proof independently of the validated source/Core. Closing
// removes active edges, not distinct terms or accumulated work.
fn release(candidate: Candidate, job: Job&, phase: u32) -> Check {
    if job.graph.failed || !job.active || candidate.status != 0 { job.graph.failed = true; return Check { status: 4 }; }
    if !proof_scopes::same(candidate.scope, job.scope) { job.graph.failed = true; return Check { status: 1 }; }
    let closed = proof_scopes::close_at(job.graph, candidate.scope, phase);
    if closed.status != 0 {
        job.graph.failed = true;
        return Check { status: if closed.status == 2 { add_proof_metered::category(closed.receipt) } else { 4 }, receipt: closed.receipt };
    }
    job.active = false;
    return Check {};
}

fn validate_plan(source: u8[:], candidate: Candidate, plan: add_core::AddPlanV4,
                 job: Job&, phase: u32) -> Check {
    if job.graph.failed || !job.active { job.graph.failed = true; return Check { status: 4 }; }
    if phase < 6 || phase > 7 { job.graph.failed = true; return Check { status: 4 }; }
    let r = work::charge(job.graph.meter, phase, 12);
    if r.status != 0 { job.graph.failed = true; return Check { status: if r.status == 1 { 3 } else { 4 }, receipt: r }; }
    if plan.schema != 4 || plan.edition != 1 || plan.semantic_policy != 1 || plan.optimization_policy != 1 ||
       plan.abi != 1 || plan.parameter_representation != 1 || plan.result_representation != 1 ||
       plan.environment_parameter != 1 || plan.source_parameters != 1 || plan.result_slot != 0 ||
       plan.opcode != 0x6a || plan.adapter_count != 0 || plan.helper_count != 0 ||
       plan.backing_allocation != 0 || plan.memory_grow != 0 || plan.memory_initial_pages != 275 ||
       plan.memory_maximum_pages != 275 || plan.depth != 1 || plan.frame_bytes != 0 {
        job.graph.failed = true; return Check { status: 1 };
    }
    var projected = candidate;
    projected.checked = plan.checked;
    return validate_core(source, projected, job, phase);
}

// A private end-to-end witness. The existing source parser and target encoder
// still do unmetered work, so this does not claim a complete required receipt.
// Failure, including release failure, returns no Wasm bytes.
struct Output { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, bytes: u8[] = [] }
fn compile(source: u8[:], job: Job&) -> Output {
    if job.graph.failed || job.attempted { job.graph.failed = true; return Output { status: 4 }; }
    let parsed = add_frontend::parse(source);
    if parsed.status != 0 { job.graph.failed = true; return Output { status: 1 }; }
    let candidate = build(parsed.core, job);
    if candidate.status != 0 { return Output { status: candidate.status, receipt: candidate.receipt }; }
    let core = validate_core(source, candidate, job, 5);
    if core.status != 0 { return Output { status: core.status, receipt: core.receipt }; }
    let plan = add_core::make_plan(candidate.checked);
    let checked = validate_plan(source, candidate, plan, job, 6);
    if checked.status != 0 { return Output { status: checked.status, receipt: checked.receipt }; }
    let final_check = validate_plan(source, candidate, plan, job, 7);
    if final_check.status != 0 { return Output { status: final_check.status, receipt: final_check.receipt }; }
    let c = plan.checked.core;
    if c.name_start < 0 || c.name_end <= c.name_start || c.name_end > source.len ||
       !wasm::identifier(source[c.name_start..c.name_end]) || !wasm::fixture_geometry_valid() {
        job.graph.failed = true; return Output { status: 4 };
    }
    var body: u8[>..] = [0, 0x20, 1, 0x41, 0, 0x6a, 0x0b];
    let bytes = wasm::emit_body(source[c.name_start..c.name_end], body);
    let released = release(candidate, job, 7);
    if released.status != 0 { return Output { status: released.status, receipt: released.receipt }; }
    return Output { bytes: copy(bytes) };
}
