// Resolved operand kinds turn header syntax into owned positional contracts.
namespace blot_check_numeric_proof_headers;
import check.numeric_proof_contracts;
import check.numeric_proof_terms;
import parse.ast;
import parse.symbols;
import support.error;
import support.option;
import support.structural_adapters;

import dictionary;
import support.structural;
type Error = blot_error::Error;
type Kind = blot_check_numeric_proof_terms::Kind;
type Term = blot_check_numeric_proof_terms::Term;
type Proposition = blot_check_numeric_proof_terms::Proposition;
type Requirement = blot_check_numeric_proof_contracts::Requirement;
type Limits = blot_check_numeric_proof_terms::Limits;
struct Owned {
    arity: u32, value_slots: const u32[:] = default<const u32[:]>(), proof_slots: const u32[:] = default<const u32[:]>(), values: const Kind[:] = default<const Kind[:]>(),
    operands: const Term[:] = default<const Term[:]>(), requirements: const Requirement[:] = default<const Requirement[:]>(),
    result: blot_support::Option<Proposition>   = blot_support::Option<Proposition> { false, default<Proposition>() , ..},
}
struct OwnedTables { value_slots: u32[>..]&, proof_slots: u32[>..]&, values: Kind[>..]&, operands: Term[>..]&, requirements: Requirement[>..]& }
fn signature(self_: Owned) -> blot_check_numeric_proof_contracts::Signature {
    return blot_check_numeric_proof_contracts::Signature { self_.arity, self_.value_slots, self_.proof_slots,
        blot_check_numeric_proof_contracts::Contract { self_.values, self_.operands, self_.requirements, self_.result , ..} , ..};
}
fn clone(self_: Owned, destination: OwnedTables) -> Owned, Error {
    let value_start = destination.value_slots.len; let proof_start = destination.proof_slots.len;
    let kind_start = destination.values.len; let operand_start = destination.operands.len; let requirement_start = destination.requirements.len;
    destination.value_slots.append(self_.value_slots); destination.proof_slots.append(self_.proof_slots);
    destination.values.append(self_.values); destination.operands.append(self_.operands); destination.requirements.append(self_.requirements);
    return Owned { self_.arity, destination.value_slots[value_start..], destination.proof_slots[proof_start..],
        destination.values[kind_start..], destination.operands[operand_start..], destination.requirements[requirement_start..], self_.result , ..}, blot_error::Error.none;
}
fn deinit(self_: Owned&) { self_.value_slots = default<const u32[:]>(); self_.proof_slots = default<const u32[:]>(); self_.values = default<const blot_check_numeric_proof_headers::Kind[:]>(); self_.operands = default<const blot_check_numeric_proof_headers::Term[:]>(); self_.requirements = default<const blot_check_numeric_proof_headers::Requirement[:]>(); self_.result.present = false; }
struct Named { binding: u32, header: Owned }
fn find(values: const Named[:], binding: u32) -> const Owned? { for &value in values { if value.binding == binding { return value.header; } } return null; }
// Retained metadata copies the fixed header and keeps only its owned readonly views.
fn findValue(values:const Named[:],binding:u32)->blot_support::Option<Owned> {for value in values {if value.binding==binding {return blot_support::some(value.header);}}return blot_support::none<Owned>();}
fn equal(left: Owned, right: Owned) -> bool { return blot_structural::equal(left, right); }
struct Binding { name: blot_parse_symbols::Symbol, formal: blot_support::Option<u32> }
struct Builder {
    tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&,
    store: blot_check_numeric_proof_terms::Store,
    bindings: Binding[>..]&, kinds: Kind[>..]&, value_slots: u32[>..]&, proof_slots: u32[>..]&, requirements: Requirement[>..]&,
}
fn visit(self_: Builder&) -> Error { if self_.store.visits >= self_.store.limits.visits { return blot_error::Error.proof_analysis_limit; } self_.store.visits += 1; return blot_error::Error.none; }
recursive fn contains(self_: Builder&, id: blot_parse_ast::Id, depth: i64) -> bool, Error {
    if id == 0 { return false, blot_error::Error.none; } if depth >= 128 { return false, blot_error::Error.proof_analysis_limit; }
    let charged = visit(self_); if charged != blot_error::Error.none { return false, charged; }
    let node = self_.tree.node(id);
    match node.tag {
        blot_parse_ast::tag_type_forall, blot_parse_ast::tag_type_exists => { return contains(self_, self_.tree.extra.items[node.c], depth + 1); },
        blot_parse_ast::tag_type_usage => { return contains(self_, node.c, depth + 1); },
        blot_parse_ast::tag_type_name => { let relation, found = blot_check_numeric_proof_terms::typeName(self_.pool.get(node.a)); return found, blot_error::Error.none; },
        blot_parse_ast::tag_type_apply, blot_parse_ast::tag_type_effect => {
            let left, le = contains(self_, node.a, depth + 1); if le != blot_error::Error.none || left { return left, le; } return contains(self_, node.b, depth + 1);
        },
        blot_parse_ast::tag_type_function => {
            let first, fe = contains(self_, node.a, depth + 1); if fe != blot_error::Error.none || first { return first, fe; }
            let second, se = contains(self_, node.b, depth + 1); if se != blot_error::Error.none || second { return second, se; } return contains(self_, node.c, depth + 1);
        },
        blot_parse_ast::tag_group => { return contains(self_, node.a, depth + 1); },
        blot_parse_ast::tag_type_binder, blot_parse_ast::tag_type_field => { return contains(self_, node.b, depth + 1); },
        blot_parse_ast::tag_type_array, blot_parse_ast::tag_type_product, blot_parse_ast::tag_type_record, blot_parse_ast::tag_effect_row => {
            let ast_walk_1_source=id;let ast_walk_1_count=self_.tree.children(ast_walk_1_source).len;for ast_walk_1_index in 0..ast_walk_1_count {let child=self_.tree.children(ast_walk_1_source)[ast_walk_1_index]; let found, error = contains(self_, child, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
        }, _ => {},
    }
    return false, blot_error::Error.none;
}
recursive fn operand(self_: Builder&, id: blot_parse_ast::Id, depth: i64) -> blot_check_numeric_proof_terms::Id, Error {
    if depth >= 128 { return 0, blot_error::Error.proof_analysis_limit; } let charged = visit(self_); if charged != blot_error::Error.none { return 0, charged; }
    let node = self_.tree.node(id);
    match node.tag {
        blot_parse_ast::tag_integer => { return self_.store.intern(Term { tag: blot_check_numeric_proof_terms::Tag.literal, a: node.a , ..}); },
        blot_parse_ast::tag_group => { return operand(self_, node.a, depth + 1); },
        blot_parse_ast::tag_type_name => {
            var i = self_.bindings.len;
            while i != 0 {
                i -= 1; let charged = visit(self_); if charged != blot_error::Error.none { return 0, charged; }
                let binding = self_.bindings[i]; if binding.name != node.a { continue; }
                if !binding.formal.present { return 0, blot_error::Error.invalid_proof_operand; } let formal = binding.formal.value;
                return self_.store.intern(Term { blot_check_numeric_proof_terms::Tag.formal, self_.kinds[formal], formal , ..});
            }
            return 0, blot_error::Error.proof_scope_escape;
        },
        blot_parse_ast::tag_type_apply => {
            let head = self_.tree.node(node.a); if head.tag != blot_parse_ast::tag_type_name { return 0, blot_error::Error.invalid_proof_operand; }
            let name = self_.pool.get(head.a); var kind = blot_check_numeric_proof_terms::Kind.array;
            if name == "@list.length" { kind = blot_check_numeric_proof_terms::Kind.list; } else if name != "@array.length" { return 0, blot_error::Error.invalid_proof_operand; }
            if self_.tree.node(node.b).tag != blot_parse_ast::tag_type_name { return 0, blot_error::Error.invalid_proof_operand; }
            let collection, error = operand(self_, node.b, depth + 1); if error != blot_error::Error.none { return 0, error; }
            let term, error = self_.store.view().get(collection); if error != blot_error::Error.none { return 0, error; }
            if term.kind != kind { return 0, blot_error::Error.invalid_proof_operand; }
            return self_.store.intern(Term { tag: blot_check_numeric_proof_terms::Tag.length, a: collection , ..});
        },
        _ => { return 0, blot_error::Error.invalid_proof_operand; },
    }
}
fn proposition(self_: Builder&, id: blot_parse_ast::Id) -> blot_support::Option<Proposition>, Error {
    let charged = visit(self_); if charged != blot_error::Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, charged; }
    let outer = self_.tree.node(id); if outer.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, blot_error::Error.none; }
    let inner = self_.tree.node(outer.a); if inner.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, blot_error::Error.none; }
    let head = self_.tree.node(inner.a); if head.tag != blot_parse_ast::tag_type_name { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, blot_error::Error.none; }
    let relation, found = blot_check_numeric_proof_terms::typeName(self_.pool.get(head.a)); if !found { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, blot_error::Error.none; }
    let left, le = operand(self_, inner.b, 0); if le != blot_error::Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, le; }
    let right, re = operand(self_, outer.b, 0); if re != blot_error::Error.none { return blot_support::Option<Proposition> { false, default<Proposition>() , ..}, re; }
    let result = Proposition { relation, left, right , ..}; let validity = self_.store.view().proposition(result);
    return blot_support::Option<Proposition> { validity == blot_error::Error.none, result , ..}, validity;
}
fn contains(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, annotation: blot_parse_ast::Id, limits: Limits) -> bool, Error {
    var terms: Term[>..] = []; var index = blot_check_numeric_proof_terms::TermIndex {..}; var store = blot_check_numeric_proof_terms::init(terms, index); store.limits = limits;
    var bindings: Binding[>..] = []; var kinds: Kind[>..] = []; var values: u32[>..] = []; var proofs: u32[>..] = []; var requirements: Requirement[>..] = [];
    var builder = Builder { tree, pool, store, bindings, kinds, values, proofs, requirements , ..}; return contains(builder, annotation, 0);
}
fn proofRelation(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, id: blot_parse_ast::Id) -> blot_support::Option<blot_check_numeric_proof_terms::Relation> {
    let outer = tree.node(id); if outer.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq , ..}; }
    let inner = tree.node(outer.a); if inner.tag != blot_parse_ast::tag_type_apply { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq , ..}; }
    let head = tree.node(inner.a); if head.tag != blot_parse_ast::tag_type_name { return blot_support::Option<blot_check_numeric_proof_terms::Relation> { false, blot_check_numeric_proof_terms::Relation.eq , ..}; }
    let relation, found = blot_check_numeric_proof_terms::typeName(pool.get(head.a)); return blot_support::Option<blot_check_numeric_proof_terms::Relation> { found, relation , ..};
}
fn lower(tree: const blot_parse_ast::Tree&, pool: const blot_parse_symbols::Pool&, annotation: blot_parse_ast::Id,
          input_kinds: const blot_support::Option<Kind>[:], limits: Limits, destination: OwnedTables) -> blot_support::Option<Owned>, Error {
    var terms: Term[>..] = []; var index = blot_check_numeric_proof_terms::TermIndex {..}; var store = blot_check_numeric_proof_terms::init(terms, index); store.limits = limits;
    var bindings: Binding[>..] = []; var kinds: Kind[>..] = []; var values: u32[>..] = []; var proofs: u32[>..] = []; var requirements: Requirement[>..] = [];
    var builder = Builder { tree, pool, store, bindings, kinds, values, proofs, requirements , ..};
    let present, error = contains(builder, annotation, 0); if error != blot_error::Error.none || !present { return blot_support::Option<Owned> { false, default<Owned>() , ..}, error; }
    var at = annotation;
    while tree.node(at).tag == blot_parse_ast::tag_type_forall { let charged = visit(builder); if charged != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, charged; } at = tree.extra.items[tree.node(at).c]; }
    var arity: u32 = 0;
    while tree.node(at).tag == blot_parse_ast::tag_type_function {
        if arity >= input_kinds.len || arity >= limits.terms { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.proof_scope_escape; }
        let charged = visit(builder); if charged != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, charged; }
        let arrow = tree.node(at); let latent, le = contains(builder, arrow.c, 0); if le != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, le; }
        if latent { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.invalid_proof_kind; }
        var input = arrow.a; var name: u32 = 0;
        if tree.node(input).tag == blot_parse_ast::tag_type_binder { name = tree.node(input).a; input = tree.node(input).b; }
        var formal = blot_support::Option<u32> { false, 0 , ..};
        let proof, pe = proposition(builder, input); if pe != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, pe; }
        if proof.present {
            if input_kinds[arity].present { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.invalid_proof_kind; }
            if builder.requirements.len >= 256 { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.proof_analysis_limit; }
            builder.requirements.push(Requirement { builder.kinds.len as u32, proof.value , ..}); builder.proof_slots.push(arity);
        } else {
            let nested, ne = contains(builder, input, 0); if ne != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, ne; }
            if nested { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.invalid_proof_kind; }
            if input_kinds[arity].present { formal = blot_support::Option<u32> { true, builder.kinds.len as u32 , ..}; builder.kinds.push(input_kinds[arity].value); builder.value_slots.push(arity); }
        }
        if name != 0 { builder.bindings.push(Binding { name, formal , ..}); } arity += 1; at = arrow.b;
    }
    if arity != input_kinds.len { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.proof_scope_escape; }
    let result, re = proposition(builder, at); if re != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, re; }
    if !result.present { let nested, ne = contains(builder, at, 0); if ne != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, ne; } if nested { return blot_support::Option<Owned> { false, default<Owned>() , ..}, blot_error::Error.invalid_proof_kind; } }
    let borrowed = Owned { arity, builder.value_slots, builder.proof_slots, builder.kinds, blot_check_numeric_proof_terms::activeTerms(builder.store.terms,builder.store.index.count), builder.requirements, result , ..};
    var remaining = limits; remaining.visits -= builder.store.visits;
    let validity = signature(borrowed).validate(remaining); if validity != blot_error::Error.none { return blot_support::Option<Owned> { false, default<Owned>() , ..}, validity; }
    let owned, error = clone(borrowed, destination); return blot_support::Option<Owned> { error == blot_error::Error.none, owned , ..}, error;
}
