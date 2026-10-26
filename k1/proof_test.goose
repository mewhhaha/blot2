import proof;

fn symbolic(n: u32, version: u32) -> proof::Term {
    return proof::Term { 1, 0, n, version, 7 };
}
fn main() {
    var a = proof::Arena { scope: 9 };
    let x = proof::intern(a, symbolic(1, 0));
    let y = proof::intern(a, symbolic(2, 0));
    let z = proof::intern(a, symbolic(3, 0));
    let old_x = proof::intern(a, symbolic(1, 1));
    assert(x.status == 0 && y.status == 0 && z.status == 0 && old_x.status == 0);
    assert(proof::intern(a, symbolic(1, 0)).id == x.id);
    assert(old_x.id != x.id);
    assert(proof::intern(a, proof::Term { 0, 0, 7, 1, 0 }).status == 1);
    assert(proof::query_le(a, 0, x.id, false).status == 1);
    assert(proof::add_le(a, x.id, 999, false).status == 1);
    assert(proof::has_path(a, 0, x.id, false).status == 1);
    assert(proof::position(a, 0, x.id).status == 1);
    assert(proof::validate_evidence(a, 0).status == 1);
    assert(proof::add_le(a, x.id, y.id, false).status == 0);
    assert(proof::add_le(a, y.id, z.id, true).status == 0);
    let answer = proof::query_le(a, x.id, z.id, true);
    assert(answer.status == 0 && answer.visits > 0);
    assert(proof::validate_evidence(a, answer.id).status == 0);
    assert(proof::query_le(a, x.id, y.id, true).status == 3);
    assert(proof::query_le(a, old_x.id, z.id, false).status == 3);
    let old_edge_count = a.edges.len;
    let old_evidence_count = a.evidence.len;
    assert(proof::add_le(a, z.id, x.id, false).status == 1); // strict cycle
    assert(a.edges.len == old_edge_count && a.evidence.len == old_evidence_count);
    assert(proof::add_eq(a, x.id, z.id).status == 1); // conflicts with strict path
    let eq = proof::add_eq(a, x.id, old_x.id);
    assert(eq.status == 0);
    let self_eq = proof::add_eq(a, y.id, y.id);
    assert(self_eq.status == 0 && proof::validate_evidence(a, self_eq.id).status == 0);
    assert(proof::canonical(a, old_x.id).id == x.id);
    let equality = proof::query_le(a, old_x.id, x.id, false);
    assert(equality.status == 0 && proof::validate_evidence(a, equality.id).status == 0);
    let literal0 = proof::intern(a, proof::Term { 0, 0, 0, 0, 0 });
    let literal1 = proof::intern(a, proof::Term { 0, 0, 1, 0, 0 });
    let literal_fact = proof::query_le(a, literal0.id, literal1.id, true);
    assert(literal_fact.status == 0 && proof::validate_evidence(a, literal_fact.id).status == 0);
    assert(proof::query_le(a, literal1.id, literal0.id, false).status == 3);
    assert(proof::add_le(a, literal1.id, x.id, false).status == 1);
    a.evidence[answer.id - 1].scope = 10;
    assert(proof::validate_evidence(a, answer.id).status == 1);
    a.evidence[answer.id - 1].scope = 9;
    a.evidence[answer.id - 1].prior = answer.id; // cyclic/forward evidence
    assert(proof::validate_evidence(a, answer.id).status == 1);
    test_corruption();
    test_limits();
    print("proof graph laws passed");
}

fn test_limits() {
    var a = proof::Arena { scope: 5 };
    let x = proof::intern(a, symbolic(10, 0));
    let y = proof::intern(a, symbolic(11, 0));
    while true {
        let q = proof::query_le(a, x.id, y.id, false);
        if q.status == 2 { break; }
        assert(q.status == 3 && q.visits == 5);
    }
    let exhausted = proof::query_le(a, x.id, y.id, false);
    assert(exhausted.status == 2 && exhausted.visits == 0 && a.visits == 65536);
    var full = proof::Arena { scope: 3 };
    for i in 4096 {
        assert(proof::intern(full, symbolic(i as u32, 0)).status == 0);
    }
    assert(proof::intern(full, symbolic(10000, 0)).status == 2);
    assert(full.terms.len == 4096);
    var facts = proof::Arena { scope: 8 };
    let only = proof::intern(facts, symbolic(30, 0));
    for i in 16383 { facts.evidence.push(proof::Evidence { 1, only.id, only.id, false, 0, 0, 8 }); }
    assert(proof::query_le(facts, only.id, only.id, false).status == 0);
    assert(facts.evidence.len == 16384);
    assert(proof::query_le(facts, only.id, only.id, false).status == 2);
    assert(facts.evidence.len == 16384);
}

fn test_corruption() {
    var duplicate = proof::Arena { scope: 1 };
    let key = symbolic(5, 0);
    let original = proof::intern(duplicate, key);
    for i in 8192 { duplicate.slots[i] = 0; }
    let forged = proof::intern(duplicate, key);
    assert(forged.id != original.id);
    assert(proof::add_le(duplicate, original.id, forged.id, true).status == 1);
    let invalid = proof::query_le(duplicate, original.id, forged.id, true);
    assert(invalid.status == 1);
    assert(proof::validate_evidence(duplicate, invalid.id).status == 1);
    var a = proof::Arena { scope: 4 };
    let x = proof::intern(a, symbolic(20, 0));
    let y = proof::intern(a, symbolic(21, 0));
    let assumption = proof::add_le(a, x.id, y.id, false);
    assert(assumption.status == 0);
    a.edges[0].next = 1;
    assert(proof::query_le(a, x.id, y.id, false).status == 1); // linked cycle
    a.edges[0].next = 999;
    assert(proof::query_le(a, x.id, y.id, false).status == 1);
    a.edges[0].next = 0;
    a.edges[0].to = 999;
    assert(proof::query_le(a, x.id, y.id, false).status == 1);
    a.edges[0].to = y.id;
    a.parents[x.id - 1] = y.id;
    a.parents[y.id - 1] = x.id;
    assert(proof::canonical(a, x.id).status == 1);
    assert(proof::query_le(a, x.id, y.id, false).status == 1);
    a.parents[x.id - 1] = 999;
    assert(proof::canonical(a, x.id).status == 1);
    a.parents[x.id - 1] = x.id;
    a.parents[y.id - 1] = y.id;
    a.parents[y.id - 1] = x.id; // smaller but unsupported by equality facts
    assert(proof::canonical(a, y.id).status == 1);
    let before = a.edges.len;
    assert(proof::add_eq(a, y.id, x.id).status == 1);
    assert(a.edges.len == before);
    a.parents[y.id - 1] = y.id;
    a.evidence[assumption.id - 1].edge = 999;
    assert(proof::validate_evidence(a, assumption.id).status == 1);
    var b = proof::Arena { scope: 6 };
    let first = proof::intern(b, symbolic(31, 0));
    let second = proof::intern(b, symbolic(32, 0));
    assert(proof::add_eq(b, first.id, second.id).status == 0);
    b.edges[0].strict = true;
    b.evidence[b.edges[0].evidence - 1].strict = true;
    assert(proof::query_le(b, first.id, second.id, true).status == 1);
    assert(proof::canonical(b, second.id).status == 1);
    b.edges[0].strict = false;
    b.evidence[b.edges[0].evidence - 1].strict = false;
    let lit = proof::intern(b, proof::Term { 0, 0, 9, 0, 0 });
    b.edges[0].to = lit.id;
    b.evidence[b.edges[0].evidence - 1].right = lit.id;
    assert(proof::query_le(b, first.id, lit.id, false).status == 1);
}
