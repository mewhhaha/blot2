import tests.frontend_test;
fn with_frontend_proofs<F>() { with_core() { b =>
    var terms = KeyIndex<ProofTermKey> {}; var facts = KeyIndex<Fact> {}; var seen = KeyIndex<ProofSeenKey> {}; var counts: ProofCounts[>..] = [];
    let index = ProofIndex { terms: terms, facts: facts, seen: seen, counts: counts }; var work = Work { .. }; let budget = proof_budget(b, work, index); F(b, work, budget, index);
} }
fn test_frontend_type_demand_boundary() {
    with_frontend_proofs() { b, w, budget, index =>
        for i in 8192 { assert(proof_track(w, budget, index, 3, i as u32 + 1)); }
        assert(index.counts[budget.id].types == 8192 && !w.exhausted);
        assert(proof_track(w, budget, index, 3, 1)); assert(index.counts[budget.id].types == 8192);
        assert(!proof_track(w, budget, index, 3, 8193) && w.exhausted);
        w.exhausted = false; let next = proof_budget(b, w, index); for i in 8192 { assert(proof_track(w, next, index, 3, i as u32 + 1)); } assert(index.counts[next.id].types == 8192 && !w.exhausted);
    }
}
fn test_frontend_proof_term_boundary() {
    with_frontend_proofs() { b, w, budget, index =>
        for i in 4096 { assert(proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, literal: i as u32, .. }) != 0); }
        assert(index.counts[budget.id].terms == 4096 && !w.exhausted);
        assert(proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, literal: 0, .. }) != 0); assert(index.counts[budget.id].terms == 4096);
        assert(proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, literal: 4096, .. }) == 0 && w.exhausted);
        w.exhausted = false; let next = proof_budget(b, w, index); for i in 4096 { assert(proof_term(b, w, next, index, Term { tag: EXPR_LITERAL, literal: i as u32, .. }) != 0); } assert(index.counts[next.id].terms == 4096 && !w.exhausted);
    }
}
fn test_frontend_fact_evidence_boundary() {
    with_frontend_proofs() { b, w, budget, index =>
        let zero = proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, .. }); let fact = Fact { tag: FACT_EQ, left: zero, right: zero, .. };
        for i in 16383 { assert(proof_evidence(b, w, budget, index, fact, RULE_REFLEXIVE, 0, 0, [], []) != 0); }
        assert(index.counts[budget.id].edges == 16384 && !w.exhausted);
        assert(proof_fact(b, w, budget, index, fact) != 0); assert(index.counts[budget.id].edges == 16384);
        assert(proof_evidence(b, w, budget, index, fact, RULE_REFLEXIVE, 0, 0, [], []) == 0 && w.exhausted);
    }
}
fn test_frontend_proof_visit_boundary() {
    with_frontend_proofs() { b, w, budget, index =>
        let zero = proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, .. }); let complement = proof_term(b, w, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [zero]), .. }); let root = proof_term(b, w, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [complement]), .. });
        while w.proof_visits < 65533 { assert(proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, .. }) == zero); }
        let value, ok = proof_literal_value(b, w, budget, index, root, 0); assert(ok && value == 0 && w.proof_visits == 65536 && !w.exhausted);
        let ignored, overflow = proof_literal_value(b, w, budget, index, zero, 0); assert(!overflow && w.exhausted);
    }
}
fn test_frontend_semantic_visit_boundary() {
    with_frontend_proofs() { b, w, budget, index =>
        let zero = proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, .. }); let complement = proof_term(b, w, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [zero]), .. }); let root = proof_term(b, w, budget, index, Term { tag: EXPR_MAX_MINUS, args: ref_span(b, [complement]), .. });
        assert(charge(w, 1048576 - w.visits - 3, 1048576)); let value, ok = proof_literal_value(b, w, budget, index, root, 0); assert(ok && value == 0 && w.visits == 1048576 && !w.exhausted);
        let ignored, overflow = proof_literal_value(b, w, budget, index, zero, 0); assert(!overflow && w.exhausted);
    }
}
fn test_frontend_syntax_and_binder_boundaries() {
    for excessive in 2 {
        var nested: u8[>..] = []; nested.append("static let value: U32 = "); for i in 64 + excessive { nested.push('('); } nested.push('0'); for i in 64 + excessive { nested.push(')'); } nested.push('\n');
        if excessive == 0 { frontend_parse_ok(nested); } else { frontend_parse_reject(nested, "k1_source_limit"); }
        var binders: u8[>..] = []; binders.append("let identity: forall ["); for i in 32 + excessive { if i != 0 { binders.push(','); } binders.append(str("T", i, ":Type")); } binders.append("] => Unit -> Unit ! {} resources {depth:1,frame:0} = fn () => return ()\n");
        if excessive == 0 { frontend_semantic_law(binders, 0); } else { frontend_semantic_law(binders, FE_SOURCE_LIMIT); }
    }
}
fn test_frontend_block_boundary() {
    for excessive in 2 {
        var source: u8[>..] = []; source.append("let run: Bool -> Unit = fn flag => do:\n");
        for i in 1365 + excessive { source.append("  if flag:\n    ()\n  else:\n    ()\n"); } source.append("  return ()\n");
        with_core() { b => var w = Work { .. }; var ds: Diagnostic[>..] = []; let ok = frontend_complete(source, "block-boundary", b, w, ds);
            if excessive == 0 { if !ok { for d in ds { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok); assert(b.blocks.len - 1 == 4096); }
            else { assert(!ok && ds.len != 0 && ds[ds.len - 1].code == FE_CORE_LIMIT); }
        }
    }
}
fn test_frontend_nested_blocks_share_declaration_limit() {
    for excessive in 2 {
        var source: u8[>..] = []; source.append("let run: Unit -> Unit = fn () => do:\n  let inner = fn (flag:Bool) => do:\n");
        for i in 1364 { source.append("    if flag:\n      ()\n    else:\n      ()\n"); }
        source.append("    let _ = do:\n      break ()\n    return ()\n");
        if excessive != 0 { source.append("  let extra = fn (u:Unit) => return ()\n"); } source.append("  return ()\n");
        with_core() { b => var w = Work { .. }; var ds: Diagnostic[>..] = []; let ok = frontend_complete(source, "nested-block-limit", b, w, ds);
            if excessive == 0 { if !ok { for d in ds { print(d.code, " ", name_bytes(core_view(b), d.detail)); } } assert(ok && b.blocks.len - 1 == 4096); }
            else { assert(!ok && ds.len != 0 && ds[ds.len - 1].code == FE_CORE_LIMIT); }
        }
    }
}
