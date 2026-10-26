import work;
import add_frontend;
import add_core;
import add_source_metered;
import add_proof_metered;

fn main() {
    let source = "let f: U32 -> U32 = fn x => return x + 0\n";
    let candidate = add_frontend::parse(source);
    assert(candidate.status == 0);
    var job = add_proof_metered::AddJob {};
    assert(add_source_metered::validate_source(source, candidate.core, job.meter) == 0);
    let source_visits = job.meter.semantic;
    assert(source_visits > 0);
    let proof = add_proof_metered::build(add_core::subject(), job);
    assert(proof.status == 0);
    assert(add_proof_metered::validate(proof.proof, add_core::subject(), job, 5).status == 0);
    let total = job.meter.semantic;
    assert(total == source_visits + 20 && job.meter.proof_visits == 20);
    var exact = add_proof_metered::AddJob { meter: work::Meter { semantic: 1048576 - total } };
    assert(add_source_metered::validate_source(source, candidate.core, exact.meter) == 0);
    let exact_proof = add_proof_metered::build(add_core::subject(), exact);
    assert(exact_proof.status == 0);
    assert(add_proof_metered::validate(exact_proof.proof, add_core::subject(), exact, 5).status == 0);
    assert(exact.meter.semantic == 1048576);
    var short = add_proof_metered::AddJob { meter: work::Meter { semantic: 1048577 - total } };
    assert(add_source_metered::validate_source(source, candidate.core, short.meter) == 0);
    let short_proof = add_proof_metered::build(add_core::subject(), short);
    assert(short_proof.status == 0);
    assert(add_proof_metered::validate(short_proof.proof, add_core::subject(), short, 5).status == 3);
    assert(short.meter.semantic == 1048576);
    var forged = candidate.core;
    forged.values[1].literal = 1;
    var invalid = work::Meter {};
    assert(add_source_metered::validate_source(source, forged, invalid) == 1);
    assert(add_source_metered::validate_source("let f: U32 -> U32 = fn x => return x + 1\n", candidate.core, invalid) == 1);
    print("shared add source and proof work laws passed");
}
