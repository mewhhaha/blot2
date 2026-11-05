// Package substitution reads exact lexical evidence in immutable type graphs.
namespace blot_check_package_contracts;
import std;
import support.error;
import support.option;
import support.structural;
import support.native;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type List = blot_check_types::List;
type Scheme = blot_check_types::Scheme;
let limit: i64 = 4096;
let ordinary_source_type_limit: i64 = 256;
struct Bits256 { words: u64[4] = [0; 4] }
struct Bits4096 { words: u64[64] = [0; 64] }
fn isSet(self: const Bits256&, index: i64) -> bool { return self.words[index >> 6] & ((1 as u64) << (index & 63)) != 0; }
fn set(self: Bits256&, index: i64) { self.words[index >> 6] |= (1 as u64) << (index & 63); }
fn count(self: const Bits256&) -> i64 { var result: i64 = 0; for word in self.words { result += popcount(word); } return result; }
fn eql(self: const Bits256&, other: const Bits256&) -> bool { return self.words == other.words; }
fn isSet(self: const Bits4096&, index: i64) -> bool { return self.words[index >> 6] & ((1 as u64) << (index & 63)) != 0; }
fn set(self: Bits4096&, index: i64) { self.words[index >> 6] |= (1 as u64) << (index & 63); }
fn count(self: const Bits4096&) -> i64 { var result: i64 = 0; for word in self.words { result += popcount(word); } return result; }
fn eql(self: const Bits4096&, other: const Bits4096&) -> bool { return self.words == other.words; }
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
    if value.start > types.extra.len || value.len > types.extra.len - value.start { return types.extra[..0], Error.invalid_artifact; }
    return types.list(value), Error.none;
}
fn projectionMember(types: const blot_check_core::Types&, node: blot_check_types::Node) -> u32, Error {
    if node.c >= types.extra.len { return 0, Error.invalid_artifact; } let start = node.c as i64 + 1; let count = types.extra[node.c];
    if count >= types.extra.len - start { return 0, Error.invalid_artifact; } let member = types.extra[start + count];
    if member == 0 { return 0, Error.invalid_artifact; } return member, Error.none;
}
fn quantified(types: const blot_check_core::Types&, root: Id, remaining: i64&) -> bool, Error { return quantifiedDepth(types, root, remaining, 0); }
recursive fn quantifiedDepth(types: const blot_check_core::Types&, root: Id, remaining: i64&, depth: i64) -> bool, Error {
    if root >= types.nodes.len || depth >= 128 || remaining == 0 { return false, Error.invalid_artifact; } remaining -= 1;
    let node = types.node(root);
    match node.tag {
        forall, existential => { return true, Error.none; },
        function => { let first, error = quantifiedDepth(types, node.a, remaining, depth + 1); if error != Error.none || first { return first, error; } return quantifiedDepth(types, node.b, remaining, depth + 1); },
        array, list, cursor, usage, resolver, provider, scoped => { return quantifiedDepth(types, node.a, remaining, depth + 1); },
        state_provider => { for child in [node.a, node.b, node.c] { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != Error.none || found { return found, error; } } },
        product => { let children, error = span(types, List { node.a, node.b }); if error != Error.none { return false, error; } for child in children { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != Error.none || found { return found, error; } } },
        record => {
            if node.b > 0x7fffffff { return false, Error.invalid_artifact; } let words, error = span(types, List { node.a, node.b * 2 }); if error != Error.none { return false, error; }
            for index in node.b { let found, error = quantifiedDepth(types, types.recordField(node, index).ty, remaining, depth + 1); if error != Error.none || found { return found, error; } }
        },
        nominal => {
            if node.c >= types.extra.len { return false, Error.invalid_artifact; } let children, error = span(types, List { node.c + 1, types.extra[node.c] }); if error != Error.none { return false, error; }
            for child in children { let found, error = quantifiedDepth(types, child, remaining, depth + 1); if error != Error.none || found { return found, error; } }
        }, _ => {},
    }
    return false, Error.none;
}
struct Opening { binding: blot_check_core::BindingId, binders: List, quantifier: Id }
type ProjectionResolver = blot_check_dictionary_contracts::PackProjection;
type PrincipalProjectionResolver = blot_check_scheme_projection::Resolver;
struct Context {
    owner_id: u64 = 0,
    types: const blot_check_core::Types&, remaining: i64&, solver: blot_check_scheme_equations::Solver? = null,
    owners: Id[4096] = [0; 4096], pure_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {},
    closed_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {}, source_instances: bool = false,
    instance_variables: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {},
    instance_rows: blot_check_package_row_facts::Facts = blot_check_package_row_facts::Facts {},
    formal: blot_support::Option<Id> = blot_support::Option<Id> { false, 0 }, generic_variables: List = List {}, generic_rows: List = List {},
    obligations: const blot_check_core::Obligation[:] = [], source_obligations: const blot_check_types::Obligation[:] = [],
    schemes: Scheme[128] = [Scheme {}; 128], scheme_count: i64 = 0,
    scheme_variables_sorted: bool[128] = [false; 128], scheme_rows_sorted: bool[128] = [false; 128],
    formals: Id[128] = [0; 128], formal_count: i64 = 0, introductions: blot_check_core::Id[128] = [0; 128], witness: bool = false,
    representation_floor: blot_support::Option<i64> = blot_support::Option<i64> { false, 0 }, executable: bool = false, large_plain_graph: bool = false,
    openings: Opening[128] = [default<Opening>(); 128], projection_resolver: ProjectionResolver? = null, opening_count: i64 = 0,
}
fn initialize(self: Context&) -> Error {
    if self.owner_id == 0 { self.owner_id = blot_native::fresh_owner_id(); }
    if !self.large_plain_graph && (self.types.nodes.len > limit || self.types.effects.rows.len > limit) { return Error.invalid_artifact; }
    let goals = blot_check_quantifier_goals::validateWithBudget(self.types.nodes, self.types.quantifier_goals, self.types.quantifier_obligations, self.remaining); if goals != Error.none { return goals; }
    for node, id in self.types.nodes {
        if node.tag != blot_check_types::Tag.forall && node.tag != blot_check_types::Tag.existential { continue; }
        if id == 0 || node.c == 0 || node.c > 128 { return Error.invalid_artifact; }
        let binders, error = span(self.types, List { node.b, node.c }); if error != Error.none { return error; }
        for binder, ordinal in binders {
            if binder >= self.types.nodes.len || binder >= self.owners.len { return Error.invalid_artifact; }
            let leaf = self.types.node(binder);
            if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b > 2 || (node.tag != blot_check_types::Tag.forall && leaf.b != 0) || leaf.c != 0 || self.owners[binder] != 0 { return Error.invalid_artifact; }
            self.owners[binder] = id as u32;
        }
    }
    for node, id in self.types.nodes { if node.tag == blot_check_types::Tag.bound { if id >= self.owners.len || (node.c == 0 && self.owners[id] == 0) { return Error.invalid_artifact; } } }
    return Error.none;
}
fn generic(self: Context&, scheme: Scheme) -> Error {
    self.instance_variables = blot_check_package_row_facts::Facts {}; self.instance_rows = blot_check_package_row_facts::Facts {};
    self.generic_variables = List {}; self.generic_rows = List {}; self.scheme_count = 0; return pushGeneric(self, scheme);
}
fn pushGeneric(self: Context&, scheme: Scheme) -> Error {
    if self.scheme_count >= self.schemes.len { return Error.invalid_artifact; }
    if self.types.node(scheme.root).tag == blot_check_types::Tag.forall {
        self.schemes[self.scheme_count] = scheme; self.scheme_variables_sorted[self.scheme_count] = false; self.scheme_rows_sorted[self.scheme_count] = false; self.scheme_count += 1; return Error.none;
    }
    let variables, ve = span(self.types, scheme.variables); if ve != Error.none { return ve; } let rows, re = span(self.types, scheme.row_variables); if re != Error.none { return re; }
    if !(self.large_plain_graph && self.source_instances) && (variables.len > 128 || rows.len > 128) { return Error.invalid_artifact; }
    let variables_sorted, ve = uniqueSchemeList(self, variables, false); if ve != Error.none { return ve; }
    let rows_sorted, re = uniqueSchemeList(self, rows, true); if re != Error.none { return re; }
    self.schemes[self.scheme_count] = scheme; self.scheme_variables_sorted[self.scheme_count] = variables_sorted; self.scheme_rows_sorted[self.scheme_count] = rows_sorted; self.scheme_count += 1;
    self.generic_variables = scheme.variables; self.generic_rows = scheme.row_variables; return Error.none;
}
fn popGeneric(self: Context&) {
    self.scheme_count -= 1; self.generic_variables = List {}; self.generic_rows = List {};
    if self.scheme_count != 0 { let scheme = self.schemes[self.scheme_count - 1]; if self.types.node(scheme.root).tag != blot_check_types::Tag.forall { self.generic_variables = scheme.variables; self.generic_rows = scheme.row_variables; } }
}
fn step(self: Context&, depth: i64) -> Error { if depth >= 128 || self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none; }
fn uniqueSchemeList(self: Context&, ids: const Id[:], rows: bool) -> bool, Error {
    var sorted = true;
    for id, index in ids {
        let charged = step(self, 0); if charged != Error.none { return false, charged; }
        if rows { if id >= self.types.effects.variable_count { return false, Error.invalid_artifact; } }
        else if id >= self.types.nodes.len || self.types.node(id).tag != blot_check_types::Tag.variable { return false, Error.invalid_artifact; }
        if index == 0 { continue; } let charged = step(self, 0); if charged != Error.none { return false, charged; }
        if ids[index - 1] == id { return false, Error.invalid_artifact; } if ids[index - 1] > id { sorted = false; }
    }
    if !sorted { for id, index in ids { for prior in ids[..index] { let charged = step(self, 0); if charged != Error.none { return false, charged; } if prior == id { return false, Error.invalid_artifact; } } } }
    return sorted, Error.none;
}
fn schemeListContains(self: Context&, ids: const Id[:], id: Id, sorted: bool) -> bool, Error {
    if !sorted { for candidate in ids { let charged = step(self, 0); if charged != Error.none { return false, charged; } if candidate == id { return true, Error.none; } } return false, Error.none; }
    var low: i64 = 0; var high = ids.len;
    while low < high { let charged = step(self, 0); if charged != Error.none { return false, charged; } let middle = low + (high - low) / 2;
        if ids[middle] == id { return true, Error.none; } if ids[middle] < id { low = middle + 1; } else { high = middle; } }
    return false, Error.none;
}
fn ownsVariable(self: Context&, id: Id) -> bool, Error {
    if self.source_instances && self.instance_variables.contains(id) { return true, Error.none; }
    if self.large_plain_graph && self.source_instances {
        let charged = step(self, 0); if charged != Error.none { return false, charged; }
        for scheme, index in self.schemes[..self.scheme_count] {
            if self.types.node(scheme.root).tag == blot_check_types::Tag.forall { continue; }
            let ids, error = span(self.types, scheme.variables); if error != Error.none { return false, error; }
            let found, error = schemeListContains(self, ids, id, self.scheme_variables_sorted[index]); if error != Error.none || found { return found, error; }
        }
        return false, Error.none;
    }
    for scheme in self.schemes[..self.scheme_count] {
        if self.types.node(scheme.root).tag == blot_check_types::Tag.forall { continue; }
        let variables, error = span(self.types, scheme.variables); if error != Error.none { return false, error; }
        for variable in variables { let charged = step(self, 0); if charged != Error.none { return false, charged; } if variable == id { return true, Error.none; } }
    }
    return false, Error.none;
}
fn ownsRow(self: Context&, id: u32) -> bool, Error {
    if self.source_instances && self.instance_rows.contains(id) { return true, Error.none; }
    if self.large_plain_graph && self.source_instances {
        let charged = step(self, 0); if charged != Error.none { return false, charged; }
        for scheme, index in self.schemes[..self.scheme_count] {
            let ids, error = span(self.types, scheme.row_variables); if error != Error.none { return false, error; }
            let found, error = schemeListContains(self, ids, id, self.scheme_rows_sorted[index]); if error != Error.none || found { return found, error; }
        }
        return false, Error.none;
    }
    for scheme in self.schemes[..self.scheme_count] {
        let variables, error = span(self.types, scheme.row_variables); if error != Error.none { return false, error; }
        for variable in variables { let charged = step(self, 0); if charged != Error.none { return false, charged; } if variable == id { return true, Error.none; } }
    }
    return false, Error.none;
}
recursive fn sourceInstance(self: Context&, root: Id, depth: i64) -> Error {
    if !self.source_instances { return Error.invalid_artifact; } let charged = step(self, depth); if charged != Error.none { return charged; } let node = self.types.node(root);
    match node.tag {
        variable => { return self.instance_variables.set(root); }, array, list, cursor, resolver, usage => { return sourceInstance(self, node.a, depth + 1); },
        function => { let parameter = sourceInstance(self, node.a, depth + 1); if parameter != Error.none { return parameter; } return sourceInstance(self, node.b, depth + 1); },
        product => { let children, error = span(self.types, List { node.a, node.b }); if error != Error.none { return error; } for child in children { let error = sourceInstance(self, child, depth + 1); if error != Error.none { return error; } } },
        record => { for index in node.b { let error = sourceInstance(self, self.types.recordField(node, index).ty, depth + 1); if error != Error.none { return error; } } },
        nominal => { for child in self.types.nominalArguments(node) { let error = sourceInstance(self, child, depth + 1); if error != Error.none { return error; } } }, _ => {},
    }
    return Error.none;
}
fn schemeGoals(self: Context&, scheme: Scheme) -> const blot_check_core::Obligation[:], Error {
    if scheme.obligations.start > self.obligations.len || scheme.obligations.len > self.obligations.len - scheme.obligations.start { return self.obligations[..0], Error.invalid_artifact; }
    return self.obligations[scheme.obligations.start..scheme.obligations.start + scheme.obligations.len], Error.none;
}
fn enter(self: Context&, owner: Id) -> Error {
    if self.formal_count >= self.formals.len || owner >= self.types.nodes.len { return Error.invalid_artifact; } let node = self.types.node(owner);
    if node.tag != blot_check_types::Tag.forall && node.tag != blot_check_types::Tag.existential { return Error.invalid_artifact; }
    self.formals[self.formal_count] = owner; self.introductions[self.formal_count] = 0; self.formal_count += 1; self.formal = blot_support::Option<Id> { true, owner }; return Error.none;
}
fn leave(self: Context&) { self.formal_count -= 1; self.formal.present = false; if self.formal_count != 0 { self.formal = blot_support::Option<Id> { true, self.formals[self.formal_count - 1] }; } }
fn ownsFormal(self: const Context&, leaf: Id) -> bool { if leaf >= self.owners.len { return false; } for owner in self.formals[..self.formal_count] { if self.owners[leaf] == owner { return true; } } return false; }
fn representationBinder(self: const Context&, root: Id) -> Error {
    if !self.representation_floor.present { return Error.none; } let node = self.types.node(root);
    if node.tag != blot_check_types::Tag.bound || node.c != 0 || root >= self.owners.len { return Error.invalid_artifact; }
    for owner in self.formals[self.representation_floor.value..self.formal_count] { if self.owners[root] == owner { return Error.none; } } return Error.invalid_artifact;
}
fn region(self: Context&, id: Id, depth: i64) -> Error {
    let charged = step(self, depth); if charged != Error.none { return charged; } if id >= self.types.nodes.len { return Error.invalid_artifact; }
    let leaf = self.types.node(id); if leaf.tag != blot_check_types::Tag.bound || leaf.b != 2 { return Error.invalid_artifact; }
    let representation = representationBinder(self, id); if representation != Error.none { return representation; }
    if leaf.c == 0 && !ownsFormal(self, id) { return Error.invalid_artifact; } return Error.none;
}
fn visit(self: Context&, root: Id) -> Error { return walk(self, root, 0); }
fn representation(self: Context&, root: Id) -> Error { let prior = self.representation_floor; self.representation_floor = blot_support::Option<i64> { true, self.formal_count }; let error = walk(self, root, 0); self.representation_floor = prior; return error; }
fn isForeign(self: const Context&, id: blot_check_effects::Id) -> bool {
    if foreign(self.types, id) { return true; } if id >= self.types.effects.rows.len || !self.closed_rows.contains(id) { return false; }
    let row = self.types.row(id); if row.labels.len == 0 { return false; } match row.tail { variable => {}, _ => { return false; }, }
    for label in self.types.rowLabels(id) { if label != blot_check_types::foreign_operation { return false; } } return true;
}
fn isPure(self: const Context&, row: blot_check_effects::Id) -> bool { return pure(self.types, row) || self.pure_rows.contains(row); }
fn genericRow(self: Context&, id: blot_check_effects::Id, depth: i64) -> bool, Error {
    if id >= self.types.effects.rows.len { return false, Error.none; } let row = self.types.row(id);
    match row.tail { variable v => { let charged = step(self, depth); if charged != Error.none { return false, charged; } return ownsRow(self, v.value); }, _ => { return false, Error.none; }, }
}
recursive fn validateRow(self: Context&, id: blot_check_effects::Id, depth: i64) -> Error {
    if id == 0 && self.types.effects.rows.len == 0 { return Error.none; } let charged = step(self, depth); if charged != Error.none { return charged; }
    if id >= self.types.effects.rows.len { return Error.invalid_artifact; } let value = self.types.row(id);
    match value.tail {
        formal v => {
            if v.value >= self.types.nodes.len { return Error.invalid_artifact; } let leaf = self.types.node(v.value);
            if leaf.tag == blot_check_types::Tag.rigid { let solver .= self.solver; if !solver || !solver.ownsRigid(leaf) || leaf.c != 1 { return Error.invalid_artifact; } }
            else { if !ownsFormal(self, v.value) || leaf.tag != blot_check_types::Tag.bound || leaf.b != 1 || leaf.c != 0 { return Error.invalid_artifact; } let represented = representationBinder(self, v.value); if represented != Error.none { return represented; } }
        },
        _ => {
            var generic_row = false; match value.tail { variable v => { let owned, error = ownsRow(self, v.value); if error != Error.none { return error; } generic_row = owned; }, _ => {}, }
            if value.tail != blot_check_effects::Tail.closed && !generic_row && !isPure(self, id) && !isForeign(self, id) && !self.closed_rows.contains(id) { return Error.invalid_artifact; }
        },
    }
    for label in self.types.rowLabels(id) {
        let charged = step(self, depth); if charged != Error.none { return charged; } if label == 0 || label >= self.types.operations.len { return Error.invalid_artifact; }
        let operation = self.types.operation(label); let arguments, error = span(self.types, operation.arguments); if error != Error.none { return error; }
        for argument in arguments { let error = walk(self, argument, depth + 1); if error != Error.none { return error; } }
        if operation.instance.unit == 0 && operation.instance.decl != 0 { let error = walk(self, operation.instance.decl, depth + 1); if error != Error.none { return error; } }
    }
    return Error.none;
}
recursive fn goalFootprint(self: Context&, root: Id, owner: Id, opened: List, sealed: const Bits4096&, depth: i64) -> bool, Error {
    let charged = step(self, depth); if charged != Error.none { return false, charged; } let node = self.types.node(root);
    if node.tag == blot_check_types::Tag.bound {
        let quantifier = self.types.node(owner); let formals, error = span(self.types, List { quantifier.b, quantifier.c }); if error != Error.none { return false, error; }
        if formals.len != opened.len { return false, Error.invalid_artifact; } let witnesses = self.types.list(opened);
        for formal, i in formals { if formal == root { return !sealed.isSet(witnesses[i]), Error.none; } } return false, Error.none;
    }
    match node.tag {
        forall, existential => {
            for goal in self.types.quantifierGoals(root) { for endpoint in [goal.ty, goal.other, goal.result, goal.signature] { if endpoint != 0 { let found, error = goalFootprint(self, endpoint, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } } }
            return goalFootprint(self, node.a, owner, opened, sealed, depth + 1);
        },
        function => {
            for child in [node.a, node.b] { let found, error = goalFootprint(self, child, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } }
            return rowFootprint(self, node.c, owner, opened, sealed, depth + 1);
        },
        usage => { if node.c != 0 { let found, error = goalFootprint(self, node.c, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } return goalFootprint(self, node.a, owner, opened, sealed, depth + 1); },
        provider => { let found, error = goalFootprint(self, node.a, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } return rowFootprint(self, node.c, owner, opened, sealed, depth + 1); },
        array, list, cursor, resolver => { return goalFootprint(self, node.a, owner, opened, sealed, depth + 1); },
        state_provider => { for child in [node.a, node.b, node.c] { let found, error = goalFootprint(self, child, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } },
        scoped => { let found, error = goalFootprint(self, node.a, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } if node.b == 0 && node.c != 0 { return goalFootprint(self, node.c, owner, opened, sealed, depth + 1); } },
        product => { for child in self.types.list(List { node.a, node.b }) { let found, error = goalFootprint(self, child, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } },
        record => { for index in node.b { let found, error = goalFootprint(self, self.types.recordField(node, index).ty, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } },
        projection, nominal, instance_selection => { for child in self.types.nominalArguments(node) { let found, error = goalFootprint(self, child, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } } }, _ => {},
    }
    return false, Error.none;
}
recursive fn rowFootprint(self: Context&, row: blot_check_effects::Id, owner: Id, opened: List, sealed: const Bits4096&, depth: i64) -> bool, Error {
    let charged = step(self, depth); if charged != Error.none { return false, charged; } if row == 0 && self.types.effects.rows.len == 0 { return false, Error.none; }
    let value = self.types.row(row);
    match value.tail { formal v => { let found, error = goalFootprint(self, v.value, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } }, _ => {}, }
    for label in self.types.rowLabels(row) {
        let charged = step(self, depth); if charged != Error.none { return false, charged; } let operation = self.types.operation(label);
        for argument in self.types.list(operation.arguments) { let found, error = goalFootprint(self, argument, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } }
        if operation.instance.unit == 0 && operation.instance.decl != 0 { let found, error = goalFootprint(self, operation.instance.decl, owner, opened, sealed, depth + 1); if error != Error.none || found { return found, error; } }
    }
    return false, Error.none;
}
fn projectionGoals(self: Context&, root: Id, goals, formals: List, opened: blot_support::Option<List>, depth: i64) -> bool, Error {
    let projection_ = self.types.node(root); let arguments = self.types.nominalArguments(projection_);
    for goal in goals {
        let charged = step(self, depth); if charged != Error.none { return false, charged; }
        if goal.kind != blot_check_types::ObligationKind.contract || goal.identity.unit != projection_.a || goal.identity.decl != projection_.b { continue; }
        let tuple = self.types.node(goal.ty); if tuple.tag != blot_check_types::Tag.product || tuple.b != arguments.len { continue; }
        var proof = Principal { left: self.types, right: self.types, remaining: self.remaining, views: self };
        if opened.present { proof.instance = formals; for witness, index in self.types.list(opened.value) { proof.witnesses[index] = witness; } }
        var matches = true; let required = self.types.list(List { tuple.a, tuple.b });
        for expected, index in required { let error = matchPrincipal(proof, expected, arguments[index], depth + 1); if error != Error.none { if self.remaining == 0 { return false, error; } matches = false; break; } }
        if matches { return true, Error.none; }
    }
    return false, Error.none;
}
fn projectionGoal(self: Context&, root: Id, owner: Id, opened: blot_support::Option<List>, depth: i64) -> bool, Error {
    let quantifier = self.types.node(owner); return projectionGoals(self, root, self.types.quantifierGoals(owner), List { quantifier.b, quantifier.c }, opened, depth);
}
fn projection(self: Context&, root: Id, depth: i64) -> Error {
    let member, error = projectionMember(self.types, self.types.node(root)); if error != Error.none { return error; }
    for argument in self.types.nominalArguments(self.types.node(root)) { let error = walk(self, argument, depth + 1); if error != Error.none { return error; } }
    var scheme = self.scheme_count;
    while scheme != 0 {
        scheme -= 1; let owner = self.schemes[scheme]; if owner.obligations.len == 0 { continue; }
        if self.source_obligations.len != 0 {
            if owner.obligations.start > self.source_obligations.len || owner.obligations.len > self.source_obligations.len - owner.obligations.start { return Error.invalid_artifact; }
            let found, error = projectionGoals(self, root, self.source_obligations[owner.obligations.start..owner.obligations.start + owner.obligations.len], List {}, blot_support::Option<List> { false, List {} }, depth + 1);
            if error != Error.none { return error; } if found { return Error.none; }
        } else {
            let goals, error = schemeGoals(self, owner); if error != Error.none { return error; }
            let found, error = projectionGoals(self, root, goals, List {}, blot_support::Option<List> { false, List {} }, depth + 1); if error != Error.none { return error; } if found { return Error.none; }
        }
    }
    var scope = self.formal_count;
    while scope != 0 { scope -= 1; let found, error = projectionGoal(self, root, self.formals[scope], blot_support::Option<List> { false, List {} }, depth + 1); if error != Error.none { return error; } if found { return Error.none; } }
    scope = self.opening_count;
    while scope != 0 { scope -= 1; let opening = self.openings[scope]; let found, error = projectionGoal(self, root, opening.quantifier, blot_support::Option<List> { true, opening.binders }, depth + 1); if error != Error.none { return error; } if found { return Error.none; } }
    return Error.invalid_artifact;
}
recursive fn walk(self: Context&, root: Id, depth: i64) -> Error {
    let charged = step(self, depth); if charged != Error.none { return charged; } if root >= self.types.nodes.len { return Error.invalid_artifact; }
    let node = self.types.node(root);
    match node.tag {
        unit, boolean, unsigned32, floating32, never => {},
        type_constructor => { if self.witness || node.c != 0 { return Error.invalid_artifact; } },
        erased_proof => { if self.witness { return Error.invalid_artifact; } },
        rigid => { let solver .= self.solver; if !solver || !solver.ownsRigid(node) { return Error.invalid_artifact; } },
        variable => { let owned, error = ownsVariable(self, root); if error != Error.none { return error; } if !owned { return Error.invalid_artifact; } },
        bound => {
            let represented = representationBinder(self, root); if represented != Error.none { return represented; } if node.b != 0 { return Error.invalid_artifact; }
            if node.c == 0 { if !ownsFormal(self, root) { return Error.invalid_artifact; } return Error.none; }
            for opening in self.openings[..self.opening_count] { if opening.binding != node.c { continue; } let binders, error = span(self.types, opening.binders); if error != Error.none { return error; } if node.a >= binders.len || binders[node.a] != root { return Error.invalid_artifact; } return Error.none; }
            return Error.invalid_artifact;
        },
        forall, existential => {
            if self.witness { return Error.invalid_artifact; } let entered = enter(self, root); if entered != Error.none { return entered; }
            let error = walkQuantifier(self, root, node, depth); leave(self); return error;
        },
        projection => { return projection(self, root, depth + 1); },
        function => { let row = validateRow(self, node.c, depth + 1); if row != Error.none { return row; } let parameter = walk(self, node.a, depth + 1); if parameter != Error.none { return parameter; } return walk(self, node.b, depth + 1); },
        usage => {
            if self.witness { return Error.invalid_artifact; }
            let loan = node.b == blot_parse_ast::usagekind_borrow || node.b == blot_parse_ast::usagekind_borrow_mut;
            let cleanup = node.b == blot_parse_ast::usagekind_cleanup;
            if cleanup && self.formal.present { return Error.invalid_artifact; }
            if loan { let region = region(self, node.c, depth + 1); if region != Error.none { return region; } }
            if loan != (node.c != 0) { return Error.invalid_artifact; }
            let concurrent = node.b == blot_parse_ast::usagekind_concurrent;
            if concurrent && !blot_check_task_types::concurrentHost(self.types, node.a) { return Error.invalid_artifact; }
            if !loan && !cleanup && !concurrent && node.b != blot_parse_ast::usagekind_unique && node.b != blot_parse_ast::usagekind_shared && node.b != blot_parse_ast::usagekind_once && node.b != blot_parse_ast::usagekind_many { return Error.invalid_artifact; }
            return walk(self, node.a, depth + 1);
        },
        scoped => {
            if self.witness { return Error.invalid_artifact; } let descriptor = walk(self, node.a, depth + 1); if descriptor != Error.none { return descriptor; }
            if node.b == 0 { let identity = self.types.node(node.c); if identity.tag == blot_check_types::Tag.bound && identity.b == 2 { return region(self, node.c, depth + 1); } return walk(self, node.c, depth + 1); }
        },
        instance_version => { if self.witness { return Error.invalid_artifact; } },
        instance_selection => {
            if self.witness { return Error.invalid_artifact; } let choices = self.types.nominalArguments(node); if choices.len != 2 && choices.len != 3 { return Error.invalid_artifact; }
            for choice in choices[..2] { if self.types.node(choice).tag != blot_check_types::Tag.scoped { return Error.invalid_artifact; } let error = walk(self, choice, depth + 1); if error != Error.none { return error; } }
            if choices.len == 3 { if self.types.node(choices[2]).tag != blot_check_types::Tag.instance_version { return Error.invalid_artifact; } return walk(self, choices[2], depth + 1); }
        },
        array, list, cursor, resolver => { return walk(self, node.a, depth + 1); },
        provider => { if self.witness { return Error.invalid_artifact; } let row = validateRow(self, node.c, depth + 1); if row != Error.none { return row; } return walk(self, node.a, depth + 1); },
        state_provider => { if self.witness { return Error.invalid_artifact; } for child in [node.a, node.b, node.c] { let error = walk(self, child, depth + 1); if error != Error.none { return error; } } },
        product => { let children, error = span(self.types, List { node.a, node.b }); if error != Error.none { return error; } for child in children { let error = walk(self, child, depth + 1); if error != Error.none { return error; } } },
        record => { if node.b > 0x7fffffff { return Error.invalid_artifact; } let fields, error = span(self.types, List { node.a, node.b * 2 }); if error != Error.none { return error; } for index in node.b { let error = walk(self, self.types.recordField(node, index).ty, depth + 1); if error != Error.none { return error; } } },
        nominal => {
            if blot_check_typed_staging::isIdentity(node.a, node.b) && (self.formal.present || self.witness) { return Error.invalid_artifact; }
            let code_ = blot_check_typed_staging::codeInfo(self.types, root);
            if code_.present { let row = validateRow(self, code_.value.effects, depth + 1); if row != Error.none { return row; } return walk(self, code_.value.result, depth + 1); }
            if node.c >= self.types.extra.len { return Error.invalid_artifact; } let children, error = span(self.types, List { node.c + 1, self.types.extra[node.c] }); if error != Error.none { return error; }
            for child in children { let error = walk(self, child, depth + 1); if error != Error.none { return error; } }
        },
        _ => { return Error.invalid_artifact; },
    }
    return Error.none;
}
recursive fn walkQuantifier(self: Context&, root: Id, node: blot_check_types::Node, depth: i64) -> Error {
    if node.tag == blot_check_types::Tag.forall && self.types.node(node.a).tag != blot_check_types::Tag.function { return Error.invalid_artifact; }
    for goal in self.types.quantifierGoals(root) { for endpoint in [goal.ty, goal.other, goal.result, goal.signature] { if endpoint != 0 { let error = walk(self, endpoint, depth + 1); if error != Error.none { return error; } } } }
    return walk(self, node.a, depth + 1);
}
fn open(self: Context&, package: Id, binding: blot_check_core::BindingId, binders: List, payload: Id) -> Error {
    let visited = visit(self, package); if visited != Error.none { return visited; } let quantifier = self.types.node(package);
    if quantifier.tag != blot_check_types::Tag.existential || quantifier.c != binders.len || binding == 0 || self.opening_count >= self.openings.len { return Error.invalid_artifact; }
    for opening in self.openings[..self.opening_count] { if opening.binding == binding { return Error.invalid_artifact; } }
    let witnesses, error = span(self.types, binders); if error != Error.none { return error; }
    for binder, ordinal in witnesses { if binder >= self.types.nodes.len { return Error.invalid_artifact; } let leaf = self.types.node(binder);
        if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b != 0 || leaf.c != binding { return Error.invalid_artifact; } }
    self.openings[self.opening_count] = Opening { binding, binders, package }; self.opening_count += 1;
    let visited = visit(self, payload); if visited != Error.none { self.opening_count -= 1; return visited; }
    let proof = Substitution { self.types, List { quantifier.b, quantifier.c }, witnesses, self.remaining, views: self };
    let error = validate(proof, quantifier.a, payload); if error != Error.none { self.opening_count -= 1; } return error;
}
fn pack(self: Context&, package: Id, payload: Id, witnesses: const Id[:]) -> Error {
    let visited = visit(self, package); if visited != Error.none { return visited; } let quantifier = self.types.node(package);
    if quantifier.tag != blot_check_types::Tag.existential { return Error.invalid_artifact; }
    let visited = visit(self, payload); if visited != Error.none { return visited; }
    self.witness = true; let error = packWitnesses(self, quantifier, payload, witnesses); self.witness = false; return error;
}
fn packWitnesses(self: Context&, quantifier: blot_check_types::Node, payload: Id, witnesses: const Id[:]) -> Error {
    for witness in witnesses { let error = visit(self, witness); if error != Error.none { return error; } }
    let proof = Substitution { self.types, List { quantifier.b, quantifier.c }, witnesses, self.remaining, views: self, projection_resolver: self.projection_resolver };
    return validate(proof, quantifier.a, payload);
}
fn close(self: Context&) { self.opening_count -= 1; }
struct Substitution {
    types: const blot_check_core::Types&,
    formal: List,
    witnesses: const Id[:],
    remaining: i64&,
    views: Context? = null,
    projection_resolver: ProjectionResolver? = null,
}
fn rowPure(self: const Substitution&, row: blot_check_effects::Id) -> bool {
    { let optional_binding_30 .= self.views; if optional_binding_30 { let views .= optional_binding_30; return views.isPure(row);  } } return pure(self.types, row);
}
fn step(self: const Substitution&, depth: i64) -> Error {
    if depth >= 128 || self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none;
}
fn validate(self: const Substitution&, expected: Id, actual: Id) -> Error {
    if self.formal.len != self.witnesses.len || self.formal.len == 0 || self.formal.len > 128 { return Error.invalid_artifact; }
    let binders, error = span(self.types, self.formal); if error != Error.none { return error; }
    for binder, ordinal in binders {
        if binder >= self.types.nodes.len { return Error.invalid_artifact; } let leaf = self.types.node(binder);
        if leaf.tag != blot_check_types::Tag.bound || leaf.a != ordinal || leaf.b != 0 || leaf.c != 0 { return Error.invalid_artifact; }
    }
    for witness in self.witnesses { let has_usage, error = blot_check_usage_check::contains(self.types, witness); if error != Error.none || has_usage { return Error.invalid_artifact; } }
    return matchSubstitution(self, expected, actual, true, 0);
}
recursive fn matchSubstitution(self: const Substitution&, expected: Id, actual: Id, replace: bool, depth: i64) -> Error {
    let error = step(self, depth); if error != Error.none { return error; }
    if expected >= self.types.nodes.len || actual >= self.types.nodes.len { return Error.invalid_artifact; }
    let left = self.types.node(expected); let right = self.types.node(actual);
    if replace && left.tag == blot_check_types::Tag.bound {
        let binders, error = span(self.types, self.formal); if error != Error.none { return error; }
        for binder, ordinal in binders { if binder == expected { return matchSubstitution(self, self.witnesses[ordinal], actual, false, depth + 1); } }
    }
    if left.tag == blot_check_types::Tag.projection && right.tag != blot_check_types::Tag.projection && replace {
        { let optional_binding_29 .= self.projection_resolver; if optional_binding_29 { let resolver .= optional_binding_29; return resolver.validate(self, expected, actual);  } } return Error.invalid_artifact;
    }
    if left.tag != right.tag { return Error.invalid_artifact; }
    match left.tag {
        blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never => { return Error.none; },
        blot_check_types::Tag.bound => {
            if left.b != 0 || expected != actual { return Error.invalid_artifact; }
            if left.c == 0 { { let optional_binding_28 .= self.views; if optional_binding_28 { let views .= optional_binding_28; if views.types.owner_id != self.types.owner_id || !views.ownsFormal(expected) { return Error.invalid_artifact; }  } else { return Error.invalid_artifact; } } }
        },
        blot_check_types::Tag.forall, blot_check_types::Tag.existential => {
            var proof = Principal { left: self.types, right: self.types, remaining: self.remaining, views: self.views, instance: self.formal };
            for witness, index in self.witnesses { proof.witnesses[index] = witness; } return validate(proof, expected, actual);
        },
        blot_check_types::Tag.function => {
            var proof = Principal { left: self.types, right: self.types, remaining: self.remaining, views: self.views };
            if replace { proof.instance = self.formal; for witness, index in self.witnesses { proof.witnesses[index] = witness; } }
            let error = matchRow(proof, left.c, right.c, depth + 1); if error != Error.none { return error; }
            let error = matchSubstitution(self, left.a, right.a, replace, depth + 1); if error != Error.none { return error; }
            return matchSubstitution(self, left.b, right.b, replace, depth + 1);
        },
        blot_check_types::Tag.usage => {
            if left.b != right.b || left.c != 0 || right.c != 0 { return Error.invalid_artifact; }
            if left.b != blot_check_types::usageCode(blot_check_types::usagekind_unique) && left.b != blot_check_types::usageCode(blot_check_types::usagekind_shared) && left.b != blot_check_types::usageCode(blot_check_types::usagekind_once) && left.b != blot_check_types::usageCode(blot_check_types::usagekind_many) { return Error.invalid_artifact; }
            return matchSubstitution(self, left.a, right.a, replace, depth + 1);
        },
        blot_check_types::Tag.array, blot_check_types::Tag.list, blot_check_types::Tag.cursor => { return matchSubstitution(self, left.a, right.a, replace, depth + 1); },
        blot_check_types::Tag.product => {
            if left.b != right.b { return Error.invalid_artifact; }
            let a, error = span(self.types, List { left.a, left.b }); if error != Error.none { return error; }
            let b, error = span(self.types, List { right.a, right.b }); if error != Error.none { return error; }
            for x, index in a { let error = matchSubstitution(self, x, b[index], replace, depth + 1); if error != Error.none { return error; } }
        },
        blot_check_types::Tag.record => {
            if left.b != right.b || left.b > 0x7fffffff { return Error.invalid_artifact; }
            let a, error = span(self.types, List { left.a, left.b * 2 }); if error != Error.none { return error; }
            let b, error = span(self.types, List { right.a, right.b * 2 }); if error != Error.none { return error; }
            for index in 0..left.b {
                let field = self.types.recordField(left, index); var matched = false;
                for other in 0..right.b { let error = step(self, depth); if error != Error.none { return error; } let candidate = self.types.recordField(right, other); if field.name != candidate.name { continue; }
                    let error = matchSubstitution(self, field.ty, candidate.ty, replace, depth + 1); if error != Error.none { return error; } matched = true; break;
                } if !matched { return Error.invalid_artifact; }
            }
        },
        blot_check_types::Tag.nominal, blot_check_types::Tag.projection => {
            if left.a != right.a || left.b != right.b { return Error.invalid_artifact; }
            if left.tag == blot_check_types::Tag.projection { let a, error = projectionMember(self.types, left); if error != Error.none { return error; } let b, error = projectionMember(self.types, right); if error != Error.none || a != b { return Error.invalid_artifact; } }
            if left.c >= self.types.extra.len || right.c >= self.types.extra.len { return Error.invalid_artifact; }
            let a, error = span(self.types, List { left.c + 1, self.types.extra[left.c] }); if error != Error.none { return error; }
            let b, error = span(self.types, List { right.c + 1, self.types.extra[right.c] }); if error != Error.none || a.len != b.len { return Error.invalid_artifact; }
            for x, index in a { let error = matchSubstitution(self, x, b[index], replace, depth + 1); if error != Error.none { return error; } }
        },
        _ => { return Error.invalid_artifact; },
    } return Error.none;
}
struct FormalPair { left: List, right: List }
struct VersionPair { left: blot_check_types::Node, right: blot_check_types::Node }
struct RowWitness { row: blot_check_effects::Id, excluded: Bits256 = Bits256 {} }
struct CertificatePairs { left: List, right: List, seen_left: Bits4096 = Bits4096 {}, seen_right: Bits4096 = Bits4096 {} }
struct Principal {
    left: const blot_check_core::Types&, right: const blot_check_core::Types&, remaining: i64&,
    formals: FormalPair[128], formal_count: i64 = 0, instance: List = List {}, witnesses: Id[256] = [0; 256],
    row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128], secondary: List = List {}, secondary_witnesses: Id[256] = [0; 256],
    views: Context? = null, pending: blot_check_effects::Id[128], pending_count: i64 = 0, foreign_views: bool = false,
    left_rows: List = List {}, instance_rows: List = List {}, scheme_row_witnesses: blot_support::Option<RowWitness>[128] = [blot_support::none<RowWitness>(); 128],
    row_search_depth: i64 = 0, projection_resolver: PrincipalProjectionResolver? = null, projection_depth: i64 = 0,
    certificate_pairs: CertificatePairs? = null, version_pairs: const VersionPair[:] = [],
}
fn sameTypes(left: const blot_check_core::Types&, right: const blot_check_core::Types&) -> bool { return left.owner_id != 0 && left.owner_id == right.owner_id; }
fn certificateRow(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    { let optional_binding_27 .= self.certificate_pairs; if optional_binding_27 { let pairs .= optional_binding_27;
        let a = self.left.row(left); let b = self.right.row(right); var x: i64 = -1; var y: i64 = -1;
        for variable, ordinal in self.left.list(pairs.left) { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; match a.tail { blot_check_effects::Tail.variable match_payload_21 => { let value = match_payload_21.value;  if value == variable { x = ordinal; } }, _ => {}, } }
        for variable, ordinal in self.right.list(pairs.right) { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; match b.tail { blot_check_effects::Tail.variable match_payload_20 => { let value = match_payload_20.value;  if value == variable { y = ordinal; } }, _ => {}, } }
        if (x < 0) != (y < 0) { return Error.invalid_artifact; } if x >= 0 { if x >= 4096 || y >= 4096 { return Error.invalid_artifact; } pairs.seen_left.set(x); pairs.seen_right.set(y); }
     } } return Error.none;
}
fn certifiedScheme<L,R>(self: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error {
    if expected.closed_rows.len != actual.closed_rows.len || expected.closed_rows.len > 4096 { return Error.invalid_artifact; }
    var pairs = CertificatePairs { expected.closed_rows, actual.closed_rows }; self.certificate_pairs .= pairs;
    let error = schemeGoals(self, expected, actual, left_goals, right_goals); self.certificate_pairs .= null; if error != Error.none { return error; }
    if pairs.seen_left.count() != pairs.seen_right.count() { return Error.invalid_artifact; } return Error.none;
}
fn substituted(self: Principal&, formals: List, replacements: const Id[:], expected: Id, actual: Id) -> Error {
    if formals.len != replacements.len || formals.len > 128 { return Error.invalid_artifact; } self.instance = formals;
    for replacement, index in replacements { self.witnesses[index] = replacement; } let error = validate(self, expected, actual); self.instance = List {}; return error;
}
fn composed(self: Principal&, formals: List, replacements: const Id[:], secondary: List, secondary_replacements: const Id[:], expected: Id, actual: Id) -> Error {
    if secondary.len != secondary_replacements.len || secondary.len > 128 { return Error.invalid_artifact; } self.secondary = secondary;
    for replacement, index in secondary_replacements { self.secondary_witnesses[index] = replacement; }
    let error = substituted(self, formals, replacements, expected, actual); self.secondary = List {}; return error;
}
fn goalEndpoints<G>(self: Principal&, left: G, right: G) -> Error {
    if left.kind != right.kind || left.name != right.name || left.operator != right.operator || left.identity.unit != right.identity.unit || left.identity.decl != right.identity.decl { return Error.invalid_artifact; }
    let xs: Id[4] = [left.ty, left.other, left.result, left.signature]; let ys: Id[4] = [right.ty, right.other, right.result, right.signature];
    for x, index in xs { let y = ys[index]; if x == 0 || y == 0 { if x != y { return Error.invalid_artifact; } } else { let error = validate(self, x, y); if error != Error.none { return error; } } } return Error.none;
}
fn schemeGoals<L,R>(self: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R) -> Error {
    if left_goals.len != right_goals.len || expected.row_variables.len != actual.row_variables.len { return Error.invalid_artifact; }
    let left_owner = self.left.node(expected.root); let right_owner = self.right.node(actual.root); let paired = left_owner.tag == blot_check_types::Tag.forall && right_owner.tag == blot_check_types::Tag.forall;
    if left_owner.tag != right_owner.tag { return Error.invalid_artifact; }
    if paired {
        let error = validate(self, expected.root, actual.root); if error != Error.none { return error; }
        if left_owner.c != right_owner.c || self.formal_count >= self.formals.len { return Error.invalid_artifact; }
        self.formals[self.formal_count] = FormalPair { List { left_owner.b, left_owner.c }, List { right_owner.b, right_owner.c } }; self.formal_count += 1;
    } else { if expected.variables.len != actual.variables.len { return Error.invalid_artifact; } let error = instantiateScheme(self, expected, actual.root); if error != Error.none { return error; } }
    let error = schemeGoalBody(self, expected, actual, left_goals, right_goals, paired); if paired { self.formal_count -= 1; } self.instance = List {}; self.instance_rows = List {}; return error;
}
fn schemeGoalBody<L,R>(self: Principal&, expected: Scheme, actual: Scheme, left_goals: L, right_goals: R, paired: bool) -> Error {
    if expected.variables.len > typeLimit(self, expected.root) || expected.row_variables.len > 128 { return Error.invalid_artifact; }
    self.instance = expected.variables; self.instance_rows = expected.row_variables; if paired { self.instance = List {}; }
    for left, index in left_goals { let error = goalEndpoints(self, left, right_goals[index]); if error != Error.none { return error; } }
    if paired { return Error.none; } var variables = Bits256 {};
    for ordinal in 0..expected.variables.len { let witness = self.witnesses[ordinal]; if witness == 0 { continue; } var found = false;
        for variable, index in self.right.list(actual.variables) { if variable != witness { continue; } if variables.isSet(index) { return Error.invalid_artifact; } variables.set(index); found = true; break; } if !found { return Error.invalid_artifact; }
    }
    var rows = Bits256 {};
    for ordinal in 0..expected.row_variables.len { let witness = self.scheme_row_witnesses[ordinal]; if !witness.present { continue; } let row = self.right.row(witness.value.row);
        if witness.value.excluded.count() != row.labels.len { return Error.invalid_artifact; } var variable: u32 = 0;
        match row.tail { blot_check_effects::Tail.variable match_payload_19 => { let value = match_payload_19.value;  variable = value; }, _ => { return Error.invalid_artifact; }, }
        var found = false; for other, index in self.right.list(actual.row_variables) { if other != variable { continue; } if rows.isSet(index) { return Error.invalid_artifact; } rows.set(index); found = true; break; } if !found { return Error.invalid_artifact; }
    } return Error.none;
}
fn sourceTypes(self: const Principal&) -> bool { { let optional_binding_26 .= self.views; if optional_binding_26 { let views .= optional_binding_26; return views.source_instances && views.large_plain_graph;  } } return false; }
fn typeLimit(self: const Principal&, root: Id) -> i64 { if root >= self.left.nodes.len { return 128; } let tag = self.left.node(root).tag; if tag != blot_check_types::Tag.forall && tag != blot_check_types::Tag.existential && sourceTypes(self) { return ordinary_source_type_limit; } return 128; }
fn publicArguments(self: Principal&, variables: List, rows: List, arguments: const Id[:]) -> Error {
    var maximum: i64 = 128; if sourceTypes(self) { maximum = ordinary_source_type_limit; }
    if arguments.len != variables.len + rows.len || self.instance.len > maximum || self.instance_rows.len > 128 { return Error.invalid_artifact; }
    var proof = Principal { left: self.right, right: self.right, remaining: self.remaining, views: self.views };
    let binders, error = span(self.left, variables); if error != Error.none { return error; } let instances, error = span(self.left, self.instance); if error != Error.none { return error; }
    for formal, index in binders { var ordinal: i64 = -1; for instance, j in instances { if instance == formal { ordinal = j; break; } }
        if ordinal < 0 || ordinal >= self.witnesses.len || self.witnesses[ordinal] == 0 { return Error.invalid_artifact; }
        let error = matchPrincipal(proof, self.witnesses[ordinal], arguments[index], 0); if error != Error.none { return error; }
    }
    let row_binders, error = span(self.left, rows); if error != Error.none { return error; } let row_instances, error = span(self.left, self.instance_rows); if error != Error.none { return error; }
    for formal, index in row_binders { var ordinal: i64 = -1; for instance, j in row_instances { if instance == formal { ordinal = j; break; } }
        let actual = arguments[variables.len + index]; if ordinal < 0 || ordinal >= self.scheme_row_witnesses.len || actual >= self.right.nodes.len { return Error.invalid_artifact; }
        let witness = self.scheme_row_witnesses[ordinal]; if !witness.present { return Error.invalid_artifact; } let carrier = self.right.node(actual);
        if carrier.tag != blot_check_types::Tag.function || carrier.a != blot_check_types::unit || carrier.b != blot_check_types::unit { return Error.invalid_artifact; }
        let error = structuredRow(proof, witness.value.row, carrier.c, witness.value.excluded, Bits256 {}, false, 0); if error != Error.none { return error; }
    } return publishPending(proof);
}
fn rows(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error { return matchRow(self, left, right, 0); }
fn instantiateScheme(self: Principal&, scheme: Scheme, actual: Id) -> Error {
    if scheme.variables.len > typeLimit(self, scheme.root) || scheme.row_variables.len > 128 { return Error.invalid_artifact; }
    self.instance = scheme.variables; self.instance_rows = scheme.row_variables; self.witnesses = [0; 256]; for &witness in self.scheme_row_witnesses { witness.present = false; }
    var endpoint = actual; let quantified_actual = self.right.node(actual).tag == blot_check_types::Tag.forall;
    if quantified_actual { { let optional_binding_25 .= self.views; if optional_binding_25 { let views .= optional_binding_25; if !sameTypes(views.types, self.right) || self.right.node(actual).c > 128 { self.instance = List {}; self.instance_rows = List {}; return Error.invalid_artifact; }
        let error = enter(views, actual); if error != Error.none { self.instance = List {}; self.instance_rows = List {}; return error; } endpoint = self.right.node(actual).a;
     } else { self.instance = List {}; self.instance_rows = List {}; return Error.invalid_artifact; } } }
    let error = validate(self, scheme.root, endpoint); if quantified_actual { { let optional_binding_24 .= self.views; if optional_binding_24 { let views .= optional_binding_24; leave(views);  } } } self.instance = List {}; self.instance_rows = List {}; return error;
}
fn instantiate(self: Principal&, owner: Id, actual: Id) -> Error { if self.left.quantifierGoals(owner).len != 0 { return Error.invalid_artifact; } return instantiateTypes(self, owner, actual); }
fn instantiateTypes(self: Principal&, owner: Id, actual: Id) -> Error {
    if owner >= self.left.nodes.len { return Error.invalid_artifact; } let quantifier = self.left.node(owner);
    if quantifier.tag != blot_check_types::Tag.forall || quantifier.c == 0 || quantifier.c > 128 { return Error.invalid_artifact; }
    self.instance = List { quantifier.b, quantifier.c }; self.witnesses = [0; 256]; for &witness in self.row_witnesses { witness.present = false; }
    let error = validate(self, quantifier.a, actual); self.instance = List {}; return error;
}
fn publishPending(self: Principal&) -> Error { { let optional_binding_23 .= self.views; if optional_binding_23 { let views .= optional_binding_23; for index in 0..self.pending_count { let row = self.pending[index]; let error = views.closed_rows.set(row); if error != Error.none { return error; } if views.types.row(row).labels.len == 0 { let error = views.pure_rows.set(row); if error != Error.none { return error; } } }  } } return Error.none; }
fn validate(self: Principal&, left: Id, right: Id) -> Error { self.pending_count = 0; let error = matchPrincipal(self, left, right, 0); if error != Error.none { return error; } return publishPending(self); }
fn hasVariable(types: const blot_check_core::Types&, variables: List, sought: u32) -> bool { for variable in types.list(variables) { if variable == sought { return true; } } return false; }
fn rowPure(self: const Principal&, types: const blot_check_core::Types&, row: blot_check_effects::Id) -> bool {
    if sameTypes(types, self.left) && row < types.effects.rows.len { let value = types.row(row); if value.labels.len == 0 { match value.tail { blot_check_effects::Tail.variable match_payload_18 => { let value = match_payload_18.value;  if hasVariable(types, self.left_rows, value) { return true; } }, _ => {}, } } }
    { let optional_binding_22 .= self.views; if optional_binding_22 { let views .= optional_binding_22; if sameTypes(views.types, types) { return views.isPure(row); }  } } return pure(types, row);
}
fn rowForeign(self: const Principal&, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if foreign(types, id) { return true; } { let optional_binding_21 .= self.views; if optional_binding_21 { let views .= optional_binding_21; if sameTypes(views.types, types) && views.isForeign(id) { return true; }  } }
    if !sameTypes(types, self.left) || id >= types.effects.rows.len { return false; } let row = types.row(id); if row.labels.len == 0 { return false; }
    match row.tail { blot_check_effects::Tail.variable match_payload_17 => { let value = match_payload_17.value;  if !hasVariable(types, self.left_rows, value) { return false; } }, _ => { return false; }, }
    for label in types.rowLabels(id) { if label != blot_check_types::foreign_operation { return false; } } return true;
}
fn operation(self: Principal&, left: blot_check_effects::Label, right: blot_check_effects::Label, depth: i64) -> Error {
    if self.remaining == 0 || depth >= 128 { return Error.invalid_artifact; } self.remaining -= 1;
    if left == 0 || right == 0 || left >= self.left.operations.len || right >= self.right.operations.len { return Error.invalid_artifact; }
    let a = self.left.operation(left); let b = self.right.operation(right);
    if a.identity != b.identity || a.instance.unit != b.instance.unit || a.arguments.len != b.arguments.len { return Error.invalid_artifact; }
    if a.instance.unit == 0 && a.instance.decl != 0 && b.instance.decl != 0 { let error = matchPrincipal(self, a.instance.decl, b.instance.decl, depth + 1); if error != Error.none { return error; } } else if a.instance.decl != b.instance.decl { return Error.invalid_artifact; }
    let xs, error = span(self.left, a.arguments); if error != Error.none { return error; } let ys, error = span(self.right, b.arguments); if error != Error.none { return error; }
    for x, index in xs { let error = matchPrincipal(self, x, ys[index], depth + 1); if error != Error.none { return error; } } return Error.none;
}
fn closedRow(self: Principal&, types: const blot_check_core::Types&, id: blot_check_effects::Id) -> bool {
    if id >= types.effects.rows.len { return false; } let row = types.row(id); if row.tail == blot_check_effects::Tail.closed { return true; }
    { let optional_binding_20 .= self.views; if optional_binding_20 { let views .= optional_binding_20; if sameTypes(views.types, types) && views.closed_rows.contains(id) { return true; }  } }
    if sameTypes(types, self.left) { match row.tail { blot_check_effects::Tail.variable match_payload_16 => { let value = match_payload_16.value;  return hasVariable(types, self.left_rows, value); }, _ => {}, } } return false;
}
fn structuredRow(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, right_excluded: Bits256, subset: bool, depth: i64) -> Error {
    if depth >= 128 || self.remaining == 0 || left >= self.left.effects.rows.len || right >= self.right.effects.rows.len { return Error.invalid_artifact; } self.remaining -= 1;
    if self.left.rowLabels(left).len > 256 || self.right.rowLabels(right).len > 256 { return Error.invalid_artifact; } return rowLabels(self, left, right, left_excluded, right_excluded, subset, 0, depth);
}
recursive fn rowLabels(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error {
    if self.row_search_depth >= 257 || self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; self.row_search_depth += 1;
    let error = searchRowLabels(self, left, right, left_excluded, used, subset, start, depth); self.row_search_depth -= 1; return error;
}
fn searchRowLabels(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, left_excluded: Bits256, used: Bits256, subset: bool, start: i64, depth: i64) -> Error {
    let xs = self.left.rowLabels(left); let ys = self.right.rowLabels(right); var ordinal = start; while ordinal < xs.len && left_excluded.isSet(ordinal) { ordinal += 1; }
    if ordinal == xs.len { return rowTail(self, left, right, used, subset, depth); }
    for candidate, index in ys {
        if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; if used.isSet(index) { continue; }
        var solver: blot_check_scheme_equations::Solver? = null; { let optional_binding_19 .= self.views; if optional_binding_19 { let views .= optional_binding_19; solver .= views.solver;  } }
        var mark: blot_check_types::Mark; { let optional_binding_18 .= solver; if optional_binding_18 { let owner .= optional_binding_18; mark = owner.store.mark();  } }
        let saved = self.witnesses; let saved_rows = self.row_witnesses; let saved_scheme_rows = self.scheme_row_witnesses; let pending = self.pending_count;
        var error = operation(self, xs[ordinal], candidate, depth + 1);
        if error == Error.none { var next = used; next.set(index); error = rowLabels(self, left, right, left_excluded, next, subset, ordinal + 1, depth); }
        if error == Error.none { return Error.none; }
        { let optional_binding_17 .= solver; if optional_binding_17 { let owner .= optional_binding_17; owner.rollback(mark);  } } self.witnesses = saved; self.row_witnesses = saved_rows; self.scheme_row_witnesses = saved_scheme_rows; self.pending_count = pending;
        if self.remaining == 0 { return Error.invalid_artifact; }
    } return Error.invalid_artifact;
}
fn mergePending(self: Principal&, proof: const Principal&) -> Error { if self.pending_count + proof.pending_count > self.pending.len { return Error.invalid_artifact; } for index in 0..proof.pending_count { self.pending[self.pending_count + index] = proof.pending[index]; } self.pending_count += proof.pending_count; return Error.none; }
fn rowWitness(self: Principal&, prior: blot_support::Option<RowWitness>&, right: blot_check_effects::Id, used: Bits256, depth: i64) -> Error {
    if prior.present { var proof = Principal { left: self.right, right: self.right, remaining: self.remaining, views: self.views }; let error = structuredRow(proof, prior.value.row, right, prior.value.excluded, used, false, depth + 1); if error != Error.none { return error; } return mergePending(self, proof); }
    prior = blot_support::Option<RowWitness> { true, RowWitness { right, used } }; return Error.none;
}
fn rowTail(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, used: Bits256, subset: bool, depth: i64) -> Error {
    let a = self.left.row(left); let b = self.right.row(right); let ys = self.right.rowLabels(right);
    if !subset {
        match a.tail {
            blot_check_effects::Tail.variable match_payload_14 => { let value = match_payload_14.value;  if self.instance_rows.len != 0 { let variables, error = span(self.left, self.instance_rows); if error != Error.none { return error; } for variable, ordinal in variables { if variable == value { return rowWitness(self, self.scheme_row_witnesses[ordinal], right, used, depth); } } } },
            blot_check_effects::Tail.formal match_payload_15 => { let value = match_payload_15.value;  if self.instance.len != 0 { let binders, error = span(self.left, self.instance); if error != Error.none { return error; } for binder, ordinal in binders { if binder != value { continue; } let node = self.left.node(binder); if node.tag != blot_check_types::Tag.bound || node.b != 1 || ordinal >= self.row_witnesses.len { return Error.invalid_artifact; } return rowWitness(self, self.row_witnesses[ordinal], right, used, depth); } } },
            _ => {},
        }
    }
    match a.tail {
        blot_check_effects::Tail.formal match_payload_13 => { let value = match_payload_13.value;  match b.tail { blot_check_effects::Tail.formal match_payload_12 => { let other = match_payload_12.value;  let error = matchPrincipal(self, value, other, depth + 1); if error != Error.none { return error; } }, _ => { return Error.invalid_artifact; }, } },
        _ => { if !subset || a.tail != blot_check_effects::Tail.closed {
            if !(closedRow(self, self.left, left) && closedRow(self, self.right, right)) && !blot_structural::equal(a.tail, b.tail) {
                { let optional_binding_16 .= self.views; if optional_binding_16 { let views .= optional_binding_16; if subset || !closedRow(self, self.left, left) || !sameTypes(views.types, self.right) { return Error.invalid_artifact; }
                    match b.tail { blot_check_effects::Tail.variable match_payload_11 => { let value = match_payload_11.value; }, _ => { return Error.invalid_artifact; }, }
                    if self.pending_count >= self.pending.len { return Error.invalid_artifact; } self.pending[self.pending_count] = right; self.pending_count += 1;
                 } else { return Error.invalid_artifact; } }
            }
        } },
    }
    if !subset { for index in 0..ys.len { if !used.isSet(index) { return Error.invalid_artifact; } } } return Error.none;
}
fn subsetRow(self: Principal&, actual: blot_check_effects::Id, declared: blot_check_effects::Id) -> Error { return structuredRow(self, actual, declared, Bits256 {}, Bits256 {}, true, 0); }
fn handledRow(self: Principal&, actual: blot_check_effects::Id, declared: blot_check_effects::Id, excluded: Bits256, subset: bool) -> Error { return structuredRow(self, actual, declared, excluded, Bits256 {}, subset, 0); }
recursive fn matchRow(self: Principal&, left: blot_check_effects::Id, right: blot_check_effects::Id, depth: i64) -> Error {
    { let optional_binding_15 .= self.views; if optional_binding_15 { let views .= optional_binding_15; { let optional_binding_14 .= views.solver; if optional_binding_14 { let solver .= optional_binding_14; if sameTypes(self.left, views.types) && sameTypes(self.right, views.types) {
        let l, error = solver.resolveRow(left); if error != Error.none { return solver.readerError(error); } let r, error = solver.resolveRow(right); if error != Error.none { return solver.readerError(error); }
        if l != left || r != right { return matchRow(self, l, r, depth + 1); }
        var variable = false; match solver.store.effects.node(l).tail { blot_check_effects::Tail.variable match_payload_10 => { let value = match_payload_10.value;  variable = true; }, _ => {}, } match solver.store.effects.node(r).tail { blot_check_effects::Tail.variable match_payload_9 => { let value = match_payload_9.value;  variable = true; }, _ => {}, }
        if variable { let error = solver.rows(l, r); if error != Error.none { return solver.readerError(error); } return Error.none; }
    }  } }  } }
    let error = certificateRow(self, left, right); if error != Error.none { return error; }
    if left < self.left.effects.rows.len { let source = self.left.row(left); match source.tail { blot_check_effects::Tail.variable match_payload_8 => { let value = match_payload_8.value;  if hasVariable(self.left, self.instance_rows, value) { return structuredRow(self, left, right, Bits256 {}, Bits256 {}, false, depth + 1); } }, _ => {}, } }
    if left < self.left.effects.rows.len && right < self.right.effects.rows.len {
        let a = self.left.row(left); let b = self.right.row(right);
        if sameTypes(self.left, self.right) && a.labels.len == 0 && b.labels.len == 0 && blot_structural::equal(a.tail, b.tail) && a.cursor == b.cursor {
            match a.tail { blot_check_effects::Tail.variable match_payload_7 => { let value = match_payload_7.value; 
                if value >= self.left.effects.variable_count { return Error.invalid_artifact; }
                { let optional_binding_13 .= self.views; if optional_binding_13 { let views .= optional_binding_13; if sameTypes(views.types, self.left) && views.isPure(right) {
                    if views.isPure(left) { return Error.none; } if self.pending_count >= self.pending.len { return Error.invalid_artifact; } self.pending[self.pending_count] = left; self.pending_count += 1; return Error.none;
                }  } }
                if !rowPure(self, self.left, left) { return Error.none; }
            }, _ => {}, }
        }
        if self.foreign_views && rowPure(self, self.left, left) {
            match b.tail { blot_check_effects::Tail.formal match_payload_6 => { let value = match_payload_6.value; 
                { let optional_binding_12 .= self.views; if optional_binding_12 { let views .= optional_binding_12; if !sameTypes(views.types, self.right) { return Error.invalid_artifact; } let leaf = self.right.node(value);
                    if leaf.tag == blot_check_types::Tag.rigid { { let optional_binding_11 .= views.solver; if optional_binding_11 { let solver .= optional_binding_11; if !solver.ownsRigid(leaf) || leaf.c != 1 { return Error.invalid_artifact; }  } else { return Error.invalid_artifact; } } }
                    else if !views.ownsFormal(value) { return Error.invalid_artifact; } return views.validateRow(right, depth + 1);
                 } } return Error.invalid_artifact;
            }, _ => {}, }
        }
        var generic_row = false; { let optional_binding_10 .= self.views; if optional_binding_10 { let views .= optional_binding_10; if sameTypes(self.left, self.right) && sameTypes(views.types, self.left) { let result, error = views.genericRow(left, depth + 1); if error != Error.none { return error; } generic_row = result; }  } }
        var a_formal = false; var b_formal = false; var a_variable = false;
        match a.tail { blot_check_effects::Tail.formal match_payload_4 => { let value = match_payload_4.value;  a_formal = true; }, blot_check_effects::Tail.variable match_payload_5 => { let value = match_payload_5.value;  a_variable = true; }, _ => {}, }
        match b.tail { blot_check_effects::Tail.formal match_payload_3 => { let value = match_payload_3.value;  b_formal = true; }, _ => {}, }
        if generic_row || a_formal || b_formal || (a_variable && self.instance_rows.len != 0) || (a.labels.len != 0 && (b.tail != blot_check_effects::Tail.closed || !rowForeign(self, self.left, left))) {
            var subset = self.foreign_views && closedRow(self, self.left, left);
            if subset && rowForeign(self, self.left, left) { match b.tail { blot_check_effects::Tail.variable match_payload_2 => { let value = match_payload_2.value; 
                { let optional_binding_9 .= self.views; if optional_binding_9 { let views .= optional_binding_9; if !sameTypes(views.types, self.right) || value >= self.right.effects.variable_count { return Error.invalid_artifact; }
                    let owned, error = views.ownsRow(value); if error != Error.none { return error; }
                    if !owned { var exact = a.labels.len == b.labels.len; for label in self.right.rowLabels(right) { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; if label != blot_check_types::foreign_operation { exact = false; } } if exact { subset = false; } }
                 } else { return Error.invalid_artifact; } }
            }, _ => {}, } }
            return structuredRow(self, left, right, Bits256 {}, Bits256 {}, subset, depth + 1);
        }
    }
    if rowForeign(self, self.left, left) { if !rowForeign(self, self.right, right) || self.left.row(left).labels.len != self.right.row(right).labels.len { return Error.invalid_artifact; } return Error.none; }
    if !rowPure(self, self.left, left) { return Error.invalid_artifact; }
    if self.foreign_views && rowForeign(self, self.right, right) { return Error.none; } if rowPure(self, self.right, right) { return Error.none; }
    if self.foreign_views && self.right.row(right).labels.len != 0 { { let optional_binding_8 .= self.views; if optional_binding_8 { let views .= optional_binding_8; if !sameTypes(views.types, self.right) { return Error.invalid_artifact; } return views.validateRow(right, depth + 1);  } } return Error.invalid_artifact; }
    { let optional_binding_7 .= self.views; if optional_binding_7 { let views .= optional_binding_7;
        if !sameTypes(views.types, self.right) || right >= self.right.effects.rows.len { return Error.invalid_artifact; } let actual = self.right.row(right);
        if actual.labels.len != 0 { return Error.invalid_artifact; } match actual.tail { blot_check_effects::Tail.variable match_payload_1 => { let value = match_payload_1.value;  if value >= self.right.effects.variable_count { return Error.invalid_artifact; } }, _ => { return Error.invalid_artifact; }, }
        for index in 0..self.pending_count { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; if self.pending[index] == right { return Error.none; } }
        if self.pending_count >= self.pending.len { return Error.invalid_artifact; } self.pending[self.pending_count] = right; self.pending_count += 1; return Error.none;
     } } return Error.invalid_artifact;
}
fn matchIndexedRecord(self: Principal&, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> bool, Error {
    if b.b <= 16 || b.b > 256 { return false, Error.none; } var slots: u16[512] = [0; 512];
    for ordinal in 0..b.b { let field = self.right.recordField(b, ordinal); var slot = ((field.name *% 0x9e3779b1) >> 23) as i64; var inserted = false;
        for attempt in 0..slots.len { if self.remaining == 0 { return false, Error.invalid_artifact; } self.remaining -= 1; let prior = slots[slot];
            if prior == 0 { slots[slot] = (ordinal + 1) as u16; inserted = true; break; }
            if self.right.recordField(b, prior as i64 - 1).name == field.name { inserted = true; break; } slot = (slot + 1) & (slots.len - 1);
        } if !inserted { return false, Error.invalid_artifact; }
    }
    for ordinal in 0..a.b { let field = self.left.recordField(a, ordinal); var slot = ((field.name *% 0x9e3779b1) >> 23) as i64; var selected: Id = 0; var found = false;
        for attempt in 0..slots.len { if self.remaining == 0 { return false, Error.invalid_artifact; } self.remaining -= 1; let entry = slots[slot]; if entry == 0 { return false, Error.invalid_artifact; }
            let candidate = self.right.recordField(b, entry as i64 - 1); if candidate.name == field.name { selected = candidate.ty; found = true; break; } slot = (slot + 1) & (slots.len - 1);
        } if !found { return false, Error.invalid_artifact; } let error = matchPrincipal(self, field.ty, selected, depth + 1); if error != Error.none { return false, error; }
    } return true, Error.none;
}
recursive fn matchPrincipal(self: Principal&, left: Id, right: Id, depth: i64) -> Error {
    if depth >= 128 || self.remaining == 0 { self.remaining = 0; return Error.invalid_artifact; } self.remaining -= 1;
    if left >= self.left.nodes.len || right >= self.right.nodes.len { return Error.invalid_artifact; }
    { let optional_binding_6 .= self.views; if optional_binding_6 { let views .= optional_binding_6; { let optional_binding_5 .= views.solver; if optional_binding_5 { let solver .= optional_binding_5; if sameTypes(self.left, views.types) && sameTypes(self.right, views.types) {
        let l = solver.store.head(left, 0); let r = solver.store.head(right, 0); if l != left || r != right { return matchPrincipal(self, l, r, depth + 1); }
        if solver.store.node(l).tag == blot_check_types::Tag.variable || solver.store.node(r).tag == blot_check_types::Tag.variable { let error = solver.unify(l, r); if error != Error.none { return solver.readerError(error); } return Error.none; }
    }  } }  } }
    let a = self.left.node(left); let b = self.right.node(right);
    if (a.tag == blot_check_types::Tag.variable || (a.tag == blot_check_types::Tag.bound && a.c == 0)) && self.instance.len != 0 {
        let binders, error = span(self.left, self.instance); if error != Error.none { return error; }
        for binder, ordinal in binders { if binder != left { continue; } var maximum: i64 = ordinary_source_type_limit; if a.tag == blot_check_types::Tag.bound || !sourceTypes(self) { maximum = 128; } if ordinal >= maximum { return Error.invalid_artifact; }
            if a.tag == blot_check_types::Tag.bound {
                if a.b == 0 { var work = blot_check_usage_check::Work { remaining: self.remaining }; let contains, error = blot_check_usage_check::containsNominalWork(self.right, [], right, work); self.remaining = work.remaining; if error != Error.none || contains { return Error.invalid_artifact; } }
                else if a.b != 2 || b.tag != blot_check_types::Tag.bound || b.b != 2 { return Error.invalid_artifact; }
            }
            if self.witnesses[ordinal] == 0 { self.witnesses[ordinal] = right; return Error.none; }
            var proof = Principal { left: self.right, right: self.right, remaining: self.remaining, views: self.views, instance: self.secondary, witnesses: self.secondary_witnesses };
            let error = matchPrincipal(proof, self.witnesses[ordinal], right, depth + 1); if error != Error.none { return error; } return mergePending(self, proof);
        }
    }
    if a.tag == blot_check_types::Tag.projection && b.tag != blot_check_types::Tag.projection {
        { let optional_binding_4 .= self.projection_resolver; if optional_binding_4 { let resolver .= optional_binding_4; if self.projection_depth >= 128 { return Error.invalid_artifact; } self.projection_depth += 1; let error = resolver.validate(self, left, right); self.projection_depth -= 1; return error;  } } return Error.invalid_artifact;
    }
    if a.tag != b.tag { return Error.invalid_artifact; }
    match a.tag {
        blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never, blot_check_types::Tag.erased_proof => {},
        blot_check_types::Tag.variable => { if !sameTypes(self.left, self.right) || left != right { return Error.invalid_artifact; } },
        blot_check_types::Tag.rigid => {
            if !sameTypes(self.left, self.right) || a.a != b.a || a.b != b.b || a.c != b.c { return Error.invalid_artifact; }
            { let optional_binding_3 .= self.views; if optional_binding_3 { let views .= optional_binding_3; { let optional_binding_2 .= views.solver; if optional_binding_2 { let solver .= optional_binding_2; if !solver.ownsRigid(a) { return Error.invalid_artifact; }  } else { return Error.invalid_artifact; } }  } else { return Error.invalid_artifact; } }
        },
        blot_check_types::Tag.bound => {
            if a.b != b.b || a.b > 2 { return Error.invalid_artifact; }
            if a.c == 0 && b.c == 0 { for index in 0..self.formal_count { let formal = self.formals[index]; let l, error = span(self.left, formal.left); if error != Error.none { return error; } let r, error = span(self.right, formal.right); if error != Error.none { return error; }
                    if a.a < l.len && b.a < r.len && l[a.a] == left && r[b.a] == right { if a.a != b.a { return Error.invalid_artifact; } return Error.none; }
                }
                { let optional_binding_1 .= self.views; if optional_binding_1 { let views .= optional_binding_1; if !sameTypes(self.left, self.right) || left != right || !views.ownsFormal(left) { return Error.invalid_artifact; }  } else { return Error.invalid_artifact; } }
            } else if !sameTypes(self.left, self.right) || left != right || a.c == 0 || b.c == 0 { return Error.invalid_artifact; }
        },
        blot_check_types::Tag.forall, blot_check_types::Tag.existential => {
            if a.c != b.c || a.c > 128 || self.formal_count >= self.formals.len { return Error.invalid_artifact; }
            let xs, error = span(self.left, List { a.b, a.c }); if error != Error.none { return error; } let ys, error = span(self.right, List { b.b, b.c }); if error != Error.none { return error; }
            for x, index in xs { if self.left.node(x).b != self.right.node(ys[index]).b { return Error.invalid_artifact; } }
            self.formals[self.formal_count] = FormalPair { List { a.b, a.c }, List { b.b, b.c } }; self.formal_count += 1;
            let error = matchQuantified(self, left, right, a, b, depth); self.formal_count -= 1; return error;
        },
        blot_check_types::Tag.function => {
            let error = matchRow(self, a.c, b.c, depth + 1); if error != Error.none { return error; } let outer = self.foreign_views; self.foreign_views = false;
            let error = matchPrincipal(self, a.a, b.a, depth + 1); self.foreign_views = outer; if error != Error.none { return error; } return matchPrincipal(self, a.b, b.b, depth + 1);
        },
        blot_check_types::Tag.usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return Error.invalid_artifact; } if a.c != 0 { let error = matchPrincipal(self, a.c, b.c, depth + 1); if error != Error.none { return error; } } return matchPrincipal(self, a.a, b.a, depth + 1); },
        blot_check_types::Tag.scoped => { if a.b != b.b || (a.b == 0) != (b.b == 0) { return Error.invalid_artifact; } if a.b == 0 { let error = matchPrincipal(self, a.c, b.c, depth + 1); if error != Error.none { return error; } } else if a.c != b.c { return Error.invalid_artifact; } return matchPrincipal(self, a.a, b.a, depth + 1); },
        blot_check_types::Tag.instance_version => {
            if a.a == b.a && a.b == b.b && a.c == b.c { return Error.none; }
            for pair in self.version_pairs { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; if a.a == pair.left.a && a.b == pair.left.b && a.c == pair.left.c && b.a == pair.right.a && b.b == pair.right.b && b.c == pair.right.c { return Error.none; } } return Error.invalid_artifact;
        },
        blot_check_types::Tag.instance_selection => {
            if a.a != b.a || a.b != b.b { return Error.invalid_artifact; } let xs = self.left.nominalArguments(a); let ys = self.right.nominalArguments(b); if xs.len != ys.len { return Error.invalid_artifact; }
            for x, index in xs { let error = matchPrincipal(self, x, ys[index], depth + 1); if error != Error.none { return error; } }
        },
        blot_check_types::Tag.array, blot_check_types::Tag.list, blot_check_types::Tag.cursor, blot_check_types::Tag.resolver => { return matchPrincipal(self, a.a, b.a, depth + 1); },
        blot_check_types::Tag.provider => { if a.b != 0 || b.b != 0 { return Error.invalid_artifact; } let error = matchRow(self, a.c, b.c, depth + 1); if error != Error.none { return error; } return matchPrincipal(self, a.a, b.a, depth + 1); },
        blot_check_types::Tag.type_constructor => { if a.a != b.a || a.b != b.b || a.c != 0 || b.c != 0 { return Error.invalid_artifact; } },
        blot_check_types::Tag.state_provider => { let error = matchPrincipal(self, a.a, b.a, depth + 1); if error != Error.none { return error; } let error = matchPrincipal(self, a.b, b.b, depth + 1); if error != Error.none { return error; } return matchPrincipal(self, a.c, b.c, depth + 1); },
        blot_check_types::Tag.product => { if a.b != b.b { return Error.invalid_artifact; } let xs, error = span(self.left, List { a.a, a.b }); if error != Error.none { return error; } let ys, error = span(self.right, List { b.a, b.b }); if error != Error.none { return error; } for x, index in xs { let error = matchPrincipal(self, x, ys[index], depth + 1); if error != Error.none { return error; } } },
        blot_check_types::Tag.record => {
            if a.b != b.b || a.b > 0x7fffffff { return Error.invalid_artifact; } let xs, error = span(self.left, List { a.a, a.b * 2 }); if error != Error.none { return error; } let ys, error = span(self.right, List { b.a, b.b * 2 }); if error != Error.none { return error; }
            let indexed, error = matchIndexedRecord(self, a, b, depth); if error != Error.none || indexed { return error; }
            for index in 0..a.b { let field = self.left.recordField(a, index); var found = false;
                for other in 0..b.b { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; let candidate = self.right.recordField(b, other); if field.name != candidate.name { continue; } let error = matchPrincipal(self, field.ty, candidate.ty, depth + 1); if error != Error.none { return error; } found = true; break; }
                if !found { return Error.invalid_artifact; }
            }
        },
        blot_check_types::Tag.nominal, blot_check_types::Tag.projection => {
            if a.a != b.a || a.b != b.b || a.c >= self.left.extra.len || b.c >= self.right.extra.len { return Error.invalid_artifact; }
            if a.tag == blot_check_types::Tag.projection { let x, error = projectionMember(self.left, a); if error != Error.none { return error; } let y, error = projectionMember(self.right, b); if error != Error.none || x != y { return Error.invalid_artifact; } }
            let xs, error = span(self.left, List { a.c + 1, self.left.extra[a.c] }); if error != Error.none { return error; } let ys, error = span(self.right, List { b.c + 1, self.right.extra[b.c] }); if error != Error.none || xs.len != ys.len { return Error.invalid_artifact; }
            for x, index in xs { let error = matchPrincipal(self, x, ys[index], depth + 1); if error != Error.none { return error; } }
        },
        _ => { return Error.invalid_artifact; },
    } return Error.none;
}
fn matchQuantified(self: Principal&, left: Id, right: Id, a: blot_check_types::Node, b: blot_check_types::Node, depth: i64) -> Error {
    let xs = self.left.quantifierGoals(left); let ys = self.right.quantifierGoals(right); if xs.len != ys.len { return Error.invalid_artifact; }
    for x, index in xs { let y = ys[index]; if !blot_check_quantifier_goals::sameHead(x, y) { return Error.invalid_artifact; }
        let left_endpoints: Id[4] = [x.ty, x.other, x.result, x.signature]; let right_endpoints: Id[4] = [y.ty, y.other, y.result, y.signature];
        for x, i in left_endpoints { if (x == 0) != (right_endpoints[i] == 0) { return Error.invalid_artifact; } if x != 0 { let error = matchPrincipal(self, x, right_endpoints[i], depth + 1); if error != Error.none { return error; } } }
    } return matchPrincipal(self, a.a, b.a, depth + 1);
}
