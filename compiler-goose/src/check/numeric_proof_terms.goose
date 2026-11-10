// Numeric propositions own value identities, never lengths or addresses.
namespace blot_check_numeric_proof_terms;
import .numeric_proof_names;
import support.error;
import support.native;
import support.structural_adapters;

import support.structural;
import std;
import dictionary;
type Id = u32;
enum Kind { unsigned32, array, list }
enum Tag { literal, formal, capture, version, length, complement }
struct Term { tag: Tag, kind: Kind = Kind.unsigned32, a: u32, b: u32 = 0 }
struct Proposition { relation: Relation, left: Id, right: Id }
struct Limits { terms: i64 = 4096, visits: i64 = 65536 }
struct Boundary { formals: const Kind[:], captures: const Kind[:] = default<const Kind[:]>(), local_versions: bool = false }
fn holds(relation: Relation, left: u32, right: u32) -> bool {
    match relation {
        eq => { return left == right; }, lt => { return left < right; }, le => { return left <= right; },
        add_fits => { return (left as u64) + right <= 0xffffffff; },
        sub_fits => { return right <= left; }, index => { return right < left; },
    }
}
struct View { terms: const Term[:], owner_id: u64 = 0 }
fn get(self_: View, id: Id) -> Term, blot_error::Error {
    if id == 0 || id > self_.terms.len { return default<Term>(), blot_error::Error.invalid_proof_operand; }
    return self_.terms[id - 1], blot_error::Error.none;
}
fn proposition(self_: View, value: Proposition) -> blot_error::Error {
    let left, le = get(self_, value.left); if le != blot_error::Error.none { return le; }
    let right, re = get(self_, value.right); if re != blot_error::Error.none { return re; }
    if right.kind != Kind.unsigned32 { return blot_error::Error.invalid_proof_operand; }
    if value.relation == Relation.index {
        if left.kind == Kind.unsigned32 { return blot_error::Error.invalid_proof_operand; }
    } else if left.kind != Kind.unsigned32 { return blot_error::Error.invalid_proof_operand; }
    return blot_error::Error.none;
}
fn validate(self_: View, boundary: Boundary, limits: Limits) -> blot_error::Error {
    if self_.terms.len > limits.terms || self_.terms.len > limits.visits { return blot_error::Error.proof_analysis_limit; }
    for term, index in self_.terms {
        match term.tag {
            literal => { if term.kind != Kind.unsigned32 || term.b != 0 { return blot_error::Error.invalid_proof_operand; } },
            formal => {
                if term.b != 0 || term.a >= boundary.formals.len { return blot_error::Error.proof_scope_escape; }
                if term.kind != boundary.formals[term.a] { return blot_error::Error.invalid_proof_operand; }
            },
            capture => {
                if term.b != 0 || term.a >= boundary.captures.len { return blot_error::Error.proof_scope_escape; }
                if term.kind != boundary.captures[term.a] { return blot_error::Error.invalid_proof_operand; }
            },
            version => { if !boundary.local_versions || term.a == 0 || term.b == 0 { return blot_error::Error.proof_scope_escape; } },
            length => {
                if term.kind != Kind.unsigned32 || term.b != 0 || term.a == 0 || term.a > index { return blot_error::Error.invalid_proof_operand; }
                let child, error = get(self_, term.a); if error != blot_error::Error.none { return error; }
                if child.kind == Kind.unsigned32 { return blot_error::Error.invalid_proof_operand; }
            },
            complement => {
                if term.kind != Kind.unsigned32 || term.b != 0 || term.a == 0 || term.a > index { return blot_error::Error.invalid_proof_operand; }
                let child, error = get(self_, term.a); if error != blot_error::Error.none { return error; }
                if child.kind != Kind.unsigned32 || child.tag == Tag.literal || child.tag == Tag.complement { return blot_error::Error.invalid_proof_operand; }
            },
        }
    }
    return blot_error::Error.none;
}
struct Owned { terms: const Term[:], owner_id: u64 }
fn view(self_: Owned) -> View { return View { self_.terms, self_.owner_id , ..}; }
fn deinit(self_: Owned&) { self_.terms = default<const blot_check_numeric_proof_terms::Term[:]>(); self_.owner_id = 0; }
struct Substitution { formals: const Id[:] = default<const Id[:]>(), captures: const Id[:] = default<const Id[:]>(), versions: const Id[:] = default<const Id[:]>() }
struct Store {
    terms: Term[>..]&, index: dictionary<Term, Id>&,
    limits: Limits = Limits {..}, visits: i64 = 0, account: i64? = null, owner_id: u64,
}
fn init(terms: Term[>..]&, index: dictionary<Term, Id>&) -> Store {
    return Store { terms: terms, index: index, owner_id: blot_native::fresh_owner_id() , ..};
}
fn deinit(self_: Store&) { ::clear(self_.index); self_.owner_id = 0; }
fn view(self_: const Store&) -> View { return termView(self_.terms,self_.index.count,self_.owner_id); }
// The index owns the live prefix; failed imports retain reusable backing capacity.
fn activeTerms(terms:Term[>..]&,count:i64)->const Term[:] {return terms[..count];}
fn termView(terms:Term[>..]&,count:i64,owner_id:u64)->View {return View{terms[..count],owner_id,..};}
fn charge(self_: Store&, amount: i64) -> blot_error::Error {
    var available: i64 = 0;
    if self_.visits < self_.limits.visits { available = self_.limits.visits - self_.visits; }
    if amount > available { return blot_error::Error.proof_analysis_limit; }
    self_.visits += amount;
    let account = self_.account; if account { account += amount; }
    return blot_error::Error.none;
}
// A literal complement charges the visit its nested intern would have charged.
fn intern(self_: Store&, term: Term) -> Id, blot_error::Error {
    let charged = charge(self_, 1); if charged != blot_error::Error.none { return 0, charged; }
    var selected = term;
    match term.tag {
        literal => { if term.kind != Kind.unsigned32 || term.b != 0 { return 0, blot_error::Error.invalid_proof_operand; } },
        formal, capture => { if term.b != 0 { return 0, blot_error::Error.invalid_proof_operand; } },
        version => { if term.a == 0 || term.b == 0 { return 0, blot_error::Error.invalid_proof_operand; } },
        length => {
            if term.kind != Kind.unsigned32 || term.b != 0 { return 0, blot_error::Error.invalid_proof_operand; }
            let child, error = get(view(self_), term.a); if error != blot_error::Error.none { return 0, error; }
            if child.kind == Kind.unsigned32 { return 0, blot_error::Error.invalid_proof_operand; }
        },
        complement => {
            if term.kind != Kind.unsigned32 || term.b != 0 { return 0, blot_error::Error.invalid_proof_operand; }
            let child, error = get(view(self_), term.a); if error != blot_error::Error.none { return 0, error; }
            if child.kind != Kind.unsigned32 { return 0, blot_error::Error.invalid_proof_operand; }
            if child.tag == Tag.literal { let recharged = charge(self_, 1); if recharged != blot_error::Error.none { return 0, recharged; } selected = Term { tag: Tag.literal, a: 0xffffffff - child.a , ..}; }
            if child.tag == Tag.complement { return child.a, blot_error::Error.none; }
        },
    }
    block { let saved = ::get(self_.index,selected); if saved { return saved, blot_error::Error.none; } }
    if self_.index.count >= min(self_.limits.terms, 0xffffffff) { return 0, blot_error::Error.proof_analysis_limit; }
    let position=self_.index.count;
    if position<self_.terms.len {self_.terms[position]=selected;}
    else {self_.terms.push(selected);}
    let id = (position+1) as u32;
    ::insert(self_.index,selected,id);
    return id, blot_error::Error.none;
}
fn copyOwned(self_: const Store&, destination: Term[>..]&) -> Owned, blot_error::Error {
    let start = destination.len; destination.append(activeTerms(self_.terms,self_.index.count));
    return Owned { destination[start..], blot_native::fresh_owner_id() , ..}, blot_error::Error.none;
}
fn importProof(self_: Store&, source: View, proof: Proposition, boundary: Boundary, substitution: Substitution) -> Proposition, blot_error::Error {
    var result: Proposition[1] = [default<Proposition>(); 1];
    let error = importInto(self_, source, [proof], result, boundary, substitution);
    if error != blot_error::Error.none { return default<Proposition>(), error; }
    return result[0], blot_error::Error.none;
}
fn importMany(self_: Store&, source: View, proofs: const Proposition[:], boundary: Boundary, substitution: Substitution) -> Proposition[>..], blot_error::Error {
    var result: Proposition[>..] = [];
    for proof in proofs { result.push(default<Proposition>()); }
    let error = importInto(self_, source, proofs, result, boundary, substitution);
    if error != blot_error::Error.none { return [], error; }
    return result, blot_error::Error.none;
}
// Either first element lies in the other range exactly when aligned term slices overlap.
fn overlaps(left:const Term[:],right:const Term[:])->bool {
    if left.len==0 || right.len==0 {return false;}
    for &value in left {if value .==right[0] {return true;}}
    for &value in right {if value .==left[0] {return true;}}
    return false;
}
fn importInto(self_: Store&, source: View, proofs: const Proposition[:], results: Proposition[:], boundary: Boundary, substitution: Substitution) -> blot_error::Error {
    if source.terms.len != 0 && self_.terms.len != 0 {
        if (source.owner_id != 0 && source.owner_id == self_.owner_id) ||
           overlaps(self_.terms, source.terms) {
            return blot_error::Error.invalid_proof_operand;
        }
    }
    let validity = validate(source, boundary, self_.limits); if validity != blot_error::Error.none { return validity; }
    let source_charge = charge(self_, source.terms.len); if source_charge != blot_error::Error.none { return source_charge; }
    let proof_charge = charge(self_, proofs.len); if proof_charge != blot_error::Error.none { return proof_charge; }
    for proof in proofs { let validity = proposition(source, proof); if validity != blot_error::Error.none { return validity; } }
    let initial = self_.index.count;
    var map: Id[>..] = []; for term in source.terms { map.push(0); }
    var context = Context { self_, source, map, substitution , ..};
    let error = importResults(context, proofs, results);
    if error != blot_error::Error.none {
        while self_.index.count > initial { let removed = self_.terms[self_.index.count-1]; assert(::remove(self_.index,removed)); }
    }
    return error;
}
struct Context { target: Store&, source: View, map: Id[:], substitution: Substitution }
recursive fn importTerm(self_: Context&, id: Id) -> Id, blot_error::Error {
    let input, get_error = get(self_.source, id); if get_error != blot_error::Error.none { return 0, get_error; }
    let charged = charge(self_.target, 1); if charged != blot_error::Error.none { return 0, charged; }
    if self_.map[id - 1] != 0 { return self_.map[id - 1], blot_error::Error.none; }
    var output: Id = 0;
    match input.tag {
        literal => { let saved, error = intern(self_.target, input); if error != blot_error::Error.none { return 0, error; } output = saved; },
        length, complement => {
            let child, child_error = importTerm(self_, input.a); if child_error != blot_error::Error.none { return 0, child_error; }
            let saved, error = intern(self_.target, Term { tag: input.tag, a: child , ..}); if error != blot_error::Error.none { return 0, error; }
            output = saved;
        },
        formal, capture, version => {
            var values = self_.substitution.formals; var position = input.a;
            if input.tag == Tag.capture { values = self_.substitution.captures; }
            if input.tag == Tag.version { values = self_.substitution.versions; position = id - 1; }
            if position >= values.len { return 0, blot_error::Error.proof_scope_escape; }
            output = values[position];
            let actual, error = get(view(self_.target), output); if error != blot_error::Error.none { return 0, error; }
            if actual.kind != input.kind { return 0, blot_error::Error.invalid_proof_operand; }
        },
    }
    self_.map[id - 1] = output;
    return output, blot_error::Error.none;
}
fn importResults(context: Context&, proofs: const Proposition[:], results: Proposition[:]) -> blot_error::Error {
    for proof, i in proofs {
        let left, le = importTerm(context, proof.left); if le != blot_error::Error.none { return le; }
        let right, re = importTerm(context, proof.right); if re != blot_error::Error.none { return re; }
        results[i] = Proposition { proof.relation, left, right , ..};
    }
    return blot_error::Error.none;
}
fn hash(value: Term) -> u64 {
    var kind: u64 = 0; match value.kind { unsigned32 => {}, array => { kind = 1; }, list => { kind = 2; }, }
    var tag: u64 = 0; match value.tag { literal => {}, formal => { tag = 1; }, capture => { tag = 2; }, version => { tag = 3; }, length => { tag = 4; }, complement => { tag = 5; }, }
    return ::hash_combine(::hash_combine(::hash_combine(::hash(tag), ::hash(kind)), ::hash(value.a)), ::hash(value.b));
}

fn kindCode(value: Kind) -> u32 {
    match value {
        unsigned32 => { return 0; },
        array => { return 1; },
        list => { return 2; },
    }
}
fn kindFromCode(code: u32) -> Kind, blot_error::Error {
    match code {
        0 => { return Kind.unsigned32, blot_error::Error.none; },
        1 => { return Kind.array, blot_error::Error.none; },
        2 => { return Kind.list, blot_error::Error.none; },
        _ => { return Kind.unsigned32, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_numeric_proof_terms::Kind, right: blot_check_numeric_proof_terms::Kind) -> bool { return left == right; }
fn blot_check_numeric_proof_terms::blotStructuralHash<S>(value: blot_check_numeric_proof_terms::Kind,sink: S&) { blot_structural::hash(sink, blot_check_numeric_proof_terms::kindCode(value) as! u8); }

fn tagCode(value: Tag) -> u32 {
    match value {
        literal => { return 0; },
        formal => { return 1; },
        capture => { return 2; },
        version => { return 3; },
        length => { return 4; },
        complement => { return 5; },
    }
}
fn tagFromCode(code: u32) -> Tag, blot_error::Error {
    match code {
        0 => { return Tag.literal, blot_error::Error.none; },
        1 => { return Tag.formal, blot_error::Error.none; },
        2 => { return Tag.capture, blot_error::Error.none; },
        3 => { return Tag.version, blot_error::Error.none; },
        4 => { return Tag.length, blot_error::Error.none; },
        5 => { return Tag.complement, blot_error::Error.none; },
        _ => { return Tag.literal, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_numeric_proof_terms::Tag, right: blot_check_numeric_proof_terms::Tag) -> bool { return left == right; }
fn blot_check_numeric_proof_terms::blotStructuralHash<S>(value: blot_check_numeric_proof_terms::Tag,sink: S&) { blot_structural::hash(sink, blot_check_numeric_proof_terms::tagCode(value) as! u8); }

fn relationCode(value: Relation) -> u32 {
    match value {
        eq => { return 0; },
        lt => { return 1; },
        le => { return 2; },
        add_fits => { return 3; },
        sub_fits => { return 4; },
        index => { return 5; },
    }
}
fn relationFromCode(code: u32) -> Relation, blot_error::Error {
    match code {
        0 => { return Relation.eq, blot_error::Error.none; },
        1 => { return Relation.lt, blot_error::Error.none; },
        2 => { return Relation.le, blot_error::Error.none; },
        3 => { return Relation.add_fits, blot_error::Error.none; },
        4 => { return Relation.sub_fits, blot_error::Error.none; },
        5 => { return Relation.index, blot_error::Error.none; },
        _ => { return Relation.eq, blot_error::Error.invalid_artifact; },
    }
}

fn blot_structural::equal(left: blot_check_numeric_proof_terms::Relation, right: blot_check_numeric_proof_terms::Relation) -> bool { return left == right; }
fn blot_check_numeric_proof_terms::blotStructuralHash<S>(value: blot_check_numeric_proof_terms::Relation,sink: S&) { blot_structural::hash(sink, blot_check_numeric_proof_terms::relationCode(value) as! u8); }
