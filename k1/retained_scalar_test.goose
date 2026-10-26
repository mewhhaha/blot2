import retained_scalar;
import public_snapshot;
import catalog;
import os;

fn emitted(revision: retained_scalar::Revision&, abi: u8[:]) -> u8[] {
    for snapshot in revision.snapshots { return public_snapshot::emit(snapshot, "pkg", "main.blot", "answer", abi); }
    return [];
}

fn main() {
    let abi: u8[32] = [7; 32];
    let source = "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return x\n";
    let edited = "pub let answer: U32 -> U32 ! {} resources {depth: 1, frame: 0} = fn x => return 7\n";
    var revision = retained_scalar::Revision {};
    var absent = public_snapshot::Snapshot {};
    var r = retained_scalar::attempt(revision, source, "pkg", "main.blot", "answer", abi, absent, false, 0);
    assert(r.status == 0 && r.cache == 0 && revision.generation == 1);
    let baseline = emitted(revision, abi);
    assert(baseline.len > 0);
    assert(write_file("retained_scalar_before.wasm", baseline));
    // Invalid edits and all failpoints preserve the prior owned snapshot.
    r = retained_scalar::attempt(revision, "invalid", "pkg", "main.blot", "answer", abi, absent, false, 0);
    assert(r.status == 1 && revision.generation == 1);
    for point in 1..6 {
        r = retained_scalar::attempt(revision, edited, "pkg", "main.blot", "answer", abi, absent, false, point);
        let expected: i64 = if point == 3 { 3 } else if point == 5 { 4 } else { 2 };
        assert(r.status == expected);
        assert(revision.generation == 1);
        assert(emitted(revision, abi)[..] == baseline[..]);
    }
    var valid = public_snapshot::make(source, "pkg", "main.blot", "answer", abi);
    assert(valid.status == 0);
    // Plausible-looking untrusted zero-work metadata cannot bypass a bad
    // source or hide a fresh-construction defect on an otherwise exact hit.
    var cheap = retained_scalar::UntrustedClaim { policy: catalog::semantic_policy(), semantic: 0,
        proof_visits: 0, proof_terms: 0, proof_peak_edges: 0 };
    r = retained_scalar::attempt_untrusted(revision, "invalid", "pkg", "main.blot", "answer", abi,
        valid.snapshot, cheap, 0);
    assert(r.status == 1 && revision.generation == 1);
    r = retained_scalar::attempt_untrusted(revision, source, "pkg", "main.blot", "answer", abi,
        valid.snapshot, cheap, 3);
    assert(r.status == 3 && revision.generation == 1);
    assert(emitted(revision, abi)[..] == baseline[..]);
    r = retained_scalar::attempt(revision, source, "pkg", "main.blot", "answer", abi, valid.snapshot, true, 0);
    assert(r.status == 0 && r.cache == 1 && revision.generation == 2);
    valid.snapshot.interface[0] ^= 1;
    r = retained_scalar::attempt(revision, source, "pkg", "main.blot", "answer", abi, valid.snapshot, true, 0);
    assert(r.status == 0 && r.cache == 0 && revision.generation == 3);
    for which in 5 {
        var corrupt = public_snapshot::make(source, "pkg", "main.blot", "answer", abi);
        if which == 0 { corrupt.snapshot.function[0] ^= 1; }
        else if which == 1 { corrupt.snapshot.plan[0] ^= 1; }
        else if which == 2 { corrupt.snapshot.source[0] ^= 1; }
        else if which == 3 { corrupt.snapshot.package[0] ^= 1; }
        else { corrupt.snapshot.abi[0] ^= 1; }
        let attempt = retained_scalar::attempt(revision, source, "pkg", "main.blot", "answer", abi, corrupt.snapshot, true, 0);
        assert(attempt.status == 0 && attempt.cache == 0);
        assert(emitted(revision, abi)[..] == baseline[..]);
    }
    // Stale but otherwise valid objects must not match the edited request.
    var stale = public_snapshot::make(source, "pkg", "main.blot", "answer", abi);
    r = retained_scalar::attempt(revision, edited, "pkg", "main.blot", "answer", abi, stale.snapshot, true, 0);
    assert(r.status == 0 && r.cache == 0 && revision.generation == 9);
    let edited_bytes = emitted(revision, abi);
    assert(edited_bytes.len > 0 && edited_bytes[..] != baseline[..]);
    assert(write_file("retained_scalar_after.wasm", edited_bytes));
    r = retained_scalar::attempt(revision, source, "pkg", "main.blot", "answer", abi, stale.snapshot, true, 0);
    assert(r.status == 0 && r.cache == 1 && revision.generation == 10);
    assert(emitted(revision, abi)[..] == baseline[..]);
    // Exact hit does not alias caller-owned candidate or the caller's source.
    stale.snapshot.source[0] = 'X'; stale.snapshot.plan[0] ^= 1;
    assert(emitted(revision, abi)[..] == baseline[..]);
    var caller_source: u8[>..] = []; caller_source.append(source);
    var owned_revision = retained_scalar::Revision {};
    let owned = retained_scalar::attempt(owned_revision, caller_source, "pkg", "main.blot", "answer", abi, absent, false, 0);
    assert(owned.status == 0);
    caller_source[0] = 'X';
    assert(emitted(owned_revision, abi)[..] == baseline[..]);
    revision.generation = 18446744073709551615;
    r = retained_scalar::attempt(revision, edited, "pkg", "main.blot", "answer", abi, absent, false, 0);
    assert(r.status == 5 && revision.generation == 18446744073709551615);
    assert(emitted(revision, abi)[..] == baseline[..]);
    print("private retained scalar transaction laws passed");
}
