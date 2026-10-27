import tests.frontend_lifecycle_test;
import tests.frontend_limits_test;

fn test_frontend_guarded_successor_work() {
    for count in [8, 10, 16] {
        var source: u8[>..] = []; source.append("pub let run: U32 -> U32 ! {} resources {depth:1,frame:0} = fn x => do:\n  let v0 = x\n");
        for i in count {
            for indent in i + 1 { source.append("  "); } source.append(str("if v", i, "<4294967295:\n"));
            for indent in i + 2 { source.append("  "); } source.append(str("let v", i + 1, " = v", i, "+1\n"));
        }
        for indent in count + 1 { source.append("  "); } source.append(str("return v", count, "\n"));
        var i = count; while i > 0 { i--; for indent in i + 1 { source.append("  "); } source.append("else:\n"); for indent in i + 2 { source.append("  "); } source.append(str("return v", i, "\n")); }
        with_core() { b =>
            var work = Work { .. }; var diagnostics: Diagnostic[>..] = [];
            let ok = frontend_complete(source, "guarded-successor-work", b, work, diagnostics);
            if !ok { for d in diagnostics { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok && !work.exhausted);
            var receipt: u64 = 0; for row in b.receipts { if row.producer != 0 { receipt = row.completed_visits; } }
            print("WORK guarded successors ", count, " proof=", work.proof_visits, " semantic=", work.visits, " receipt=", receipt, " facts=", b.facts.len - 1, " evidence=", b.evidence.len - 1);
            assert(work.proof_visits < (if count == 8 { 4000 } else if count == 10 { 6000 } else { 15000 })); assert(receipt != 0 && receipt < 45000);
            assert(build_plans(b, "", diagnostics)); assert(canonical_schemas(b, diagnostics)); assert(seal_completion(b));
            var validation = Work { .. }; let valid = validator::validate_core(core_view(b), 0, validation, diagnostics);
            if !valid { for d in diagnostics { print("validation ", d.code, " ", d.origin, " ", d.related); } } assert(valid);
        }
    }
    frontend_planned("let bad: U32 -> U32 = fn x => return x+1\n", false, FE_ARITHMETIC);
    frontend_planned("let bad: (U32,U32) -> U32 = fn (x,y) => do:\n  if x<4294967295:\n    return y+1\n  return y\n", false, FE_ARITHMETIC);
}

fn test_frontend_literal_equality_order_transport() {
    // Literal graph edges must work even when their terms were created after
    // the unknown endpoints; recursive rank-decreasing rewriting cannot help.
    with_frontend_proofs() { b, work, budget, index =>
        let x = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 1, .. });
        let y = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 2, .. });
        let one = proof_term(b, work, budget, index, Term { tag: EXPR_LITERAL, literal: 1, .. });
        let two = proof_term(b, work, budget, index, Term { tag: EXPR_LITERAL, literal: 2, .. });
        let sum = proof_term(b, work, budget, index, Term { tag: EXPR_ADD, args: ref_span(b, [one, one]), .. });
        let eq_x = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: x, right: one, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let eq_y = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: y, right: two, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let eq_sum = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: y, right: sum, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        assert(proof_query(b, work, budget, index, 0, [eq_x], Fact { tag: FACT_LT, left: x, right: two, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_y], Fact { tag: FACT_LT, left: one, right: y, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_LT, left: x, right: y, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_sum], Fact { tag: FACT_LT, left: x, right: y, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_LT, left: y, right: x, .. }) == 0);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_LE, left: y, right: x, .. }) == 0);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_EQ, left: x, right: y, .. }) == 0);
        let eq_two = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: two, right: x, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        assert(proof_query(b, work, budget, index, 0, [eq_two, eq_sum], Fact { tag: FACT_EQ, left: x, right: y, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_two, eq_sum], Fact { tag: FACT_EQ, left: y, right: x, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [eq_two, eq_sum], Fact { tag: FACT_LT, left: x, right: y, .. }) == 0);
        let complement_x = proof_term(b, work, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [x]), .. });
        let complement_y = proof_term(b, work, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [y]), .. });
        let strict_complements = proof_evidence(b, work, budget, index, Fact { tag: FACT_LT, left: complement_y, right: complement_x, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let weak_complements = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: complement_y, right: complement_x, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        assert(proof_query(b, work, budget, index, 0, [strict_complements], Fact { tag: FACT_LT, left: x, right: y, .. }) != 0);
        assert(proof_query(b, work, budget, index, 0, [strict_complements], Fact { tag: FACT_EQ, left: x, right: y, .. }) == 0);
        assert(proof_query(b, work, budget, index, 0, [weak_complements], Fact { tag: FACT_EQ, left: x, right: y, .. }) == 0);
        assert(!work.exhausted);
    }
    frontend_planned("pub let one: U32 -> U32 ! {} requires [Eq(arg,1)] ensures [Lt(result,2)] resources {depth:1,frame:0} = fn x => return x\n", true, 0);
    frontend_planned("pub let ordered: (U32,U32) -> (U32,U32) ! {} requires [Eq(arg.0,1),Eq(arg.1,2)] ensures [Lt(result.0,result.1)] resources {depth:1,frame:256} = fn pair => return pair\n", true, 0);
    frontend_planned("pub let compound: U32 -> U32 ! {} requires [Eq(MAX-4294967294,arg)] ensures [Lt(result,2)] resources {depth:1,frame:0} = fn x => return x\n", true, 0);
    frontend_planned("pub let compound: U32 -> U32 ! {} requires [Eq(arg,MAX-4294967294)] ensures [Lt(result,2)] resources {depth:1,frame:0} = fn x => return x\n", true, 0);
    frontend_planned("pub let compounds: (U32,U32) -> (U32,U32) ! {} requires [Eq(arg.0,MAX-4294967294),Eq(arg.1,MAX-4294967293)] ensures [Lt(result.0,result.1)] resources {depth:1,frame:256} = fn pair => return pair\n", true, 0);
    frontend_planned("pub let equal: U32 -> U32 ! {} requires [Eq(arg,MAX-4294967293)] ensures [Eq(result,2)] resources {depth:1,frame:0} = fn x => return x\n", true, 0);
    frontend_planned("let bad: U32 -> U32 ! {} requires [Eq(arg,MAX-4294967294)] ensures [Lt(result,1)] resources {depth:1,frame:0} = fn x => return x\n", false, FE_CONTRACT);
    frontend_planned("let bad: U32 -> U32 ! {} requires [Eq(arg,MAX-4294967294)] ensures [Le(2,result)] resources {depth:1,frame:0} = fn x => return x\n", false, FE_CONTRACT);
    frontend_planned("let bad: U32 -> U32 ! {} requires [Eq(arg,MAX-4294967294)] ensures [Eq(result,2)] resources {depth:1,frame:0} = fn x => return x\n", false, FE_CONTRACT);
}

fn test_frontend_strict_cycle_components() {
    with_frontend_proofs() { b, work, budget, index =>
        let x = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 1, .. });
        let y = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 2, .. });
        let z = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 3, .. });
        let p = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 4, .. });
        let q = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 5, .. });
        let xy = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: x, right: y, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let yz = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: y, right: z, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let zx = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: z, right: x, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let pq = proof_evidence(b, work, budget, index, Fact { tag: FACT_LT, left: p, right: q, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let strict = proof_evidence(b, work, budget, index, Fact { tag: FACT_LT, left: x, right: y, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        // A weak cycle permits equality; a disconnected strict edge does not
        // turn it into a contradiction. A strict edge inside the SCC does.
        assert(proof_cycle(b, work, budget, index, 0, [xy, yz, zx]) == 0);
        assert(proof_cycle(b, work, budget, index, 0, [pq, xy, yz, zx]) == 0);
        assert(proof_cycle(b, work, budget, index, 0, [pq, strict, yz]) == 0);
        let cycle = proof_cycle(b, work, budget, index, 0, [pq, strict, yz, zx]);
        assert(cycle != 0); let contradiction = b.facts[b.evidence[cycle].fact];
        assert(contradiction.tag == FACT_LT && contradiction.left == x && contradiction.right == x);
        // A subsequent smaller active set cannot inherit the old SCC result.
        assert(proof_cycle(b, work, budget, index, 0, [pq, xy, yz, zx]) == 0);
        assert(!work.exhausted);
        var depleted = work; depleted.proof_visits = budget.visits_start + LIMIT_PROOF_VISITS;
        assert(proof_cycle(b, depleted, budget, index, 0, [strict, yz, zx]) == 0 && depleted.exhausted);
    };
    frontend_planned("pub let cycle: (U32,U32,U32) -> U32 ! {} resources {depth:1,frame:128} = fn (x,y,z) => do:\n  if x<y:\n    if y<=z:\n      if z<=x:\n        return x+4294967295\n      return x\n    return y\n  return z\n", true, 0);
    frontend_planned("let weak: (U32,U32,U32) -> U32 ! {} resources {depth:1,frame:128} = fn (x,y,z) => do:\n  if x<=y:\n    if y<=z:\n      if z<=x:\n        return x+4294967295\n      return x\n    return y\n  return z\n", false, FE_ARITHMETIC);
    print("PROOF strict SCC cycles retain exact active-set contradiction evidence and bounded work");
}

fn test_frontend_lazy_proof_evidence() {
    with_frontend_proofs() { b, work, budget, index =>
        let x = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 1, .. });
        let y = proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: 2, .. });
        let one = proof_term(b, work, budget, index, Term { tag: EXPR_LITERAL, literal: 1, .. });
        let two = proof_term(b, work, budget, index, Term { tag: EXPR_LITERAL, literal: 2, .. });
        let eq_x = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: x, right: one, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let eq_y = proof_evidence(b, work, budget, index, Fact { tag: FACT_EQ, left: y, right: two, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let strict = proof_evidence(b, work, budget, index, Fact { tag: FACT_LT, left: x, right: y, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let complement = proof_term(b, work, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [x]), .. });
        let fits = proof_evidence(b, work, budget, index, Fact { tag: FACT_ADD_FITS, left: x, right: y, .. }, RULE_ASSUMPTION, 0, 0, [], []);
        let kept = b.evidence.len; let facts = b.facts.len;
        // Both graphs contain valid deferred derivations, but no requested
        // strict path or contradiction. Scratch recipes must not become Core.
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_LT, left: y, right: x, .. }) == 0);
        assert(proof_cycle(b, work, budget, index, 0, [strict, eq_x, eq_y]) == 0);
        assert(proof_query(b, work, budget, index, 0, [fits], Fact { tag: FACT_LT, left: y, right: complement, .. }) == 0);
        assert(b.evidence.len == kept && b.facts.len == facts && !work.exhausted);
        let result = proof_query(b, work, budget, index, 0, [fits], Fact { tag: FACT_LE, left: y, right: complement, .. });
        assert(result != 0); var symmetry = false; var derived = false;
        for row in b.evidence[kept..] { if row.rule == RULE_ADD_SYMMETRY { symmetry = true; } if row.rule == RULE_ADD_FROM_COMPLEMENT { derived = true; } }
        assert(symmetry && derived);
        let before = b.evidence.len; index.counts[budget.id].edges = LIMIT_FACT_EDGES;
        assert(proof_cycle(b, work, budget, index, 0, [strict, eq_x, eq_y]) == 0 && !work.exhausted && b.evidence.len == before);
        assert(proof_query(b, work, budget, index, 0, [eq_x, eq_y], Fact { tag: FACT_LT, left: x, right: y, .. }) == 0 && work.exhausted && b.evidence.len == before);
    };
    // Success publishes ordinary rule DAGs that the independent validator must
    // check, including the two-step symmetry/complement recipe.
    frontend_planned("pub let fits: (U32,U32) -> U32 ! {} requires [AddFits(arg.0,arg.1)] ensures [Le(result,MAX-arg.0)] resources {depth:1,frame:256} = fn (x,y) => return y\n", true, 0);
    frontend_planned("pub let subtract: (U32,U32) -> U32 ! {} requires [SubFits(arg.0,arg.1)] ensures [Le(arg.1,result)] resources {depth:1,frame:256} = fn (x,y) => return x\n", true, 0);
    frontend_planned("pub let complement: (U32,U32) -> U32 ! {} requires [Lt(MAX-arg.1,MAX-arg.0)] ensures [Lt(result,arg.1)] resources {depth:1,frame:256} = fn (x,y) => return x\n", true, 0);
    frontend_planned("pub let literal_cycle: (U32,U32) -> U32 ! {} resources {depth:1,frame:256} = fn (x,y) => do:\n  if x<y:\n    if y<=1:\n      if x>=2:\n        return x+4294967295\n      return x\n    return y\n  return 0\n", true, 0);
    print("PROOF failed and acyclic queries publish no unused evidence; successful recipes retain exact validated prerequisites and caps");
}

fn test_frontend_tarjan_component_boundaries() {
    with_frontend_proofs() { b, work, budget, index =>
        var terms: u32[>..] = [];
        for i in 7 { terms.push(proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: i as u32 + 1, .. })); }
        var active: u32[>..] = [];
        // Two weak components merge through non-tree/back/cross edges. A
        // strict edge into the final weak component must not merge it too.
        for pair in [[0 as u32, 1], [1 as u32, 2], [2 as u32, 0], [0 as u32, 2], [0 as u32, 3], [3 as u32, 4], [4 as u32, 3], [4 as u32, 1], [5 as u32, 6], [6 as u32, 5]] {
            active.push(proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: terms[pair[0]], right: terms[pair[1]], .. }, RULE_ASSUMPTION, 0, 0, [], []));
        }
        let strict = proof_evidence(b, work, budget, index, Fact { tag: FACT_LT, left: terms[4], right: terms[5], .. }, RULE_ASSUMPTION, 0, 0, [], []); active.push(strict);
        let evidence = b.evidence.len; let facts = b.facts.len;
        assert(proof_cycle(b, work, budget, index, 0, active) == 0 && !work.exhausted);
        assert(b.evidence.len == evidence && b.facts.len == facts);
        let closing = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: terms[6], right: terms[2], .. }, RULE_ASSUMPTION, 0, 0, [], []); active.push(closing);
        let result = proof_cycle(b, work, budget, index, 0, active); assert(result != 0);
        let fact = b.facts[b.evidence[result].fact]; assert(fact.tag == FACT_LT && fact.left == terms[4] && fact.right == terms[4]);
        active.resize(active.len - 1); assert(proof_cycle(b, work, budget, index, 0, active) == 0 && !work.exhausted);
    };
    var previous: u64 = 0;
    for count in [64, 256, 512] {
        with_frontend_proofs() { b, work, budget, index =>
            var terms: u32[>..] = []; var active: u32[>..] = [];
            for i in count { terms.push(proof_term(b, work, budget, index, Term { tag: EXPR_BINDER, binder: i as u32 + 1, .. })); }
            for i in 1..count { active.push(proof_evidence(b, work, budget, index, Fact { tag: if i == 1 { FACT_LT } else { FACT_LE }, left: terms[i - 1], right: terms[i], .. }, RULE_ASSUMPTION, 0, 0, [], [])); }
            let before = work.proof_visits; let evidence = b.evidence.len;
            assert(proof_cycle(b, work, budget, index, 0, active) == 0 && !work.exhausted);
            let visits = work.proof_visits - before; assert(b.evidence.len == evidence && visits < count as u64 * 18);
            if previous != 0 { assert(visits < previous * (if count == 256 { 5 } else { 3 })); } previous = visits;
            let closing = proof_evidence(b, work, budget, index, Fact { tag: FACT_LE, left: terms[terms.len - 1], right: terms[0], .. }, RULE_ASSUMPTION, 0, 0, [], []); active.push(closing);
            let cycle = proof_cycle(b, work, budget, index, 0, active); assert(cycle != 0 && !work.exhausted);
            let fact = b.facts[b.evidence[cycle].fact]; assert(fact.tag == FACT_LT && fact.left == terms[0] && fact.right == terms[0]);
            print("WORK forward SCC chain ", count, " acyclic=", visits, " total=", work.proof_visits);
            var depleted = work; depleted.proof_visits = budget.visits_start + LIMIT_PROOF_VISITS;
            assert(proof_cycle(b, depleted, budget, index, 0, active) == 0 && depleted.exhausted);
        };
    }
    print("PROOF forward SCC traversal handles finished components, cross edges, deep bounded stacks and exhausted budgets");
}
