import tests.frontend_lifecycle_test;
import tests.frontend_limits_test;

fn test_frontend_guarded_successor_work() {
    for count in [8, 10] {
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
            print("WORK guarded successors ", count, " proof=", work.proof_visits, " semantic=", work.visits, " receipt=", receipt);
            assert(work.proof_visits < (if count == 8 { 20000 } else { 40000 })); assert(receipt != 0 && receipt < 45000);
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
