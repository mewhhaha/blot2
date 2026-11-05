// Recipes establish consistent requirements; producers still need witnesses.
namespace blot_check_numeric_proof_contracts;
import std;
import dictionary;
import support.error;
import support.option;
type Error = blot_error::Error;
type Id = blot_check_numeric_proof_terms::Id;
type Proposition = blot_check_numeric_proof_terms::Proposition;
type Term = blot_check_numeric_proof_terms::Term;
type Kind = blot_check_numeric_proof_terms::Kind;
type Relation = blot_check_numeric_proof_terms::Relation;
type Tag = blot_check_numeric_proof_terms::Tag;
type Limits = blot_check_numeric_proof_terms::Limits;
struct Stats { terms: i64 = 0, edges: i64 = 0, visits: i64 = 0 }
struct Requirement { before: u32, proposition: Proposition }
struct Contract { values: const Kind[:], operands: const Term[:], requirements: const Requirement[:], result: blot_support::Option<Proposition> = blot_support::Option<Proposition> { false, default<Proposition>() , ..} }
struct Signature { arity: u32, value_slots: const u32[:], proof_slots: const u32[:], contract: Contract }
fn validate(self: Signature, limits: Limits) -> Error { let measured, error = validateMeasured(self, limits); return error; }
fn validateMeasured(self: Signature, limits: Limits) -> Stats, Error {
    if self.arity > limits.terms { return Stats {..}, Error.proof_analysis_limit; }
    if self.value_slots.len != self.contract.values.len || self.proof_slots.len != self.contract.requirements.len { return Stats {..}, Error.invalid_proof_operand; }
    for slots in [self.value_slots, self.proof_slots] {
        for slot, i in slots { if slot >= self.arity || (i != 0 && slot <= slots[i - 1]) { return Stats {..}, Error.proof_scope_escape; } }
    }
    var values: i64 = 0;
    for slot, i in self.proof_slots {
        let requirement = self.contract.requirements[i];
        while values < self.value_slots.len && self.value_slots[values] < slot { values += 1; }
        if values < self.value_slots.len && self.value_slots[values] == slot { return Stats {..}, Error.invalid_proof_operand; }
        if requirement.before != values { return Stats {..}, Error.proof_scope_escape; }
    }
    let visits = self.value_slots.len + self.proof_slots.len; if visits > limits.visits { return Stats {..}, Error.proof_analysis_limit; }
    var remaining = limits; remaining.visits -= visits;
    let measured, error = validateMeasured(self.contract, remaining); if error != Error.none { return Stats {..}, error; }
    var result = measured; result.visits += visits; return result, Error.none;
}
fn validateInto(self: Signature, destination: blot_check_numeric_proof_terms::Store&) -> Error {
    var remaining = destination.limits; remaining.visits = max(remaining.visits - destination.visits, 0);
    let measured, error = validateMeasured(self, remaining); if error != Error.none { return error; } return destination.charge(measured.visits);
}
fn instantiate(self: Signature, destination: blot_check_numeric_proof_terms::Store&, arguments: const Id[:]) -> Proposition[>..], Error {
    let validity = validateInto(self, destination); if validity != Error.none { return [], validity; }
    if arguments.len != self.arity { return [], Error.proof_scope_escape; } var next_value: i64 = 0;
    for argument, slot in arguments {
        if next_value < self.value_slots.len && self.value_slots[next_value] == slot { next_value += 1; }
        else if argument != 0 { return [], Error.invalid_proof_operand; }
    }
    var formals: Id[>..] = [];
    for slot, i in self.value_slots {
        let actual = arguments[slot]; let term, error = destination.view().get(actual); if error != Error.none { return [], error; }
        if term.kind != self.contract.values[i] { return [], Error.invalid_proof_operand; } formals.push(actual);
    }
    var propositions: Proposition[>..] = [];
    for requirement in self.contract.requirements { propositions.push(requirement.proposition); }
    if self.contract.result.present { propositions.push(self.contract.result.value); }
    return destination.importMany(blot_check_numeric_proof_terms::View { self.contract.operands , ..}, propositions,
        blot_check_numeric_proof_terms::Boundary { self.contract.values , ..}, blot_check_numeric_proof_terms::Substitution { formals: formals , ..});
}
fn instantiateRequirement(self: Signature, destination: blot_check_numeric_proof_terms::Store&, slot: u32, preceding: const Id[:]) -> Proposition, Error {
    let validity = validateInto(self, destination); if validity != Error.none { return default<Proposition>(), validity; }
    if slot != preceding.len || slot >= self.arity { return default<Proposition>(), Error.proof_scope_escape; }
    var requested: blot_support::Option<Proposition> = blot_support::Option<Proposition> { false, default<Proposition>() , ..};
    for position, i in self.proof_slots { if position == slot { requested = blot_support::Option<Proposition> { true, self.contract.requirements[i].proposition , ..}; break; } }
    if !requested.present { return default<Proposition>(), Error.invalid_proof_operand; }
    var formals: Id[>..] = []; for item in self.value_slots { formals.push(0); }
    var next: i64 = 0;
    for actual, position in preceding {
        if next < self.value_slots.len && self.value_slots[next] == position {
            let term, error = destination.view().get(actual); if error != Error.none { return default<Proposition>(), error; }
            if term.kind != self.contract.values[next] { return default<Proposition>(), Error.invalid_proof_operand; }
            formals[next] = actual; next += 1;
        } else if actual != 0 { return default<Proposition>(), Error.invalid_proof_operand; }
    }
    return destination.importProof(blot_check_numeric_proof_terms::View { self.contract.operands , ..}, requested.value,
        blot_check_numeric_proof_terms::Boundary { self.contract.values , ..}, blot_check_numeric_proof_terms::Substitution { formals: formals , ..});
}
fn validate(self: Contract, limits: Limits) -> Error { let measured, error = validateMeasured(self, limits); return error; }
fn validateMeasured(self: Contract, limits: Limits) -> Stats, Error {
    if self.values.len > limits.terms || self.requirements.len > 256 { return Stats {..}, Error.proof_analysis_limit; }
    let source = blot_check_numeric_proof_terms::View { self.operands , ..};
    let validity = source.validate(blot_check_numeric_proof_terms::Boundary { self.values , ..}, limits); if validity != Error.none { return Stats {..}, validity; }
    if self.requirements.len == 0 && !self.result.present { return Stats { terms: self.operands.len, visits: self.operands.len , ..}, Error.none; }
    var terms: Term[>..<] = []; var index = dictionary<Term, Id> {}; var owned = blot_check_numeric_proof_terms::init(terms, index);
    owned.limits = limits; owned.visits = self.operands.len; var mapping: Id[>..] = [];
    for input in self.operands {
        var term = input; if term.tag == Tag.length || term.tag == Tag.complement { term.a = mapping[term.a - 1]; }
        let target, error = owned.intern(term); if error != Error.none { return Stats {..}, error; } mapping.push(target);
    }
    let initial_visits = owned.visits; var edges: Edge[>..] = [];
    var graph = Order { edges, max(limits.visits - initial_visits, 0) , ..}; var prior: u32 = 0;
    for requirement in self.requirements {
        if requirement.before < prior || requirement.before > self.values.len { return Stats {..}, Error.proof_scope_escape; } prior = requirement.before;
        let scope = inScope(source, requirement.proposition, requirement.before); if scope != Error.none { return Stats {..}, scope; }
        let added = proposition(graph, owned, remap(mapping, requirement.proposition)); if added != Error.none { return Stats {..}, added; }
    }
    if self.result.present {
        let scope = inScope(source, self.result.value, self.values.len); if scope != Error.none { return Stats {..}, scope; }
        let added = proposition(graph, owned, remap(mapping, self.result.value)); if added != Error.none { return Stats {..}, added; }
    }
    let dual = complements(graph, owned); if dual != Error.none { return Stats {..}, dual; }
    let bounded = bounds(graph, owned); if bounded != Error.none { return Stats {..}, bounded; }
    let normalized = spend(graph, owned.visits - initial_visits); if normalized != Error.none { return Stats {..}, normalized; }
    let consistent = checkConsistency(graph, owned.terms.len); if consistent != Error.none { return Stats {..}, consistent; }
    return Stats { owned.terms.len, graph.edges.len, limits.visits - graph.remaining , ..}, Error.none;
}
fn inScope(source: blot_check_numeric_proof_terms::View, proof: Proposition, before: i64) -> Error {
    let validity = source.proposition(proof); if validity != Error.none { return validity; }
    for root in [proof.left, proof.right] {
        var cursor = root;
        for step in 3 {
            let term, error = source.get(cursor); if error != Error.none { return error; }
            match term.tag {
                literal => { break; }, formal => { if term.a >= before { return Error.proof_scope_escape; } break; },
                length, complement => { cursor = term.a; }, capture, version => { return Error.proof_scope_escape; },
            }
        }
    }
    return Error.none;
}
fn remap(mapping: const Id[:], proof: Proposition) -> Proposition { return Proposition { proof.relation, mapping[proof.left - 1], mapping[proof.right - 1] , ..}; }
struct Pair { left: Id, right: Id }
struct Edge { pair: Pair, strict: bool }
struct Constraint { forward: Edge, reverse: bool = false }
struct Unequal { left: Id, right: Id }
struct Order { edges: Edge[>..]&, remaining: i64, needs_complements: bool = false }
fn spend(self: Order&, count: i64) -> Error { if count > self.remaining { return Error.proof_analysis_limit; } self.remaining -= count; return Error.none; }
fn charge(self: Order&) -> Error { return spend(self, 1); }
fn edge(self: Order&, left: Id, right: Id, strict: bool) -> Error {
    let charged = charge(self); if charged != Error.none { return charged; }
    if left == right { if strict { return Error.contradictory_proof; } return Error.none; }
    self.edges.push(Edge { Pair { left, right }, strict , ..}); return Error.none;
}
fn constraint(self: Order&, store: blot_check_numeric_proof_terms::Store&, value: Proposition) -> Constraint, Error {
    let validity = store.view().proposition(value); if validity != Error.none { return default<Constraint>(), validity; }
    self.needs_complements = self.needs_complements || store.terms[value.left - 1].tag == Tag.complement || store.terms[value.right - 1].tag == Tag.complement;
    match value.relation {
        eq, lt, le => { return Constraint { Edge { Pair { value.left, value.right }, value.relation == Relation.lt }, value.relation == Relation.eq , ..}, Error.none; },
        sub_fits => { return Constraint { Edge { Pair { value.right, value.left }, false } , ..}, Error.none; },
        add_fits => {
            let complement, error = store.intern(Term { Tag.complement, a: value.right , ..}); if error != Error.none { return default<Constraint>(), error; }
            self.needs_complements = self.needs_complements || store.terms[complement - 1].tag == Tag.complement;
            return Constraint { Edge { Pair { value.left, complement }, false } , ..}, Error.none;
        },
        index => { let length, error = store.intern(Term { Tag.length, a: value.left , ..}); if error != Error.none { return default<Constraint>(), error; } return Constraint { Edge { Pair { value.right, length }, true } , ..}, Error.none; },
    }
}
fn proposition(self: Order&, store: blot_check_numeric_proof_terms::Store&, value: Proposition) -> Error {
    let item, error = constraint(self, store, value); if error != Error.none { return error; }
    let added = edge(self, item.forward.pair.left, item.forward.pair.right, item.forward.strict); if added != Error.none { return added; }
    if item.reverse { return edge(self, item.forward.pair.right, item.forward.pair.left, false); } return Error.none;
}
fn bounds(self: Order&, store: blot_check_numeric_proof_terms::Store&) -> Error {
    let zero, ze = store.intern(Term { Tag.literal, a: 0 , ..}); if ze != Error.none { return ze; }
    let maximum, me = store.intern(Term { Tag.literal, a: 0xffffffff , ..}); if me != Error.none { return me; }
    for term, ordinal in store.terms {
        if term.kind != Kind.unsigned32 { continue; } let id = (ordinal + 1) as u32;
        let lower = edge(self, zero, id, false); if lower != Error.none { return lower; } let upper = edge(self, id, maximum, false); if upper != Error.none { return upper; }
        if term.tag != Tag.literal { continue; }
        for other, other_ordinal in store.terms[..ordinal] {
            let charged = charge(self); if charged != Error.none { return charged; } if other.tag != Tag.literal { continue; }
            let other_id = (other_ordinal + 1) as u32;
            if other.a < term.a { let added = edge(self, other_id, id, true); if added != Error.none { return added; } }
            else if term.a < other.a { let added = edge(self, id, other_id, true); if added != Error.none { return added; } }
        }
    }
    return Error.none;
}
struct Step { node: Id, strict: bool }
fn reaches(self: Order&, count: i64, requested: Edge) -> bool, Error {
    let charged = spend(self, count + self.edges.len); if charged != Error.none { return false, charged; }
    var first: i64[>..] = []; for index in count + 1 { first.push(-1); }
    var next: i64[>..] = [];
    for item, index in self.edges { next.push(first[item.pair.left]); first[item.pair.left] = index; }
    var seen: bool[2][>..] = []; for index in count + 1 { seen.push([false, false]); }
    if count + 1 > 0x7fffffffffffffff / 2 { return false, Error.proof_analysis_limit; }
    var queue: Step[>..] = []; queue.push(Step { requested.pair.left, false , ..}); seen[requested.pair.left][0] = true;
    var begin: i64 = 0;
    while begin < queue.len {
        let current = queue[begin]; begin += 1; let charged = charge(self); if charged != Error.none { return false, charged; }
        if current.node == requested.pair.right && (current.strict || !requested.strict) { return true, Error.none; }
        var edge_id = first[current.node];
        while edge_id != -1 {
            let charged = charge(self); if charged != Error.none { return false, charged; } let item = self.edges[edge_id]; let strict = current.strict || item.strict;
            var state: i64 = 0; if strict { state = 1; }
            if !seen[item.pair.right][state] { seen[item.pair.right][state] = true; queue.push(Step { item.pair.right, strict , ..}); }
            edge_id = next[edge_id];
        }
    }
    return false, Error.none;
}
fn complements(self: Order&, store: blot_check_numeric_proof_terms::Store&) -> Error {
    if !self.needs_complements { return Error.none; } let count = store.terms.len;
    if count == 0x7fffffffffffffff { return Error.proof_analysis_limit; }
    var opposite: Id[>..] = []; for index in count + 1 { opposite.push(0); }
    for id in 1..count + 1 { if store.terms[id - 1].kind == Kind.unsigned32 { let value, error = store.intern(Term { Tag.complement, a: id as u32 , ..}); if error != Error.none { return error; } opposite[id] = value; } }
    let edges = self.edges.len;
    for index in edges { let prior = self.edges[index]; let added = edge(self, opposite[prior.pair.right], opposite[prior.pair.left], prior.strict); if added != Error.none { return added; } }
    return Error.none;
}
struct State { index: u32 = 0, low: u32 = 0, component: u32 = 0, first: i64 = -1 }
struct Frame { node: Id, next: i64 }
fn checkConsistency(self: Order&, count: i64) -> Error {
    let charged = spend(self, count + self.edges.len); if charged != Error.none { return charged; }
    var states: State[>..] = []; for index in count + 1 { states.push(State {..}); }
    var next: i64[>..] = []; for item, edge_id in self.edges { next.push(states[item.pair.left].first); states[item.pair.left].first = edge_id; }
    var frames: Frame[>..<] = []; var stack: Id[>..<] = []; var discovered: u32 = 0; var component: u32 = 0;
    for root_ in 1..count + 1 {
        let charged = charge(self); if charged != Error.none { return charged; } let root = root_ as u32; if states[root].index != 0 { continue; }
        discovered += 1; states[root].index = discovered; states[root].low = discovered;
        stack.push(root); frames.push(Frame { root, states[root].first , ..});
        while frames.len != 0 {
            let top = frames.len - 1;
            if frames[top].next != -1 {
                let charged = charge(self); if charged != Error.none { return charged; }
                let edge_id = frames[top].next; frames[top].next = next[edge_id]; let child = self.edges[edge_id].pair.right;
                if states[child].index == 0 { discovered += 1; states[child].index = discovered; states[child].low = discovered; stack.push(child); frames.push(Frame { child, states[child].first , ..}); }
                else if states[child].component == 0 { let parent = frames[top].node; states[parent].low = min(states[parent].low, states[child].index); }
                continue;
            }
            let finished = frames.pop().node;
            if states[finished].low == states[finished].index {
                component += 1;
                while stack.len > 0 { let member = stack.pop(); let charged = charge(self); if charged != Error.none { return charged; } states[member].component = component; if member == finished { break; } }
            }
            if frames.len != 0 { let parent = frames[frames.len - 1].node; states[parent].low = min(states[parent].low, states[finished].low); }
        }
    }
    for item in self.edges { let charged = charge(self); if charged != Error.none { return charged; } if item.strict && states[item.pair.left].component == states[item.pair.right].component { return Error.contradictory_proof; } }
    return Error.none;
}
fn entails(store: blot_check_numeric_proof_terms::Store&, facts: const Proposition[:], goal: Proposition) -> bool, Error { return entailsWithUnequal(store, facts, [], goal); }
fn entailsWithUnequal(store: blot_check_numeric_proof_terms::Store&, facts: const Proposition[:], unequal: const Unequal[:], goal: Proposition) -> bool, Error {
    let initial_visits = store.visits; let budget = max(store.limits.visits - initial_visits, 0); var edges: Edge[>..] = []; var graph = Order { edges, budget , ..}; var normalized_visits: i64 = 0;
    let result, error = entailsGraph(graph, store, facts, unequal, goal, initial_visits, normalized_visits);
    let added = budget - graph.remaining - normalized_visits; store.visits = min(store.limits.visits, store.visits + added); return result, error;
}
fn entailsGraph(graph: Order&, store: blot_check_numeric_proof_terms::Store&, facts: const Proposition[:], unequal: const Unequal[:], goal: Proposition,
                 initial_visits: i64, normalized_visits: i64&) -> bool, Error {
    for fact in facts { let added = proposition(graph, store, fact); if added != Error.none { return false, added; } }
    let requested, error = constraint(graph, store, goal); if error != Error.none { return false, error; }
    let dual = complements(graph, store); if dual != Error.none { return false, dual; }
    let bounded = bounds(graph, store); if bounded != Error.none { return false, bounded; }
    let visits = store.visits - initial_visits; let spent = spend(graph, visits); if spent != Error.none { return false, spent; } normalized_visits = visits;
    let consistency = checkConsistency(graph, store.terms.len); if consistency != Error.none { return false, consistency; }
    for pair in unequal {
        let validity = store.view().proposition(Proposition { Relation.eq, pair.left, pair.right , ..}); if validity != Error.none { return false, validity; }
        let forward, fe = reaches(graph, store.terms.len, Edge { Pair { pair.left, pair.right }, false , ..}); if fe != Error.none { return false, fe; }
        if forward { let added = edge(graph, pair.left, pair.right, true); if added != Error.none { return false, added; } }
        else { let reverse, re = reaches(graph, store.terms.len, Edge { Pair { pair.right, pair.left }, false , ..}); if re != Error.none { return false, re; } if reverse { let added = edge(graph, pair.right, pair.left, true); if added != Error.none { return false, added; } } }
    }
    if unequal.len != 0 { let consistency = checkConsistency(graph, store.terms.len); if consistency != Error.none { return false, consistency; } }
    let forward, error = reaches(graph, store.terms.len, requested.forward); if error != Error.none || !forward { return forward, error; }
    if requested.reverse { return reaches(graph, store.terms.len, Edge { Pair { requested.forward.pair.right, requested.forward.pair.left }, false , ..}); } return true, Error.none;
}
