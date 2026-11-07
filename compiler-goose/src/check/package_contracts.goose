// Package substitution reads exact lexical evidence in immutable type graphs.
namespace blot_check_package_contracts;
import check.core;
import check.dictionary_contracts;
import check.effects;
import check.package_row_facts;
import check.quantifier_goals;
import check.scheme_equations;
import check.scheme_projection;
import check.task_types;
import check.typed_staging;
import check.types;
import check.usage_check;
import parse.ast;
import support.error;
import support.native;
import support.option;
import support.structural_adapters;

import std;
import support.structural;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type List = blot_check_types::List;
type Scheme = blot_check_types::Scheme;
let limit: i64 = 4096;
let ordinary_source_type_limit: i64 = 256;
struct Bits256 { words: u64[4] = [0; 4] }
struct Bits4096 { words: u64[64] = [0; 64] }
fn isSet(self_: const Bits256&, index: i64) -> bool { return self_.words[index >> 6] & ((1 as u64) << (index & 63)) != 0; }
fn set(self_: Bits256&, index: i64) { self_.words[index >> 6] |= (1 as u64) << (index & 63); }
fn count(self_: const Bits256&) -> i64 { var result: i64 = 0; for word in self_.words { result += popcount(word); } return result; }
fn eql(self_: const Bits256&, other: const Bits256&) -> bool { return self_.words == other.words; }
fn isSet(self_: const Bits4096&, index: i64) -> bool { return self_.words[index >> 6] & ((1 as u64) << (index & 63)) != 0; }
fn set(self_: Bits4096&, index: i64) { self_.words[index >> 6] |= (1 as u64) << (index & 63); }
fn count(self_: const Bits4096&) -> i64 { var result: i64 = 0; for word in self_.words { result += popcount(word); } return result; }
fn eql(self_: const Bits4096&, other: const Bits4096&) -> bool { return self_.words == other.words; }
fn foreign(types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if id >= types.effects.rows.len { return false; } let row = types.row(id);
    if row.tail != blot_check_effects::Tail.closed || row.labels.len == 0 { return false; }
    for label in types.rowLabels(id) { if label != blot_check_types::foreign_operation { return false; } } return true;
}
fn pure(types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if id == 0 && types.effects.rows.len == 0 { return true; } if id >= types.effects.rows.len { return false; }
    let row = types.row(id); return row.tail == blot_check_effects::Tail.closed && row.labels.len == 0;
}
fn span(types: const blot_check_core::Types&, value: List) -> const Id[:], Error {
    if value.start > types.extra.len || value.len > types.extra.len - value.start { return types.extra[..0], blot_error::Error.invalid_artifact; }
    return types.list(value), blot_error::Error.none;
}
fn projectionMember(types: const blot_check_core::Types&, node: blot_check_types::Node) -> u32, Error {
    if node.c >= types.extra.len { return 0, blot_error::Error.invalid_artifact; } let start = node.c as i64 + 1; let count = types.extra[node.c];
    if count >= types.extra.len - start { return 0, blot_error::Error.invalid_artifact; } let member = types.extra[start + count];
    if member == 0 { return 0, blot_error::Error.invalid_artifact; } return member, blot_error::Error.none;
}
fn quantified(types: const blot_check_core::Types&, root: Id, remaining: i64&) -> bool, Error { return quantifiedDepth(types, root, remaining, 0); }
recursive fn quantifiedDepth(types: const blot_check_core::Types&, root: Id, remaining: i64&, depth: i64) -> bool, Error {
    if root >= types.nodes.len || depth >= 128 || remaining == 0 { return false, blot_error::Error.invalid_artifact; } remaining -= 1;
    let node = types.node(root);
    match node.tag {
        forall, existential => { return true, blot_error::Error.none; },
        function => { let first, error = quantifiedDepth(types, node.a, remaining, depth + 1); if error != blot_error::Error.none || first { return first, error; } return quantifiedDepth(types, node.b, remaining, depth + 1); },
        array, list, cursor, usage, resolver, provider, scoped => { return quantifiedDepth(types, node.a, remaining, depth + 1); },
        state_provider => { for child in [node.a, node.b, node.c] { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != blot_error::Error.none || found { return found, error; } } },
        product => { let children, error = span(types, List { node.a, node.b , ..}); if error != blot_error::Error.none { return false, error; } for child in children { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != blot_error::Error.none || found { return found, error; } } },
        record => {
            if node.b > 0x7fffffff { return false, blot_error::Error.invalid_artifact; } let words, error = span(types, List { node.a, node.b * 2 , ..}); if error != blot_error::Error.none { return false, error; }
            for index in node.b { let found, error = quantifiedDepth(types, types.recordField(node, index).ty, remaining, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
        },
        nominal => {
            if node.c >= types.extra.len { return false, blot_error::Error.invalid_artifact; } let children, error = span(types, List { node.c + 1, types.extra[node.c] , ..}); if error != blot_error::Error.none { return false, error; }
            for child in children { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
        }, _ => {},
    }
    return false, blot_error::Error.none;
}
struct Opening { binding: blot_check_core::BindingId, binders: List, quantifier: Id }
type ProjectionResolver = blot_check_dictionary_contracts::PackProjection;
type PrincipalProjectionResolver = blot_check_scheme_projection::Resolver;
struct Context {
    owner_id: u64 = 0,
    types: const blot_check_core::Types&, remaining: i64&, solver: blot_check_scheme_equations::Solver? = null,
    owners: Id[4096] = [0; 4096], pure_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {..},
    closed_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {..}, source_instances: bool = false,
    instance_variables: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {..},
    instance_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {..},
    formal: blot_support::Option<Id>   = blot_support::Option<Id> { false, 0 , ..}, generic_variables: List = List {..}, generic_rows: List = List {..},
    obligations: const blot_check_core::Obligation[:] = default<const blot_check_core::Obligation[:]>(), source_obligations: const blot_check_types::Obligation[:] = default<const blot_check_types::Obligation[:]>(),
    schemes: Scheme[128] = [Scheme {..}; 128], scheme_count: i64 = 0,
    scheme_variables_sorted: bool[128] = [false; 128], scheme_rows_sorted: bool[128] = [false; 128],
    formals: Id[128] = [0; 128], formal_count: i64 = 0, introductions: blot_check_core::Id[128] = [0; 128], witness: bool = false,
    representation_floor: blot_support::Option<i64>   = blot_support::Option<i64> { false, 0 , ..}, executable: bool = false, large_plain_graph: bool = false,
    openings: Opening[128] = [default<Opening>(); 128], projection_resolver: ProjectionResolver? = null, opening_count: i64 = 0,
}
fn initialize(self_: Context&) -> Error {
    if self_.owner_id == 0 { self_.owner_id = blot_native::fresh_owner_id(); }
    if !self_.large_plain_graph && (self_.types.nodes.len > limit || self_.types.effects.rows.len > limit) { return blot_error::Error.invalid_artifact; }
    let goals = blot_check_quantifier_goals::validateWithBudget(self_.types.nodes, self_.types.quantifier_goals, self_.types.quantifier_obligations, self_.remaining); if goals != blot_error::Error.none { return goals; }
    for node, id in self_.types.nodes {
        if node.tag != blot_check_types::Tag.forall && node.tag != blot_check_types::Tag.existential { continue; }
        if id == 0 || node.c == 0 || node.c > 128 { return blot_error::Error.invalid_artifact; }
        let binders, error = span(self_.types, List { node.b, node.c , ..}); if error != blot_error::Error.none { return error; }
        for binder, ordinal in binders {
            if binder >= self_.types.nodes.len || binder >= self_.owners.len { return blot_error::Error.invalid_artifact; }
            let leaf = self_.types.node(binder);
            if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b > 2 || (node.tag != blot_check_types::Tag.forall && leaf.b != 0) || leaf.c != 0 || self_.owners[binder] != 0 { return blot_error::Error.invalid_artifact; }
            self_.owners[binder] = id as u32;
        }
    }
    for node, id in self_.types.nodes { if node.tag == blot_check_types::Tag.bound { if id >= self_.owners.len || (node.c == 0 && self_.owners[id] == 0) { return blot_error::Error.invalid_artifact; } } }
    return blot_error::Error.none;
}
fn generic(self_: Context&, scheme: Scheme) -> Error {
    self_.instance_variables = blot_check_package_row_facts::Facts {..}; self_.instance_rows = blot_check_package_row_facts::Facts {..};
    self_.generic_variables = List {..}; self_.generic_rows = List {..}; self_.scheme_count = 0; return pushGeneric(self_, scheme);
}
fn pushGeneric(self_: Context&, scheme: Scheme) -> Error {
    if self_.scheme_count >= self_.schemes.len { return blot_error::Error.invalid_artifact; }
    if self_.types.node(scheme.root).tag == blot_check_types::Tag.forall {
        self_.schemes[self_.scheme_count] = scheme; self_.scheme_variables_sorted[self_.scheme_count] = false; self_.scheme_rows_sorted[self_.scheme_count] = false; self_.scheme_count += 1; return blot_error::Error.none;
    }
    let variables, ve = span(self_.types, scheme.variables); if ve != blot_error::Error.none { return ve; } let rows, re = span(self_.types, scheme.row_variables); if re != blot_error::Error.none { return re; }
    if !(self_.large_plain_graph && self_.source_instances) && (variables.len > 128 || rows.len > 128) { return blot_error::Error.invalid_artifact; }
    let variables_sorted, ve = uniqueSchemeList(self_, variables, false); if ve != blot_error::Error.none { return ve; }
    let rows_sorted, re = uniqueSchemeList(self_, rows, true); if re != blot_error::Error.none { return re; }
    self_.schemes[self_.scheme_count] = scheme; self_.scheme_variables_sorted[self_.scheme_count] = variables_sorted; self_.scheme_rows_sorted[self_.scheme_count] = rows_sorted; self_.scheme_count += 1;
    self_.generic_variables = scheme.variables; self_.generic_rows = scheme.row_variables; return blot_error::Error.none;
}
fn popGeneric(self_: Context&) {
    self_.scheme_count -= 1; self_.generic_variables = List {..}; self_.generic_rows = List {..};
    if self_.scheme_count != 0 { let scheme = self_.schemes[self_.scheme_count - 1]; if self_.types.node(scheme.root).tag != blot_check_types::Tag.forall { self_.generic_variables = scheme.variables; self_.generic_rows = scheme.row_variables; } }
}
fn step(self_: Context&, depth: i64) -> Error { if depth >= 128 || self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none; }
fn uniqueSchemeList(self_: Context&, ids: const Id[:], rows: bool) -> bool, Error {
    var sorted = true;
    for id, index in ids {
        let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; }
        if rows { if id >= self_.types.effects.variable_count { return false, blot_error::Error.invalid_artifact; } }
        else if id >= self_.types.nodes.len || self_.types.node(id).tag != blot_check_types::Tag.variable { return false, blot_error::Error.invalid_artifact; }
        if index == 0 { continue; } let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; }
        if ids[index - 1] == id { return false, blot_error::Error.invalid_artifact; } if ids[index - 1] > id { sorted = false; }
    }
    if !sorted { for id, index in ids { for prior in ids[..index] { let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; } if prior == id { return false, blot_error::Error.invalid_artifact; } } } }
    return sorted, blot_error::Error.none;
}
fn schemeListContains(self_: Context&, ids: const Id[:], id: Id, sorted: bool) -> bool, Error {
    if !sorted { for candidate in ids { let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; } if candidate == id { return true, blot_error::Error.none; } } return false, blot_error::Error.none; }
    var low: i64 = 0; var high = ids.len;
    while low < high { let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; } let middle = low + (high - low) / 2;
        if ids[middle] == id { return true, blot_error::Error.none; } if ids[middle] < id { low = middle + 1; } else { high = middle; } }
    return false, blot_error::Error.none;
}
fn ownsVariable(self_: Context&, id: Id) -> bool, Error {
    if self_.source_instances && self_.instance_variables.contains(id) { return true, blot_error::Error.none; }
    if self_.large_plain_graph && self_.source_instances {
        let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; }
        for scheme, index in self_.schemes[..self_.scheme_count] {
            if self_.types.node(scheme.root).tag == blot_check_types::Tag.forall { continue; }
            let ids, error = span(self_.types, scheme.variables); if error != blot_error::Error.none { return false, error; }
            let found, error = schemeListContains(self_, ids, id, self_.scheme_variables_sorted[index]); if error != blot_error::Error.none || found { return found, error; }
        }
        return false, blot_error::Error.none;
    }
    for scheme in self_.schemes[..self_.scheme_count] {
        if self_.types.node(scheme.root).tag == blot_check_types::Tag.forall { continue; }
        let variables, error = span(self_.types, scheme.variables); if error != blot_error::Error.none { return false, error; }
        for variable in variables { let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; } if variable == id { return true, blot_error::Error.none; } }
    }
    return false, blot_error::Error.none;
}
fn ownsRow(self_: Context&, id: u32) -> bool, Error {
    if self_.source_instances && self_.instance_rows.contains(id) { return true, blot_error::Error.none; }
    if self_.large_plain_graph && self_.source_instances {
        let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; }
        for scheme, index in self_.schemes[..self_.scheme_count] {
            let ids, error = span(self_.types, scheme.row_variables); if error != blot_error::Error.none { return false, error; }
            let found, error = schemeListContains(self_, ids, id, self_.scheme_rows_sorted[index]); if error != blot_error::Error.none || found { return found, error; }
        }
        return false, blot_error::Error.none;
    }
    for scheme in self_.schemes[..self_.scheme_count] {
        let variables, error = span(self_.types, scheme.row_variables); if error != blot_error::Error.none { return false, error; }
        for variable in variables { let charged = step(self_, 0); if charged != blot_error::Error.none { return false, charged; } if variable == id { return true, blot_error::Error.none; } }
    }
    return false, blot_error::Error.none;
}
recursive fn sourceInstance(self_: Context&, root: Id, depth: i64) -> Error {
    if !self_.source_instances { return blot_error::Error.invalid_artifact; } let charged = step(self_, depth); if charged != blot_error::Error.none { return charged; } let node = self_.types.node(root);
    match node.tag {
        variable => { return self_.instance_variables.set(root); }, array, list, cursor, resolver, usage => { return sourceInstance(self_, node.a, depth + 1); },
        function => { let parameter = sourceInstance(self_, node.a, depth + 1); if parameter != blot_error::Error.none { return parameter; } return sourceInstance(self_, node.b, depth + 1); },
        product => { let children, error = span(self_.types, List { node.a, node.b , ..}); if error != blot_error::Error.none { return error; } for child in children { let error = sourceInstance(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } },
        record => { for index in node.b { let error = sourceInstance(self_, self_.types.recordField(node, index).ty, depth + 1); if error != blot_error::Error.none { return error; } } },
        nominal => { for child in self_.types.nominalArguments(node) { let error = sourceInstance(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } }, _ => {},
    }
    return blot_error::Error.none;
}
fn schemeGoals(self_: Context&, scheme: Scheme) -> const blot_check_core::Obligation[:], Error {
    if scheme.obligations.start > self_.obligations.len || scheme.obligations.len > self_.obligations.len - scheme.obligations.start { return self_.obligations[..0], blot_error::Error.invalid_artifact; }
    return self_.obligations[scheme.obligations.start..scheme.obligations.start + scheme.obligations.len], blot_error::Error.none;
}
fn enter(self_: Context&, owner: Id) -> Error {
    if self_.formal_count >= self_.formals.len || owner >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; } let node = self_.types.node(owner);
    if node.tag != blot_check_types::Tag.forall && node.tag != blot_check_types::Tag.existential { return blot_error::Error.invalid_artifact; }
    self_.formals[self_.formal_count] = owner; self_.introductions[self_.formal_count] = 0; self_.formal_count += 1; self_.formal = blot_support::Option<Id> { true, owner , ..}; return blot_error::Error.none;
}
fn leave(self_: Context&) { self_.formal_count -= 1; self_.formal.present = false; if self_.formal_count != 0 { self_.formal = blot_support::Option<Id> { true, self_.formals[self_.formal_count - 1] , ..}; } }
fn ownsFormal(self_: const Context&, leaf: Id) -> bool { if leaf >= self_.owners.len { return false; } for owner in self_.formals[..self_.formal_count] { if self_.owners[leaf] == owner { return true; } } return false; }
fn representationBinder(self_: const Context&, root: Id) -> Error {
    if !self_.representation_floor.present { return blot_error::Error.none; } let node = self_.types.node(root);
    if node.tag != blot_check_types::Tag.bound || node.c != 0 || root >= self_.owners.len { return blot_error::Error.invalid_artifact; }
    for owner in self_.formals[self_.representation_floor.value..self_.formal_count] { if self_.owners[root] == owner { return blot_error::Error.none; } } return blot_error::Error.invalid_artifact;
}
fn region(self_: Context&, id: Id, depth: i64) -> Error {
    let charged = step(self_, depth); if charged != blot_error::Error.none { return charged; } if id >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; }
    let leaf = self_.types.node(id); if leaf.tag != blot_check_types::Tag.bound || leaf.b != 2 { return blot_error::Error.invalid_artifact; }
    let representation = representationBinder(self_, id); if representation != blot_error::Error.none { return representation; }
    if leaf.c == 0 && !ownsFormal(self_, id) { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn visit(self_: Context&, root: Id) -> Error { return walk(self_, root, 0); }
fn representation(self_: Context&, root: Id) -> Error { let prior = self_.representation_floor; self_.representation_floor = blot_support::Option<i64> { true, self_.formal_count , ..}; let error = walk(self_, root, 0); self_.representation_floor = prior; return error; }
fn isForeign(self_: const Context&, id: blot_check_effects::Id) -> bool {
    if foreign(self_.types, id) { return true; } if id >= self_.types.effects.rows.len || !self_.closed_rows.contains(id) { return false; }
    let row = self_.types.row(id); if row.labels.len == 0 { return false; } match row.tail { variable => {}, _ => { return false; }, }
    for label in self_.types.rowLabels(id) { if label != blot_check_types::foreign_operation { return false; } } return true;
}
fn isPure(self_: const Context&, row: blot_check_effects::Id) -> bool { return pure(self_.types, row) || self_.pure_rows.contains(row); }
fn genericRow(self_: Context&, id: blot_check_effects::Id, depth: i64) -> bool, Error {
    if id >= self_.types.effects.rows.len { return false, blot_error::Error.none; } let row = self_.types.row(id);
    match row.tail { variable v => { let charged = step(self_, depth); if charged != blot_error::Error.none { return false, charged; } return ownsRow(self_, v.value); }, _ => { return false, blot_error::Error.none; }, }
}
recursive fn validateRow(self_: Context&, id: blot_check_effects::Id, depth: i64) -> Error {
    if id == 0 && self_.types.effects.rows.len == 0 { return blot_error::Error.none; } let charged = step(self_, depth); if charged != blot_error::Error.none { return charged; }
    if id >= self_.types.effects.rows.len { return blot_error::Error.invalid_artifact; } let value = self_.types.row(id);
    match value.tail {
        formal v => {
            if v.value >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; } let leaf = self_.types.node(v.value);
            if leaf.tag == blot_check_types::Tag.rigid { let solver .= self_.solver; if !solver || !solver.ownsRigid(leaf) || leaf.c != 1 { return blot_error::Error.invalid_artifact; } }
            else { if !ownsFormal(self_, v.value) || leaf.tag != blot_check_types::Tag.bound || leaf.b != 1 || leaf.c != 0 { return blot_error::Error.invalid_artifact; } let represented = representationBinder(self_, v.value); if represented != blot_error::Error.none { return represented; } }
        },
        _ => {
            var generic_row = false; match value.tail { variable v => { let owned, error = ownsRow(self_, v.value); if error != blot_error::Error.none { return error; } generic_row = owned; }, _ => {}, }
            if value.tail != blot_check_effects::Tail.closed && !generic_row && !isPure(self_, id) && !isForeign(self_, id) && !self_.closed_rows.contains(id) { return blot_error::Error.invalid_artifact; }
        },
    }
    for label in self_.types.rowLabels(id) {
        let charged = step(self_, depth); if charged != blot_error::Error.none { return charged; } if label == 0 || label >= self_.types.operations.len { return blot_error::Error.invalid_artifact; }
        let operation = self_.types.operation(label); let arguments, error = span(self_.types, operation.arguments); if error != blot_error::Error.none { return error; }
        for argument in arguments { let error = walk(self_, argument, depth + 1); if error != blot_error::Error.none { return error; } }
        if operation.instance.unit == 0 && operation.instance.decl != 0 { let error = walk(self_, operation.instance.decl, depth + 1); if error != blot_error::Error.none { return error; } }
    }
    return blot_error::Error.none;
}
recursive fn goalFootprint(self_: Context&, root: Id, owner: Id, opened: List, sealed: const Bits4096&, depth: i64) -> bool, Error {
    let charged = step(self_, depth); if charged != blot_error::Error.none { return false, charged; } let node = self_.types.node(root);
    if node.tag == blot_check_types::Tag.bound {
        let quantifier = self_.types.node(owner); let formals, error = span(self_.types, List { quantifier.b, quantifier.c , ..}); if error != blot_error::Error.none { return false, error; }
        if formals.len != opened.len { return false, blot_error::Error.invalid_artifact; } let witnesses = self_.types.list(opened);
        for formal, i in formals { if formal == root { return !sealed.isSet(witnesses[i]), blot_error::Error.none; } } return false, blot_error::Error.none;
    }
    match node.tag {
        forall, existential => {
            for goal in self_.types.quantifierGoals(root) { for endpoint in [goal.ty, goal.other, goal.result, goal.signature] { if endpoint != 0 { let found, error = goalFootprint(self_, endpoint, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } } }
            return goalFootprint(self_, node.a, owner, opened, sealed, depth + 1);
        },
        function => {
            for child in [node.a, node.b] { let found, error = goalFootprint(self_, child, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
            return rowFootprint(self_, node.c, owner, opened, sealed, depth + 1);
        },
        usage => { if node.c != 0 { let found, error = goalFootprint(self_, node.c, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } return goalFootprint(self_, node.a, owner, opened, sealed, depth + 1); },
        provider => { let found, error = goalFootprint(self_, node.a, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } return rowFootprint(self_, node.c, owner, opened, sealed, depth + 1); },
        array, list, cursor, resolver => { return goalFootprint(self_, node.a, owner, opened, sealed, depth + 1); },
        state_provider => { for child in [node.a, node.b, node.c] { let found, error = goalFootprint(self_, child, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } },
        scoped => { let found, error = goalFootprint(self_, node.a, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } if node.b == 0 && node.c != 0 { return goalFootprint(self_, node.c, owner, opened, sealed, depth + 1); } },
        product => { for child in self_.types.list(List { node.a, node.b , ..}) { let found, error = goalFootprint(self_, child, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } },
        record => { for index in node.b { let found, error = goalFootprint(self_, self_.types.recordField(node, index).ty, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } },
        projection, nominal, instance_selection => { for child in self_.types.nominalArguments(node) { let found, error = goalFootprint(self_, child, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } } }, _ => {},
    }
    return false, blot_error::Error.none;
}
recursive fn rowFootprint(self_: Context&, row: blot_check_effects::Id, owner: Id, opened: List, sealed: const Bits4096&, depth: i64) -> bool, Error {
    let charged = step(self_, depth); if charged != blot_error::Error.none { return false, charged; } if row == 0 && self_.types.effects.rows.len == 0 { return false, blot_error::Error.none; }
    let value = self_.types.row(row);
    match value.tail { formal v => { let found, error = goalFootprint(self_, v.value, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } }, _ => {}, }
    for label in self_.types.rowLabels(row) {
        let charged = step(self_, depth); if charged != blot_error::Error.none { return false, charged; } let operation = self_.types.operation(label);
        for argument in self_.types.list(operation.arguments) { let found, error = goalFootprint(self_, argument, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
        if operation.instance.unit == 0 && operation.instance.decl != 0 { let found, error = goalFootprint(self_, operation.instance.decl, owner, opened, sealed, depth + 1); if error != blot_error::Error.none || found { return found, error; } }
    }
    return false, blot_error::Error.none;
}
recursive fn projectionGoals<G>(self_: Context&, root: Id, goals: G, formals: List, opened: blot_support::Option<List>, depth: i64) -> bool, Error {
    let projection_ = self_.types.node(root); let arguments = self_.types.nominalArguments(projection_);
    for goal in goals {
        let charged = step(self_, depth); if charged != blot_error::Error.none { return false, charged; }
        if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != projection_.a || goal.identity.decl != projection_.b { continue; }
        let tuple = self_.types.node(goal.ty); if tuple.tag != blot_check_types::Tag.product || tuple.b != arguments.len { continue; }
        var proof = PrincipalState {..};
        if opened.present { proof.instance = formals; for witness, index in self_.types.list(opened.value) { proof.witnesses[index] = witness; } }
        var matches = true; let required = self_.types.list(List { tuple.a, tuple.b , ..});
        for expected, index in required { let error = matchPrincipalMode(proof, self_.types, self_.types, self_.remaining, self_, null, default<const VersionPair[:]>(), null, expected, arguments[index], depth + 1, rejectPrincipalProjection); if error != blot_error::Error.none { if self_.remaining == 0 { return false, error; } matches = false; break; } }
        if matches { return true, blot_error::Error.none; }
    }
    return false, blot_error::Error.none;
}
recursive fn projectionGoal(self_: Context&, root: Id, owner: Id, opened: blot_support::Option<List>, depth: i64) -> bool, Error {
    let quantifier = self_.types.node(owner); return projectionGoals(self_, root, self_.types.quantifierGoals(owner), List { quantifier.b, quantifier.c , ..}, opened, depth);
}
recursive fn projection(self_: Context&, root: Id, depth: i64) -> Error {
    let member, error = projectionMember(self_.types, self_.types.node(root)); if error != blot_error::Error.none { return error; }
    for argument in self_.types.nominalArguments(self_.types.node(root)) { let error = walk(self_, argument, depth + 1); if error != blot_error::Error.none { return error; } }
    var scheme = self_.scheme_count;
    while scheme != 0 {
        scheme -= 1; let owner = self_.schemes[scheme]; if owner.obligations.len == 0 { continue; }
        if self_.source_obligations.len != 0 {
            if owner.obligations.start > self_.source_obligations.len || owner.obligations.len > self_.source_obligations.len - owner.obligations.start { return blot_error::Error.invalid_artifact; }
            let found, error = projectionGoals(self_, root, self_.source_obligations[owner.obligations.start..owner.obligations.start + owner.obligations.len], List {..}, blot_support::Option<List> { false, List {..} , ..}, depth + 1);
            if error != blot_error::Error.none { return error; } if found { return blot_error::Error.none; }
        } else {
            let goals, error = schemeGoals(self_, owner); if error != blot_error::Error.none { return error; }
            let found, error = projectionGoals(self_, root, goals, List {..}, blot_support::Option<List> { false, List {..} , ..}, depth + 1); if error != blot_error::Error.none { return error; } if found { return blot_error::Error.none; }
        }
    }
    var scope = self_.formal_count;
    while scope != 0 { scope -= 1; let found, error = projectionGoal(self_, root, self_.formals[scope], blot_support::Option<List> { false, List {..} , ..}, depth + 1); if error != blot_error::Error.none { return error; } if found { return blot_error::Error.none; } }
    scope = self_.opening_count;
    while scope != 0 { scope -= 1; let opening = self_.openings[scope]; let found, error = projectionGoal(self_, root, opening.quantifier, blot_support::Option<List> { true, opening.binders , ..}, depth + 1); if error != blot_error::Error.none { return error; } if found { return blot_error::Error.none; } }
    return blot_error::Error.invalid_artifact;
}
recursive fn walk(self_: Context&, root: Id, depth: i64) -> Error {
    let charged = step(self_, depth); if charged != blot_error::Error.none { return charged; } if root >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; }
    let node = self_.types.node(root);
    match node.tag {
        unit, boolean, unsigned32, floating32, never => {},
        type_constructor => { if self_.witness || node.c != 0 { return blot_error::Error.invalid_artifact; } },
        erased_proof => { if self_.witness { return blot_error::Error.invalid_artifact; } },
        rigid => { let solver .= self_.solver; if !solver || !solver.ownsRigid(node) { return blot_error::Error.invalid_artifact; } },
        variable => { let owned, error = ownsVariable(self_, root); if error != blot_error::Error.none { return error; } if !owned { return blot_error::Error.invalid_artifact; } },
        bound => {
            let represented = representationBinder(self_, root); if represented != blot_error::Error.none { return represented; } if node.b != 0 { return blot_error::Error.invalid_artifact; }
            if node.c == 0 { if !ownsFormal(self_, root) { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
            for opening in self_.openings[..self_.opening_count] { if opening.binding != node.c { continue; } let binders, error = span(self_.types, opening.binders); if error != blot_error::Error.none { return error; } if node.a >= binders.len || binders[node.a] != root { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
            return blot_error::Error.invalid_artifact;
        },
        forall, existential => {
            if self_.witness { return blot_error::Error.invalid_artifact; } let entered = enter(self_, root); if entered != blot_error::Error.none { return entered; }
            let error = walkQuantifier(self_, root, node, depth); leave(self_); return error;
        },
        projection => { return projection(self_, root, depth + 1); },
        function => { let row = validateRow(self_, node.c, depth + 1); if row != blot_error::Error.none { return row; } let parameter = walk(self_, node.a, depth + 1); if parameter != blot_error::Error.none { return parameter; } return walk(self_, node.b, depth + 1); },
        usage => {
            if self_.witness { return blot_error::Error.invalid_artifact; }
            let loan = node.b == blot_parse_ast::usagekind_borrow || node.b == blot_parse_ast::usagekind_borrow_mut;
            let cleanup = node.b == blot_parse_ast::usagekind_cleanup;
            if cleanup && self_.formal.present { return blot_error::Error.invalid_artifact; }
            if loan { let region = region(self_, node.c, depth + 1); if region != blot_error::Error.none { return region; } }
            if loan != (node.c != 0) { return blot_error::Error.invalid_artifact; }
            let concurrent = node.b == blot_parse_ast::usagekind_concurrent;
            if concurrent && !blot_check_task_types::concurrentHost(self_.types, node.a) { return blot_error::Error.invalid_artifact; }
            if !loan && !cleanup && !concurrent && node.b != blot_parse_ast::usagekind_unique && node.b != blot_parse_ast::usagekind_shared && node.b != blot_parse_ast::usagekind_once && node.b != blot_parse_ast::usagekind_many { return blot_error::Error.invalid_artifact; }
            return walk(self_, node.a, depth + 1);
        },
        scoped => {
            if self_.witness { return blot_error::Error.invalid_artifact; } let descriptor = walk(self_, node.a, depth + 1); if descriptor != blot_error::Error.none { return descriptor; }
            if node.b == 0 { let identity = self_.types.node(node.c); if identity.tag == blot_check_types::Tag.bound && identity.b == 2 { return region(self_, node.c, depth + 1); } return walk(self_, node.c, depth + 1); }
        },
        instance_version => { if self_.witness { return blot_error::Error.invalid_artifact; } },
        instance_selection => {
            if self_.witness { return blot_error::Error.invalid_artifact; } let choices = self_.types.nominalArguments(node); if choices.len != 2 && choices.len != 3 { return blot_error::Error.invalid_artifact; }
            for choice in choices[..2] { if self_.types.node(choice).tag != blot_check_types::Tag.scoped { return blot_error::Error.invalid_artifact; } let error = walk(self_, choice, depth + 1); if error != blot_error::Error.none { return error; } }
            if choices.len == 3 { if self_.types.node(choices[2]).tag != blot_check_types::Tag.instance_version { return blot_error::Error.invalid_artifact; } return walk(self_, choices[2], depth + 1); }
        },
        array, list, cursor, resolver => { return walk(self_, node.a, depth + 1); },
        provider => { if self_.witness { return blot_error::Error.invalid_artifact; } let row = validateRow(self_, node.c, depth + 1); if row != blot_error::Error.none { return row; } return walk(self_, node.a, depth + 1); },
        state_provider => { if self_.witness { return blot_error::Error.invalid_artifact; } for child in [node.a, node.b, node.c] { let error = walk(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } },
        product => { let children, error = span(self_.types, List { node.a, node.b , ..}); if error != blot_error::Error.none { return error; } for child in children { let error = walk(self_, child, depth + 1); if error != blot_error::Error.none { return error; } } },
        record => { if node.b > 0x7fffffff { return blot_error::Error.invalid_artifact; } let fields, error = span(self_.types, List { node.a, node.b * 2 , ..}); if error != blot_error::Error.none { return error; } for index in node.b { let error = walk(self_, self_.types.recordField(node, index).ty, depth + 1); if error != blot_error::Error.none { return error; } } },
        nominal => {
            if blot_check_typed_staging::isIdentity(node.a, node.b) && (self_.formal.present || self_.witness) { return blot_error::Error.invalid_artifact; }
            let code_ = blot_check_typed_staging::codeInfo(self_.types, root);
            if code_.present { let row = validateRow(self_, code_.value.effects, depth + 1); if row != blot_error::Error.none { return row; } return walk(self_, code_.value.result, depth + 1); }
            if node.c >= self_.types.extra.len { return blot_error::Error.invalid_artifact; } let children, error = span(self_.types, List { node.c + 1, self_.types.extra[node.c] , ..}); if error != blot_error::Error.none { return error; }
            for child in children { let error = walk(self_, child, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        _ => { return blot_error::Error.invalid_artifact; },
    }
    return blot_error::Error.none;
}
recursive fn walkQuantifier(self_: Context&, root: Id, node: blot_check_types::Node, depth: i64) -> Error {
    if node.tag == blot_check_types::Tag.forall && self_.types.node(node.a).tag != blot_check_types::Tag.function { return blot_error::Error.invalid_artifact; }
    for goal in self_.types.quantifierGoals(root) { for endpoint in [goal.ty, goal.other, goal.result, goal.signature] { if endpoint != 0 { let error = walk(self_, endpoint, depth + 1); if error != blot_error::Error.none { return error; } } } }
    return walk(self_, node.a, depth + 1);
}
fn open(self_: Context&, package: Id, binding: blot_check_core::BindingId, binders: List, payload: Id) -> Error {
    let visited = visit(self_, package); if visited != blot_error::Error.none { return visited; } let quantifier = self_.types.node(package);
    if quantifier.tag != blot_check_types::Tag.existential || quantifier.c != binders.len || binding == 0 || self_.opening_count >= self_.openings.len { return blot_error::Error.invalid_artifact; }
    for opening in self_.openings[..self_.opening_count] { if opening.binding == binding { return blot_error::Error.invalid_artifact; } }
    let witnesses, error = span(self_.types, binders); if error != blot_error::Error.none { return error; }
    for binder, ordinal in witnesses { if binder >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; } let leaf = self_.types.node(binder);
        if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b != 0 || leaf.c != binding { return blot_error::Error.invalid_artifact; } }
    self_.openings[self_.opening_count] = Opening { binding, binders, package , ..}; self_.opening_count += 1;
    let visited = visit(self_, payload); if visited != blot_error::Error.none { self_.opening_count -= 1; return visited; }
    let proof = substitutionView(self_.types,List{quantifier.b,quantifier.c,..},witnesses,self_.remaining,self_);
    let error = validate(proof, quantifier.a, payload); if error != blot_error::Error.none { self_.opening_count -= 1; } return error;
}
fn pack(self_: Context&, package: Id, payload: Id, witnesses: const Id[:]) -> Error {
    let visited = visit(self_, package); if visited != blot_error::Error.none { return visited; } let quantifier = self_.types.node(package);
    if quantifier.tag != blot_check_types::Tag.existential { return blot_error::Error.invalid_artifact; }
    let visited = visit(self_, payload); if visited != blot_error::Error.none { return visited; }
    self_.witness = true; let error = packWitnesses(self_, quantifier, payload, witnesses); self_.witness = false; return error;
}
fn packWitnesses(self_: Context&, quantifier: blot_check_types::Node, payload: Id, witnesses: const Id[:]) -> Error {
    for witness in witnesses { let error = visit(self_, witness); if error != blot_error::Error.none { return error; } }
    let proof = substitutionView(self_.types,List{quantifier.b,quantifier.c,..},witnesses,self_.remaining,self_,self_.projection_resolver);
    return validate(proof, quantifier.a, payload);
}
fn close(self_: Context&) { self_.opening_count -= 1; }
struct Substitution {
    types: const blot_check_core::Types&,
    formal: List,
    witnesses: const Id[:],
    remaining: i64&,
    views: Context? = null,
    projection_resolver: ProjectionResolver? = null,
}
fn substitutionView(types:const blot_check_core::Types&,formal:List,witnesses:const Id[:],remaining:i64&,views:Context?,projection:ProjectionResolver?=null)->Substitution {return Substitution{types:types,formal:formal,witnesses:witnesses,remaining:remaining,views:views,projection_resolver:projection};}
fn rowPure(self_: const Substitution&, row: blot_check_effects::Id) -> bool {
    { let optional_binding_30 .= self_.views; if optional_binding_30 { let views .= optional_binding_30; return views.isPure(row);  } } return pure(self_.types, row);
}
fn step(self_: const Substitution&, depth: i64) -> Error {
    if depth >= 128 || self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none;
}
fn validate(self_: const Substitution&, expected: Id, actual: Id) -> Error {
    if self_.formal.len != self_.witnesses.len || self_.formal.len == 0 || self_.formal.len > 128 { return blot_error::Error.invalid_artifact; }
    let binders, error = span(self_.types, self_.formal); if error != blot_error::Error.none { return error; }
    for binder, ordinal in binders {
        if binder >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; } let leaf = self_.types.node(binder);
        if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b != 0 || leaf.c != 0 { return blot_error::Error.invalid_artifact; }
    }
    for witness in self_.witnesses { let has_usage, error = blot_check_usage_check::contains(self_.types, witness); if error != blot_error::Error.none || has_usage { return blot_error::Error.invalid_artifact; } }
    return matchSubstitution(self_, expected, actual, true, 0);
}
recursive fn matchSubstitution(self_: const Substitution&, expected: Id, actual: Id, replace: bool, depth: i64) -> Error {
    let error = step(self_, depth); if error != blot_error::Error.none { return error; }
    if expected >= self_.types.nodes.len || actual >= self_.types.nodes.len { return blot_error::Error.invalid_artifact; }
    let left = self_.types.node(expected); let right = self_.types.node(actual);
    if replace && left.tag == blot_check_types::Tag.bound {
        let binders, error = span(self_.types, self_.formal); if error != blot_error::Error.none { return error; }
        for binder, ordinal in binders { if binder == expected { return matchSubstitution(self_, self_.witnesses[ordinal], actual, false, depth + 1); } }
    }
    if left.tag == blot_check_types::Tag.projection && right.tag != blot_check_types::Tag.projection && replace {
        { let optional_binding_29 .= self_.projection_resolver; if optional_binding_29 { let resolver .= optional_binding_29; return resolver.validate(self_, expected, actual);  } } return blot_error::Error.invalid_artifact;
    }
    if left.tag != right.tag { return blot_error::Error.invalid_artifact; }
    match left.tag {
        unit, boolean, unsigned32, floating32, never => { return blot_error::Error.none; },
        bound => {
            if left.b != 0 || expected != actual { return blot_error::Error.invalid_artifact; }
            if left.c == 0 { { let optional_binding_28 .= self_.views; if optional_binding_28 { let views .= optional_binding_28; if views.types.owner_id != self_.types.owner_id || !views.ownsFormal(expected) { return blot_error::Error.invalid_artifact; }  } else { return blot_error::Error.invalid_artifact; } } }
        },
        forall, existential => {
            var proof = principalFromState(self_.types,self_.types,self_.remaining,self_.views,PrincipalState{instance:self_.formal,..});
            for witness, index in self_.witnesses { proof.witnesses[index] = witness; } return validate(proof, expected, actual);
        },
        function => {
            var proof = principalFromState(self_.types,self_.types,self_.remaining,self_.views,PrincipalState{..});
            if replace { proof.instance = self_.formal; for witness, index in self_.witnesses { proof.witnesses[index] = witness; } }
            let error = matchRow(proof, left.c, right.c, depth + 1); if error != blot_error::Error.none { return error; }
            let error = matchSubstitution(self_, left.a, right.a, replace, depth + 1); if error != blot_error::Error.none { return error; }
            return matchSubstitution(self_, left.b, right.b, replace, depth + 1);
        },
        usage => {
            if left.b != right.b || left.c != 0 || right.c != 0 { return blot_error::Error.invalid_artifact; }
            if left.b != blot_check_types::usageCode(blot_parse_ast::usagekind_unique) && left.b != blot_check_types::usageCode(blot_parse_ast::usagekind_shared) && left.b != blot_check_types::usageCode(blot_parse_ast::usagekind_once) && left.b != blot_check_types::usageCode(blot_parse_ast::usagekind_many) { return blot_error::Error.invalid_artifact; }
            return matchSubstitution(self_, left.a, right.a, replace, depth + 1);
        },
        array, list, cursor => { return matchSubstitution(self_, left.a, right.a, replace, depth + 1); },
        product => {
            if left.b != right.b { return blot_error::Error.invalid_artifact; }
            let a, error = span(self_.types, List { left.a, left.b , ..}); if error != blot_error::Error.none { return error; }
            let b, error = span(self_.types, List { right.a, right.b , ..}); if error != blot_error::Error.none { return error; }
            for x, index in a { let error = matchSubstitution(self_, x, b[index], replace, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        record => {
            if left.b != right.b || left.b > 0x7fffffff { return blot_error::Error.invalid_artifact; }
            let a, error = span(self_.types, List { left.a, left.b * 2 , ..}); if error != blot_error::Error.none { return error; }
            let b, error = span(self_.types, List { right.a, right.b * 2 , ..}); if error != blot_error::Error.none { return error; }
            for index in 0..left.b {
                let field = self_.types.recordField(left, index); var matched = false;
                for other in 0..right.b { let error = step(self_, depth); if error != blot_error::Error.none { return error; } let candidate = self_.types.recordField(right, other); if field.name != candidate.name { continue; }
                    let error = matchSubstitution(self_, field.ty, candidate.ty, replace, depth + 1); if error != blot_error::Error.none { return error; } matched = true; break;
                } if !matched { return blot_error::Error.invalid_artifact; }
            }
        },
        nominal, projection => {
            if left.a != right.a || left.b != right.b { return blot_error::Error.invalid_artifact; }
            if left.tag == blot_check_types::Tag.projection { let a, error = projectionMember(self_.types, left); if error != blot_error::Error.none { return error; } let b, error = projectionMember(self_.types, right); if error != blot_error::Error.none || a != b { return blot_error::Error.invalid_artifact; } }
            if left.c >= self_.types.extra.len || right.c >= self_.types.extra.len { return blot_error::Error.invalid_artifact; }
            let a, error = span(self_.types, List { left.c + 1, self_.types.extra[left.c] , ..}); if error != blot_error::Error.none { return error; }
            let b, error = span(self_.types, List { right.c + 1, self_.types.extra[right.c] , ..}); if error != blot_error::Error.none || a.len != b.len { return blot_error::Error.invalid_artifact; }
            for x, index in a { let error = matchSubstitution(self_, x, b[index], replace, depth + 1); if error != blot_error::Error.none { return error; } }
        },
        _ => { return blot_error::Error.invalid_artifact; },
    } return blot_error::Error.none;
}
struct FormalPair { left: List, right: List }
struct VersionPair { left: blot_check_types::Node, right: blot_check_types::Node }
struct RowWitness { row: blot_check_effects::Id, excluded: Bits256 = Bits256 {..} }
struct CertificatePairs { left: List, right: List, seen_left: Bits4096 = Bits4096 {..}, seen_right: Bits4096 = Bits4096 {..} }
// Fresh recursive comparisons own scalar state; borrowed roots travel as arguments.
struct PrincipalState {
    formals: FormalPair[128], formal_count: i64 = 0, instance: List = List {..}, witnesses: Id[256] = [0; 256],
    row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128], secondary: List = List {..}, secondary_witnesses: Id[256] = [0; 256],
    pending: blot_check_effects::Id[128], pending_count: i64 = 0, foreign_views: bool = false,
    left_rows: List = List {..}, instance_rows: List = List {..}, scheme_row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128],
    row_search_depth: i64 = 0, projection_depth: i64 = 0,
}
struct Principal {
    left: const blot_check_core::Types&, right: const blot_check_core::Types&, remaining: i64&,
    formals: FormalPair[128], formal_count: i64 = 0, instance: List = List {..}, witnesses: Id[256] = [0; 256],
    row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128], secondary: List = List {..}, secondary_witnesses: Id[256] = [0; 256],
    views: Context? = null, pending: blot_check_effects::Id[128], pending_count: i64 = 0, foreign_views: bool = false,
    left_rows: List = List {..}, instance_rows: List = List {..}, scheme_row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128],
    row_search_depth: i64 = 0, projection_resolver: PrincipalProjectionResolver? = null, projection_depth: i64 = 0,
    certificate_pairs: CertificatePairs? = null, version_pairs: const VersionPair[:] = default<const VersionPair[:]>(),
}
// Snapshot only owned scalar state; borrowed roots remain explicit arguments.
fn principalState<P>(self_: const P&) -> PrincipalState {
    return PrincipalState {
        formals: self_.formals,
        formal_count: self_.formal_count,
        instance: self_.instance,
        witnesses: self_.witnesses,
        row_witnesses: self_.row_witnesses,
        secondary: self_.secondary,
        secondary_witnesses: self_.secondary_witnesses,
        pending: self_.pending,
        pending_count: self_.pending_count,
        foreign_views: self_.foreign_views,
        left_rows: self_.left_rows,
        instance_rows: self_.instance_rows,
        scheme_row_witnesses: self_.scheme_row_witnesses,
        row_search_depth: self_.row_search_depth,
        projection_depth: self_.projection_depth,
    };
}
// Publish owned witnesses without extending any borrowed root lifetime.
fn publishPrincipalState<P>(self_:P&,state:PrincipalState) {
    self_.formals=state.formals;
    self_.formal_count=state.formal_count;
    self_.instance=state.instance;
    self_.witnesses=state.witnesses;
    self_.row_witnesses=state.row_witnesses;
    self_.secondary=state.secondary;
    self_.secondary_witnesses=state.secondary_witnesses;
    self_.pending=state.pending;
    self_.pending_count=state.pending_count;
    self_.foreign_views=state.foreign_views;
    self_.left_rows=state.left_rows;
    self_.instance_rows=state.instance_rows;
    self_.scheme_row_witnesses=state.scheme_row_witnesses;
    self_.row_search_depth=state.row_search_depth;
    self_.projection_depth=state.projection_depth;
}
// Construct a proof from explicit live roots and owned state.
fn principalFromState(left:const blot_check_core::Types&,right:const blot_check_core::Types&,remaining:i64&,views:Context?,state:PrincipalState,projection_resolver:PrincipalProjectionResolver?=null,certificate_pairs:CertificatePairs?=null,version_pairs:const VersionPair[:]=default<const VersionPair[:]>())->Principal {
    return Principal {
        left:left, right:right, remaining:remaining,
        formals:state.formals,
        formal_count:state.formal_count,
        instance:state.instance,
        witnesses:state.witnesses,
        row_witnesses:state.row_witnesses,
        secondary:state.secondary,
        secondary_witnesses:state.secondary_witnesses,
        views:views,
        pending:state.pending,
        pending_count:state.pending_count,
        foreign_views:state.foreign_views,
        left_rows:state.left_rows,
        instance_rows:state.instance_rows,
        scheme_row_witnesses:state.scheme_row_witnesses,
        row_search_depth:state.row_search_depth,
        projection_resolver:projection_resolver,
        projection_depth:state.projection_depth,
        certificate_pairs:certificate_pairs,
        version_pairs:version_pairs,
        ..
    };
}
// Clone owned state while retaining the exact live proof roots.
fn clonePrincipal(proof:const Principal&)->Principal {
    return principalFromState(proof.left,proof.right,proof.remaining,proof.views,principalState(proof),proof.projection_resolver,proof.certificate_pairs,proof.version_pairs);
}
fn sameTypes(left: const blot_check_core::Types&, right: const blot_check_core::Types&) -> bool { return left.owner_id != 0 && left.owner_id == right.owner_id; }
fn certificateRow(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error { return certificateRowMode(self_.left, self_.right, self_.remaining, self_.certificate_pairs, left, right); }
fn certificateRowMode(left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, certificates: CertificatePairs?, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    { let optional_binding_27 .= certificates; if optional_binding_27 { let pairs .= optional_binding_27;
        let a = left_types.row(left); let b = right_types.row(right); var x: i64 = -1; var y: i64 = -1;
        for variable, ordinal in left_types.list(pairs.left) { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; match a.tail { variable match_payload_21 => { let value = match_payload_21.value;  if value == variable { x = ordinal; } }, _ => {}, } }
        for variable, ordinal in right_types.list(pairs.right) { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; match b.tail { variable match_payload_20 => { let value = match_payload_20.value;  if value == variable { y = ordinal; } }, _ => {}, } }
        if (x < 0) != (y < 0) { return blot_error::Error.invalid_artifact; } if x >= 0 { if x >= 4096 || y >= 4096 { return blot_error::Error.invalid_artifact; } pairs.seen_left.set(x); pairs.seen_right.set(y); }
     } } return blot_error::Error.none;
}
fn certifiedScheme<L,R>(self_: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error {
    if expected.closed_rows.len != actual.closed_rows.len || expected.closed_rows.len > 4096 { return blot_error::Error.invalid_artifact; }
    var pairs = CertificatePairs { expected.closed_rows, actual.closed_rows, ..};
    var state = principalState(self_);
    let error = schemeGoalsMode(state, self_.left, self_.right, self_.remaining, self_.views, pairs, self_.version_pairs, self_.projection_resolver, expected, actual, left_goals, right_goals, resolvePrincipalProjectionMode);
    publishPrincipalState(self_, state);
    self_.certificate_pairs .= null;
    if error != blot_error::Error.none { return error; }
    if pairs.seen_left.count() != pairs.seen_right.count() { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
// Fresh certified endpoints keep borrowed roots outside their scalar proof state.
fn certifiedEndpoint<L,R>(left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, remaining: i64&, views: Context?, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error {
    if expected.closed_rows.len != actual.closed_rows.len || expected.closed_rows.len > 4096 { return blot_error::Error.invalid_artifact; }
    var endpoint = PrincipalState { left_rows: expected.closed_rows, ..};
    var pairs = CertificatePairs { expected.closed_rows, actual.closed_rows, ..};
    let error = schemeGoalsMode(endpoint, left_types, right_types, remaining, views, pairs, default<const VersionPair[:]>(), null, expected, actual, left_goals, right_goals, rejectPrincipalProjection);
    if error != blot_error::Error.none { return error; }
    if pairs.seen_left.count() != pairs.seen_right.count() { return blot_error::Error.invalid_artifact; }
    return blot_error::Error.none;
}
fn substituted(self_: Principal&, formals: List, replacements: const Id[:], expected: Id, actual: Id) -> Error {
    if formals.len != replacements.len || formals.len > 128 { return blot_error::Error.invalid_artifact; } self_.instance = formals;
    for replacement, index in replacements { self_.witnesses[index] = replacement; } let error = validate(self_, expected, actual); self_.instance = List {..}; return error;
}
fn composed(self_: Principal&, formals: List, replacements: const Id[:], secondary: List, secondary_replacements: const Id[:], expected: Id, actual: Id) -> Error {
    if secondary.len != secondary_replacements.len || secondary.len > 128 { return blot_error::Error.invalid_artifact; } self_.secondary = secondary;
    for replacement, index in secondary_replacements { self_.secondary_witnesses[index] = replacement; }
    let error = substituted(self_, formals, replacements, expected, actual); self_.secondary = List {..}; return error;
}
fn goalEndpoints<G>(self_: Principal&, left: G, right: G) -> Error { return goalEndpointsMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, resolvePrincipalProjectionMode); }
fn goalEndpointsMode<P,G,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: G, right: G) -> Error {
    if left.kind != right.kind || left.name != right.name || left.operator != right.operator || left.identity.unit != right.identity.unit || left.identity.decl != right.identity.decl { return blot_error::Error.invalid_artifact; }
    let xs: Id[4] = [left.ty, left.other, left.result, left.signature]; let ys: Id[4] = [right.ty, right.other, right.result, right.signature];
    for x, index in xs { let y = ys[index]; if x == 0 || y == 0 { if x != y { return blot_error::Error.invalid_artifact; } } else { let error = validateMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, y, F); if error != blot_error::Error.none { return error; } } } return blot_error::Error.none;
}
fn schemeGoals<L,R>(self_: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error { return schemeGoalsMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, expected, actual, left_goals, right_goals, resolvePrincipalProjectionMode); }
fn schemeGoalsMode<P,L,R,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error {
    if left_goals.len != right_goals.len || expected.row_variables.len != actual.row_variables.len { return blot_error::Error.invalid_artifact; }
    let left_owner = left_types.node(expected.root); let right_owner = right_types.node(actual.root); let paired = left_owner.tag == blot_check_types::Tag.forall && right_owner.tag == blot_check_types::Tag.forall;
    if left_owner.tag != right_owner.tag { return blot_error::Error.invalid_artifact; }
    if paired {
        let error = validateMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, expected.root, actual.root, F); if error != blot_error::Error.none { return error; }
        if left_owner.c != right_owner.c || self_.formal_count >= self_.formals.len { return blot_error::Error.invalid_artifact; }
        self_.formals[self_.formal_count] = FormalPair { List { left_owner.b, left_owner.c }, List { right_owner.b, right_owner.c , ..} , ..}; self_.formal_count += 1;
    } else { if expected.variables.len != actual.variables.len { return blot_error::Error.invalid_artifact; } let error = instantiateSchemeMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, expected, actual.root, F); if error != blot_error::Error.none { return error; } }
    let error = schemeGoalBodyMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, expected, actual, left_goals, right_goals, paired, F); if paired { self_.formal_count -= 1; } self_.instance = List {..}; self_.instance_rows = List {..}; return error;
}
fn schemeGoalBody<L,R>(self_: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R, paired: bool) -> Error { return schemeGoalBodyMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, expected, actual, left_goals, right_goals, paired, resolvePrincipalProjectionMode); }
fn schemeGoalBodyMode<P,L,R,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R, paired: bool) -> Error {
    if expected.variables.len > typeLimitMode(left_types, context, expected.root) || expected.row_variables.len > 128 { return blot_error::Error.invalid_artifact; }
    self_.instance = expected.variables; self_.instance_rows = expected.row_variables; if paired { self_.instance = List {..}; }
    for left, index in left_goals { let error = goalEndpointsMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right_goals[index], F); if error != blot_error::Error.none { return error; } }
    if paired { return blot_error::Error.none; } var variables = Bits256 {..};
    for ordinal in 0..expected.variables.len { let witness = self_.witnesses[ordinal]; if witness == 0 { continue; } var found = false;
        for variable, index in right_types.list(actual.variables) { if variable != witness { continue; } if variables.isSet(index) { return blot_error::Error.invalid_artifact; } variables.set(index); found = true; break; } if !found { return blot_error::Error.invalid_artifact; }
    }
    var rows = Bits256 {..};
    for ordinal in 0..expected.row_variables.len { let witness = self_.scheme_row_witnesses[ordinal]; if !witness.present { continue; } let row = right_types.row(witness.value.row);
        if witness.value.excluded.count() != row.labels.len { return blot_error::Error.invalid_artifact; } var variable: u32 = 0;
        match row.tail { variable match_payload_19 => { let value = match_payload_19.value;  variable = value; }, _ => { return blot_error::Error.invalid_artifact; }, }
        var found = false; for other, index in right_types.list(actual.row_variables) { if other != variable { continue; } if rows.isSet(index) { return blot_error::Error.invalid_artifact; } rows.set(index); found = true; break; } if !found { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.none;
}
fn sourceTypes(self_: const Principal&) -> bool { return sourceTypesMode(self_.views); }
fn sourceTypesMode(context: Context?) -> bool { { let optional_binding_26 .= context; if optional_binding_26 { let views .= optional_binding_26; return views.source_instances && views.large_plain_graph;  } } return false; }
fn typeLimit(self_: const Principal&, root: Id) -> i64 { return typeLimitMode(self_.left, self_.views, root); }
fn typeLimitMode(left_types: const blot_check_core::Types&, context: Context?, root: Id) -> i64 { if root >= left_types.nodes.len { return 128; } let tag = left_types.node(root).tag; if tag != blot_check_types::Tag.forall && tag != blot_check_types::Tag.existential && sourceTypesMode(context) { return ordinary_source_type_limit; } return 128; }
fn publicArguments(self_: Principal&, variables: List, rows: List, arguments: const Id[:]) -> Error {
    var maximum: i64 = 128; if sourceTypes(self_) { maximum = ordinary_source_type_limit; }
    if arguments.len != variables.len + rows.len || self_.instance.len > maximum || self_.instance_rows.len > 128 { return blot_error::Error.invalid_artifact; }
    var proof = principalFromState(self_.right,self_.right,self_.remaining,self_.views,PrincipalState{..});
    let binders, error = span(self_.left, variables); if error != blot_error::Error.none { return error; } let instances, error = span(self_.left, self_.instance); if error != blot_error::Error.none { return error; }
    for formal, index in binders { var ordinal: i64 = -1; for instance, j in instances { if instance == formal { ordinal = j; break; } }
        if ordinal < 0 || ordinal >= self_.witnesses.len || self_.witnesses[ordinal] == 0 { return blot_error::Error.invalid_artifact; }
        let error = matchPrincipal(proof, self_.witnesses[ordinal], arguments[index], 0); if error != blot_error::Error.none { return error; }
    }
    let row_binders, error = span(self_.left, rows); if error != blot_error::Error.none { return error; } let row_instances, error = span(self_.left, self_.instance_rows); if error != blot_error::Error.none { return error; }
    for formal, index in row_binders { var ordinal: i64 = -1; for instance, j in row_instances { if instance == formal { ordinal = j; break; } }
        let actual = arguments[variables.len + index]; if ordinal < 0 || ordinal >= self_.scheme_row_witnesses.len || actual >= self_.right.nodes.len { return blot_error::Error.invalid_artifact; }
        let witness = self_.scheme_row_witnesses[ordinal]; if !witness.present { return blot_error::Error.invalid_artifact; } let carrier = self_.right.node(actual);
        if carrier.tag != blot_check_types::Tag.function || carrier.a != blot_check_types::unit || carrier.b != blot_check_types::unit { return blot_error::Error.invalid_artifact; }
        let error = structuredRow(proof, witness.value.row, carrier.c, witness.value.excluded, Bits256 {..}, false, 0); if error != blot_error::Error.none { return error; }
    } return publishPending(proof);
}
fn rows(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error { return matchRow(self_, left, right, 0); }
fn instantiateScheme(self_: Principal&, scheme: Scheme, actual: Id) -> Error { return instantiateSchemeMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, scheme, actual, resolvePrincipalProjectionMode); }
fn instantiateSchemeMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, scheme: Scheme, actual: Id) -> Error {
    if scheme.variables.len > typeLimitMode(left_types, context, scheme.root) || scheme.row_variables.len > 128 { return blot_error::Error.invalid_artifact; }
    self_.instance = scheme.variables; self_.instance_rows = scheme.row_variables; self_.witnesses = [0; 256]; for &witness in self_.scheme_row_witnesses { witness.present = false; }
    var endpoint = actual; let quantified_actual = right_types.node(actual).tag == blot_check_types::Tag.forall;
    if quantified_actual { { let optional_binding_25 .= context; if optional_binding_25 { let views .= optional_binding_25; if !sameTypes(views.types, right_types) || right_types.node(actual).c > 128 { self_.instance = List {..}; self_.instance_rows = List {..}; return blot_error::Error.invalid_artifact; }
        let error = enter(views, actual); if error != blot_error::Error.none { self_.instance = List {..}; self_.instance_rows = List {..}; return error; } endpoint = right_types.node(actual).a;
     } else { self_.instance = List {..}; self_.instance_rows = List {..}; return blot_error::Error.invalid_artifact; } } }
    let error = validateMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, scheme.root, endpoint, F); if quantified_actual { { let optional_binding_24 .= context; if optional_binding_24 { let views .= optional_binding_24; leave(views);  } } } self_.instance = List {..}; self_.instance_rows = List {..}; return error;
}
fn instantiate(self_: Principal&, owner: Id, actual: Id) -> Error { if self_.left.quantifierGoals(owner).len != 0 { return blot_error::Error.invalid_artifact; } return instantiateTypes(self_, owner, actual); }
fn instantiateTypes(self_: Principal&, owner: Id, actual: Id) -> Error {
    if owner >= self_.left.nodes.len { return blot_error::Error.invalid_artifact; } let quantifier = self_.left.node(owner);
    if quantifier.tag != blot_check_types::Tag.forall || quantifier.c == 0 || quantifier.c > 128 { return blot_error::Error.invalid_artifact; }
    self_.instance = List { quantifier.b, quantifier.c , ..}; self_.witnesses = [0; 256]; for &witness in self_.row_witnesses { witness.present = false; }
    let error = validate(self_, quantifier.a, actual); self_.instance = List {..}; return error;
}
fn publishPending(self_: Principal&) -> Error { return publishPendingMode(self_, self_.views); }
fn publishPendingMode<P>(self_: P&, context: Context?) -> Error { { let optional_binding_23 .= context; if optional_binding_23 { let views .= optional_binding_23; for index in 0..self_.pending_count { let row = self_.pending[index]; let error = views.closed_rows.set(row); if error != blot_error::Error.none { return error; } if views.types.row(row).labels.len == 0 { let error = views.pure_rows.set(row); if error != blot_error::Error.none { return error; } } }  } } return blot_error::Error.none; }
recursive fn validate(self_: Principal&, left: Id, right: Id) -> Error { return validateMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, resolvePrincipalProjectionMode); }
recursive fn validateMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: Id, right: Id) -> Error { self_.pending_count = 0; let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, 0, F); if error != blot_error::Error.none { return error; } return publishPendingMode(self_, context); }
// A fresh endpoint has no projection resolver; its static policy excludes that backedge.
fn validateEndpoint(types: const blot_check_core::Types&, remaining: i64&, views: Context?, left: Id, right: Id) -> Error {
    var endpoint = PrincipalState {..};
    return validateEndpointState(endpoint, types, remaining, views, left, right);
}
fn validateEndpointState(endpoint: PrincipalState&, types: const blot_check_core::Types&, remaining: i64&, views: Context?, left: Id, right: Id) -> Error {
    return validateMode(endpoint, types, types, remaining, views, null, default<const VersionPair[:]>(), null, left, right, rejectPrincipalProjection);
}
recursive fn resolvePrincipalProjection(self_: Principal&, left: Id, right: Id) -> Error {
    return resolvePrincipalProjectionMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right);
}
recursive fn resolvePrincipalProjectionMode<P>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: Id, right: Id) -> Error {
    { let resolver .= projection_resolver; if resolver {
        if self_.projection_depth >= 128 { return blot_error::Error.invalid_artifact; }
        self_.projection_depth += 1;
        let error = resolver.validateMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right);
        self_.projection_depth -= 1;
        return error;
    } }
    return blot_error::Error.invalid_artifact;
}
fn rejectPrincipalProjection<P>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: Id, right: Id) -> Error { return blot_error::Error.invalid_artifact; }

fn hasVariable(types: const blot_check_core::Types&, variables: List, sought: u32) -> bool { for variable in types.list(variables) { if variable == sought { return true; } } return false; }
fn rowPure(self_: const Principal&, types: const blot_check_core::Types&, row: blot_check_effects::Id) -> bool { return rowPureMode(self_, self_.left, self_.views, types, row); }
fn rowPureMode<P>(self_: const P&, left_types: const blot_check_core::Types&, context: Context?, types: const blot_check_core::Types&, row: blot_check_effects::Id) -> bool {
    if sameTypes(types, left_types) && row < types.effects.rows.len { let value = types.row(row); if value.labels.len == 0 { match value.tail { variable match_payload_18 => { let value = match_payload_18.value;  if hasVariable(types, self_.left_rows, value) { return true; } }, _ => {}, } } }
    { let optional_binding_22 .= context; if optional_binding_22 { let views .= optional_binding_22; if sameTypes(views.types, types) { return views.isPure(row); }  } } return pure(types, row);
}
fn rowForeign(self_: const Principal&, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool { return rowForeignMode(self_, self_.left, self_.views, types, id); }
fn rowForeignMode<P>(self_: const P&, left_types: const blot_check_core::Types&, context: Context?, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if foreign(types, id) { return true; } { let optional_binding_21 .= context; if optional_binding_21 { let views .= optional_binding_21; if sameTypes(views.types, types) && views.isForeign(id) { return true; }  } }
    if !sameTypes(types, left_types) || id >= types.effects.rows.len { return false; } let row = types.row(id); if row.labels.len == 0 { return false; }
    match row.tail { variable match_payload_17 => { let value = match_payload_17.value;  if !hasVariable(types, self_.left_rows, value) { return false; } }, _ => { return false; }, }
    for label in types.rowLabels(id) { if label != blot_check_types::foreign_operation { return false; } } return true;
}
recursive fn operation(self_: Principal&, left: blot_check_effects::Label, right: blot_check_effects::Label, depth: i64) -> Error { return operationMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, depth, resolvePrincipalProjectionMode); }
recursive fn operationMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Label, right: blot_check_effects::Label, depth: i64) -> Error {
    if budget == 0 || depth >= 128 { return blot_error::Error.invalid_artifact; } budget -= 1;
    if left == 0 || right == 0 || left >= left_types.operations.len || right >= right_types.operations.len { return blot_error::Error.invalid_artifact; }
    let a = left_types.operation(left); let b = right_types.operation(right);
    if a.identity != b.identity || a.instance.unit != b.instance.unit || a.arguments.len != b.arguments.len { return blot_error::Error.invalid_artifact; }
    if a.instance.unit == 0 && a.instance.decl != 0 && b.instance.decl != 0 { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.instance.decl, b.instance.decl, depth + 1, F); if error != blot_error::Error.none { return error; } } else if a.instance.decl != b.instance.decl { return blot_error::Error.invalid_artifact; }
    let xs, error = span(left_types, a.arguments); if error != blot_error::Error.none { return error; } let ys, error = span(right_types, b.arguments); if error != blot_error::Error.none { return error; }
    for x, index in xs { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, ys[index], depth + 1, F); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn closedRow(self_: Principal&, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool { return closedRowMode(self_, self_.left, self_.views, types, id); }
fn closedRowMode<P>(self_: P&, left_types: const blot_check_core::Types&, context: Context?, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if id >= types.effects.rows.len { return false; } let row = types.row(id); if row.tail == blot_check_effects::Tail.closed { return true; }
    { let optional_binding_20 .= context; if optional_binding_20 { let views .= optional_binding_20; if sameTypes(views.types, types) && views.closed_rows.contains(id) { return true; }  } }
    if sameTypes(types, left_types) { match row.tail { variable match_payload_16 => { let value = match_payload_16.value;  return hasVariable(types, self_.left_rows, value); }, _ => {}, } } return false;
}
recursive fn structuredRow(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, right_excluded: Bits256, subset: bool, depth: i64) -> Error { return structuredRowMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, left_excluded, right_excluded, subset, depth, resolvePrincipalProjectionMode); }
recursive fn structuredRowMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, right_excluded: Bits256, subset: bool, depth: i64) -> Error {
    if depth >= 128 || budget == 0 || left >= left_types.effects.rows.len || right >= right_types.effects.rows.len { return blot_error::Error.invalid_artifact; } budget -= 1;
    if left_types.rowLabels(left).len > 256 || right_types.rowLabels(right).len > 256 { return blot_error::Error.invalid_artifact; } return rowLabelsMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, left_excluded, right_excluded, subset, 0, depth, F);
}
recursive fn rowLabels(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error { return rowLabelsMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, left_excluded, used, subset, start, depth, resolvePrincipalProjectionMode); }
recursive fn rowLabelsMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error {
    if self_.row_search_depth >= 257 || budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; self_.row_search_depth += 1;
    let error = searchRowLabelsMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, left_excluded, used, subset, start, depth, F); self_.row_search_depth -= 1; return error;
}
recursive fn searchRowLabels(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error { return searchRowLabelsMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, left_excluded, used, subset, start, depth, resolvePrincipalProjectionMode); }
recursive fn searchRowLabelsMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error {
    let xs = left_types.rowLabels(left); let ys = right_types.rowLabels(right); var ordinal = start; while ordinal < xs.len && left_excluded.isSet(ordinal) { ordinal += 1; }
    if ordinal == xs.len { return rowTailMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, used, subset, depth, F); }
    for candidate, index in ys {
        if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; if used.isSet(index) { continue; }
        var solver: blot_check_scheme_equations::Solver? = null; { let optional_binding_19 .= context; if optional_binding_19 { let views .= optional_binding_19; solver .= views.solver;  } }
        var mark = default<blot_check_types::Mark>(); { let optional_binding_18 .= solver; if optional_binding_18 { let owner .= optional_binding_18; mark = owner.store.mark();  } }
        let saved = self_.witnesses; let saved_rows = self_.row_witnesses; let saved_scheme_rows = self_.scheme_row_witnesses; let pending = self_.pending_count;
        var error = operationMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, xs[ordinal], candidate, depth + 1, F);
        if error == blot_error::Error.none { var next = used; next.set(index); error = rowLabelsMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, left_excluded, next, subset, ordinal + 1, depth, F); }
        if error == blot_error::Error.none { return blot_error::Error.none; }
        { let optional_binding_17 .= solver; if optional_binding_17 { let owner .= optional_binding_17; owner.rollback(mark);  } } self_.witnesses = saved; self_.row_witnesses = saved_rows; self_.scheme_row_witnesses = saved_scheme_rows; self_.pending_count = pending;
        if budget == 0 { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.invalid_artifact;
}
fn mergePending<P,Q>(self_: P&, proof: const Q&) -> Error { if self_.pending_count + proof.pending_count > self_.pending.len { return blot_error::Error.invalid_artifact; } for index in 0..proof.pending_count { self_.pending[self_.pending_count + index] = proof.pending[index]; } self_.pending_count += proof.pending_count; return blot_error::Error.none; }
recursive fn rowWitness(self_: Principal&, prior: blot_support::Option<RowWitness>&, right: blot_check_effects::Id, used: Bits256, depth: i64) -> Error { return rowWitnessMode(self_, self_.right, self_.remaining, self_.views, prior, right, used, depth); }
recursive fn rowWitnessMode<P>(self_: P&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, prior: blot_support::Option<RowWitness>&, right: blot_check_effects::Id, used: Bits256, depth: i64) -> Error {
    if prior.present { var proof = PrincipalState {..}; let error = structuredRowMode(proof, right_types, right_types, budget, context, null, default<const VersionPair[:]>(), null, prior.value.row, right, prior.value.excluded, used, false, depth + 1, rejectPrincipalProjection); if error != blot_error::Error.none { return error; } return mergePending(self_, proof); }
    prior = blot_support::Option<RowWitness> { true, RowWitness { right, used , ..} , ..}; return blot_error::Error.none;
}
recursive fn rowTail(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, used: Bits256, subset: bool, depth: i64) -> Error { return rowTailMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, used, subset, depth, resolvePrincipalProjectionMode); }
recursive fn rowTailMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Id, right: blot_check_effects::Id, used: Bits256, subset: bool, depth: i64) -> Error {
    let a = left_types.row(left); let b = right_types.row(right); let ys = right_types.rowLabels(right);
    if !subset {
        match a.tail {
            variable match_payload_14 => { let value = match_payload_14.value;  if self_.instance_rows.len != 0 { let variables, error = span(left_types, self_.instance_rows); if error != blot_error::Error.none { return error; } for variable, ordinal in variables { if variable == value { return rowWitnessMode(self_, right_types, budget, context, self_.scheme_row_witnesses[ordinal], right, used, depth); } } } },
            formal match_payload_15 => { let value = match_payload_15.value;  if self_.instance.len != 0 { let binders, error = span(left_types, self_.instance); if error != blot_error::Error.none { return error; } for binder, ordinal in binders { if binder != value { continue; } let node = left_types.node(binder); if node.tag != blot_check_types::Tag.bound || node.b != 1 || ordinal >= self_.row_witnesses.len { return blot_error::Error.invalid_artifact; } return rowWitnessMode(self_, right_types, budget, context, self_.row_witnesses[ordinal], right, used, depth); } } },
            _ => {},
        }
    }
    match a.tail {
        formal match_payload_13 => { let value = match_payload_13.value;  match b.tail { formal match_payload_12 => { let other = match_payload_12.value;  let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, value, other, depth + 1, F); if error != blot_error::Error.none { return error; } }, _ => { return blot_error::Error.invalid_artifact; }, } },
        _ => { if !subset || a.tail != blot_check_effects::Tail.closed {
            if !(closedRowMode(self_, left_types, context, left_types, left) && closedRowMode(self_, left_types, context, right_types, right)) && !blot_structural::equal(a.tail, b.tail) {
                { let optional_binding_16 .= context; if optional_binding_16 { let views .= optional_binding_16; if subset || !closedRowMode(self_, left_types, context, left_types, left) || !sameTypes(views.types, right_types) { return blot_error::Error.invalid_artifact; }
                    match b.tail { variable match_payload_11 => { let value = match_payload_11.value; }, _ => { return blot_error::Error.invalid_artifact; }, }
                    if self_.pending_count >= self_.pending.len { return blot_error::Error.invalid_artifact; } self_.pending[self_.pending_count] = right; self_.pending_count += 1;
                 } else { return blot_error::Error.invalid_artifact; } }
            }
        } },
    }
    if !subset { for index in 0..ys.len { if !used.isSet(index) { return blot_error::Error.invalid_artifact; } } } return blot_error::Error.none;
}
fn subsetRow(self_: Principal&, actual: blot_check_effects::Id, declared: blot_check_effects::Id) -> Error { return structuredRow(self_, actual, declared, Bits256 {..}, Bits256 {..}, true, 0); }
fn handledRow(self_: Principal&, actual: blot_check_effects::Id, declared: blot_check_effects::Id, excluded: Bits256, subset: bool) -> Error { return structuredRow(self_, actual, declared, excluded, Bits256 {..}, subset, 0); }
recursive fn matchRow(self_: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, depth: i64) -> Error { return matchRowMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, depth, resolvePrincipalProjectionMode); }
recursive fn matchRowMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: blot_check_effects::Id, right: blot_check_effects::Id, depth: i64) -> Error {
    { let optional_binding_15 .= context; if optional_binding_15 { let views .= optional_binding_15; { let optional_binding_14 .= views.solver; if optional_binding_14 { let solver .= optional_binding_14; if sameTypes(left_types, views.types) && sameTypes(right_types, views.types) {
        let l, error = solver.resolveRow(left); if error != blot_error::Error.none { return solver.readerError(error); } let r, error = solver.resolveRow(right); if error != blot_error::Error.none { return solver.readerError(error); }
        if l != left || r != right { return matchRowMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, l, r, depth + 1, F); }
        var variable = false; match solver.store.effects.node(l).tail { variable match_payload_10 => { let value = match_payload_10.value;  variable = true; }, _ => {}, } match solver.store.effects.node(r).tail { variable match_payload_9 => { let value = match_payload_9.value;  variable = true; }, _ => {}, }
        if variable { let error = solver.rows(l, r); if error != blot_error::Error.none { return solver.readerError(error); } return blot_error::Error.none; }
    }  } }  } }
    let error = certificateRowMode(left_types, right_types, budget, certificates, left, right); if error != blot_error::Error.none { return error; }
    if left < left_types.effects.rows.len { let source = left_types.row(left); match source.tail { variable match_payload_8 => { let value = match_payload_8.value;  if hasVariable(left_types, self_.instance_rows, value) { return structuredRowMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, Bits256 {..}, Bits256 {..}, false, depth + 1, F); } }, _ => {}, } }
    if left < left_types.effects.rows.len && right < right_types.effects.rows.len {
        let a = left_types.row(left); let b = right_types.row(right);
        if sameTypes(left_types, right_types) && a.labels.len == 0 && b.labels.len == 0 && blot_structural::equal(a.tail, b.tail) && a.cursor == b.cursor {
            match a.tail { variable match_payload_7 => { let value = match_payload_7.value;
                if value >= left_types.effects.variable_count { return blot_error::Error.invalid_artifact; }
                { let optional_binding_13 .= context; if optional_binding_13 { let views .= optional_binding_13; if sameTypes(views.types, left_types) && views.isPure(right) {
                    if views.isPure(left) { return blot_error::Error.none; } if self_.pending_count >= self_.pending.len { return blot_error::Error.invalid_artifact; } self_.pending[self_.pending_count] = left; self_.pending_count += 1; return blot_error::Error.none;
                }  } }
                if !rowPureMode(self_, left_types, context, left_types, left) { return blot_error::Error.none; }
            }, _ => {}, }
        }
        if self_.foreign_views && rowPureMode(self_, left_types, context, left_types, left) {
            match b.tail { formal match_payload_6 => { let value = match_payload_6.value;
                { let optional_binding_12 .= context; if optional_binding_12 { let views .= optional_binding_12; if !sameTypes(views.types, right_types) { return blot_error::Error.invalid_artifact; } let leaf = right_types.node(value);
                    if leaf.tag == blot_check_types::Tag.rigid { { let optional_binding_11 .= views.solver; if optional_binding_11 { let solver .= optional_binding_11; if !solver.ownsRigid(leaf) || leaf.c != 1 { return blot_error::Error.invalid_artifact; }  } else { return blot_error::Error.invalid_artifact; } } }
                    else if !views.ownsFormal(value) { return blot_error::Error.invalid_artifact; } return views.validateRow(right, depth + 1);
                 } } return blot_error::Error.invalid_artifact;
            }, _ => {}, }
        }
        var generic_row = false; { let optional_binding_10 .= context; if optional_binding_10 { let views .= optional_binding_10; if sameTypes(left_types, right_types) && sameTypes(views.types, left_types) { let result, error = views.genericRow(left, depth + 1); if error != blot_error::Error.none { return error; } generic_row = result; }  } }
        var a_formal = false; var b_formal = false; var a_variable = false;
        match a.tail { formal match_payload_4 => { let value = match_payload_4.value;  a_formal = true; }, variable match_payload_5 => { let value = match_payload_5.value;  a_variable = true; }, _ => {}, }
        match b.tail { formal match_payload_3 => { let value = match_payload_3.value;  b_formal = true; }, _ => {}, }
        if generic_row || a_formal || b_formal || (a_variable && self_.instance_rows.len != 0) || (a.labels.len != 0 && (b.tail != blot_check_effects::Tail.closed || !rowForeignMode(self_, left_types, context, left_types, left))) {
            var subset = self_.foreign_views && closedRowMode(self_, left_types, context, left_types, left);
            if subset && rowForeignMode(self_, left_types, context, left_types, left) { match b.tail { variable match_payload_2 => { let value = match_payload_2.value;
                { let optional_binding_9 .= context; if optional_binding_9 { let views .= optional_binding_9; if !sameTypes(views.types, right_types) || value >= right_types.effects.variable_count { return blot_error::Error.invalid_artifact; }
                    let owned, error = views.ownsRow(value); if error != blot_error::Error.none { return error; }
                    if !owned { var exact = a.labels.len == b.labels.len; for label in right_types.rowLabels(right) { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; if label != blot_check_types::foreign_operation { exact = false; } } if exact { subset = false; } }
                 } else { return blot_error::Error.invalid_artifact; } }
            }, _ => {}, } }
            return structuredRowMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, Bits256 {..}, Bits256 {..}, subset, depth + 1, F);
        }
    }
    if rowForeignMode(self_, left_types, context, left_types, left) { if !rowForeignMode(self_, left_types, context, right_types, right) || left_types.row(left).labels.len != right_types.row(right).labels.len { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
    if !rowPureMode(self_, left_types, context, left_types, left) { return blot_error::Error.invalid_artifact; }
    if self_.foreign_views && rowForeignMode(self_, left_types, context, right_types, right) { return blot_error::Error.none; } if rowPureMode(self_, left_types, context, right_types, right) { return blot_error::Error.none; }
    if self_.foreign_views && right_types.row(right).labels.len != 0 { { let optional_binding_8 .= context; if optional_binding_8 { let views .= optional_binding_8; if !sameTypes(views.types, right_types) { return blot_error::Error.invalid_artifact; } return views.validateRow(right, depth + 1);  } } return blot_error::Error.invalid_artifact; }
    { let optional_binding_7 .= context; if optional_binding_7 { let views .= optional_binding_7;
        if !sameTypes(views.types, right_types) || right >= right_types.effects.rows.len { return blot_error::Error.invalid_artifact; } let actual = right_types.row(right);
        if actual.labels.len != 0 { return blot_error::Error.invalid_artifact; } match actual.tail { variable match_payload_1 => { let value = match_payload_1.value;  if value >= right_types.effects.variable_count { return blot_error::Error.invalid_artifact; } }, _ => { return blot_error::Error.invalid_artifact; }, }
        for index in 0..self_.pending_count { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; if self_.pending[index] == right { return blot_error::Error.none; } }
        if self_.pending_count >= self_.pending.len { return blot_error::Error.invalid_artifact; } self_.pending[self_.pending_count] = right; self_.pending_count += 1; return blot_error::Error.none;
     } } return blot_error::Error.invalid_artifact;
}
recursive fn matchIndexedRecord(self_: Principal&, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> bool, Error { return matchIndexedRecordMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, a, b, depth, resolvePrincipalProjectionMode); }
recursive fn matchIndexedRecordMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> bool, Error {
    if b.b <= 16 || b.b > 256 { return false, blot_error::Error.none; } var slots: u16[512] = [0; 512];
    for ordinal in 0..b.b { let field = right_types.recordField(b, ordinal); var slot = ((field.name * 0x9e3779b1) >> 23) as i64; var inserted = false;
        for attempt in 0..slots.len { if budget == 0 { return false, blot_error::Error.invalid_artifact; } budget -= 1; let prior = slots[slot];
            if prior == 0 { slots[slot] = (ordinal + 1) as u16; inserted = true; break; }
            if right_types.recordField(b, prior as i64 - 1).name == field.name { inserted = true; break; } slot = (slot + 1) & (slots.len - 1);
        } if !inserted { return false, blot_error::Error.invalid_artifact; }
    }
    for ordinal in 0..a.b { let field = left_types.recordField(a, ordinal); var slot = ((field.name * 0x9e3779b1) >> 23) as i64; var selected: Id = 0; var found = false;
        for attempt in 0..slots.len { if budget == 0 { return false, blot_error::Error.invalid_artifact; } budget -= 1; let entry = slots[slot]; if entry == 0 { return false, blot_error::Error.invalid_artifact; }
            let candidate = right_types.recordField(b, entry as i64 - 1); if candidate.name == field.name { selected = candidate.ty; found = true; break; } slot = (slot + 1) & (slots.len - 1);
        } if !found { return false, blot_error::Error.invalid_artifact; } let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, field.ty, selected, depth + 1, F); if error != blot_error::Error.none { return false, error; }
    } return true, blot_error::Error.none;
}
recursive fn matchPrincipal(self_: Principal&, left: Id, right: Id, depth: i64) -> Error { return matchPrincipalMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, depth, resolvePrincipalProjectionMode); }
recursive fn matchPrincipalMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: Id, right: Id, depth: i64) -> Error {
    if depth >= 128 || budget == 0 { budget = 0; return blot_error::Error.invalid_artifact; } budget -= 1;
    if left >= left_types.nodes.len || right >= right_types.nodes.len { return blot_error::Error.invalid_artifact; }
    { let optional_binding_6 .= context; if optional_binding_6 { let views .= optional_binding_6; { let optional_binding_5 .= views.solver; if optional_binding_5 { let solver .= optional_binding_5; if sameTypes(left_types, views.types) && sameTypes(right_types, views.types) {
        let l = solver.store.head(left, 0); let r = solver.store.head(right, 0); if l != left || r != right { return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, l, r, depth + 1, F); }
        if solver.store.node(l).tag == blot_check_types::Tag.variable || solver.store.node(r).tag == blot_check_types::Tag.variable { let error = solver.unify(l, r); if error != blot_error::Error.none { return solver.readerError(error); } return blot_error::Error.none; }
    }  } }  } }
    let a = left_types.node(left); let b = right_types.node(right);
    if (a.tag == blot_check_types::Tag.variable || (a.tag == blot_check_types::Tag.bound && a.c == 0)) && self_.instance.len != 0 {
        let binders, error = span(left_types, self_.instance); if error != blot_error::Error.none { return error; }
        for binder, ordinal in binders { if binder != left { continue; } var maximum: i64 = ordinary_source_type_limit; if a.tag == blot_check_types::Tag.bound || !sourceTypesMode(context) { maximum = 128; } if ordinal >= maximum { return blot_error::Error.invalid_artifact; }
            if a.tag == blot_check_types::Tag.bound {
                if a.b == 0 { var work = blot_check_usage_check::Work { remaining: budget , ..}; let contains, error = blot_check_usage_check::containsNominalWork(right_types, default<const blot_check_core::Nominal[:]>(), right, work); budget = work.remaining; if error != blot_error::Error.none || contains { return blot_error::Error.invalid_artifact; } }
                else if a.b != 2 || b.tag != blot_check_types::Tag.bound || b.b != 2 { return blot_error::Error.invalid_artifact; }
            }
            if self_.witnesses[ordinal] == 0 { self_.witnesses[ordinal] = right; return blot_error::Error.none; }
            var proof = PrincipalState { instance: self_.secondary, witnesses: self_.secondary_witnesses , ..};
            let error = matchPrincipalMode(proof, right_types, right_types, budget, context, null, default<const VersionPair[:]>(), null, self_.witnesses[ordinal], right, depth + 1, rejectPrincipalProjection); if error != blot_error::Error.none { return error; } return mergePending(self_, proof);
        }
    }
    if a.tag == blot_check_types::Tag.projection && b.tag != blot_check_types::Tag.projection {
        return F(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right);
    }
    if a.tag != b.tag { return blot_error::Error.invalid_artifact; }
    match a.tag {
        unit, boolean, unsigned32, floating32, never, erased_proof => {},
        variable => { if !sameTypes(left_types, right_types) || left != right { return blot_error::Error.invalid_artifact; } },
        rigid => {
            if !sameTypes(left_types, right_types) || a.a != b.a || a.b != b.b || a.c != b.c { return blot_error::Error.invalid_artifact; }
            { let optional_binding_3 .= context; if optional_binding_3 { let views .= optional_binding_3; { let optional_binding_2 .= views.solver; if optional_binding_2 { let solver .= optional_binding_2; if !solver.ownsRigid(a) { return blot_error::Error.invalid_artifact; }  } else { return blot_error::Error.invalid_artifact; } }  } else { return blot_error::Error.invalid_artifact; } }
        },
        bound => {
            if a.b != b.b || a.b > 2 { return blot_error::Error.invalid_artifact; }
            if a.c == 0 && b.c == 0 { for index in 0..self_.formal_count { let formal = self_.formals[index]; let l, error = span(left_types, formal.left); if error != blot_error::Error.none { return error; } let r, error = span(right_types, formal.right); if error != blot_error::Error.none { return error; }
                    if a.a < l.len && b.a < r.len && l[a.a] == left && r[b.a] == right { if a.a != b.a { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
                }
                { let optional_binding_1 .= context; if optional_binding_1 { let views .= optional_binding_1; if !sameTypes(left_types, right_types) || left != right || !views.ownsFormal(left) { return blot_error::Error.invalid_artifact; }  } else { return blot_error::Error.invalid_artifact; } }
            } else if !sameTypes(left_types, right_types) || left != right || a.c == 0 || b.c == 0 { return blot_error::Error.invalid_artifact; }
        },
        forall, existential => {
            if a.c != b.c || a.c > 128 || self_.formal_count >= self_.formals.len { return blot_error::Error.invalid_artifact; }
            let xs, error = span(left_types, List { a.b, a.c , ..}); if error != blot_error::Error.none { return error; } let ys, error = span(right_types, List { b.b, b.c , ..}); if error != blot_error::Error.none { return error; }
            for x, index in xs { if left_types.node(x).b != right_types.node(ys[index]).b { return blot_error::Error.invalid_artifact; } }
            self_.formals[self_.formal_count] = FormalPair { List { a.b, a.c }, List { b.b, b.c , ..} , ..}; self_.formal_count += 1;
            let error = matchQuantifiedMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, left, right, a, b, depth, F); self_.formal_count -= 1; return error;
        },
        function => {
            let error = matchRowMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.c, b.c, depth + 1, F); if error != blot_error::Error.none { return error; } let outer = self_.foreign_views; self_.foreign_views = false;
            let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); self_.foreign_views = outer; if error != blot_error::Error.none { return error; } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.b, b.b, depth + 1, F);
        },
        usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return blot_error::Error.invalid_artifact; } if a.c != 0 { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.c, b.c, depth + 1, F); if error != blot_error::Error.none { return error; } } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); },
        scoped => { if a.b != b.b || (a.b == 0) != (b.b == 0) { return blot_error::Error.invalid_artifact; } if a.b == 0 { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.c, b.c, depth + 1, F); if error != blot_error::Error.none { return error; } } else if a.c != b.c { return blot_error::Error.invalid_artifact; } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); },
        instance_version => {
            if a.a == b.a && a.b == b.b && a.c == b.c { return blot_error::Error.none; }
            for pair in versions { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; if a.a == pair.left.a && a.b == pair.left.b && a.c == pair.left.c && b.a == pair.right.a && b.b == pair.right.b && b.c == pair.right.c { return blot_error::Error.none; } } return blot_error::Error.invalid_artifact;
        },
        instance_selection => {
            if a.a != b.a || a.b != b.b { return blot_error::Error.invalid_artifact; } let xs = left_types.nominalArguments(a); let ys = right_types.nominalArguments(b); if xs.len != ys.len { return blot_error::Error.invalid_artifact; }
            for x, index in xs { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, ys[index], depth + 1, F); if error != blot_error::Error.none { return error; } }
        },
        array, list, cursor, resolver => { return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); },
        provider => { if a.b != 0 || b.b != 0 { return blot_error::Error.invalid_artifact; } let error = matchRowMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.c, b.c, depth + 1, F); if error != blot_error::Error.none { return error; } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); },
        type_constructor => { if a.a != b.a || a.b != b.b || a.c != 0 || b.c != 0 { return blot_error::Error.invalid_artifact; } },
        state_provider => { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F); if error != blot_error::Error.none { return error; } let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.b, b.b, depth + 1, F); if error != blot_error::Error.none { return error; } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.c, b.c, depth + 1, F); },
        product => { if a.b != b.b { return blot_error::Error.invalid_artifact; } let xs, error = span(left_types, List { a.a, a.b , ..}); if error != blot_error::Error.none { return error; } let ys, error = span(right_types, List { b.a, b.b , ..}); if error != blot_error::Error.none { return error; } for x, index in xs { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, ys[index], depth + 1, F); if error != blot_error::Error.none { return error; } } },
        record => {
            if a.b != b.b || a.b > 0x7fffffff { return blot_error::Error.invalid_artifact; } let xs, error = span(left_types, List { a.a, a.b * 2 , ..}); if error != blot_error::Error.none { return error; } let ys, error = span(right_types, List { b.a, b.b * 2 , ..}); if error != blot_error::Error.none { return error; }
            let indexed, error = matchIndexedRecordMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a, b, depth, F); if error != blot_error::Error.none || indexed { return error; }
            for index in 0..a.b { let field = left_types.recordField(a, index); var found = false;
                for other in 0..b.b { if budget == 0 { return blot_error::Error.invalid_artifact; } budget -= 1; let candidate = right_types.recordField(b, other); if field.name != candidate.name { continue; } let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, field.ty, candidate.ty, depth + 1, F); if error != blot_error::Error.none { return error; } found = true; break; }
                if !found { return blot_error::Error.invalid_artifact; }
            }
        },
        nominal, projection => {
            if a.a != b.a || a.b != b.b || a.c >= left_types.extra.len || b.c >= right_types.extra.len { return blot_error::Error.invalid_artifact; }
            if a.tag == blot_check_types::Tag.projection { let x, error = projectionMember(left_types, a); if error != blot_error::Error.none { return error; } let y, error = projectionMember(right_types, b); if error != blot_error::Error.none || x != y { return blot_error::Error.invalid_artifact; } }
            let xs, error = span(left_types, List { a.c + 1, left_types.extra[a.c] , ..}); if error != blot_error::Error.none { return error; } let ys, error = span(right_types, List { b.c + 1, right_types.extra[b.c] , ..}); if error != blot_error::Error.none || xs.len != ys.len { return blot_error::Error.invalid_artifact; }
            for x, index in xs { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, ys[index], depth + 1, F); if error != blot_error::Error.none { return error; } }
        },
        _ => { return blot_error::Error.invalid_artifact; },
    } return blot_error::Error.none;
}
recursive fn matchQuantified(self_: Principal&, left: Id, right: Id, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> Error { return matchQuantifiedMode(self_, self_.left, self_.right, self_.remaining, self_.views, self_.certificate_pairs, self_.version_pairs, self_.projection_resolver, left, right, a, b, depth, resolvePrincipalProjectionMode); }
recursive fn matchQuantifiedMode<P,F>(self_: P&, left_types: const blot_check_core::Types&, right_types: const blot_check_core::Types&, budget: i64&, context: Context?, certificates: CertificatePairs?, versions: const VersionPair[:], projection_resolver: PrincipalProjectionResolver?, left: Id, right: Id, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> Error {
    let xs = left_types.quantifierGoals(left); let ys = right_types.quantifierGoals(right); if xs.len != ys.len { return blot_error::Error.invalid_artifact; }
    for x, index in xs { let y = ys[index]; if !blot_check_quantifier_goals::sameHead(x, y) { return blot_error::Error.invalid_artifact; }
        let left_endpoints: Id[4] = [x.ty, x.other, x.result, x.signature]; let right_endpoints: Id[4] = [y.ty, y.other, y.result, y.signature];
        for x, i in left_endpoints { if (x == 0) != (right_endpoints[i] == 0) { return blot_error::Error.invalid_artifact; } if x != 0 { let error = matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, x, right_endpoints[i], depth + 1, F); if error != blot_error::Error.none { return error; } } }
    } return matchPrincipalMode(self_, left_types, right_types, budget, context, certificates, versions, projection_resolver, a.a, b.a, depth + 1, F);
}
