// Resolved operand kinds turn header syntax into owned positional contracts.
namespace blot_check_numeric_proof_headers;
import dictionary;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Kind = blot_check_numeric_proof_terms::Kind;
type Term = blot_check_numeric_proof_terms::Term;
type Proposition = blot_check_numeric_proof_terms::Proposition;
type Requirement = blot_check_numeric_proof_contracts::Requirement;
type Limits = blot_check_numeric_proof_terms::Limits;
struct Owned {
    arity: u32, value_slots: const u32[:] = [], proof_slots: const u32[:] = [], values: const Kind[:] = [],
    operands: const Term[:] = [], requirements: const Requirement[:] = [],
    result: blot_support::Option<Proposition> = blot_support::Option<Proposition> { false, default<Proposition>() },
}
struct OwnedTables { value_slots: u32[>..]&, proof_slots: u32[>..]&, values: Kind[>..]&, operands: Term[>..]&, requirements: Requirement[>..]& }
fn signature(self: Owned) -> blot_check_numeric_proof_contracts::Signature {
    return blot_check_numeric_proof_contracts::Signature { self.arity, self.value_slots, self.proof_slots,
        blot_check_numeric_proof_contracts::Contract { self.values, self.operands, self.requirements, self.result } };
}
fn clone(self: Owned, destination: OwnedTables) -> Owned, Error {
    let value_start = destination.value_slots.len; let proof_start = destination.proof_slots.len;
    let kind_start = destination.values.len; let operand_start = destination.operands.len; let requirement_start = destination.requirements.len;
    destination.value_slots.append(self.value_slots); destination.proof_slots.append(self.proof_slots);
    destination.values.append(self.values); destination.operands.append(self.operands); destination.requirements.append(self.requirements);
    return Owned { self.arity, destination.value_slots[value_start..], destination.proof_slots[proof_start..],
        destination.values[kind_start..], destination.operands[operand_start..], destination.requirements[requirement_start..], self.result }, Error.none;
}
fn deinit(self: Owned&) { self.value_slots = []; self.proof_slots = []; self.values = []; self.operands = []; self.requirements = []; self.result.present = false; }
struct Named { binding: u32, header: Owned }
fn find(values: const Named[:], binding: u32) -> const Owned? { for &value in values { if value.binding == binding { return value.header; } } return null; }
fn equal(left: Owned, right: Owned) -> bool { return blot_structural::equal(left, right); }
struct Binding { name: blot_parse_symbols::Symbol, formal: blot_support::Option<u32> }
struct Builder {
    tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&,
    store: blot_check_numeric_proof_terms::Store,
    bindings: Binding[>..]&, kinds: Kind[>..]&, value_slots: u32[>..]&, proof_slots: u32[>..]&, requirements: Requirement[>..]&,
}
fn visit(self: Builder&) -> Error { if self.store.visits >= self.store.limits.visits { return Error.proof_analysis_limit; } self.store.visits += 1; return Error.none; }
recursive fn contains(self: Builder&, id: blot_parse_ast::Id, depth: i64) -> bool, Error {
    if id == 0 { return false, Error.none; } if depth >= 128 { return false, Error.proof_analysis_limit; }
    let charged = visit(self); if charged != Error.none { return false, charged; }
    let node = self.tree.node(id);
    match node.tag {
        blot_parse_ast::tag_type_forall, blot_parse_ast::tag_type_exists => { return contains(self, self.tree.extra[node.c], depth + 1); },
        blot_parse_ast::tag_type_usage => { return contains(self, node.c, depth + 1); },
        blot_parse_ast::tag_type_name => { let relation, found = blot_check_numeric_proof_terms::typeName(self.pool.get(node.a)); return found, Error.none; },
        blot_parse_ast::tag_type_apply, blot_parse_ast::tag_type_effect => {
            let left, le = contains(self, node.a, depth + 1); if le != Error.none || left { return left, le; } return contains(self, node.b, depth + 1);
        },
        blot_parse_ast::tag_type_function => {
            let first, fe = contains(self, node.a, depth + 1); if fe != Error.none || first { return first, fe; }
            let second, se = contains(self, node.b, depth + 1); if se != Error.none || second { return second, se; } return contains(self, node.c, depth + 1);
        },
        blot_parse_ast::tag_group => { return contains(self, node.a, depth + 1); },
        blot_parse_ast::tag_type_binder, blot_parse_ast::tag_type_field => { return contains(self, node.b, depth + 1); },
        blot_parse_ast::tag_type_array, blot_parse_ast::tag_type_product, blot_parse_ast::tag_type_record, blot_parse_ast::tag_effect_row => {
            for child in self.tree.children(id) { let found, error = contains(self, child, depth + 1); if error != Error.none || found { return found, error; } }
        }, _ => {},
    }
    return false, Error.none;
}
recursive fn operand(self: Builder&, id: blot_parse_ast::Id, depth: i64) -> blot_check_numeric_proof_terms::Id, Error {
    if depth >= 128 { return 0, Error.proof_analysis_limit; } let charged = visit(self); if charged != Error.none { return 0, charged; }
    let node = self.tree.node(id);
    match node.tag {
        blot_parse_ast::tag_integer => { return self.store.intern(Term { blot_check_numeric_proof_terms::Tag.literal, a: node.a }); },
        blot_parse_ast::tag_group => { return operand(self, node.a, depth + 1); },
        blot_parse_ast::tag_type_name => {
            var i = self.bindings.len;
            while i != 0 {
                i -= 1; let charged = visit(self); if charged != Error.none { return 0, charged; }
                let binding = self.bindings[i]; if binding.name != node.a { continue; }
                if !binding.formal.present { return 0, Error.invalid_proof_operand; } let formal = binding.formal.value;
                return self.store.intern(Term { blot_check_numeric_proof_terms::Tag.formal, self.kinds[formal], formal });
            }
            return 0, Error.proof_scope_escape;
        },
        blot_parse_ast::tag_type_apply => {
            let head = self.tree.node(node.a); if head.tag != blot_parse_ast::tag_type_name { return 0, Error.invalid_proof_operand; }
            let name = self.pool.get(head.a); var kind = Kind.array;
            if name == "@list.length" { kind = Kind.list; } else if name != "@array.length" { return 0, Error.invalid_proof_operand; }
            if self.tree.node(node.b).tag != blot_parse_ast::tag_type_name { return 0, Error.invalid_proof_operand; }
            let collection, error = operand(self, node.b, depth + 1); if error != Error.none { return 0, error; }
            let term, error = self.store.view().get(collection); if error != Error.none { return 0, error; }
            if term.kind != kind { return 0, Error.invalid_proof_operand; }
            return self.store.intern(Term { blot_check_numeric_proof_terms::Tag.length, a: collection });
        },
        _ => { return 0, Error.invalid_proof_operand; },
    }
}
fn proposition(self: Builder&, id: blot_parse_ast::Id) -> blot_support::Option<Proposition>, Error {
    let charged = visit(self); if charged != Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() }, charged; }
    let outer = self.tree.node(id); if outer.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<Proposition> { false, default<Proposition>() }, Error.none; }
    let inner = self.tree.node(outer.a); if inner.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<Proposition> { false, default<Proposition>() }, Error.none; }
    let head = self.tree.node(inner.a); if head.tag != blot_parse_ast::tag_type_name { return blot_support::Option<Proposition> { false, default<Proposition>() }, Error.none; }
    let relation, found = blot_check_numeric_proof_terms::typeName(self.pool.get(head.a)); if !found { return blot_support::Option<Proposition> { false, default<Proposition>() }, Error.none; }
    let left, le = operand(self, inner.b, 0); if le != Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() }, le; }
    let right, re = operand(self, outer.b, 0); if re != Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() }, re; }
    let result = Proposition { relation, left, right }; let validity = self.store.view().proposition(result);
    return blot_support::Option<Proposition> { validity == Error.none, result }, validity;
}
fn contains(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, annotation: blot_parse_ast::Id, limits: Limits) -> bool, Error {
    var terms: Term[>..<] = []; var index = dictionary<Term, u32> {}; var store = blot_check_numeric_proof_terms::init(terms, index); store.limits = limits;
    var bindings: Binding[>..] = []; var kinds: Kind[>..] = []; var values: u32[>..] = []; var proofs: u32[>..] = []; var requirements: Requirement[>..] = [];
    var builder = Builder { tree, pool, store, bindings, kinds, values, proofs, requirements }; return contains(builder, annotation, 0);
}
fn proofRelation(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, id: blot_parse_ast::Id) -> blot_support::Option<blot_check_numeric_proof_terms::Relation> {
    let outer = tree.node(id); if outer.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq }; }
    let inner = tree.node(outer.a); if inner.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq }; }
    let head = tree.node(inner.a); if head.tag != blot_parse_ast::tag_type_name { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq }; }
    let relation, found = blot_check_numeric_proof_terms::typeName(pool.get(head.a)); return blot_support::Option<blot_check_numeric_proof_terms::Relation> { found, relation };
}
fn lower(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, annotation: blot_parse_ast::Id,
          input_kinds: const blot_support::Option<Kind>[:], limits: Limits, destination: OwnedTables) -> blot_support::Option<Owned>, Error {
    var terms: Term[>..<] = []; var index = dictionary<Term, u32> {}; var store = blot_check_numeric_proof_terms::init(terms, index); store.limits = limits;
    var bindings: Binding[>..] = []; var kinds: Kind[>..] = []; var values: u32[>..] = []; var proofs: u32[>..] = []; var requirements: Requirement[>..] = [];
    var builder = Builder { tree, pool, store, bindings, kinds, values, proofs, requirements };
    let present, error = contains(builder, annotation, 0); if error != Error.none || !present { return blot_support::Option<Owned> { false, default<Owned>() }, error; }
    var at = annotation;
    while tree.node(at).tag == blot_parse_ast::tag_type_forall { let charged = visit(builder); if charged != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, charged; } at = tree.extra[tree.node(at).c]; }
    var arity: u32 = 0;
    while tree.node(at).tag == blot_parse_ast::tag_type_function {
        if arity >= input_kinds.len || arity >= limits.terms { return blot_support::Option<Owned> { false, default<Owned>() }, Error.proof_scope_escape; }
        let charged = visit(builder); if charged != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, charged; }
        let arrow = tree.node(at); let latent, le = contains(builder, arrow.c, 0); if le != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, le; }
        if latent { return blot_support::Option<Owned> { false, default<Owned>() }, Error.invalid_proof_kind; }
        var input = arrow.a; var name: u32 = 0;
        if tree.node(input).tag == blot_parse_ast::tag_type_binder { name = tree.node(input).a; input = tree.node(input).b; }
        var formal = blot_support::Option<u32> { false, 0 };
        let proof, pe = proposition(builder, input); if pe != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, pe; }
        if proof.present {
            if input_kinds[arity].present { return blot_support::Option<Owned> { false, default<Owned>() }, Error.invalid_proof_kind; }
            if builder.requirements.len >= 256 { return blot_support::Option<Owned> { false, default<Owned>() }, Error.proof_analysis_limit; }
            builder.requirements.push(Requirement { builder.kinds.len as u32, proof.value }); builder.proof_slots.push(arity);
        } else {
            let nested, ne = contains(builder, input, 0); if ne != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, ne; }
            if nested { return blot_support::Option<Owned> { false, default<Owned>() }, Error.invalid_proof_kind; }
            if input_kinds[arity].present { formal = blot_support::Option<u32> { true, builder.kinds.len as u32 }; builder.kinds.push(input_kinds[arity].value); builder.value_slots.push(arity); }
        }
        if name != 0 { builder.bindings.push(Binding { name, formal }); } arity += 1; at = arrow.b;
    }
    if arity != input_kinds.len { return blot_support::Option<Owned> { false, default<Owned>() }, Error.proof_scope_escape; }
    let result, re = proposition(builder, at); if re != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, re; }
    if !result.present { let nested, ne = contains(builder, at, 0); if ne != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, ne; } if nested { return blot_support::Option<Owned> { false, default<Owned>() }, Error.invalid_proof_kind; } }
    let borrowed = Owned { arity, builder.value_slots, builder.proof_slots, builder.kinds, builder.store.terms, builder.requirements, result };
    var remaining = limits; remaining.visits -= builder.store.visits;
    let validity = signature(borrowed).validate(remaining); if validity != Error.none { return blot_support::Option<Owned> { false, default<Owned>() }, validity; }
    let owned, error = clone(borrowed, destination); return blot_support::Option<Owned> { error == Error.none, owned }, error;
}
