// Private transactional experiment for the existing public-scalar snapshot.
// This is not a K1 retained-project implementation, policy receipt, cache, or
// filesystem authority. A successful attempt recompletes source from scratch;
// the optional candidate is only observed and never shortcuts required work.
namespace retained_scalar;
import public_frontend;
import public_interface;
import public_snapshot;

// Revision storage is owned. It may be read only while the calling code does
// not mutate it; this experiment does not implement concurrent leases.
struct Revision { generation: u64 = 0, snapshots: public_snapshot::Snapshot[>..] = [] }
// status: 0 published, 1 source/request rejected, 2 interrupted, 3 internal
// invalid fresh result, 4 publication failure, 5 generation exhaustion.
// cache: 0 absent/declined, 1 exact fully rechecked candidate.
struct Outcome { status: i64 = 1, cache: i64 = 0 }
// Simulated imported receipt metadata. These self-asserted counters are never
// authority; this type is deliberately not a serialization or policy receipt.
struct UntrustedClaim {
    policy: u8[] = [], semantic: u32 = 0, proof_visits: u32 = 0,
    proof_terms: u32 = 0, proof_peak_edges: u32 = 0
}

// Comparing all bytes here is essential. Header/digest equality alone is not
// authority. public_snapshot::validate additionally rechecks source semantic
// correspondence, producer, ABI and all three artifact structures.
fn same_snapshot(a: public_snapshot::Snapshot&, b: public_snapshot::Snapshot&) -> bool {
    return a.source[..] == b.source[..] && a.package[..] == b.package[..] &&
           a.module[..] == b.module[..] && a.declaration[..] == b.declaration[..] &&
           a.abi[..] == b.abi[..] && a.interface[..] == b.interface[..] &&
           a.function[..] == b.function[..] && a.plan[..] == b.plan[..];
}

// Failpoints are test controls, not asynchronous interruption or OOM support:
// 1 before admission, 2 after source recognition, 3 corrupt fresh artifact,
// 4 before publication, 5 fail publication. All five leave revision unchanged.
// Source recognition and complete fresh construction happen for every candidate
// including exact hits, because this model has no trusted required-work receipt.
fn attempt(revision: Revision&, source: u8[:], package: u8[:], module: u8[:],
           declaration: u8[:], abi: u8[:], candidate: public_snapshot::Snapshot&,
           has_candidate: bool, failpoint: i64) -> Outcome {
    if failpoint < 0 || failpoint > 5 { return Outcome { status: 3 }; }
    if failpoint == 1 { return Outcome { status: 2 }; }
    if source.len > 16777216 || abi.len != 32 ||
       !public_interface::identity_valid(package, module, declaration) { return Outcome {}; }
    let parsed = public_frontend::parse(source);
    if parsed.status != 0 { return Outcome {}; }
    if !public_frontend::verify(source, parsed) { return Outcome { status: 3 }; }
    if failpoint == 2 { return Outcome { status: 2 }; }
    var fresh = public_snapshot::make(source, package, module, declaration, abi);
    if fresh.status != 0 { return Outcome { status: 3 }; }
    if failpoint == 3 {
        // The normal constructor has already built a nonempty valid interface.
        // Simulate an invalid compiler-produced result at the publication gate.
        if fresh.snapshot.interface.len == 0 { return Outcome { status: 3 }; }
        fresh.snapshot.interface[0] ^= 1;
    }
    if !public_snapshot::validate(fresh.snapshot, package, module, declaration, abi) {
        return Outcome { status: 3 };
    }
    var cache: i64 = 0;
    // The size guards in validate are applied before any decoding. Exact bytes
    // must also match the newly completed snapshot, including source origins.
    if has_candidate && public_snapshot::sizes_fit(candidate.source.len, candidate.interface.len,
                                                     candidate.function.len, candidate.plan.len) &&
       same_snapshot(candidate, fresh.snapshot) &&
       public_snapshot::validate(candidate, package, module, declaration, abi) { cache = 1; }
    if failpoint == 4 { return Outcome { status: 2, cache: cache }; }
    if failpoint == 5 { return Outcome { status: 4, cache: cache }; }
    if revision.generation == 18446744073709551615 { return Outcome { status: 5, cache: cache }; }
    // Only this point mutates the last successful revision. The source and all
    // artifact bytes in fresh.snapshot are newly owned copies of caller input.
    revision.snapshots = [copy(fresh.snapshot)];
    revision.generation += 1;
    return Outcome { status: 0, cache: cache };
}

// An externally supplied claim is intentionally unused: it cannot seed the
// current job, skip source recognition, assert a completed phase, or make an
// unvalidated fresh result publishable. The regular attempt always recompletes.
// This is a negative test seam, not a disk/cache decoder or a trusted receipt.
fn attempt_untrusted(revision: Revision&, source: u8[:], package: u8[:], module: u8[:],
                    declaration: u8[:], abi: u8[:], candidate: public_snapshot::Snapshot&,
                    claim: UntrustedClaim&, failpoint: i64) -> Outcome {
    return attempt(revision, source, package, module, declaration, abi, candidate, true, failpoint);
}
