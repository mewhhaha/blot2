// Deterministic finite proof queries. Evidence remains explicit for independent validation.
import .model;
import .intern;
struct ProofTermKey { tag: u32, type_id: u32, value: u32, binder: u32, literal: u32, version: u32, scope: u32, args: u32[..4] }
struct ProofSeenKey { budget: u32, kind: u32, id: u32 }
struct ProofCounts { terms: u32, edges: u32, types: u32, owned_head: u32 }
struct ProofIndex { terms: KeyIndex<ProofTermKey>&, facts: KeyIndex<Fact>&, seen: KeyIndex<ProofSeenKey>&, counts: ProofCounts[>..]& }
fn hash(key: ProofTermKey) -> u64 { var h: u64 = 0; for word in [key.tag, key.type_id, key.value, key.binder, key.literal, key.version, key.scope] { h = hash_combine(h, hash(word)); } for word in key.args { h = hash_combine(h, hash(word)); } return h; }
fn hash(key: Fact) -> u64 { var h: u64 = 0; for word in [key.tag, key.left, key.right, key.third, key.domain, key.version] { h = hash_combine(h, hash(word)); } return h; }
fn hash(key: ProofSeenKey) -> u64 { hash_combine(hash(key.budget), hash_combine(hash(key.kind), hash(key.id))) }
fn proof_key(b: CoreBuilder, t: Term) -> ProofTermKey { var key = ProofTermKey { tag: t.tag, type_id: t.type_id, value: t.value, binder: t.binder, literal: t.literal, version: t.version, scope: t.scope, .. }; for i in t.args.count { key.args.push(b.refs[t.args.start + i]); } return key; }
fn proof_index_load(b: CoreBuilder, index: ProofIndex) { for t, id in b.terms { if id != 0 { key_index_insert(index.terms, proof_key(b, t), id as u32); } } for f, id in b.facts { if id != 0 { key_index_insert(index.facts, f, id as u32); } } }
struct ProofBudget { terms_start: u32, edges_start: u32, visits_start: u64, semantic_start: u64, id: u32 }
fn proof_budget(b: CoreBuilder, w: Work&, index: ProofIndex) -> ProofBudget { let id = index.counts.len as u32; index.counts.push(ProofCounts { .. }); return ProofBudget { terms_start: b.terms.len as u32, edges_start: (b.facts.len + b.evidence.len) as u32, visits_start: w.proof_visits, semantic_start: w.visits, id: id }; }
fn proof_track(w: Work&, budget: ProofBudget, index: ProofIndex, kind: u32, id: u32) -> bool { let key = ProofSeenKey { budget: budget.id, kind: kind, id: id }; if key_index_get(index.seen, key) != 0 { return true; } var rank: u32 = 0; if kind == 1 { index.counts[budget.id].terms++; rank = index.counts[budget.id].terms; if rank > LIMIT_TERMS { w.exhausted = true; return false; } } else if kind == 3 { index.counts[budget.id].types++; rank = index.counts[budget.id].types; if rank > LIMIT_TYPES { w.exhausted = true; return false; } } else { index.counts[budget.id].edges++; rank = index.counts[budget.id].edges; if rank > LIMIT_FACT_EDGES { w.exhausted = true; return false; } } key_index_insert(index.seen, key, rank); return true; }
fn proof_rank(index: ProofIndex, budget: ProofBudget, id: u32) -> u32 { key_index_get(index.seen, ProofSeenKey { budget: budget.id, kind: 1, id: id }) }
recursive fn proof_demand(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, id: u32) -> bool { if id == 0 { return true; } if proof_rank(index, budget, id) != 0 { return true; } if !proof_charge(w, budget, 1) || !proof_track(w, budget, index, 1, id) { return false; } let t = b.terms[id]; for i in t.args.count { if !proof_demand(b, w, budget, index, b.refs[t.args.start + i]) { return false; } } return true; }
fn proof_charge(w: Work&, budget: ProofBudget, n: u64) -> bool {
    if w.proof_visits - budget.visits_start > LIMIT_PROOF_VISITS || n > LIMIT_PROOF_VISITS - (w.proof_visits - budget.visits_start) { w.exhausted = true; return false; }
    if !charge(w, n, budget.semantic_start + LIMIT_VISITS) { return false; }
    w.proof_visits += n; return true;
}
fn proof_term(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, term: Term) -> u32 {
    if !proof_charge(w, budget, 1 + term.args.count) { return 0; } let key = proof_key(b, term); var id: u32 = 0; id = key_index_get(index.terms, key);
    if id == 0 { if !allocation(w) { return 0; } id = b.terms.len as u32; b.terms.push(term); key_index_insert(index.terms, key, id); }
    if !proof_track(w, budget, index, 1, id) { return 0; } return id;
}
fn proof_fact_equal(a: Fact, b: Fact) -> bool { a.tag == b.tag && a.left == b.left && a.right == b.right && a.third == b.third && a.domain == b.domain && a.version == b.version }
fn proof_fact(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, fact: Fact) -> u32 {
    if !proof_charge(w, budget, 1) { return 0; } var id: u32 = 0; id = key_index_get(index.facts, fact);
    if id == 0 { if !allocation(w) { return 0; } id = b.facts.len as u32; b.facts.push(fact); key_index_insert(index.facts, fact, id); }
    if !proof_track(w, budget, index, 2, id) { return 0; } return id;
}
fn proof_evidence(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, fact: Fact, rule: u32, scope: u32, edge: u32, operands: const u32[:], premises: const u32[:]) -> u32 {
    if !proof_charge(w, budget, 1) { return 0; }
    let f = proof_fact(b, w, budget, index, fact); if f == 0 { return 0; }
    if index.counts[budget.id].edges >= LIMIT_FACT_EDGES || !allocation(w) { w.exhausted = true; return 0; }
    index.counts[budget.id].edges++; let id = b.evidence.len as u32;
    b.evidence.push(Evidence { rule: rule, fact: f, scope: scope, edge: edge, operands: ref_span(b, operands), premises: ref_span(b, premises), .. }); return id;
}
recursive fn proof_literal_value(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, id: u32, depth: u32) -> u64, bool {
    if depth > 64 || !id_ok(id, b.terms.len) || !proof_charge(w, budget, 1) { return 0, false; } let t = b.terms[id];
    if t.tag == EXPR_LITERAL { return t.literal, true; }
    if t.tag == EXPR_MAX_MINUS && t.args.count == 1 { let x, ok = proof_literal_value(b, w, budget, index, b.refs[t.args.start], depth + 1); return MAX_U32 - x, ok; }
    if (t.tag == EXPR_ADD || t.tag == EXPR_SUB) && t.args.count == 2 { let x, xok = proof_literal_value(b, w, budget, index, b.refs[t.args.start], depth + 1); let y, yok = proof_literal_value(b, w, budget, index, b.refs[t.args.start + 1], depth + 1); if !xok || !yok { return 0, false; } if t.tag == EXPR_ADD { if x + y > MAX_U32 { return 0, false; } return x + y, true; } if x < y { return 0, false; } return x - y, true; } return 0, false;
}
fn proof_literal_truth(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, fact: Fact) -> bool {
    let x, xok = proof_literal_value(b, w, budget, index, fact.left, 0); let y, yok = proof_literal_value(b, w, budget, index, fact.right, 0); if !xok || !yok { return false; }
    if fact.tag == FACT_EQ { return x == y; } if fact.tag == FACT_LE { return x <= y; } if fact.tag == FACT_LT { return x < y; }
    if fact.tag == FACT_ADD_FITS { return x + y <= MAX_U32; } if fact.tag == FACT_SUB_FITS { return y <= x; } if fact.tag == FACT_MUL_FITS { return x * y <= MAX_U32; } return false;
}
struct ProofArc { to: u32, evidence: u32, recipe: u32, next: u32, strict: u32 }
// Private derivation plans are lookup scratch, never published evidence. Each
// prerequisite points backward; the sole compound plan is symmetry followed
// by add-complement, so materialization has at most two recipe frames.
struct ProofRecipe { fact: Fact, rule: u32, evidence: u32, prerequisite: u32, materialized: u32 }
struct ProofLiteral { term: u32, value: u64 }
struct ProofWalk { node: u32, next: u32 }
fn proof_order_graph(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, scope: u32, active: const u32[:], wanted: Fact, find_cycle: bool) -> u32 {
    var target = wanted;
    // Sorted adjacency lists and a two-state BFS preserve strictness without
    // materializing transitive pairs. Every examined edge is charged.
    var heads: u32[>..] = []; var arcs: ProofArc[>..] = [ProofArc { .. }]; var recipes: ProofRecipe[>..] = [ProofRecipe { .. }];
    fn defer_evidence(fact: Fact, rule: u32, evidence: u32, prerequisite: u32) -> u32 {
        if !proof_charge(w, budget, 1) { return 0 from proof_order_graph; }
        if recipes.len - 1 >= LIMIT_FACT_EDGES { w.exhausted = true; return 0 from proof_order_graph; }
        assert(prerequisite == 0 || prerequisite < recipes.len && recipes[prerequisite].prerequisite == 0);
        let id = recipes.len as u32; recipes.push(ProofRecipe { fact: fact, rule: rule, evidence: evidence, prerequisite: prerequisite, .. }); return id;
    }
    recursive fn materialize(id: u32) -> u32 {
        if !proof_charge(w, budget, 1) { return 0; } let recipe = recipes[id]; if recipe.materialized != 0 { return recipe.materialized; }
        var premise = recipe.evidence;
        if recipe.prerequisite != 0 { premise = materialize(recipe.prerequisite); if premise == 0 { return 0; } }
        let result = if premise == 0 { proof_evidence(b, w, budget, index, recipe.fact, recipe.rule, scope, 0, [], []) } else { proof_evidence(b, w, budget, index, recipe.fact, recipe.rule, scope, 0, [], [premise]) };
        recipes[id].materialized = result; return result;
    }
    // All remaining workspaces are one or two entries per tracked term or
    // bounded arc. proof_track checks LIMIT_TERMS before collecting a node.
    var queue: u32[>..] = []; var predecessor: u32[>..] = []; var via: u32[>..] = [];
    var terms: u32[>..] = []; var positions = KeyIndex<u32> {};
    recursive fn collect(id: u32) { if id == 0 || key_index_get(positions, id) != 0 { return; } if !proof_charge(w, budget, 1) || !proof_track(w, budget, index, 1, id) { return 0 from proof_order_graph; } key_index_insert(positions, id, 1); terms.push(id); let t = b.terms[id]; for i in t.args.count { collect(b.refs[t.args.start + i]); } }
    collect(target.left); collect(target.right); collect(target.third);
    for e in active { if !proof_charge(w, budget, 1) || !id_ok(e, b.evidence.len) { return 0; } let f = b.facts[b.evidence[e].fact]; collect(f.left); collect(f.right); collect(f.third); }
    sort(terms[..]) { left, right => if !proof_charge(w, budget, 1) { return 0 from proof_order_graph; } proof_rank(index, budget, left) < proof_rank(index, budget, right) };
    for id, i in terms { key_index_insert(positions, id, i as u32 + 1); heads.push(0); predecessor.push(0); predecessor.push(0); via.push(0); via.push(0); }
    fn add_arc(source: u32, destination: u32, strict: u32, evidence: u32, recipe: u32) -> bool {
        if !proof_charge(w, budget, 1) { return false; }
        if arcs.len - 1 >= LIMIT_PROOF_VISITS { w.exhausted = true; return false; }
        let from = key_index_get(positions, source) - 1; let to = key_index_get(positions, destination) - 1;
        var previous: u32 = 0; var cursor = heads[from];
        while cursor != 0 && arcs[cursor].to <= to { if !proof_charge(w, budget, 1) { return false; } previous = cursor; cursor = arcs[cursor].next; }
        let id = arcs.len as u32; arcs.push(ProofArc { to: to, evidence: evidence, recipe: recipe, next: cursor, strict: strict });
        if previous == 0 { heads[from] = id; } else { arcs[previous].next = id; } return true;
    }
    // Adjacent literal values connect the complete finite order with linear
    // edges. Equal-valued compound terms connect in both directions, so their
    // admission is independent of equality orientation or term creation rank.
    var literals: ProofLiteral[>..] = []; var complements: u32[>..] = []; var complement_last = KeyIndex<u32> {};
    for term in terms {
        if !proof_charge(w, budget, 1) { return 0; } let t = b.terms[term];
        if t.tag == EXPR_MAX_MINUS && t.args.count == 1 { complements.push(term); key_index_insert(complement_last, b.refs[t.args.start], term); }
        let value, known = proof_literal_value(b, w, budget, index, term, 0); if w.exhausted { return 0; } if known { literals.push(ProofLiteral { term: term, value: value }); } }
    sort(literals[..]) { left, right => if !proof_charge(w, budget, 1) { return 0 from proof_order_graph; } left.value < right.value || (left.value == right.value && proof_rank(index, budget, left.term) < proof_rank(index, budget, right.term)) };
    for i in 1..literals.len {
        if !proof_charge(w, budget, 1) { return 0; } let left = literals[i - 1]; let right = literals[i]; let equal = left.value == right.value;
        if !equal && target.tag == FACT_EQ { continue; }
        let recipe = defer_evidence(Fact { tag: if equal { FACT_EQ } else { FACT_LT }, left: left.term, right: right.term, .. }, RULE_LITERAL, 0, 0);
        if !add_arc(left.term, right.term, if equal { 0 } else { 1 }, 0, recipe) { return 0; }
        if equal && !add_arc(right.term, left.term, 0, 0, recipe) { return 0; }
    }
    for e in active {
        if !proof_charge(w, budget, 1) || !id_ok(e, b.evidence.len) { return 0; }
        let f = b.facts[b.evidence[e].fact];
        if f.tag == FACT_EQ || (target.tag != FACT_EQ && (f.tag == FACT_LT || f.tag == FACT_LE)) { if !add_arc(f.left, f.right, if f.tag == FACT_LT { 1 } else { 0 }, e, 0) { return 0; } }
        if f.tag == FACT_EQ { if !add_arc(f.right, f.left, 0, e, 0) { return 0; } }
        if target.tag != FACT_EQ && f.tag == FACT_SUB_FITS { let recipe = defer_evidence(Fact { tag: FACT_LE, left: f.right, right: f.left, .. }, RULE_SUB_FROM_LE, e, 0); if !add_arc(f.right, f.left, 0, 0, recipe) { return 0; } }
        if target.tag != FACT_EQ && f.tag == FACT_ADD_FITS {
            for tid in complements { if !proof_charge(w, budget, 1) { return 0; } let term = b.terms[tid]; let operand = b.refs[term.args.start]; var prerequisite: u32 = 0; var lhs = f.left;
                if operand == f.left { prerequisite = defer_evidence(Fact { tag: FACT_ADD_FITS, left: f.right, right: f.left, .. }, RULE_ADD_SYMMETRY, e, 0); lhs = f.right; } else if operand != f.right { continue; }
                let recipe = defer_evidence(Fact { tag: FACT_LE, left: lhs, right: tid, .. }, RULE_ADD_FROM_COMPLEMENT, if prerequisite == 0 { e } else { 0 }, prerequisite); if !add_arc(lhs, tid, 0, 0, recipe) { return 0; }
            }
        }
        if f.tag == FACT_EQ || (target.tag != FACT_EQ && (f.tag == FACT_LT || f.tag == FACT_LE)) {
            let left_comp = key_index_get(complement_last, f.left); let right_comp = key_index_get(complement_last, f.right);
            if left_comp != 0 && right_comp != 0 { let recipe = defer_evidence(Fact { tag: f.tag, left: right_comp, right: left_comp, .. }, RULE_COMPLEMENT_ORDER, e, 0); if !add_arc(right_comp, left_comp, if f.tag == FACT_LT { 1 } else { 0 }, 0, recipe) { return 0; } if f.tag == FACT_EQ && !add_arc(left_comp, right_comp, 0, 0, recipe) { return 0; } }
            let left = b.terms[f.left]; let right = b.terms[f.right]; if left.tag == EXPR_MAX_MINUS && right.tag == EXPR_MAX_MINUS && left.args.count == 1 && right.args.count == 1 { let x = b.refs[right.args.start]; let y = b.refs[left.args.start]; let recipe = defer_evidence(Fact { tag: f.tag, left: x, right: y, .. }, RULE_COMPLEMENT_ORDER, e, 0); if !add_arc(x, y, if f.tag == FACT_LT { 1 } else { 0 }, 0, recipe) { return 0; } }
        }
    }
    if find_cycle {
        // Iterative Tarjan uses only forward adjacency. The DFS and component
        // stacks each contain at most one entry per tracked term. A completed
        // component contradicts order only if one of its own edges is strict;
        // strict edges crossing components do not establish a cycle.
        var discovery: u32[>..] = []; var low: u32[>..] = []; var components: u32[>..] = [];
        var on_stack: bool[>..] = []; var strict_components: bool[>..] = [];
        for term in terms { if !proof_charge(w, budget, 1) { return 0; } discovery.push(0); low.push(0); components.push(0); on_stack.push(false); strict_components.push(false); }
        var walk: ProofWalk[>..] = []; var component_stack: u32[>..] = [];
        var serial: u32 = 0; var component: u32 = 0;
        for term, root in terms {
            if !proof_charge(w, budget, 1) { return 0; } if discovery[root] != 0 { continue; }
            serial++; discovery[root] = serial; low[root] = serial; on_stack[root] = true;
            component_stack.push(root as u32); walk.push(ProofWalk { node: root as u32, next: heads[root] });
            while walk.len != 0 {
                if !proof_charge(w, budget, 1) { return 0; } let at = walk.len - 1; let top = walk[at];
                if top.next != 0 {
                    let edge = arcs[top.next]; walk[at].next = edge.next;
                    if discovery[edge.to] == 0 {
                        serial++; discovery[edge.to] = serial; low[edge.to] = serial; on_stack[edge.to] = true;
                        component_stack.push(edge.to); walk.push(ProofWalk { node: edge.to, next: heads[edge.to] });
                    } else if on_stack[edge.to] { low[top.node] = min(low[top.node], discovery[edge.to]); }
                    continue;
                }
                walk.resize(at);
                if low[top.node] == discovery[top.node] {
                    component++;
                    loop {
                        if !proof_charge(w, budget, 1) { return 0; }
                        let last = component_stack.len - 1; let node = component_stack[last]; component_stack.resize(last);
                        components[node] = component; on_stack[node] = false; if node == top.node { break; }
                    }
                }
                if walk.len != 0 {
                    if !proof_charge(w, budget, 1) { return 0; }
                    let parent = walk[walk.len - 1].node; low[parent] = min(low[parent], low[top.node]);
                }
            }
        }
        for first, from in heads {
            if !proof_charge(w, budget, 1) { return 0; } var arc = first;
            while arc != 0 { if !proof_charge(w, budget, 1) { return 0; } let edge = arcs[arc]; if edge.strict != 0 && components[from] == components[edge.to] { strict_components[components[from] - 1] = true; } arc = edge.next; }
        }
        var root: u32 = 0;
        for evidence in active {
            if !proof_charge(w, budget, 1) { return 0; } let fact = b.facts[b.evidence[evidence].fact];
            if fact.tag == FACT_LT && strict_components[components[key_index_get(positions, fact.left) - 1] - 1] { root = fact.left; break; }
        }
        if root == 0 { return 0; } target = Fact { tag: FACT_LT, left: root, right: root, .. };
    }
    let start = (key_index_get(positions, target.left) - 1) * 2; queue.push(start); predecessor[start] = start + 1;
    var head: i64 = 0; var found: u32 = 0;
    while head < queue.len {
        let state = queue[head]; head++; let from = state / 2; let strict = state % 2;
        if terms[from] == target.right && (target.tag == FACT_LE || target.tag == FACT_EQ || strict == 1) { found = state + 1; break; }
        var cursor = heads[from];
        while cursor != 0 { if !proof_charge(w, budget, 1) { return 0; } let arc = arcs[cursor]; let destination = arc.to * 2 + (strict | arc.strict); if predecessor[destination] == 0 { predecessor[destination] = state + 1; via[destination] = cursor; queue.push(destination); } cursor = arc.next; }
    }
    if found == 0 { return 0; }
    var path: u32[>..] = []; var destinations: u32[>..] = []; var cursor = found - 1;
    while cursor != start { if !proof_charge(w, budget, 1) { return 0; } path.push(via[cursor]); destinations.push(terms[cursor / 2]); cursor = predecessor[cursor] - 1; }
    var result = proof_evidence(b, w, budget, index, Fact { tag: if target.tag == FACT_EQ { FACT_EQ } else { FACT_LE }, left: target.left, right: target.left, .. }, RULE_REFLEXIVE, scope, 0, [], []);
    var current = target.left; var strict = false; var i = path.len;
    while i > 0 {
        if !proof_charge(w, budget, 1) { return 0; }
        i--; let arc = arcs[path[i]]; var step = if arc.evidence != 0 { arc.evidence } else { materialize(arc.recipe) };
        if step == 0 { return 0; } let destination = destinations[i]; let f = b.facts[b.evidence[step].fact];
        if f.tag == FACT_EQ && f.left != current {
            let identity = proof_evidence(b, w, budget, index, Fact { tag: FACT_EQ, left: current, right: current, .. }, RULE_REFLEXIVE, scope, 0, [], []);
            step = proof_evidence(b, w, budget, index, Fact { tag: FACT_EQ, left: current, right: destination, .. }, RULE_EQUALITY, scope, 0, [], [step, identity]);
        }
        strict = strict || f.tag == FACT_LT;
        let conclusion = Fact { tag: if i == 0 { target.tag } else if target.tag == FACT_EQ { FACT_EQ } else if strict { FACT_LT } else { FACT_LE }, left: target.left, right: destination, .. };
        result = proof_evidence(b, w, budget, index, conclusion, RULE_TRANSITIVE, scope, 0, [], [result, step]);
        if result == 0 { return 0; } current = destination;
    }
    return result;
}
fn proof_order(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, scope: u32, active: const u32[:], target: Fact) -> u32 {
    proof_order_graph(b, w, budget, index, scope, active, target, false)
}
fn proof_cycle(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, scope: u32, active: const u32[:]) -> u32 {
    for evidence in active {
        if !proof_charge(w, budget, 1) || !id_ok(evidence, b.evidence.len) { return 0; } let fact = b.facts[b.evidence[evidence].fact];
        if fact.tag == FACT_LT { return proof_order_graph(b, w, budget, index, scope, active, Fact { tag: FACT_LT, left: fact.left, right: fact.left, .. }, true); }
    }
    return 0;
}

fn proof_numeric_value(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, value: u32) -> u32 {
    let v = b.values[value]; if v.op != 0 && b.ops[v.op].tag == OP_U32 { return proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, type_id: v.type_id, literal: b.ops[v.op].imm0, .. }); }
    return proof_term(b, w, budget, index, Term { tag: EXPR_VALUE, type_id: v.type_id, value: value, version: v.version, scope: v.scope, .. });
}
recursive fn proof_query_inner(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, scope: u32, active: const u32[:], target: Fact, depth: u32) -> u32 {
    if depth > LIMIT_TERMS || !proof_charge(w, budget, 1) { return 0; }
    if !id_ok(target.left, b.terms.len) || !id_ok(target.right, b.terms.len) { return 0; }
    if !proof_demand(b, w, budget, index, target.left) || !proof_demand(b, w, budget, index, target.right) || !proof_demand(b, w, budget, index, target.third) { return 0; }
    for evidence in active { if !proof_charge(w, budget, 1) { return 0; } if !id_ok(evidence, b.evidence.len) { return 0; } if proof_fact_equal(b.facts[b.evidence[evidence].fact], target) { return evidence; } }
    if (target.tag == FACT_EQ || target.tag == FACT_LE) && target.left == target.right { return proof_evidence(b, w, budget, index, target, RULE_REFLEXIVE, scope, 0, [], []); }
    if proof_literal_truth(b, w, budget, index, target) { return proof_evidence(b, w, budget, index, target, RULE_LITERAL, scope, 0, [], []); }
    let a = b.terms[target.left]; let c = b.terms[target.right];
    // Prefer an exact guarded successor before attempting equality transport.
    // Every older arithmetic result may have a symbolic equality; exploring
    // those alternatives first repeats failed congruence searches unnecessarily.
    if target.tag == FACT_ADD_FITS && c.tag == EXPR_LITERAL && c.literal == 1 {
        for premise in active { if !proof_charge(w, budget, 1) { return 0; } let fact = b.facts[b.evidence[premise].fact];
            if fact.tag == FACT_LT && fact.left == target.left { return proof_evidence(b, w, budget, index, target, RULE_SUCCESSOR, scope, 0, [], [premise]); }
        }
    }
    if target.tag == FACT_LE && ((a.tag == EXPR_LITERAL && a.literal == 0) || (c.tag == EXPR_LITERAL && c.literal == 4294967295)) { return proof_evidence(b, w, budget, index, target, RULE_U32_BOUNDS, scope, 0, [], []); }
    if target.tag == FACT_LE || target.tag == FACT_LT || target.tag == FACT_EQ {
        let graph = proof_order(b, w, budget, index, scope, active, target); if graph != 0 { return graph; }
        // Literal order and every active equality transport are graph edges.
        // Replaying strict-order queries through those equalities adds no path.
        if target.tag == FACT_LT { return 0; }
    }
    if target.tag != FACT_INDEX {
        for e in active { if !proof_charge(w, budget, 1) { return 0; } let eq = b.facts[b.evidence[e].fact]; if eq.tag != FACT_EQ { continue; }
            var replacement: u32 = 0; var side: u32 = 0;
            if eq.left == target.left && proof_rank(index, budget, eq.right) < proof_rank(index, budget, target.left) { replacement = eq.right; side = 1; }
            else if eq.right == target.left && proof_rank(index, budget, eq.left) < proof_rank(index, budget, target.left) { replacement = eq.left; side = 1; }
            else if eq.left == target.right && proof_rank(index, budget, eq.right) < proof_rank(index, budget, target.right) { replacement = eq.right; side = 2; }
            else if eq.right == target.right && proof_rank(index, budget, eq.left) < proof_rank(index, budget, target.right) { replacement = eq.left; side = 2; }
            if replacement == 0 { continue; }
            let smaller = Fact { tag: target.tag, left: if side == 1 { replacement } else { target.left }, right: if side == 2 { replacement } else { target.right }, .. };
            let p = proof_query_inner(b, w, budget, index, scope, active, smaller, depth + 1); if p == 0 { continue; }
            let result = proof_evidence(b, w, budget, index, target, RULE_EQUALITY, scope, 0, [], [e, p]); if result != 0 { return result; }
        }
    }
    if target.tag == FACT_EQ && ((a.tag == EXPR_ADD || a.tag == EXPR_SUB) && c.tag == EXPR_VALUE || (c.tag == EXPR_ADD || c.tag == EXPR_SUB) && a.tag == EXPR_VALUE) {
        let expression = if a.tag == EXPR_VALUE { c } else { a }; let value = if a.tag == EXPR_VALUE { a.value } else { c.value };
        if value != 0 && b.values[value].op != 0 && expression.args.count == 2 { let op = b.ops[b.values[value].op]; if op.args.count == 2 && ((expression.tag == EXPR_ADD && op.tag == OP_U32_ADD) || (expression.tag == EXPR_SUB && op.tag == OP_U32_SUB)) {
            let lhs = proof_numeric_value(b, w, budget, index, b.refs[op.args.start]); let rhs = proof_numeric_value(b, w, budget, index, b.refs[op.args.start + 1]);
            let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_EQ, left: b.refs[expression.args.start], right: lhs, .. }, depth + 1);
            let q = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_EQ, left: b.refs[expression.args.start + 1], right: rhs, .. }, depth + 1);
            if p != 0 && q != 0 { return proof_evidence(b, w, budget, index, target, RULE_CHECKED_SUCCESS, scope, 0, [value], [p, q]); }
        } }
    }
    if target.tag == FACT_EQ && a.tag == EXPR_VALUE && c.tag == EXPR_VALUE && a.value != 0 && c.value != 0 {
        let left_op = b.values[a.value].op; let right_op = b.values[c.value].op;
        if left_op != 0 && right_op != 0 { let x = b.ops[left_op]; let y = b.ops[right_op];
            if (x.tag == OP_U32_ADD || x.tag == OP_U32_SUB) && x.tag == y.tag && x.args.count == 2 && y.args.count == 2 {
                let xa = proof_numeric_value(b, w, budget, index, b.refs[x.args.start]); let xb = proof_numeric_value(b, w, budget, index, b.refs[x.args.start + 1]); let ya = proof_numeric_value(b, w, budget, index, b.refs[y.args.start]); let yb = proof_numeric_value(b, w, budget, index, b.refs[y.args.start + 1]);
                let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_EQ, left: xa, right: ya, .. }, depth + 1);
                let q = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_EQ, left: xb, right: yb, .. }, depth + 1);
                if p != 0 && q != 0 { return proof_evidence(b, w, budget, index, target, RULE_CHECKED_SUCCESS, scope, 0, [a.value, c.value], [p, q]); }
            }
        }
    }
    if target.tag == FACT_LE && a.tag == EXPR_VALUE && a.value != 0 && b.values[a.value].op != 0 {
        let op = b.ops[b.values[a.value].op];
        if op.tag == OP_U32_ADD && op.args.count == 2 { let rhs = proof_numeric_value(b, w, budget, index, b.refs[op.args.start + 1]); if b.terms[rhs].tag == EXPR_LITERAL && b.terms[rhs].literal == 1 { let lhs = proof_numeric_value(b, w, budget, index, b.refs[op.args.start]); let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_LT, left: lhs, right: target.right, .. }, depth + 1); if p != 0 { return proof_evidence(b, w, budget, index, target, RULE_SUCCESSOR, scope, 0, [], [p]); } } }
    }
    if target.tag == FACT_SUB_FITS { let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_LE, left: target.right, right: target.left, .. }, depth + 1); if p != 0 { return proof_evidence(b, w, budget, index, target, RULE_SUB_FROM_LE, scope, 0, [], [p]); } }
    if target.tag == FACT_ADD_FITS {
        for premise in active { if !proof_charge(w, budget, 1) { return 0; } let f = b.facts[b.evidence[premise].fact]; if f.tag == FACT_ADD_FITS && f.left == target.right && f.right == target.left { return proof_evidence(b, w, budget, index, target, RULE_ADD_SYMMETRY, scope, 0, [], [premise]); } }
        if c.tag == EXPR_LITERAL && c.literal == 1 {
            for premise in active { if !proof_charge(w, budget, 1) { return 0; } let f = b.facts[b.evidence[premise].fact]; if f.tag == FACT_LT {
                var strict = premise;
                if f.left != target.left { let eq = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_EQ, left: target.left, right: f.left, .. }, depth + 1); if eq == 0 { continue; } strict = proof_evidence(b, w, budget, index, Fact { tag: FACT_LT, left: target.left, right: f.right, .. }, RULE_EQUALITY, scope, 0, [], [eq, premise]); }
                return proof_evidence(b, w, budget, index, target, RULE_SUCCESSOR, scope, 0, [], [strict]);
            } }
        }
        let comp = proof_term(b, w, budget, index, Term { tag: EXPR_MAX_MINUS, type_id: c.type_id, args: ref_span(b, [target.right]), scope: scope, .. });
        if comp == 0 { return 0; }
        let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_LE, left: target.left, right: comp, .. }, depth + 1);
        if p != 0 { return proof_evidence(b, w, budget, index, target, RULE_ADD_FROM_COMPLEMENT, scope, 0, [], [p]); }
    }
    if target.tag == FACT_MUL_FITS {
        var k: u32 = 0; var x: u32 = 0;
        if a.tag == EXPR_LITERAL { k = a.literal; x = target.right; } else if c.tag == EXPR_LITERAL { k = c.literal; x = target.left; } else { return 0; }
        if k == 0 { return proof_evidence(b, w, budget, index, target, RULE_MUL_CONSTANT, scope, 0, [], []); }
        let bound = proof_term(b, w, budget, index, Term { tag: EXPR_LITERAL, type_id: a.type_id, literal: 4294967295 / k, .. });
        let p = proof_query_inner(b, w, budget, index, scope, active, Fact { tag: FACT_LE, left: x, right: bound, .. }, depth + 1);
        if p != 0 { return proof_evidence(b, w, budget, index, target, RULE_MUL_CONSTANT, scope, 0, [], [p]); }
    }
    return 0;
}
fn proof_query(b: CoreBuilder, w: Work&, budget: ProofBudget, index: ProofIndex, scope: u32, active: const u32[:], target: Fact) -> u32 { proof_query_inner(b, w, budget, index, scope, active, target, 0) }
