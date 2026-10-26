import os;
import std;
import add_scoped;
import add_frontend;
import add_core;
import proof_scopes;
import work;

fn main() {
    let source = "let f: U32 -> U32 = fn x => return x + 0";
    let parsed = add_frontend::parse(source);
    assert(parsed.status == 0);
    var job = add_scoped::Job {};
    job.graph.meter.gate = 4;
    let candidate = add_scoped::build(parsed.core, job);
    assert(candidate.status == 0 && job.graph.meter.proof_terms == 4 && job.graph.meter.proof_edges == 5);
    assert(job.graph.meter.proof_peak_edges == 5);
    job.graph.meter.gate = 5;
    assert(add_scoped::validate_core(source, candidate, job, 5).status == 0);
    let plan = add_core::make_plan(candidate.checked);
    job.graph.meter.gate = 6;
    assert(add_scoped::validate_plan(source, candidate, plan, job, 6).status == 0);
    job.graph.meter.gate = 7;
    assert(add_scoped::validate_plan(source, candidate, plan, job, 7).status == 0);
    assert(add_scoped::release(candidate, job, 7).status == 0);
    assert(job.graph.meter.proof_edges == 0 && job.graph.meter.proof_peak_edges == 5 && job.graph.meter.proof_terms == 4);
    assert(add_scoped::validate_core(source, candidate, job, 7).status != 0);
    assert(job.graph.failed);

    // Real source must match the exact checked operation and operand versions.
    var invalid_source_job = add_scoped::Job {};
    let invalid_source = add_scoped::build(parsed.core, invalid_source_job);
    assert(add_scoped::validate_core("let f: U32 -> U32 = fn x => return x + 1", invalid_source, invalid_source_job, 5).status == 1);
    let after_failure = invalid_source_job.graph.meter.semantic;
    assert(add_scoped::validate_plan(source, invalid_source, add_core::make_plan(invalid_source.checked), invalid_source_job, 6).status == 4);
    assert(invalid_source_job.graph.meter.semantic == after_failure);
    for which in 6 {
        var forged_job = add_scoped::Job {};
        var forged = add_scoped::build(parsed.core, forged_job);
        if which == 0 { forged.checked.evidence.subject.result_version += 1; }
        else if which == 1 { forged.checked.evidence.terms[1].literal = 1; }
        else if which == 2 { forged.checked.evidence.nodes[2].prior1 = 3; }
        else if which == 3 { forged.checked.evidence.nodes[2].operation_version = 0; }
        else if which == 4 { forged.checked.core.values[2].left_id = 1; }
        else { forged.conclusion = forged.first; }
        assert(add_scoped::validate_core(source, forged, forged_job, 5).status == 1);
        assert(forged_job.graph.failed);
    }
    var stale = add_scoped::Job {};
    let stale_candidate = add_scoped::build(parsed.core, stale);
    assert(add_scoped::release(stale_candidate, stale, 4).status == 0);
    assert(add_scoped::validate_core(source, stale_candidate, stale, 5).status != 0);
    var bad_release = add_scoped::Job {};
    var other = add_scoped::build(parsed.core, bad_release);
    other.scope = other.first;
    assert(add_scoped::release(other, bad_release, 7).status == 1);

    // The full private witness shares this meter through proof construction,
    // source/Core, plan, emission revalidation, and proof scope release.
    var total = add_scoped::Job {};
    let generated = add_scoped::compile(source, total);
    assert(generated.status == 0 && generated.bytes.len > 0);
    assert(total.graph.meter.proof_edges == 0 && total.graph.meter.proof_terms == 4);
    assert(total.graph.meter.proof_peak_edges == 5 && !total.active);
    assert(write_file("add_scoped.wasm", generated.bytes));
    let events = total.graph.meter.semantic;
    assert(events > 20 && events < 5000);
    // Exhaust each charged semantic event in turn, including release. A failed
    // event cannot publish a partial proof or executable.
    for i in 0..events {
        var limited = add_scoped::Job {};
        limited.graph.meter.semantic = 1048577 - events + i;
        let rejected = add_scoped::compile(source, limited);
        if rejected.status != 3 || rejected.receipt.quantity != 1 || rejected.bytes.len != 0 {
            print(str("failed injection event=", i, " total=", events, " status=", rejected.status,
                      " receipt=", rejected.receipt.quantity, " bytes=", rejected.bytes.len));
        }
        assert(rejected.status == 3 && rejected.receipt.quantity == 1 && rejected.bytes.len == 0);
        assert(limited.graph.failed && limited.graph.meter.semantic == 1048576);
    }
    // Proof visits include actual construction, edge walks and all three
    // independent evidence rechecks. Exhaust each such event in turn.
    let proof_events = total.graph.meter.proof_visits;
    assert(proof_events > 20 && proof_events < 1000);
    for i in 0..proof_events {
        var limited = add_scoped::Job {};
        limited.graph.meter.proof_visits = 65537 - proof_events + i;
        let rejected = add_scoped::compile(source, limited);
        assert(rejected.status == 2 && rejected.receipt.quantity == 2 && rejected.bytes.len == 0);
        assert(limited.graph.failed && limited.graph.meter.proof_visits == 65536);
    }
    var edge = add_scoped::Job {};
    edge.graph.meter.proof_edges = 16380;
    let edge_failure = add_scoped::build(parsed.core, edge);
    assert(edge_failure.status == 2 && edge_failure.receipt.quantity == 4 && edge_failure.checked.schema == 0);
    assert(edge.graph.failed && edge.graph.meter.proof_edges == 16384);
    var terms = add_scoped::Job {};
    terms.graph.meter.proof_terms = 4093;
    let term_failure = add_scoped::build(parsed.core, terms);
    assert(term_failure.status == 2 && term_failure.receipt.quantity == 3 && term_failure.checked.schema == 0);
    var simultaneous = add_scoped::Job {};
    simultaneous.graph.meter.semantic = 1048576;
    simultaneous.graph.meter.proof_visits = 65536;
    let failure = add_scoped::build(parsed.core, simultaneous);
    assert(failure.status == 3 && failure.receipt.quantity == 1 && failure.checked.schema == 0);
    var wrong_phase = add_scoped::Job {};
    wrong_phase.graph.meter.gate = 4;
    let wrong_candidate = add_scoped::build(parsed.core, wrong_phase);
    wrong_phase.graph.meter.gate = 5;
    let before_wrong = wrong_phase.graph.meter.semantic;
    assert(add_scoped::release(wrong_candidate, wrong_phase, 4).status == 4);
    assert(wrong_phase.graph.failed && wrong_phase.graph.meter.semantic == before_wrong);
    var invalid = add_scoped::Job {};
    assert(add_scoped::compile("let f: U32 -> U32 = fn x => return x + 1", invalid).bytes.len == 0);
    print("scoped checked-add source/Core/plan proof work passed");
}
