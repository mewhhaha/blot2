// Private one-declaration witness, not K1 admission or a complete work
// receipt. Parser byte work, output encoding and target traversal are not fully
// metered. The returned bytes never contain a proof or compiler-owned handle.
namespace increment_compile;
import work;
import proof_scopes;
import increment_core;
import increment_parse;
import increment_validate;
import increment_wasm;
import increment_target;
struct Job {
    attempted: bool = false,
    active: bool = false,
    root: proof_scopes::Handle = proof_scopes::Handle {},
    branch: proof_scopes::Handle = proof_scopes::Handle {},
    fact: proof_scopes::Handle = proof_scopes::Handle {},
    conclusion: proof_scopes::Handle = proof_scopes::Handle {},
    graph: proof_scopes::Job = proof_scopes::Job {}
}
struct Prepared { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, core: increment_core::Core = increment_core::Core {} }
struct Output { status: u32 = 0, receipt: work::Receipt = work::Receipt {}, bytes: u8[] = [] }
fn code(r: work::Receipt) -> u32 { return if r.status == 1 { 3 } else if r.status == 2 { 2 } else { 4 }; }
fn stop(job: Job&, status: u32, receipt: work::Receipt) -> Prepared { job.graph.failed = true; return Prepared { status: status, receipt: receipt }; }
fn scope_stop(job: Job&, r: proof_scopes::Result) -> Prepared { return stop(job, if r.status == 2 { code(r.receipt) } else { 4 }, r.receipt); }
// The source producer is not proof authority. It creates only a candidate;
// each term/fact and prerequisite edge is charged before being materialized.
fn prepare(source: u8[:], job: Job&) -> Prepared {
    if job.graph.failed || job.attempted { return stop(job,4,work::Receipt {}); }
    job.attempted = true;
    var c, status = increment_parse::parse(source);
    if status != 0 { return stop(job,1,work::Receipt {}); }
    var r = work::charge(job.graph.meter,4,20); if r.status != 0 { return stop(job,code(r),r); }
    r = work::charge(job.graph.meter,4,21); if r.status != 0 { return stop(job,code(r),r); }
    c.terms[0] = increment_core::Term { kind: 1, value: 0, version: 1 };
    r = work::charge(job.graph.meter,4,21); if r.status != 0 { return stop(job,code(r),r); }
    c.terms[1] = increment_core::Term { kind: 2, literal: 4294967295 };
    r = work::charge(job.graph.meter,4,21); if r.status != 0 { return stop(job,code(r),r); }
    c.terms[2] = increment_core::Term { kind: 2, literal: 1 };
    let none = proof_scopes::Handle {};
    let root = proof_scopes::open(job.graph,none); if root.status != 0 { return scope_stop(job,root); }
    let branch = proof_scopes::open(job.graph,root.handle); if branch.status != 0 { return scope_stop(job,branch); }
    let guard_fact = proof_scopes::add(job.graph,branch.handle,none,none); if guard_fact.status != 0 { return scope_stop(job,guard_fact); }
    c.evidence[0] = increment_core::Evidence { rule: 1, scope: 2, left: 1, right: 2 };
    let successor = proof_scopes::add(job.graph,branch.handle,guard_fact.handle,none); if successor.status != 0 { return scope_stop(job,successor); }
    c.evidence[1] = increment_core::Evidence { rule: 2, scope: 2, left: 1, right: 3, prior: 1, result: 1, result_version: 2 };
    job.root = root.handle; job.branch = branch.handle; job.fact = guard_fact.handle; job.conclusion = successor.handle;
    job.active = true;
    return Prepared { core: c };
}
// Keep this job-local inventory live through the final consumer. Handles are
// trusted internals, not cross-job identities or artifact authority.
fn release(job: Job&, phase: u32) -> increment_validate::Check {
    if job.graph.failed || !job.active { job.graph.failed = true; return increment_validate::Check { status: 4 }; }
    let branch = proof_scopes::close_at(job.graph,job.branch,phase);
    if branch.status != 0 { job.graph.failed = true; return increment_validate::Check { status: if branch.status == 2 { code(branch.receipt) } else { 4 }, receipt: branch.receipt }; }
    let root = proof_scopes::close_at(job.graph,job.root,phase);
    if root.status != 0 { job.graph.failed = true; return increment_validate::Check { status: if root.status == 2 { code(root.receipt) } else { 4 }, receipt: root.receipt }; }
    job.active = false; return increment_validate::Check {};
}
fn run(source: u8[:], job: Job&) -> Output {
    let candidate = prepare(source,job);
    if candidate.status != 0 { return Output { status: candidate.status, receipt: candidate.receipt }; }
    var core = candidate.core;
    for phase in [5 as u32, 7] {
        let checked = increment_validate::verify(source,core,job.graph.meter,phase);
        if checked.status != 0 { job.graph.failed = true; return Output { status: checked.status, receipt: checked.receipt }; }
    }
    let bytes = increment_wasm::encode();
    if !increment_target::verify(bytes) { job.graph.failed = true; return Output { status: 4 }; }
    let closed = release(job,7);
    if closed.status != 0 { return Output { status: closed.status, receipt: closed.receipt }; }
    return Output { bytes: copy(bytes) };
}
