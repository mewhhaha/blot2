import work;
import frontend;
import add_core;
import add_proof_metered;

fn main() {
    let source = "let f: U32 -> U32 = fn x => return x";
    var job = add_proof_metered::AddJob {};
    assert(frontend::parse_scalar_with_work(source, job.meter).status == 0);
    let source_visits = job.meter.semantic;
    let built = add_proof_metered::build(add_core::subject(), job);
    let before_retry = job.meter.semantic;
    assert(add_proof_metered::build(add_core::subject(), job).status == 4);
    assert(job.meter.semantic == before_retry);
    assert(built.status == 0 && job.meter.proof_terms == 4 && job.meter.proof_edges == 5);
    assert(job.meter.proof_visits == 10 && job.meter.semantic == source_visits + 10);
    assert(add_proof_metered::validate(built.proof, add_core::subject(), job, 5).status == 0);
    assert(add_proof_metered::validate(built.proof, add_core::subject(), job, 6).status == 0);
    assert(add_proof_metered::validate(built.proof, add_core::subject(), job, 7).status == 0);
    assert(job.meter.proof_visits == 40 && job.meter.semantic == source_visits + 40);
    assert(job.meter.phase_semantic[3] == 10 && job.meter.phase_semantic[4] == 10 && job.meter.phase_semantic[5] == 10 && job.meter.phase_semantic[6] == 10);

    var bad = built.proof;
    bad.nodes[2].operation_version += 1;
    assert(add_proof_metered::validate(bad, add_core::subject(), job, 5).status == 1);
    // A malformed second prerequisite must not be inspected when its charge
    // cannot be made. With one more visit available it is rejected as invalid.
    var bad_link = built.proof;
    bad_link.nodes[2].prior2 = 99;
    var stopped = add_proof_metered::AddJob { meter: work::Meter { proof_terms: 4, proof_edges: 5, proof_visits: 65527 } };
    let stopped_check = add_proof_metered::validate(bad_link, add_core::subject(), stopped, 5);
    assert(stopped_check.status == 2 && stopped_check.visits == 9);
    var enough = add_proof_metered::AddJob { meter: work::Meter { proof_terms: 4, proof_edges: 5 } };
    assert(add_proof_metered::validate(bad_link, add_core::subject(), enough, 5).status == 1);
    var fresh = add_proof_metered::AddJob {};
    assert(add_proof_metered::validate(built.proof, add_core::subject(), fresh, 5).status == 1);
    var semantic = add_proof_metered::AddJob { meter: work::Meter { semantic: 1048566 } };
    let e = add_proof_metered::build(add_core::subject(), semantic);
    assert(e.status == 0 && semantic.meter.semantic == 1048576);
    let denied = add_proof_metered::validate(e.proof, add_core::subject(), semantic, 5);
    assert(denied.status == 3 && denied.receipt.quantity == 1 && semantic.meter.semantic == 1048576);
    var proof = add_proof_metered::AddJob { meter: work::Meter { proof_visits: 65527 } };
    let fail = add_proof_metered::build(add_core::subject(), proof);
    assert(fail.status == 2 && fail.receipt.quantity == 2 && proof.meter.proof_visits == 65536);
    assert(fail.proof.schema == 0); // no partial publication
    var bad_phase = add_proof_metered::AddJob {};
    assert(add_proof_metered::validate(built.proof, add_core::subject(), bad_phase, 4).status == 4);
    assert(bad_phase.meter.semantic == 0);
    print("shared proof work laws passed");
}
