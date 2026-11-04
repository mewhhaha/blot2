// Copy open graphs between owners, preserving aliases and freshening binders.
namespace blot_reuse_principal_type_graph;
import std;
import dictionary;
import check.types;
import check.effects;
import check.frozen_types;
import check.core;
import support.error;
import support.option;
type Error = blot_error::Error;
type Id = u32;
type Tag = blot_check_types::Tag;
type Store = blot_check_types::Store;
type Source = blot_check_frozen_types::Source;
type Tail = blot_check_effects::Tail;
fn allUnknown(source: const Store&, root: Id, max_depth: i64) -> bool {
    var cursor = root;
    for depth in max_depth {
        let node = source.node(cursor); if node.tag != Tag.function { return node.tag == Tag.variable; }
        if source.node(node.a).tag != Tag.variable { return false; }
        let row = source.row(node.c);
        if row.labels.len != 0 { return false; }
        match row.tail { Tail.parameter => { return false; }, _ => {} }
        cursor = node.b;
    }
    return false;
}
struct Pair { principal: Id, actual: Id, ambient: bool }
struct Item { pair: Pair, depth: i64 }
struct MatchedRow { variable: blot_support::Option<u32>, cursor: u32 }
fn matchesOpen(source: const Store&, principal: Id, caller: const Store&, actual: Id, max_depth: i64, max_nodes: i64) -> bool, Error {
    return matches(source, principal, caller, actual, max_depth, max_nodes, false);
}
fn sameOpen(source: const Store&, left: Id, right: Id, max_depth: i64, max_nodes: i64) -> bool, Error {
    return matches(source, left, source, right, max_depth, max_nodes, true);
}
fn room(maximum: i64, used: i64, needed: i64) -> bool { used <= maximum && needed <= maximum - used }
fn matches(source: const Store&, principal: Id, caller: const Store&, actual: Id,
    max_depth: i64, max_nodes: i64, exact_binders: bool) -> bool, Error {
    var pending: Item[>..<] = [];
    var seen: dictionary<Pair,bool> = dictionary<Pair,bool> {};
    var variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var rows: dictionary<u32,MatchedRow> = dictionary<u32,MatchedRow> {};
    pending.push(Item { Pair { principal, actual, true }, 0 });
    while pending.len != 0 {
        let item = pending[pending.len - 1]; pending.resize(pending.len - 1);
        if item.depth >= max_depth { return false, Error.none; }
        let original = source.head(item.pair.principal, 0); let live = caller.head(item.pair.actual, 0);
        let key = Pair { original, live, item.pair.ambient };
        if seen.contains(key) { continue; }
        if seen.count >= max_nodes { return false, Error.none; } seen.insert(key, true);
        let from = source.node(original); let to = caller.node(live);
        if from.tag == Tag.variable {
            if to.tag != Tag.variable || exact_binders && original != live { return false, Error.none; }
            if let known = variables.get(from.a) { if known != live { return false, Error.none; } }
            else { variables.insert(from.a, live); }
            continue;
        }
        if from.tag != to.tag { return false, Error.none; }
        let depth = item.depth + 1;
        match from.tag {
            Tag.usage => {
                if from.b != to.b || (from.c == 0) != (to.c == 0) { return false, Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth });
                if from.c != 0 { pending.push(Item { Pair { from.c, to.c, false }, depth }); }
            },
            Tag.scoped => {
                if from.b != to.b { return false, Error.none; }
                if from.b == 0 { pending.push(Item { Pair { from.c, to.c, false }, depth }); }
                else if from.c != to.c { return false, Error.none; }
                pending.push(Item { Pair { from.a, to.a, false }, depth });
            },
            Tag.function => {
                let before = source.row(from.c); let after = caller.row(to.c);
                if before.labels.len > max_nodes { return false, Error.none; }
                if exact_binders && (before.tail != after.tail || before.cursor != after.cursor) { return false, Error.none; }
                if before.labels.len != after.labels.len { return false, Error.none; }
                match before.tail { Tail.parameter => { return false, Error.none; }, _ => {} }
                match after.tail { Tail.parameter => { return false, Error.none; }, _ => {} }
                let left_labels = source.rowLabels(from.c); let right_labels = caller.rowLabels(to.c);
                for left, index in left_labels {
                    let right = right_labels[index]; let old = source.operation(left); let current = caller.operation(right);
                    if old.identity != current.identity { return false, Error.none; }
                    if old.instance.unit == 0 && old.instance.decl != 0 && current.instance.unit == 0 && current.instance.decl != 0 {
                        pending.push(Item { Pair { old.instance.decl, current.instance.decl, false }, depth });
                    } else if old.instance != current.instance { return false, Error.none; }
                    let arguments = source.operationArguments(left); let actuals = caller.operationArguments(right);
                    if arguments.len != actuals.len || !room(max_nodes, pending.len, arguments.len) { return false, Error.none; }
                    for argument, i in arguments { pending.push(Item { Pair { argument, actuals[i], false }, depth }); }
                }
                // Only the covariant ambient return spine may keep an open
                // caller view of a pure source row. Callback inputs stay exact.
                if before.tail == Tail.closed && (before.labels.len != 0 || !item.pair.ambient) && after.tail != Tail.closed {
                    return false, Error.none;
                }
                match before.tail {
                    Tail.variable variable => {
                        var row = MatchedRow { cursor: after.cursor };
                        match after.tail { Tail.variable value => { row.variable = blot_support::some(value.value); }, _ => {} }
                        if let known = rows.get(variable.value) { if known != row { return false, Error.none; } }
                        else { rows.insert(variable.value, row); }
                    },
                    _ => {},
                }
                pending.push(Item { Pair { from.a, to.a, false }, depth });
                pending.push(Item { Pair { from.b, to.b, item.pair.ambient }, depth });
            },
            Tag.array, Tag.list, Tag.cursor => { pending.push(Item { Pair { from.a, to.a, false }, depth }); },
            Tag.product, Tag.nominal, Tag.instance_selection => {
                let nominal = from.tag == Tag.nominal || from.tag == Tag.instance_selection;
                if nominal && (from.a != to.a || from.b != to.b) { return false, Error.none; }
                var left: const Id[:] = []; var right: const Id[:] = [];
                if nominal { left = source.nominalArguments(from); right = caller.nominalArguments(to); }
                else { left = source.list(blot_check_types::List { from.a, from.b }); right = caller.list(blot_check_types::List { to.a, to.b }); }
                if left.len != right.len || !room(max_nodes, pending.len, left.len) { return false, Error.none; }
                for child, index in left { pending.push(Item { Pair { child, right[index], false }, depth }); }
            },
            Tag.record => {
                if from.b != to.b || !room(max_nodes, pending.len, from.b) { return false, Error.none; }
                for index in from.b {
                    let left = source.recordField(from, index); let right = caller.recordField(to, index);
                    if left.name != right.name { return false, Error.none; }
                    pending.push(Item { Pair { left.ty, right.ty, false }, depth });
                }
            },
            Tag.instance_version => { if from.a != to.a || from.b != to.b || from.c != to.c { return false, Error.none; } },
            Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => {},
            _ => { return false, Error.none; },
        }
    }
    return true, Error.none;
}

struct Copier {
    source: Source, destination: Store&, max_depth: i64, max_nodes: i64,
    frozen: bool = false, remaining: i64? = null, projection_observed: i64? = null,
    types: dictionary<Id,Id>&, variables: dictionary<u32,Id>&, rows: dictionary<Id,Id>&,
    row_variables: dictionary<u32,Id>&, labels: dictionary<Id,Id>&,
}
type Copy = Copier;
type NormalizedCopy = Copier;
type FrozenCopy = Copier;
fn deinit(self: Copier&) { self.types.clear(); self.variables.clear(); self.rows.clear(); self.row_variables.clear(); self.labels.clear(); }
fn charge(self: Copier&) -> Error {
    if let remaining = self.remaining {
        if let observed = self.projection_observed {
            let spent = self.destination.projection_steps - observed;
            if spent > remaining { return Error.type_limit; }
            remaining -= spent; observed = self.destination.projection_steps;
        }
        if remaining == 0 { return Error.type_limit; } remaining--;
        if self.projection_observed != null { self.destination.projection_limit = self.destination.projection_steps + remaining; }
    }
    return Error.none;
}
fn ty(self: Copier&, original: Id, depth: i64) -> Id, Error {
    if self.frozen {
        match self.source {
            Source.store store => { assert(store.value.versions.len == 0 && store.value.effects.versions.len == 0); },
            _ => {},
        }
    }
    if original <= 5 { return original, Error.none; }
    if depth >= self.max_depth || self.types.count >= self.max_nodes { return 0, Error.type_limit; }
    if let known = self.types.get(original) { return known, Error.none; }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let root = self.source.head(original, 0);
    if root != original {
        let result, error = self.ty(root, depth + 1); if error != Error.none { return 0, error; }
        self.types.insert(original, result); return result, Error.none;
    }
    let node = self.source.node(root);
    var result: Id = 0; var failure = Error.none;
    match node.tag {
        Tag.bound, Tag.rigid, Tag.erased_proof => { return 0, Error.type_limit; },
        Tag.forall, Tag.existential => {
            var binders: Id[>..<] = [];
            let old = self.source.list(blot_check_types::List { node.b, node.c });
            for binder_source in old {
                let leaf = self.source.node(binder_source); if leaf.tag != Tag.bound { return 0, Error.type_limit; }
                let binder, error = self.destination.boundType(leaf.a, leaf.b); if error != Error.none { return 0, error; }
                binders.push(binder); self.types.insert(binder_source, binder);
            }
            let body, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            var goals: blot_check_types::Obligation[>..<] = [];
            for old_goal in self.source.quantifierGoals(root) {
                var goal = old_goal;
                let ty, ty_error = self.ty(goal.ty, depth + 1); if ty_error != Error.none { return 0, ty_error; } goal.ty = ty;
                let other, other_error = self.ty(goal.other, depth + 1); if other_error != Error.none { return 0, other_error; } goal.other = other;
                let selected, result_error = self.ty(goal.result, depth + 1); if result_error != Error.none { return 0, result_error; } goal.result = selected;
                let signature, sig_error = self.ty(goal.signature, depth + 1); if sig_error != Error.none { return 0, sig_error; } goal.signature = signature;
                goal.source = 0; goals.push(goal);
            }
            let value, error = self.destination.quantifiedWithGoals(node.tag, body, binders, goals); result = value; failure = error;
        },
        Tag.instance_version => { let value, error = self.destination.instanceVersion(blot_check_types::NominalIdentity { node.a, node.b }, node.c); result = value; failure = error; },
        Tag.variable => {
            if let known = self.variables.get(node.a) { result = known; }
            else { let value, error = self.destination.fresh(); if error != Error.none { return 0, error; } self.variables.insert(node.a, value); result = value; }
        },
        Tag.usage => {
            let payload, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            var region: Id = 0;
            if node.c != 0 { let value, error = self.ty(node.c, depth + 1); if error != Error.none { return 0, error; } region = value; }
            let value, error = self.destination.usage(payload, node.b as blot_check_types::UsageKind, region); result = value; failure = error;
        },
        Tag.scoped => {
            let descriptor, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            var identity = blot_check_types::NominalIdentity { node.b, node.c };
            if node.b == 0 { let value, error = self.ty(node.c, depth + 1); if error != Error.none { return 0, error; } identity.decl = value; }
            let value, error = self.destination.scoped(descriptor, identity); result = value; failure = error;
        },
        Tag.function => {
            let parameter, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let output, e2 = self.ty(node.b, depth + 1); if e2 != Error.none { return 0, e2; }
            let row, e3 = self.row(node.c, depth + 1); if e3 != Error.none { return 0, e3; }
            let value, error = self.destination.functionWithEffects(parameter, output, row); result = value; failure = error;
        },
        Tag.array, Tag.list, Tag.cursor => {
            let element, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.sequence(node.tag, element); result = value; failure = error;
        },
        Tag.provider => {
            let operation, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let effects, e2 = self.row(node.c, depth + 1); if e2 != Error.none { return 0, e2; }
            let value, error = self.destination.provider(operation, effects); result = value; failure = error;
        },
        Tag.resolver => {
            let target, error = self.ty(node.a, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.resolver(target); result = value; failure = error;
        },
        Tag.state_provider => {
            let read, e1 = self.ty(node.a, depth + 1); if e1 != Error.none { return 0, e1; }
            let write, e2 = self.ty(node.b, depth + 1); if e2 != Error.none { return 0, e2; }
            let state, e3 = self.ty(node.c, depth + 1); if e3 != Error.none { return 0, e3; }
            let value, error = self.destination.stateProvider(read, write, state); result = value; failure = error;
        },
        Tag.type_constructor => { let value, error = self.destination.typeConstructor(blot_check_types::NominalIdentity { node.a, node.b }); result = value; failure = error; },
        Tag.record => {
            var fields: blot_check_types::Field[>..<] = [];
            for index in node.b {
                let old = self.source.recordField(node, index); let ty, error = self.ty(old.ty, depth + 1); if error != Error.none { return 0, error; }
                fields.push(blot_check_types::Field { old.name, ty });
            }
            let value, error = self.destination.record(fields); result = value; failure = error;
        },
        Tag.product, Tag.nominal, Tag.projection, Tag.instance_selection => {
            var children: const Id[:] = [];
            if node.tag == Tag.product { children = self.source.list(blot_check_types::List { node.a, node.b }); }
            else { children = self.source.nominalArguments(node); }
            var copied: Id[>..<] = [];
            for child in children { let value, error = self.ty(child, depth + 1); if error != Error.none { return 0, error; } copied.push(value); }
            let identity = blot_check_types::NominalIdentity { node.a, node.b };
            if node.tag == Tag.instance_selection { let value, error = self.destination.instanceSelection(identity, copied); result = value; failure = error; }
            else if node.tag == Tag.projection { let value, error = self.destination.projection(identity, self.source.projectionMember(node), copied); result = value; failure = error; }
            else if node.tag == Tag.nominal { let value, error = self.destination.nominal(identity, copied); result = value; failure = error; }
            else { let value, error = self.destination.product(copied); result = value; failure = error; }
        },
        Tag.absent, Tag.unit, Tag.boolean, Tag.unsigned32, Tag.floating32, Tag.never => { assert(false); },
    }
    if failure != Error.none { return 0, failure; } self.types.insert(original, result); return result, Error.none;
}
fn rowVariable(self: Copier&, variable: u32) -> Id, Error {
    if let known = self.row_variables.get(variable) { return known, Error.none; }
    if self.row_variables.count >= self.max_nodes { return 0, Error.type_limit; }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let fresh, error = self.destination.freshEffects(); if error != Error.none { return 0, error; }
    self.row_variables.insert(variable, fresh); return fresh, Error.none;
}
fn row(self: Copier&, original: Id, depth: i64) -> Id, Error {
    if original == 0 { return 0, Error.none; }
    if depth >= self.max_depth || self.rows.count >= self.max_nodes { return 0, Error.type_limit; }
    if let known = self.rows.get(original) { return known, Error.none; }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let source = self.source.row(original); var copied: Id[>..<] = [];
    for operation in self.source.rowLabels(source.labels) {
        let value, error = self.label(operation, depth + 1); if error != Error.none { return 0, error; } copied.push(value);
    }
    var result: Id = 0; var failure = Error.none;
    match source.tail {
        Tail.closed => { let value, error = self.destination.effects.row(copied, Tail.closed); result = value; failure = blot_check_types::effectError(error); },
        Tail.variable variable => {
            let replacement, error = self.rowVariable(variable.value); if error != Error.none { return 0, error; }
            if copied.len == 0 { result = replacement; }
            else {
                let resolved, error = self.destination.resolveEffects(replacement, 0); if error != Error.none { return 0, error; }
                let row = self.destination.row(resolved); copied.append(self.destination.rowLabels(resolved));
                let value, error = self.destination.effects.rowAt(copied, row.tail, row.cursor); result = value; failure = blot_check_types::effectError(error);
            }
        },
        Tail.formal formal => {
            let ty, error = self.ty(formal.value, depth + 1); if error != Error.none { return 0, error; }
            let value, error = self.destination.effects.row(copied, Tail.formal { ty }); result = value; failure = blot_check_types::effectError(error);
        },
        Tail.parameter => { return 0, Error.type_limit; },
    }
    if failure != Error.none { return 0, failure; } self.rows.insert(original, result); return result, Error.none;
}
fn label(self: Copier&, original: Id, depth: i64) -> Id, Error {
    if depth >= self.max_depth || self.labels.count >= self.max_nodes { return 0, Error.type_limit; }
    if let known = self.labels.get(original) { return known, Error.none; }
    let charged = self.charge(); if charged != Error.none { return 0, charged; }
    let operation = self.source.operation(original); var arguments: Id[>..<] = [];
    for old in self.source.list(operation.arguments) {
        let value, error = self.ty(old, depth + 1); if error != Error.none { return 0, error; } arguments.push(value);
    }
    var instance = operation.instance;
    if instance.unit == 0 && instance.decl != 0 {
        let value, error = self.ty(instance.decl, depth + 1); if error != Error.none { return 0, error; } instance.decl = value;
    }
    let result, error = self.destination.internScopedOperation(operation.identity, instance, arguments);
    if error != Error.none { return 0, error; } self.labels.insert(original, result); return result, Error.none;
}
fn withCopy<C,F>(source: Source, destination: Store&, max_depth: i64, max_nodes: i64,
    remaining: i64&, observed: i64&, context: C&) -> Error {
    var types: dictionary<Id,Id> = dictionary<Id,Id> {}; var variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var rows: dictionary<Id,Id> = dictionary<Id,Id> {}; var row_variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var labels: dictionary<Id,Id> = dictionary<Id,Id> {};
    var copier = Copier { source, destination, max_depth, max_nodes, false, remaining, observed, types, variables, rows, row_variables, labels };
    return F(context, copier);
}
fn withFrozenCopy<C,F>(source: Source, destination: Store&, max_depth: i64, max_nodes: i64,
    remaining: i64&, observed: i64&, context: C&) -> Error {
    var types: dictionary<Id,Id> = dictionary<Id,Id> {}; var variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var rows: dictionary<Id,Id> = dictionary<Id,Id> {}; var row_variables: dictionary<u32,Id> = dictionary<u32,Id> {};
    var labels: dictionary<Id,Id> = dictionary<Id,Id> {};
    var copier = Copier { source, destination, max_depth, max_nodes, true, remaining, observed, types, variables, rows, row_variables, labels };
    return F(context, copier);
}
