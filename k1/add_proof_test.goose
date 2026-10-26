import add_proof;

fn subject() -> add_proof::Subject {
    return add_proof::Subject { owner: 23, scope: 8,
        parameter: 0, parameter_version: 4, zero: 1, zero_version: 5,
        result: 2, result_version: 6, zero_literal: 0, operation: 1 };
}
fn rejected(p: add_proof::Proof, expected: add_proof::Subject) {
    // Synthetic already-charged inventory for testing malformed in-memory DAGs.
    var work = add_proof::Work { terms: 4, edges: 5 };
    assert(add_proof::validate(p, expected, work).status == 1);
}

fn main() {
    let s = subject();
    var work = add_proof::Work {};
    let made = add_proof::build(s, work);
    assert(made.status == 0 && made.proof.term_count == 4 && made.proof.node_count == 3);
    assert(work.terms == 4 && work.edges == 5 && work.proof_visits == 10 && work.semantic_visits == 10);
    let checked = add_proof::validate(made.proof, s, work);
    assert(checked.status == 0 && checked.visits == 10);
    assert(work.proof_visits == 20 && work.semantic_visits == 20);
    var uncharged = add_proof::Work {};
    assert(add_proof::validate(made.proof, s, uncharged).status == 1);

    var p = made.proof;
    p.schema = 2; rejected(p, s); p = made.proof;
    p.semantic_policy = 0; rejected(p, s); p = made.proof;
    p.term_count = 5; rejected(p, s); p = made.proof;
    p.node_count = 0; rejected(p, s); p = made.proof;
    p.conclusion = 2; rejected(p, s); p = made.proof;
    p.subject.owner += 1; rejected(p, s); p = made.proof;
    p.subject.parameter_version += 1; rejected(p, s); p = made.proof;
    p.terms[0].version += 1; rejected(p, s); p = made.proof;
    p.terms[0].value = 1; rejected(p, s); p = made.proof;
    p.terms[1].literal = 1; rejected(p, s); p = made.proof;
    p.terms[1].scope += 1; rejected(p, s); p = made.proof;
    p.terms[2].literal = 4294967294; rejected(p, s); p = made.proof;
    p.terms[3].base = 1; rejected(p, s); p = made.proof;
    p.nodes[0].rule = 2; rejected(p, s); p = made.proof;
    p.nodes[1].right = 1; rejected(p, s); p = made.proof;
    p.nodes[2].left = 2; rejected(p, s); p = made.proof;
    p.nodes[2].prior1 = 0; rejected(p, s); p = made.proof;
    p.nodes[2].prior1 = 3; rejected(p, s); p = made.proof;
    p.nodes[2].prior2 = 999; rejected(p, s); p = made.proof;
    p.nodes[2].operation_result = 3; rejected(p, s); p = made.proof;
    p.nodes[2].operation_version += 1; rejected(p, s); p = made.proof;
    p.nodes[2].scope += 1; rejected(p, s);
    var other = s;
    other.parameter_version += 1;
    rejected(made.proof, other);

    var wrong = s;
    wrong.zero_literal = 1;
    var bad_work = add_proof::Work {};
    let nonzero = add_proof::build(wrong, bad_work);
    assert(nonzero.status == 1 && nonzero.proof.schema == 0);
    wrong = s; wrong.zero = wrong.parameter;
    assert(add_proof::build(wrong, bad_work).status == 1);
    wrong = s; wrong.operation = 2;
    assert(add_proof::build(wrong, bad_work).status == 1);
    wrong = s; wrong.owner = 0;
    assert(add_proof::build(wrong, bad_work).status == 1);

    // Exact-at-limit success and first failing extension for all four limits.
    var exact = add_proof::Work { terms: 4092, edges: 16379,
        proof_visits: 65526, semantic_visits: 1048566 };
    assert(add_proof::build(s, exact).status == 0);
    assert(exact.terms == 4096 && exact.edges == 16384 &&
           exact.proof_visits == 65536 && exact.semantic_visits == 1048576);
    var term_full = add_proof::Work { terms: 4093 };
    let term_fail = add_proof::build(s, term_full);
    assert(term_fail.status == 2 && term_full.limit_quantity == 1 && term_fail.proof.schema == 0 && term_full.terms == 4096);
    var edge_full = add_proof::Work { edges: 16380 };
    let edge_fail = add_proof::build(s, edge_full);
    assert(edge_fail.status == 2 && edge_full.limit_quantity == 2 && edge_fail.proof.schema == 0 && edge_full.edges == 16384);
    var proof_full = add_proof::Work { proof_visits: 65527 };
    assert(add_proof::build(s, proof_full).status == 2 && proof_full.limit == 2 && proof_full.limit_quantity == 3 && proof_full.proof_visits == 65536);
    var semantic_full = add_proof::Work { semantic_visits: 1048567 };
    assert(add_proof::build(s, semantic_full).status == 3 && semantic_full.limit == 3 && semantic_full.limit_quantity == 4 && semantic_full.semantic_visits == 1048576);
    var validation_exact = add_proof::Work { terms: 4, edges: 5, proof_visits: 65526, semantic_visits: 1048566 };
    assert(add_proof::validate(made.proof, s, validation_exact).status == 0);
    var validation_over = add_proof::Work { terms: 4, edges: 5, proof_visits: 65527 };
    assert(add_proof::validate(made.proof, s, validation_over).status == 2);
    var validation_semantic = add_proof::Work { terms: 4, edges: 5, semantic_visits: 1048567 };
    assert(add_proof::validate(made.proof, s, validation_semantic).status == 3);
    var both = add_proof::Work { terms: 4096, edges: 16384, proof_visits: 65536, semantic_visits: 1048576 };
    assert(add_proof::build(s, both).status == 3 && both.limit == 3 && both.limit_quantity == 4);
    var malformed = add_proof::Work { terms: 4097 };
    assert(add_proof::build(s, malformed).status == 2);
    print("checked addition evidence laws passed");
}
