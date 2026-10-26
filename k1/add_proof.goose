// Isolated K1 AddFits(x, 0) evidence experiment. No source is admitted here.
// The caller must independently validate the actual source/Core operation and
// supply its exact Subject. This is not an artifact decoder or a general solver.
namespace add_proof;

// IDs name values in one already-checked, owner-local function. operation=1
// names this module's checked-U32-add subject, not a frozen Core operation ID.
struct Subject {
    owner: u32 = 0, scope: u32 = 0,
    parameter: u32 = 0, parameter_version: u32 = 0,
    zero: u32 = 0, zero_version: u32 = 0,
    result: u32 = 0, result_version: u32 = 0,
    zero_literal: u32 = 0, operation: u32 = 0
}
// kind 1 parameter, 2 zero source value, 3 MAX literal, 4 MAX-minus term.
// Only kind 4 has a base, which is the one-based term ID of the zero value.
struct Term {
    kind: u32 = 0, owner: u32 = 0, scope: u32 = 0,
    value: u32 = 0, version: u32 = 0, literal: u32 = 0, base: u32 = 0
}
// rule 1: U32 upper bound Le(parameter, MAX); rule 2: normalization
// Eq(MAX-minus-zero, MAX); rule 3: AddFits(parameter, zero) from rules 1,2.
// All term and prerequisite IDs are one-based. The conclusion binds to the
// actual addition result and version, rather than a reusable Boolean flag.
struct Node {
    rule: u32 = 0, owner: u32 = 0, scope: u32 = 0,
    left: u32 = 0, right: u32 = 0, prior1: u32 = 0, prior2: u32 = 0,
    operation_result: u32 = 0, operation_version: u32 = 0
}
struct Proof {
    schema: u32 = 0, semantic_policy: u32 = 0,
    subject: Subject = Subject {},
    term_count: u32 = 0, node_count: u32 = 0,
    terms: Term[4] = [Term {}; 4],
    nodes: Node[3] = [Node {}; 3],
    conclusion: u32 = 0
}
// Compiler-owned cumulative per-declaration work, never accepted from an
// artifact. A single visit is charged for each subject/header, term, node and
// prerequisite checked or constructed. Failure spends work already performed,
// but no proof is published. The total semantic budget is shared by the caller.
// limit_quantity: 1 terms, 2 fact/evidence edges, 3 proof visits, 4 total
// semantic visits. These are compiler-owned receipts, not serialized claims.
struct Work { terms: u32 = 0, edges: u32 = 0, proof_visits: u32 = 0, semantic_visits: u32 = 0,
              limit: u32 = 0, limit_quantity: u32 = 0 }
// status: 0 success, 1 invalid subject/evidence, 2 proof limit, 3 semantic limit.
struct Result { status: u32 = 0, proof: Proof = Proof {} }
struct Check { status: u32 = 0, visits: u32 = 0 }

fn spend(w: Work&, new_terms: u32, new_edges: u32) -> bool {
    // K1-CORE C09 gives the total semantic ceiling precedence when reached;
    // preserve it when proof and semantic ceilings are simultaneously exhausted.
    if w.semantic_visits >= 1048576 { w.limit = 3; w.limit_quantity = 4; return false; }
    if w.terms > 4096 || new_terms > 4096 - w.terms { w.limit = 2; w.limit_quantity = 1; return false; }
    if w.edges > 16384 || new_edges > 16384 - w.edges { w.limit = 2; w.limit_quantity = 2; return false; }
    if w.proof_visits >= 65536 { w.limit = 2; w.limit_quantity = 3; return false; }
    w.limit = 0;
    w.limit_quantity = 0;
    w.terms += new_terms;
    w.edges += new_edges;
    w.proof_visits += 1;
    w.semantic_visits += 1;
    return true;
}
fn valid_subject(s: Subject) -> bool {
    return s.owner != 0 && s.scope != 0 && s.operation == 1 &&
        s.zero_literal == 0 && s.parameter < s.zero && s.zero < s.result;
}
fn same_subject(a: Subject, b: Subject) -> bool {
    return a.owner == b.owner && a.scope == b.scope &&
        a.parameter == b.parameter && a.parameter_version == b.parameter_version &&
        a.zero == b.zero && a.zero_version == b.zero_version &&
        a.result == b.result && a.result_version == b.result_version &&
        a.zero_literal == b.zero_literal && a.operation == b.operation;
}

// The only admitted arithmetic proposition here is AddFits(parameter, 0).
// Other literals and operations do not produce a proof.
fn build(s: Subject, w: Work&) -> Result {
    if !spend(w, 0, 0) { return Result { status: w.limit }; }
    if !valid_subject(s) { return Result { status: 1 }; }
    var p = Proof { schema: 1, semantic_policy: 1, subject: s };
    if !spend(w, 1, 0) { return Result { status: w.limit }; }
    p.terms[0] = Term { kind: 1, owner: s.owner, scope: s.scope,
                        value: s.parameter, version: s.parameter_version };
    if !spend(w, 1, 0) { return Result { status: w.limit }; }
    p.terms[1] = Term { kind: 2, owner: s.owner, scope: s.scope,
                        value: s.zero, version: s.zero_version, literal: 0 };
    if !spend(w, 1, 0) { return Result { status: w.limit }; }
    p.terms[2] = Term { kind: 3, owner: s.owner, scope: s.scope, literal: 4294967295 };
    if !spend(w, 1, 0) { return Result { status: w.limit }; }
    p.terms[3] = Term { kind: 4, owner: s.owner, scope: s.scope, base: 2 };
    if !spend(w, 0, 1) { return Result { status: w.limit }; }
    p.nodes[0] = Node { rule: 1, owner: s.owner, scope: s.scope, left: 1, right: 3 };
    if !spend(w, 0, 1) { return Result { status: w.limit }; }
    p.nodes[1] = Node { rule: 2, owner: s.owner, scope: s.scope, left: 4, right: 3 };
    if !spend(w, 0, 1) { return Result { status: w.limit }; }
    // Count the conclusion and its two prerequisite links separately.
    if !spend(w, 0, 1) { return Result { status: w.limit }; }
    if !spend(w, 0, 1) { return Result { status: w.limit }; }
    p.nodes[2] = Node { rule: 3, owner: s.owner, scope: s.scope, left: 1, right: 2,
        prior1: 1, prior2: 2, operation_result: s.result, operation_version: s.result_version };
    p.term_count = 4; p.node_count = 3; p.conclusion = 3;
    return Result { proof: p };
}

fn same_term(a: Term, b: Term) -> bool {
    return a.kind == b.kind && a.owner == b.owner && a.scope == b.scope &&
        a.value == b.value && a.version == b.version && a.literal == b.literal && a.base == b.base;
}
fn same_node(a: Node, b: Node) -> bool {
    return a.rule == b.rule && a.owner == b.owner && a.scope == b.scope &&
        a.left == b.left && a.right == b.right && a.prior1 == b.prior1 && a.prior2 == b.prior2 &&
        a.operation_result == b.operation_result && a.operation_version == b.operation_version;
}

// Independently check every field and the explicit DAG rules against the
// caller's already source-validated Subject. The caller must pass the same
// compiler-owned per-declaration Work used by build: this experiment does not
// admit imported proofs or authenticate externally supplied work inventories.
// No parser, builder, cached success flag or graph assumption is authority.
fn validate(p: Proof, expected: Subject, w: Work&) -> Check {
    let before = w.proof_visits;
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if w.terms < 4 || w.edges < 5 || !valid_subject(expected) || !same_subject(p.subject, expected) ||
       p.schema != 1 || p.semantic_policy != 1 || p.term_count != 4 || p.node_count != 3 || p.conclusion != 3 {
        return Check { status: 1, visits: w.proof_visits - before };
    }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_term(p.terms[0], Term { kind: 1, owner: expected.owner, scope: expected.scope,
                 value: expected.parameter, version: expected.parameter_version }) { return Check { status: 1, visits: w.proof_visits - before }; }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_term(p.terms[1], Term { kind: 2, owner: expected.owner, scope: expected.scope,
                 value: expected.zero, version: expected.zero_version, literal: 0 }) { return Check { status: 1, visits: w.proof_visits - before }; }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_term(p.terms[2], Term { kind: 3, owner: expected.owner, scope: expected.scope,
                 literal: 4294967295 }) { return Check { status: 1, visits: w.proof_visits - before }; }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_term(p.terms[3], Term { kind: 4, owner: expected.owner, scope: expected.scope, base: 2 }) {
        return Check { status: 1, visits: w.proof_visits - before };
    }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_node(p.nodes[0], Node { rule: 1, owner: expected.owner, scope: expected.scope, left: 1, right: 3 }) {
        return Check { status: 1, visits: w.proof_visits - before };
    }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_node(p.nodes[1], Node { rule: 2, owner: expected.owner, scope: expected.scope, left: 4, right: 3 }) {
        return Check { status: 1, visits: w.proof_visits - before };
    }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !same_node(p.nodes[2], Node { rule: 3, owner: expected.owner, scope: expected.scope, left: 1, right: 2,
                 prior1: 1, prior2: 2, operation_result: expected.result, operation_version: expected.result_version }) {
        return Check { status: 1, visits: w.proof_visits - before };
    }
    // Charge both prerequisite-link checks. The fixed IDs and prerequisite
    // nodes were independently checked above; neither needs to be re-read.
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    if !spend(w, 0, 0) { return Check { status: w.limit, visits: w.proof_visits - before }; }
    return Check { status: 0, visits: w.proof_visits - before };
}
