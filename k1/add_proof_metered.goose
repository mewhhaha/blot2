// Checked AddFits(x, 0) evidence using a declaration-owned shared work meter.
// This is a private fixture, not a portable proof or an authenticated receipt.
// The caller must independently establish the exact Subject from checked source
// and Core; counters and fixed fixture identities are not evidence provenance.
namespace add_proof_metered;
import add_proof;
import work;

struct Built { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, proof: add_proof::Proof = add_proof::Proof {} }
struct Checked { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, visits: u32 = 0 }
// The single declaration job owns both the shared meter and its proof-build
// state. This prevents callers accidentally pairing one meter with fresh guard
// objects. A general implementation must replace the one-build restriction
// with per-declaration term interning. The job is not artifact authentication.
struct AddJob { meter: work::Meter = work::Meter {}, proof_attempted: bool = false }
// 0 success, 1 invalid input, 2 proof limit, 3 semantic limit, 4 internal accounting error.
fn category(receipt: work::Receipt) -> u32 {
    if receipt.status == 0 { return 0; }
    if receipt.status == 1 { return 3; }
    if receipt.status == 2 { return 2; }
    return 4;
}

fn build(s: add_proof::Subject, job: AddJob&) -> Built {
    if job.proof_attempted { return Built { status: 4 }; }
    job.proof_attempted = true;
    var r = work::charge(job.meter, 4, 20);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    if !add_proof::valid_subject(s) { return Built { status: 1 }; }
    var p = add_proof::Proof { schema: 1, semantic_policy: 1, subject: s };
    r = work::charge(job.meter, 4, 21);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.terms[0] = add_proof::Term { kind: 1, owner: s.owner, scope: s.scope,
                                   value: s.parameter, version: s.parameter_version };
    r = work::charge(job.meter, 4, 21);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.terms[1] = add_proof::Term { kind: 2, owner: s.owner, scope: s.scope,
                                   value: s.zero, version: s.zero_version, literal: 0 };
    r = work::charge(job.meter, 4, 21);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.terms[2] = add_proof::Term { kind: 3, owner: s.owner, scope: s.scope, literal: 4294967295 };
    r = work::charge(job.meter, 4, 21);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.terms[3] = add_proof::Term { kind: 4, owner: s.owner, scope: s.scope, base: 2 };
    r = work::charge(job.meter, 4, 22);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.nodes[0] = add_proof::Node { rule: 1, owner: s.owner, scope: s.scope, left: 1, right: 3 };
    r = work::charge(job.meter, 4, 22);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.nodes[1] = add_proof::Node { rule: 2, owner: s.owner, scope: s.scope, left: 4, right: 3 };
    // One conclusion and two prerequisite edges are charged separately before
    // the conclusion is made visible. Failure publishes no partial proof.
    r = work::charge(job.meter, 4, 22);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    r = work::charge(job.meter, 4, 22);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    r = work::charge(job.meter, 4, 22);
    if r.status != 0 { return Built { status: category(r), receipt: r }; }
    p.nodes[2] = add_proof::Node { rule: 3, owner: s.owner, scope: s.scope, left: 1, right: 2,
        prior1: 1, prior2: 2, operation_result: s.result, operation_version: s.result_version };
    p.term_count = 4; p.node_count = 3; p.conclusion = 3;
    return Built { proof: p };
}

// Repeat validation in phase 5 (semantic), 6 (plan), or 7 (emission).
// All 10 visits are charged again. The term/edge inventory is only a local
// sanity check; it is not an authentication of imported or stale evidence.
fn validate_meter(p: add_proof::Proof, expected: add_proof::Subject,
                  meter: work::Meter&, phase: u32) -> Checked {
    let before = meter.proof_visits;
    if phase < 5 || phase > 7 { return Checked { status: 4 }; }
    var r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if meter.proof_terms < 4 || meter.proof_edges < 5 || !add_proof::valid_subject(expected) ||
       !add_proof::same_subject(p.subject, expected) || p.schema != 1 || p.semantic_policy != 1 ||
       p.term_count != 4 || p.node_count != 3 || p.conclusion != 3 { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_term(p.terms[0], add_proof::Term { kind: 1, owner: expected.owner, scope: expected.scope,
        value: expected.parameter, version: expected.parameter_version }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_term(p.terms[1], add_proof::Term { kind: 2, owner: expected.owner, scope: expected.scope,
        value: expected.zero, version: expected.zero_version, literal: 0 }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_term(p.terms[2], add_proof::Term { kind: 3, owner: expected.owner, scope: expected.scope,
        literal: 4294967295 }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_term(p.terms[3], add_proof::Term { kind: 4, owner: expected.owner, scope: expected.scope, base: 2 }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_node(p.nodes[0], add_proof::Node { rule: 1, owner: expected.owner, scope: expected.scope, left: 1, right: 3 }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if !add_proof::same_node(p.nodes[1], add_proof::Node { rule: 2, owner: expected.owner, scope: expected.scope, left: 4, right: 3 }) { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    // Validate the conclusion record without inspecting prerequisite IDs yet.
    if p.nodes[2].rule != 3 || p.nodes[2].owner != expected.owner ||
       p.nodes[2].scope != expected.scope || p.nodes[2].left != 1 || p.nodes[2].right != 2 ||
       p.nodes[2].operation_result != expected.result ||
       p.nodes[2].operation_version != expected.result_version {
        return Checked { status: 1, visits: meter.proof_visits - before };
    }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if p.nodes[2].prior1 != 1 { return Checked { status: 1, visits: meter.proof_visits - before }; }
    r = work::charge(meter, phase, 20);
    if r.status != 0 { return Checked { status: category(r), receipt: r, visits: meter.proof_visits - before }; }
    if p.nodes[2].prior2 != 2 { return Checked { status: 1, visits: meter.proof_visits - before }; }
    return Checked { visits: meter.proof_visits - before };
}

// Compatibility wrapper for the original one-proof fixture.
fn validate(p: add_proof::Proof, expected: add_proof::Subject,
            job: AddJob&, phase: u32) -> Checked {
    return validate_meter(p, expected, job.meter, phase);
}
