// Standalone bounded ordering-graph kernel. Facts inserted here are assumptions
// supplied by a caller; this module does not validate source, contracts, scopes,
// evidence from disk, arithmetic transfer, or ownership. Do not use it to admit
// K1 code until those checks and a separate evidence validator exist.
namespace proof;

// A term's identity includes every field. A source name is not an SSA version.
// kind 0 is a U32 literal; kind 1 is a caller-owned symbolic value.
struct Term { kind: u32, sort: u32, value: u32, version: u32, producer: u32 }
struct Edge { from: u32, to: u32, strict: bool, next: u32, evidence: u32 }
struct Step { state: u32, previous: u32, edge: u32 }
// rule 0 is an assumption, 1 is reflexivity, 2 is literal comparison,
// 3 is transitivity. `prior` and `edge` name earlier evidence nodes.
struct Evidence { rule: u32, left: u32, right: u32, strict: bool, prior: u32, edge: u32, scope: u32 }
struct Answer { status: u32, id: u32 = 0, visits: u32 = 0 }
// status: 0 success, 1 invalid input, 2 proof limit, 3 not established.
// IDs are one-based; zero never grants authority. A separate arena is needed
// for each scope. The caller must not reuse branch-local facts in another arena.
struct Arena {
    scope: u32,
    visits: u32 = 0,
    terms: Term[..4096] = [],
    slots: u32[8192] = [0; 8192],
    heads: u32[4096] = [0; 4096],
    parents: u32[4096] = [0; 4096],
    edges: Edge[..16384] = [],
    evidence: Evidence[..16384] = []
}

fn charge(a: Arena&) -> bool {
    if a.visits >= 65536 { return false; }
    a.visits += 1;
    return true;
}
fn same(a: Term, b: Term) -> bool {
    return a.kind == b.kind && a.sort == b.sort && a.value == b.value &&
           a.version == b.version && a.producer == b.producer;
}
fn valid_term(t: Term) -> bool {
    // Only U32 terms are implemented. Literal identity is canonical.
    return t.sort == 0 && (t.kind == 1 || (t.kind == 0 && t.version == 0 && t.producer == 0));
}
fn hash(t: Term) -> u32 {
    // Goose unsigned arithmetic wraps. Hash collisions are resolved by equality.
    var h: u32 = 2166136261;
    h = (h ^ t.kind) * 16777619;
    h = (h ^ t.sort) * 16777619;
    h = (h ^ t.value) * 16777619;
    h = (h ^ t.version) * 16777619;
    h = (h ^ t.producer) * 16777619;
    return h;
}
// Construction-only API: `a.slots` and `a.terms` are compiler-owned mutable
// state, never deserialized or accepted from an untrusted caller. This routine
// detects invalid slot IDs but does not authenticate a corrupted hash table;
// importing an artifact needs a separate bounded validator and fresh interning.
fn intern(a: Arena&, term: Term) -> Answer {
    let before = a.visits;
    if !valid_term(term) { return Answer { status: 1 }; }
    var slot = (hash(term) % 8192) as i64;
    while true {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        let id = a.slots[slot];
        if id == 0 {
            if a.terms.len == 4096 { return Answer { status: 2, visits: a.visits - before }; }
            if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
            a.terms.push(term);
            let added = a.terms.len as u32;
            a.slots[slot] = added;
            a.parents[added - 1] = added;
            return Answer { status: 0, id: added, visits: a.visits - before };
        }
        if id > a.terms.len { return Answer { status: 1, visits: a.visits - before }; }
        if same(a.terms[id - 1], term) { return Answer { status: 0, id: id, visits: a.visits - before }; }
        slot = (slot + 1) % 8192;
    }
    return Answer { status: 2, visits: a.visits - before };
}
fn valid_id(a: Arena&, id: u32) -> bool { return id != 0 && id <= a.terms.len; }
// Defensive in-memory integrity check. It does not authenticate assumptions or
// replace the required independent artifact validator. Every traversal charges
// the declaration budget, including malformed linked-list walks.
fn check_graph(a: Arena&) -> Answer {
    let before = a.visits;
    if a.edges.len + a.evidence.len > 16384 { return Answer { status: 1 }; }
    var count = 0;
    for t in a.terms.len {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        let parent = a.parents[t];
        if !valid_term(a.terms[t]) || !valid_id(a, parent) || parent > t + 1 {
            return Answer { status: 1, visits: a.visits - before };
        }
        // Every interned term must be the first equal key in its own probe
        // sequence. This rejects duplicate identities and missing/forged
        // slots before any graph fact is used as evidence.
        let key = a.terms[t];
        var slot = (hash(key) % 8192) as i64;
        var probes = 0;
        var found = false;
        while probes < 8192 {
            if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
            probes += 1;
            let id = a.slots[slot];
            if id == 0 || id > a.terms.len { return Answer { status: 1, visits: a.visits - before }; }
            if same(a.terms[id - 1], key) {
                if id != t + 1 { return Answer { status: 1, visits: a.visits - before }; }
                found = true;
                break;
            }
            slot = (slot + 1) % 8192;
        }
        if !found { return Answer { status: 1, visits: a.visits - before }; }
        var edge = a.heads[t];
        var last: u32 = 0;
        var last_strict = true;
        while edge != 0 {
            if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
            if edge > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
            count += 1;
            // Since each edge has one checked source, a repeated edge implies
            // a cycle; the total number of records is a hard traversal bound.
            if count > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
            let item = a.edges[edge - 1];
            if item.from != t + 1 || !valid_id(a, item.to) || a.terms[t].kind == 0 ||
               a.terms[item.to - 1].kind == 0 || item.evidence == 0 || item.evidence > a.evidence.len ||
               item.to < last || (item.to == last && !last_strict && item.strict) {
                return Answer { status: 1, visits: a.visits - before };
            }
            let e = a.evidence[item.evidence - 1];
            if e.rule != 0 || e.scope != a.scope || e.left != item.from || e.right != item.to ||
               e.strict != item.strict || e.prior != 0 || e.edge != 0 {
                return Answer { status: 1, visits: a.visits - before };
            }
            last = item.to;
            last_strict = item.strict;
            edge = item.next;
        }
    }
    if count != a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
    // Recheck strict cycles even if callers modified both edge and evidence
    // records. This bounded defensive walk is not source-contract validation.
    for item in a.edges {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        if item.strict {
            let reverse = has_path(a, item.to, item.from, false);
            if reverse.status == 0 || reverse.status == 1 { return Answer { status: 1, visits: a.visits - before }; }
            if reverse.status == 2 { return Answer { status: 2, visits: a.visits - before }; }
        }
    }
    return Answer { status: 0, visits: a.visits - before };
}
// Check reachability without publishing evidence. The caller validates IDs.
// 0 is found, 3 is absent, 2 is the deterministic work limit.
fn adjacency_valid(a: Arena&, left: u32) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) { return Answer { status: 1 }; }
    var edge = a.heads[left - 1];
    var walked = 0;
    while edge != 0 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        walked += 1;
        if walked > a.edges.len || edge > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
        let item = a.edges[edge - 1];
        if item.from != left || !valid_id(a, item.to) { return Answer { status: 1, visits: a.visits - before }; }
        edge = item.next;
    }
    return Answer { status: 0, visits: a.visits - before };
}
fn has_path(a: Arena&, left: u32, right: u32, strict: bool) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) || !valid_id(a, right) { return Answer { status: 1 }; }
    if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    let initial = adjacency_valid(a, left);
    if initial.status != 0 { return Answer { status: initial.status, visits: a.visits - before }; }
    if !strict && left == right { return Answer { status: 0, visits: a.visits - before }; }
    var queue: u32[..8192] = [];
    let start = (left - 1) * 2;
    queue.push(start);
    var head = 0;
    while head < queue.len {
        let state = queue[head];
        head += 1;
        let term = state / 2 + 1;
        let checked = adjacency_valid(a, term);
        if checked.status != 0 { return Answer { status: checked.status, visits: a.visits - before }; }
        var edge = a.heads[term - 1];
        var walked = 0;
        while edge != 0 {
            if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
            walked += 1;
            if walked > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
            if edge > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
            let item = a.edges[edge - 1];
            if item.from != term || !valid_id(a, item.to) { return Answer { status: 1, visits: a.visits - before }; }
            let is_strict = state % 2 == 1 || item.strict;
            let next = (item.to - 1) * 2 + (if is_strict { 1 } else { 0 });
            if item.to == right && (!strict || is_strict) { return Answer { status: 0, visits: a.visits - before }; }
            var seen = false;
            for previous in queue {
                if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
                if previous == next { seen = true; break; }
            }
            if !seen {
                if queue.len == 8192 { return Answer { status: 2, visits: a.visits - before }; }
                queue.push(next);
            }
            edge = item.next;
        }
    }
    return Answer { status: 3, visits: a.visits - before };
}

fn position(a: Arena&, left: u32, right: u32) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) || !valid_id(a, right) { return Answer { status: 1 }; }
    let checked = adjacency_valid(a, left);
    if checked.status != 0 { return Answer { status: checked.status, visits: a.visits - before }; }
    var previous: u32 = 0;
    var current = a.heads[left - 1];
    var walked = 0;
    while current != 0 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        walked += 1;
        if walked > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
        if current > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
        let edge = a.edges[current - 1];
        if edge.from != left || !valid_id(a, edge.to) { return Answer { status: 1, visits: a.visits - before }; }
        if edge.to > right { break; }
        previous = current;
        current = edge.next;
    }
    return Answer { status: 0, id: previous, visits: a.visits - before };
}
// Add both directions and merge to the smallest term ID atomically. Equality
// is an explicit assumption, not a license to equate unrelated domains.
fn add_eq(a: Arena&, left: u32, right: u32) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) || !valid_id(a, right) || a.terms[left - 1].sort != a.terms[right - 1].sort {
        return Answer { status: 1 };
    }
    let graph = check_graph(a);
    if graph.status != 0 { return Answer { status: graph.status, visits: a.visits - before }; }
    if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    if left == right {
        let reflexive = query_le(a, left, right, false);
        return Answer { status: reflexive.status, id: reflexive.id, visits: a.visits - before };
    }
    if a.terms[left - 1].kind == 0 || a.terms[right - 1].kind == 0 { return Answer { status: 1, visits: a.visits - before }; }
    if a.edges.len + a.evidence.len + 4 > 16384 { return Answer { status: 2, visits: a.visits - before }; }
    let forward = has_path(a, left, right, true);
    if forward.status == 0 || forward.status == 1 { return Answer { status: 1, visits: a.visits - before }; }
    if forward.status == 2 { return Answer { status: 2, visits: a.visits - before }; }
    let backward = has_path(a, right, left, true);
    if backward.status == 0 || backward.status == 1 { return Answer { status: 1, visits: a.visits - before }; }
    if backward.status == 2 { return Answer { status: 2, visits: a.visits - before }; }
    let first = position(a, left, right);
    if first.status != 0 { return Answer { status: first.status, visits: a.visits - before }; }
    let second = position(a, right, left);
    if second.status != 0 { return Answer { status: second.status, visits: a.visits - before }; }
    let lroot = canonical(a, left);
    if lroot.status != 0 { return Answer { status: lroot.status, visits: a.visits - before }; }
    let rroot = canonical(a, right);
    if rroot.status != 0 { return Answer { status: rroot.status, visits: a.visits - before }; }
    let l = lroot.id;
    let r = rroot.id;
    // Charge all four records before committing either direction.
    for i in 4 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    }
    let first_next = if first.id == 0 { a.heads[left - 1] } else { a.edges[first.id - 1].next };
    let second_next = if second.id == 0 { a.heads[right - 1] } else { a.edges[second.id - 1].next };
    a.evidence.push(Evidence { 0, left, right, false, 0, 0, a.scope });
    let evidence = a.evidence.len as u32;
    a.edges.push(Edge { left, right, false, first_next, evidence });
    let first_edge = a.edges.len as u32;
    if first.id == 0 { a.heads[left - 1] = first_edge; } else { a.edges[first.id - 1].next = first_edge; }
    a.evidence.push(Evidence { 0, right, left, false, 0, 0, a.scope });
    let reverse_evidence = a.evidence.len as u32;
    a.edges.push(Edge { right, left, false, second_next, reverse_evidence });
    let second_edge = a.edges.len as u32;
    if second.id == 0 { a.heads[right - 1] = second_edge; } else { a.edges[second.id - 1].next = second_edge; }
    if l < r { a.parents[r - 1] = l; } else if r < l { a.parents[l - 1] = r; }
    return Answer { status: 0, id: evidence, visits: a.visits - before };
}
fn canonical(a: Arena&, id: u32) -> Answer {
    let before = a.visits;
    if !valid_id(a, id) { return Answer { status: 1 }; }
    let graph = check_graph(a);
    if graph.status != 0 { return Answer { status: graph.status, visits: a.visits - before }; }
    var p = id;
    while true {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        let next = a.parents[p - 1];
        if !valid_id(a, next) { return Answer { status: 1, visits: a.visits - before }; }
        if next == p {
            if p != id {
                let forward = has_path(a, id, p, false);
                if forward.status != 0 { return Answer { status: if forward.status == 2 { 2 } else { 1 }, visits: a.visits - before }; }
                let backward = has_path(a, p, id, false);
                if backward.status != 0 { return Answer { status: if backward.status == 2 { 2 } else { 1 }, visits: a.visits - before }; }
            }
            return Answer { status: 0, id: p, visits: a.visits - before };
        }
        if next > p { return Answer { status: 1, visits: a.visits - before }; }
        p = next;
    }
    return Answer { status: 1, visits: a.visits - before };
}

// Facts and their proof nodes count together towards the 16,384 active-edge
// budget. Insertion orders each adjacency by target ID then strictness.
fn add_le(a: Arena&, left: u32, right: u32, strict: bool) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) || !valid_id(a, right) || a.terms[left - 1].sort != a.terms[right - 1].sort {
        return Answer { status: 1 };
    }
    let graph = check_graph(a);
    if graph.status != 0 { return Answer { status: graph.status, visits: a.visits - before }; }
    if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    if strict && left == right { return Answer { status: 1, visits: a.visits - before }; }
    let l = a.terms[left - 1];
    let r = a.terms[right - 1];
    // Literal axioms are handled by query_le. Mixed literal assumptions are
    // outside this kernel until transitive consistency checks are implemented.
    if l.kind == 0 || r.kind == 0 {
        return Answer { status: 1, visits: a.visits - before };
    }
    let cycle = has_path(a, right, left, !strict);
    if cycle.status == 0 || cycle.status == 1 { return Answer { status: 1, visits: a.visits - before }; }
    if cycle.status == 2 { return Answer { status: 2, visits: a.visits - before }; }
    if a.edges.len + a.evidence.len + 2 > 16384 { return Answer { status: 2, visits: a.visits - before }; }
    var previous: u32 = 0;
    var current = a.heads[left - 1];
    while current != 0 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        if current > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
        let candidate = a.edges[current - 1];
        if candidate.from != left || !valid_id(a, candidate.to) { return Answer { status: 1, visits: a.visits - before }; }
        if candidate.to > right || (candidate.to == right && !candidate.strict && strict) { break; }
        previous = current;
        current = candidate.next;
    }
    for i in 2 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    }
    a.evidence.push(Evidence { 0, left, right, strict, 0, 0, a.scope });
    let evidence = a.evidence.len as u32;
    a.edges.push(Edge { left, right, strict, current, evidence });
    let edge = a.edges.len as u32;
    if previous == 0 { a.heads[left - 1] = edge; } else { a.edges[previous - 1].next = edge; }
    return Answer { status: 0, id: evidence, visits: a.visits - before };
}

// Query a directed path using stable adjacency ordering. Each worklist state
// records whether a strict edge has appeared, so <= and < remain distinct.
// A successful answer names a DAG of explicit assumptions and transitivity.
fn query_le(a: Arena&, left: u32, right: u32, strict: bool) -> Answer {
    let before = a.visits;
    if !valid_id(a, left) || !valid_id(a, right) || a.terms[left - 1].sort != a.terms[right - 1].sort {
        return Answer { status: 1 };
    }
    let graph = check_graph(a);
    if graph.status != 0 { return Answer { status: graph.status, visits: a.visits - before }; }
    if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    let l = a.terms[left - 1];
    let r = a.terms[right - 1];
    if (!strict && left == right) || (l.kind == 0 && r.kind == 0 &&
       (l.value < r.value || (!strict && l.value == r.value))) {
        if a.edges.len + a.evidence.len + 1 > 16384 { return Answer { status: 2, visits: a.visits - before }; }
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        a.evidence.push(Evidence { if left == right { 1 } else { 2 }, left, right, strict, 0, 0, a.scope });
        return Answer { status: 0, id: a.evidence.len as u32, visits: a.visits - before };
    }
    // Contradictory assumptions do not prove x < x or a false literal order.
    if (strict && left == right) || (l.kind == 0 && r.kind == 0) {
        return Answer { status: 3, visits: a.visits - before };
    }
    var queue: Step[..8192] = [];
    let start = (left - 1) * 2;
    queue.push(Step { start, 0, 0 });
    var head = 0;
    var found: u32 = 0;
    var has_result = false;
    while head < queue.len && !has_result {
        let state = queue[head].state;
        let previous = head as u32;
        head += 1;
        let term = state / 2 + 1;
        var edge = a.heads[term - 1];
        while edge != 0 {
            if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
            if edge > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
            let item = a.edges[edge - 1];
            if item.from != term || !valid_id(a, item.to) || item.evidence == 0 || item.evidence > a.evidence.len {
                return Answer { status: 1, visits: a.visits - before };
            }
            let is_strict = state % 2 == 1 || item.strict;
            let next = (item.to - 1) * 2 + (if is_strict { 1 } else { 0 });
            var seen = false;
            for step in queue {
                if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
                if step.state == next { seen = true; break; }
            }
            if !seen {
                if queue.len == 8192 { return Answer { status: 2, visits: a.visits - before }; }
                queue.push(Step { next, previous, edge });
                if item.to == right && (!strict || is_strict) {
                    found = (queue.len - 1) as u32;
                    has_result = true;
                    break;
                }
            }
            edge = item.next;
        }
    }
    if !has_result { return Answer { status: 3, visits: a.visits - before }; }
    var path: u32[..8192] = [];
    var cursor = found;
    while cursor != 0 {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        let step = queue[cursor];
        path.push(step.edge);
        cursor = step.previous;
    }
    let additional = path.len - 1;
    if a.edges.len + a.evidence.len + additional > 16384 { return Answer { status: 2, visits: a.visits - before }; }
    // Reserve logical work before publishing any new nodes.
    for i in additional {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
    }
    var i = path.len - 1;
    let first = a.edges[path[i] - 1];
    var answer = first.evidence;
    var is_strict = first.strict;
    while i > 0 {
        i -= 1;
        let next = a.edges[path[i] - 1];
        is_strict = is_strict || next.strict;
        a.evidence.push(Evidence { 3, left, next.to, is_strict, answer, next.evidence, a.scope });
        answer = a.evidence.len as u32;
    }
    return Answer { status: 0, id: answer, visits: a.visits - before };
}

// Structural checking only: assumptions must still be established by the
// enclosing completed contract. In particular, this validates neither their
// source provenance nor the safety of importing them from an artifact.
fn validate_evidence(a: Arena&, target: u32) -> Answer {
    let before = a.visits;
    if target == 0 || target > a.evidence.len { return Answer { status: 1 }; }
    let graph = check_graph(a);
    if graph.status != 0 { return Answer { status: graph.status, visits: a.visits - before }; }
    for n in target {
        if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
        let node = a.evidence[n];
        if node.scope != a.scope || !valid_id(a, node.left) || !valid_id(a, node.right) ||
           a.terms[node.left - 1].sort != a.terms[node.right - 1].sort {
            return Answer { status: 1, visits: a.visits - before };
        }
        if node.rule == 0 {
            if node.prior != 0 || node.edge != 0 { return Answer { status: 1, visits: a.visits - before }; }
            var edge = a.heads[node.left - 1];
            var matched = false;
            while edge != 0 {
                if !charge(a) { return Answer { status: 2, visits: a.visits - before }; }
                if edge > a.edges.len { return Answer { status: 1, visits: a.visits - before }; }
                let item = a.edges[edge - 1];
                if item.from != node.left { return Answer { status: 1, visits: a.visits - before }; }
                if item.evidence == n + 1 && item.to == node.right && item.strict == node.strict { matched = true; break; }
                edge = item.next;
            }
            if !matched { return Answer { status: 1, visits: a.visits - before }; }
        } else if node.rule == 1 {
            if node.left != node.right || node.strict || node.prior != 0 || node.edge != 0 {
                return Answer { status: 1, visits: a.visits - before };
            }
        } else if node.rule == 2 {
            let l = a.terms[node.left - 1];
            let r = a.terms[node.right - 1];
            if l.kind != 0 || r.kind != 0 || node.prior != 0 || node.edge != 0 ||
               l.value > r.value || (node.strict && l.value == r.value) {
                return Answer { status: 1, visits: a.visits - before };
            }
        } else if node.rule == 3 {
            if node.prior == 0 || node.edge == 0 || node.prior > n || node.edge > n {
                return Answer { status: 1, visits: a.visits - before };
            }
            let p = a.evidence[node.prior - 1];
            let e = a.evidence[node.edge - 1];
            if p.left != node.left || p.right != e.left || e.right != node.right ||
               node.strict != (p.strict || e.strict) {
                return Answer { status: 1, visits: a.visits - before };
            }
        } else { return Answer { status: 1, visits: a.visits - before }; }
    }
    return Answer { status: 0, id: target, visits: a.visits - before };
}
