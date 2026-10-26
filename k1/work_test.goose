import work;

fn main() {
    var m = work::Meter {};
    assert(work::charge(m, 1, 1).status == 0);  // token
    assert(work::charge(m, 2, 2).status == 0);  // AST node
    assert(work::charge(m, 3, 30).status == 0); // Core operation
    assert(work::charge(m, 4, 21).status == 0); // intern new proof term
    assert(work::charge(m, 4, 22).status == 0); // new evidence edge
    assert(work::charge(m, 4, 20).status == 0); // proof revalidation
    assert(work::charge(m, 6, 12).status == 0); // plan node
    assert(m.semantic == 7 && m.proof_visits == 3 && m.proof_terms == 1 && m.proof_edges == 1);
    assert(m.core_operations == 1 && m.phase_semantic[0] == 1 && m.phase_semantic[3] == 3 && m.phase_semantic[5] == 1);
    assert(work::source_size(16777216).status == 0);
    let too_large = work::source_size(16777217);
    assert(too_large.status == 4 && too_large.quantity == 7 && too_large.measured == 16777217 && too_large.limit == 16777216);
    assert(work::source_read(m, 16777216).status == 0);
    assert(work::source_read(m, 10).status == 0 && m.source_byte_reads == 16777226);
    assert(m.semantic == 7); // Byte telemetry is not a semantic-visit limit.
    assert(work::charge(m, 0, 1).status == 5);
    assert(work::charge(m, 8, 1).status == 5);
    assert(work::charge(m, 1, 99).status == 5 && m.semantic == 7);

    var sem = work::Meter { semantic: 1048575 };
    assert(work::charge(sem, 1, 3).status == 0 && sem.semantic == 1048576);
    let sem_fail = work::charge(sem, 1, 3);
    assert(sem_fail.status == 1 && sem_fail.quantity == 1 && sem_fail.measured == 1048576 && sem_fail.limit == 1048576);
    assert(sem.semantic == 1048576 && sem.phase_semantic[0] == 1);
    var terms = work::Meter { proof_terms: 4095, proof_visits: 65535 };
    assert(work::charge(terms, 4, 21).status == 0);
    assert(terms.proof_terms == 4096 && terms.proof_visits == 65536 && terms.semantic == 1);
    let term_fail = work::charge(terms, 4, 21);
    assert(term_fail.status == 2 && term_fail.quantity == 3 && term_fail.measured == 4096);
    assert(terms.semantic == 1 && terms.proof_visits == 65536 && terms.proof_terms == 4096);
    var edges = work::Meter { proof_edges: 16383 };
    assert(work::charge(edges, 4, 22).status == 0 && edges.proof_edges == 16384);
    let edge_fail = work::charge(edges, 4, 22);
    assert(edge_fail.status == 2 && edge_fail.quantity == 4 && edge_fail.measured == 16384 && edges.semantic == 1);
    var visits = work::Meter { proof_visits: 65535 };
    assert(work::charge(visits, 4, 20).status == 0 && visits.proof_visits == 65536);
    let visit_fail = work::charge(visits, 4, 20);
    assert(visit_fail.status == 2 && visit_fail.quantity == 2 && visit_fail.measured == 65536 && visits.semantic == 1);
    var both = work::Meter { semantic: 1048576, proof_terms: 4096, proof_visits: 65536 };
    assert(work::charge(both, 4, 21).status == 1); // Total semantic ceiling wins.

    var operations = work::Meter { core_operations: 65535 };
    assert(work::charge(operations, 3, 30).status == 0 && operations.core_operations == 65536);
    let op_fail = work::charge(operations, 3, 30);
    assert(op_fail.status == 3 && op_fail.quantity == 5 && operations.semantic == 1);
    var blocks = work::Meter { core_blocks: 4095 };
    assert(work::charge(blocks, 3, 31).status == 0 && blocks.core_blocks == 4096);
    let block_fail = work::charge(blocks, 3, 31);
    assert(block_fail.status == 3 && block_fail.quantity == 6 && blocks.semantic == 1);

    var telemetry = work::Meter {};
    let maximum: u64 = ~(0 as u64);
    assert(work::source_read(telemetry, maximum).status == 0);
    let overflow = work::source_read(telemetry, 1);
    assert(overflow.status == 6 && overflow.quantity == 8 && telemetry.source_byte_reads == maximum);
    var target = work::Meter { target_visits: maximum - 1 };
    assert(work::target_visit(target).status == 0 && target.target_visits == maximum);
    let target_overflow = work::target_visit(target);
    assert(target_overflow.status == 6 && target_overflow.quantity == 9 && target.target_visits == maximum);
    assert(target.semantic == 0);
    var bad_phase = work::Meter {};
    bad_phase.phase_semantic[0] = 1;
    assert(work::charge(bad_phase, 1, 1).status == 5 && bad_phase.semantic == 0);
    print("required work model laws passed");
}
