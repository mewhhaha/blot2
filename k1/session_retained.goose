// Private current-process retained scalar fixture. This is not K1 public
// admission, complete C09 accounting, untrusted disk import, or a project
// server. The trusted compiler must exclusively own Session; Goose namespace
// privacy does not prevent arbitrary in-process code mutating its fields.
// Source programs and serialized inputs must never receive a Session reference.
namespace session_retained;
import catalog;
import scalar_scheduled;
import work;
import frontend;
import scalar_core;
import scalar_plan;
import fixture_geometry;
import wasm_scalar_validation_metered;
import session_target_exact;

struct Observation {
    kind: u32 = 0, key_len: u32 = 0, key: u8[64] = [0; 64],
    found: bool = false, value_len: u32 = 0, value: u8[128] = [0; 128]
}
struct Observations { count: u32 = 0, values: Observation[16] = [Observation {}; 16] }
struct Entry {
    sealed: bool = false, source_len: u32 = 0, source: u8[4096] = [0; 4096],
    target_len: u32 = 0, target: u8[8192] = [0; 8192],
    observations: Observations = Observations {}, receipt: work::ScheduledWork = work::ScheduledWork {},
    plan: scalar_plan::ScalarLoweringPlan = scalar_plan::ScalarLoweringPlan {}
}
// Both cells are compiler-owned fixed storage. Only the inactive cell is
// written during publication; the final active-index change is the sole
// logical publication point. This does not implement concurrency or recover
// from the process aborting on Goose allocator/stack exhaustion.
struct Session {
    entries: Entry[2] = [Entry {}; 2], active: u32 = 0, has_revision: bool = false,
    generation: u64 = 0, fresh_runs: u64 = 0, hits: u64 = 0
}
// status: 0 compiled/reused, 1 source rejected, 2 semantic limit,
// 3 Core limit, 4 internal error, 5 unsupported policy, 6 test interruption.
// Unretained success still returns fresh bytes; it does not overwrite the old
// retained revision, and the caller must not mistake that revision for the
// result of the newer request.
struct Result {
    status: i64 = 0, bytes: u8[] = [], reused: bool = false, retained: bool = false,
    semantic: u32 = 0, proof_visits: u32 = 0, validation_semantic: u32 = 0, validation_target_visits: u64 = 0
}

// These ordered observations are trusted query results supplied by compiler
// code, not records or authority supplied by the program being compiled.
// Kinds distinguish interface, body, static, ABI, capture, provider, source
// origin, policy, and recursion facts. found=false is a negative lookup;
// found=true plus an empty value is a distinct positive observation.
fn observations_valid(observations: Observations&) -> bool {
    if observations.count > 16 { return false; }
    for i in observations.count as i64 {
        let o = observations.values[i];
        if o.kind < 1 || o.kind > 9 || o.key_len == 0 || o.key_len > 64 || o.value_len > 128 ||
           (!o.found && o.value_len != 0) { return false; }
        // Canonical fixed storage keeps stale trailing bytes from affecting
        // serialized or fieldwise identities in future integrations.
        for j in (o.key_len as i64)..64 { if o.key[j] != 0 { return false; } }
        for j in (o.value_len as i64)..128 { if o.value[j] != 0 { return false; } }
    }
    return true;
}
fn same_observations(a: Observations&, b: Observations&) -> bool {
    if !observations_valid(a) || !observations_valid(b) || a.count != b.count { return false; }
    for i in a.count as i64 {
        let x = a.values[i]; let y = b.values[i];
        if x.kind != y.kind || x.key_len != y.key_len || x.found != y.found || x.value_len != y.value_len ||
           x.key[..x.key_len] != y.key[..y.key_len] || x.value[..x.value_len] != y.value[..y.value_len] { return false; }
    }
    return true;
}
fn receipt_valid(job: work::ScheduledWork&) -> bool {
    if !work::schedule_complete(job) || job.meter.semantic > 1048576 || job.meter.proof_visits != 0 ||
       job.meter.proof_terms != 0 || job.meter.proof_edges != 0 || job.meter.proof_peak_edges != 0 ||
       job.meter.core_operations > 65536 || job.meter.core_blocks > 4096 || job.phases[3] != 3 { return false; }
    var sum: u64 = 0;
    for count in job.meter.phase_semantic { sum += count as u64; }
    return sum == job.meter.semantic as u64;
}
fn entry_valid(e: Entry&) -> bool {
    return e.sealed && e.source_len <= 4096 && e.target_len > 0 && e.target_len <= 8192 &&
        observations_valid(e.observations) && receipt_valid(e.receipt);
}
fn add1(n: u64) -> u64 { if n == 18446744073709551615 { return n; } return n + 1; }
fn own_bytes(data: u8[:]) -> u8[>..] { var out: u8[>..] = []; out.append(data); return out; }

// Build a closed scalar plan from source for target admission. This optional
// extra parse is not yet covered by complete C09 accounting. The subsequent
// independent target verifier checks the plan, source, geometry and every
// executable section; neither this helper nor a digest authenticates code.
fn plan_for(source: u8[:]) -> scalar_plan::ScalarLoweringPlan {
    let p = frontend::parse_scalar(source);
    if p.status != 0 { return scalar_plan::ScalarLoweringPlan {}; }
    var c = scalar_core::build(p.result_type, p.binary_op, p.kind, p.literal, p.right_kind, p.right_literal);
    c.name_start = p.name_start; c.name_end = p.name_end;
    c.parameter_start = p.parameter_start; c.parameter_end = p.parameter_end;
    c.left_start = p.start; c.left_end = p.end;
    c.operator_start = p.operator_start; c.operator_end = p.operator_end;
    c.right_start = p.right_start; c.right_end = p.right_end;
    return scalar_plan::make(c);
}

// The optional claim is deliberately ignored: imported bytes cannot assert
// work, executable provenance, or a current-process sealed record. A warm hit
// is possible only against this Session's own successfully published entry.
// failpoint 1 interrupts before checking, 2 after checking and before staging,
// 3 after staging and before publication; all preserve the prior active cell.
fn compile(session: Session&, source: u8[:], observations: Observations&, policy: u8[:],
           external_claim: u8[:], failpoint: u32) -> Result {
    if failpoint > 3 || session.active > 1 { return Result { status: 4 }; }
    if policy != catalog::semantic_policy() { return Result { status: 5 }; }
    if failpoint == 1 { return Result { status: 6 }; }
    if failpoint == 0 && session.has_revision && source.len <= 4096 && observations_valid(observations) {
        let e = session.entries[session.active];
        if entry_valid(e) && e.source_len == source.len && e.source[..e.source_len] == source &&
           same_observations(e.observations, observations) {
            var geometry, geometry_ok = fixture_geometry::build();
            var validation = e.receipt.meter;
            validation.gate = 0;
            if geometry_ok && wasm_scalar_validation_metered::verify(source, e.plan, geometry,
                                                                       e.target[..e.target_len], validation) == 0 &&
               session_target_exact::verify(e.target[..e.target_len], validation) == 0 {
                session.hits = add1(session.hits);
                return Result { bytes: own_bytes(e.target[..e.target_len]), reused: true, retained: true,
                    semantic: e.receipt.meter.semantic, proof_visits: e.receipt.meter.proof_visits,
                    validation_semantic: validation.semantic - e.receipt.meter.semantic,
                    validation_target_visits: validation.target_visits - e.receipt.meter.target_visits };
            }
            // Invalid or budget-declined optional retained bytes never escape;
            // run the ordinary fresh path instead.
        }
    }
    session.fresh_runs = add1(session.fresh_runs);
    var job = work::ScheduledWork {};
    let completed = scalar_scheduled::run(source, job);
    if completed.status != 0 { return Result { status: completed.status }; }
    if !receipt_valid(job) { return Result { status: 4 }; }
    if failpoint == 2 { return Result { status: 6 }; }
    // Decline this optional retained family when any fixed bound does not fit.
    // The checked bytes remain valid as an unretained result.
    if source.len > 4096 || completed.bytes.len > 8192 || !observations_valid(observations) ||
       session.generation == 18446744073709551615 {
        return Result { bytes: copy(completed.bytes), semantic: job.meter.semantic, proof_visits: job.meter.proof_visits };
    }
    let plan = plan_for(source);
    var geometry, geometry_ok = fixture_geometry::build();
    if !scalar_plan::validate(plan) || !geometry_ok { return Result { status: 4 }; }
    var validation = job.meter;
    validation.gate = 0;
    let validation_status = wasm_scalar_validation_metered::verify(source, plan, geometry, completed.bytes, validation);
    if validation_status == 3 {
        // Optional target revalidation exhaustion cannot reject valid fresh work.
        return Result { bytes: copy(completed.bytes), semantic: job.meter.semantic, proof_visits: job.meter.proof_visits };
    }
    if validation_status != 0 { return Result { status: 4 }; }
    if session_target_exact::verify(completed.bytes, validation) != 0 { return Result { status: 4 }; }
    var staged = Entry { sealed: true, source_len: source.len as u32, target_len: completed.bytes.len as u32,
        observations: observations, receipt: job, plan: plan };
    for b, i in source { staged.source[i] = b; }
    for b, i in completed.bytes { staged.target[i] = b; }
    if !entry_valid(staged) { return Result { status: 4 }; }
    let next: u32 = if session.active == 0 { 1 } else { 0 };
    session.entries[next] = staged;
    if failpoint == 3 { return Result { status: 6 }; }
    session.active = next; session.has_revision = true; session.generation += 1;
    return Result { bytes: copy(completed.bytes), retained: true, semantic: job.meter.semantic,
        proof_visits: job.meter.proof_visits, validation_semantic: validation.semantic - job.meter.semantic,
        validation_target_visits: validation.target_visits - job.meter.target_visits };
}
