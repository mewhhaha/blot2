// Read-only invocation relocation preserves captured owner/version identities.
namespace blot_check_generative_relocation;
import check.core;
import check.effects;
import check.rank_equal;
import check.types;
import support.error;
import support.option;
import support.structural_adapters;

import support.structural;
type Error = blot_error::Error;
type Types = blot_check_core::Types;
type Module = blot_check_core::Module;
type Tag = blot_check_types::Tag;
type Tail = blot_check_effects::Tail;
fn list(types: const Types&, span: blot_check_types::List) -> const u32[:], Error { if span.start > types.extra.len || span.len > types.extra.len - span.start { return [], blot_error::Error.invalid_artifact; } return types.list(span), blot_error::Error.none; }
fn arguments(types: const Types&, node: blot_check_types::Node) -> const u32[:], Error { if node.c >= types.extra.len { return [], blot_error::Error.invalid_artifact; } let count = types.extra[node.c]; if count > types.extra.len - node.c - 1 || (node.tag == blot_check_types::Tag.projection && count >= types.extra.len - node.c - 1) { return [], blot_error::Error.invalid_artifact; } return types.nominalArguments(node), blot_error::Error.none; }
fn labels(types: const Types&, row: u32) -> const u32[:], Error { if row >= types.effects.rows.len { return [], blot_error::Error.invalid_artifact; } let span = types.row(row).labels; if span.start > types.effects.labels.len || span.len > types.effects.labels.len - span.start { return [], blot_error::Error.invalid_artifact; } return types.rowLabels(row), blot_error::Error.none; }
fn sameVersion(left: blot_check_types::Node, right: blot_check_types::Node) -> bool { return left.a == right.a && left.b == right.b && left.c == right.c; }
fn sameOwner(left: const Module&, right: const Module&) -> bool { return left .== right; }
fn equal(types: const Types&, left: u32, right: u32) -> bool { let value, err = blot_check_rank_equal::equal(types, left, right, true); return err == blot_error::Error.none && value; }
struct Pair { before: u32, after: u32, opened: bool = false }
struct Instance { variable: u32, owner: blot_check_types::NominalIdentity }
struct RowInstance { variable: u32, labels: blot_check_effects::List, tail: Tail }
struct Relocation {
    source: const Module&, target: const Module&, scheme: blot_check_types::Scheme, endpoint: u32,
    strict_versions: bool = false, closing: bool = false,
    fresh_versions: u32[16], fresh_len: i64 = 0, fresh_pairs: Pair[16], fresh_pair_len: i64 = 0,
    pairs: Pair[4096], len: i64 = 0, remaining: i64 = 65536,
    instances: Instance[32], instance_len: i64 = 0, rows: RowInstance[32], row_len: i64 = 0
}
fn init(source: const Module&, target: const Module&, scheme: blot_check_types::Scheme, actual: u32, output: u32, consumed: i64, endpoint: u32) -> Relocation, Error {
    var result = Relocation { source: source, target: target, scheme: scheme, endpoint: endpoint , ..};
    if scheme.generative.len > 32 || scheme.generative.len % 2 != 0 { return result, blot_error::Error.invalid_artifact; } let words, err = list(source.types, scheme.generative); if err != blot_error::Error.none { return result, err; } var arrow = scheme.root;
    for ignored in 0..consumed { if arrow >= source.types.nodes.len { return result, blot_error::Error.invalid_artifact; } let n = source.types.node(arrow); if n.tag != blot_check_types::Tag.function { return result, blot_error::Error.invalid_artifact; }
        for index in 0..words.len / 2 { if words[index * 2] != arrow { continue; } if words[index * 2 + 1] >= source.types.nodes.len { return result, blot_error::Error.invalid_artifact; } let selected = source.types.node(words[index * 2 + 1]); if selected.tag != blot_check_types::Tag.scoped || selected.b != 0 || selected.c >= source.types.nodes.len { return result, blot_error::Error.invalid_artifact; } let term = source.types.node(selected.c); if term.tag != blot_check_types::Tag.instance_selection { return result, blot_error::Error.invalid_artifact; } let children, err = arguments(source.types, term); if err != blot_error::Error.none { return result, err; }
            if children.len != 3 || result.fresh_len == result.fresh_versions.len || children[2] >= source.types.nodes.len || source.types.node(children[2]).tag != blot_check_types::Tag.instance_version { return result, blot_error::Error.invalid_artifact; } result.fresh_versions[result.fresh_len] = children[2]; result.fresh_len += 1;
        } arrow = n.b;
    }
    let err = result.tyOpened(scheme.root, actual, 0, true); if err != blot_error::Error.none { return result, err; } var kept: i64 = 0;
    for pair in result.pairs[..result.len] { if source.types.node(pair.before).tag == blot_check_types::Tag.variable { result.pairs[kept] = pair; kept += 1; } }
    result.len = kept; result.strict_versions = true; let err = result.tyOpened(arrow, output, 0, true); return result, err;
}
fn applications(self_: Relocation&, id: u32) -> Error {
    if id == 0 || id >= self_.target.nodes.len { return blot_error::Error.invalid_artifact; } var chain: u32[16]; var count: i64 = 0; var callee = id;
    while self_.target.node(callee).tag == blot_check_core::Tag.apply { if count == chain.len { return blot_error::Error.invalid_artifact; } chain[count] = callee; count += 1; callee = self_.target.node(callee).a; if callee == 0 || callee >= self_.target.nodes.len { return blot_error::Error.invalid_artifact; } }
    var arrow = self_.scheme.root; for index in 0..count { let function = self_.source.types.node(arrow); if function.tag != blot_check_types::Tag.function { return blot_error::Error.invalid_artifact; } arrow = function.b; let err = self_.tyOpened(arrow, self_.target.node(chain[count - index - 1]).ty, 0, true); if err != blot_error::Error.none { return err; } } return blot_error::Error.none;
}
fn invoked(module: const Module&, variables: blot_check_types::List, before: u32, after: u32, versions: const u32[:], endpoint: u32) -> Error {
    var relation = Relocation { source: module, target: module, scheme: blot_check_types::Scheme { root: before, variables: variables , ..}, endpoint: endpoint, strict_versions: true , ..};
    if versions.len > relation.fresh_versions.len { return blot_error::Error.invalid_artifact; } for version, index in versions { if version >= module.types.nodes.len || module.types.node(version).tag != blot_check_types::Tag.instance_version { return blot_error::Error.invalid_artifact; } relation.fresh_versions[index] = version; } relation.fresh_len = versions.len; return relation.ty(before, after, 0);
}
fn generalized(module: const Module&, scheme: blot_check_types::Scheme, raw: u32) -> Error {
    var relation = Relocation { source: module, target: module, scheme: scheme, endpoint: 0, strict_versions: true, closing: true , ..}; let closed, err = list(module.types, scheme.closed_rows); if err != blot_error::Error.none { return err; }
    for variable in closed { let safe, err = relation.safeClosing(raw, variable, 0); if err != blot_error::Error.none { return err; } if !safe { return blot_error::Error.invalid_artifact; } } return relation.tyOpened(raw, scheme.root, 0, true);
}
fn hasRow(self_: Relocation&, root: u32, variable: u32, depth: i64) -> bool, Error {
    if depth >= 128 || self_.remaining == 0 || root >= self_.source.types.nodes.len { return false, blot_error::Error.invalid_artifact; } self_.remaining -= 1; let node = self_.source.types.node(root);
    match node.tag {
        function, provider => { if node.c >= self_.source.types.effects.rows.len { return false, blot_error::Error.invalid_artifact; } let row = self_.source.types.row(node.c); match row.tail { variable payload => { if payload.value == variable { return true, blot_error::Error.none; } }, _ => {}, }
            let row_labels, err = labels(self_.source.types, node.c); if err != blot_error::Error.none { return false, err; } for label in row_labels { if label >= self_.source.types.operations.len { return false, blot_error::Error.invalid_artifact; } let operation = self_.source.types.operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { let found, err = self_.hasRow(operation.instance.decl, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } let args, err = list(self_.source.types, operation.arguments); if err != blot_error::Error.none { return false, err; } for argument in args { let found, err = self_.hasRow(argument, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } }
            let found, err = self_.hasRow(node.a, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } if node.tag == blot_check_types::Tag.function { return self_.hasRow(node.b, variable, depth + 1); }
        },
        array, list, cursor, resolver => { return self_.hasRow(node.a, variable, depth + 1); },
        usage => { let found, err = self_.hasRow(node.a, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } if node.c != 0 { return self_.hasRow(node.c, variable, depth + 1); } },
        state_provider => { for child in [node.a, node.b, node.c] { let found, err = self_.hasRow(child, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } },
        scoped => { let found, err = self_.hasRow(node.a, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } if node.b == 0 { return self_.hasRow(node.c, variable, depth + 1); } },
        product => { let children, err = list(self_.source.types, blot_check_types::List { node.a, node.b , ..}); if err != blot_error::Error.none { return false, err; } for child in children { let found, err = self_.hasRow(child, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } },
        record => { if node.a > self_.source.types.extra.len || node.b > (self_.source.types.extra.len - node.a) / 2 { return false, blot_error::Error.invalid_artifact; } for index in 0..node.b { let found, err = self_.hasRow(self_.source.types.recordField(node, index).ty, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } },
        nominal, projection, instance_selection => { let children, err = arguments(self_.source.types, node); if err != blot_error::Error.none { return false, err; } for child in children { let found, err = self_.hasRow(child, variable, depth + 1); if err != blot_error::Error.none || found { return found, err; } } },
        forall, existential, bound, rigid, absent => { return false, blot_error::Error.invalid_artifact; },
        _ => {},
    } return false, blot_error::Error.none;
}
fn safeClosing(self_: Relocation&, root: u32, variable: u32, depth: i64) -> bool, Error {
    if depth >= 128 || self_.remaining == 0 || root >= self_.source.types.nodes.len { return false, blot_error::Error.invalid_artifact; } self_.remaining -= 1; let node = self_.source.types.node(root);
    match node.tag {
        function => { let found, err = self_.hasRow(node.a, variable, depth + 1); if err != blot_error::Error.none { return false, err; } if found { return false, blot_error::Error.none; } if node.c >= self_.source.types.effects.rows.len { return false, blot_error::Error.invalid_artifact; } let tail = self_.source.types.row(node.c).tail;
            match tail { variable payload => { if payload.value == variable { let found, err = self_.hasRow(node.b, variable, depth + 1); if err != blot_error::Error.none { return false, err; } if found { return false, blot_error::Error.none; } } }, _ => {}, } return self_.safeClosing(node.b, variable, depth + 1);
        },
        provider => { let found, err = self_.hasRow(node.a, variable, depth + 1); return !found, err; },
        array, list, cursor, usage => { return self_.safeClosing(node.a, variable, depth + 1); },
        product => { let children, err = list(self_.source.types, blot_check_types::List { node.a, node.b , ..}); if err != blot_error::Error.none { return false, err; } for child in children { let safe, err = self_.safeClosing(child, variable, depth + 1); if err != blot_error::Error.none || !safe { return safe, err; } } },
        record => { if node.a > self_.source.types.extra.len || node.b > (self_.source.types.extra.len - node.a) / 2 { return false, blot_error::Error.invalid_artifact; } for index in 0..node.b { let safe, err = self_.safeClosing(self_.source.types.recordField(node, index).ty, variable, depth + 1); if err != blot_error::Error.none || !safe { return safe, err; } } },
        _ => { let found, err = self_.hasRow(root, variable, depth + 1); return !found, err; },
    } return true, blot_error::Error.none;
}
fn get(self_: const Relocation&, before: u32) -> blot_support::Option<u32> { for pair in self_.pairs[..self_.len] { if pair.before == before { return blot_support::some(pair.after); } } return blot_support::none<u32>(); }
fn ownedVariable(self_: const Relocation&, id: u32) -> bool, Error { let variables, err = list(self_.source.types, self_.scheme.variables); if err != blot_error::Error.none { return false, err; } for variable in variables { if variable == id { return true, blot_error::Error.none; } } return false, blot_error::Error.none; }
fn instance(self_: Relocation&, variable: u32, actual: blot_check_types::NominalIdentity) -> Error {
    let owned, err = self_.ownedVariable(variable); if err != blot_error::Error.none { return err; } if !owned { if !sameOwner(self_.source, self_.target) || actual.unit != 0 || actual.decl != variable { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
    if actual.unit == 0 { if actual.decl >= self_.target.types.nodes.len { return blot_error::Error.invalid_artifact; } let node = self_.target.types.node(actual.decl); if node.tag != blot_check_types::Tag.variable && node.tag != blot_check_types::Tag.instance_selection { return blot_error::Error.invalid_artifact; } } else if actual.decl == 0 { return blot_error::Error.invalid_artifact; }
    let mapped = self_.get(variable); if mapped.present && (actual.unit != 0 || !equal(self_.target.types, mapped.value, actual.decl)) { return blot_error::Error.invalid_artifact; }
    for prior in self_.instances[..self_.instance_len] { if prior.variable == variable { if prior.owner.unit == 0 && actual.unit == 0 { if !equal(self_.target.types, prior.owner.decl, actual.decl) { return blot_error::Error.invalid_artifact; } } else if prior.owner != actual { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; } }
    if self_.instance_len == self_.instances.len { return blot_error::Error.invalid_artifact; } self_.instances[self_.instance_len] = Instance { variable, actual , ..}; self_.instance_len += 1; return blot_error::Error.none;
}
fn freshVersion(self_: Relocation&, before: u32, after: u32) -> Error { let source = self_.source.types.node(before); let target = self_.target.types.node(after); for pair in self_.fresh_pairs[..self_.fresh_pair_len] { let same_source = sameVersion(source, self_.source.types.node(pair.before)); let same_target = sameVersion(target, self_.target.types.node(pair.after)); if same_source { if !same_target { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; } if same_target { return blot_error::Error.invalid_artifact; } } if self_.fresh_pair_len == self_.fresh_pairs.len { return blot_error::Error.invalid_artifact; } self_.fresh_pairs[self_.fresh_pair_len] = Pair { before, after , ..}; self_.fresh_pair_len += 1; return blot_error::Error.none; }
fn ty(self_: Relocation&, before: u32, after: u32, depth: i64) -> Error { return self_.tyOpened(before, after, depth, false); }
fn tyOpened(self_: Relocation&, before: u32, after: u32, depth: i64, opened: bool) -> Error {
    if depth >= 128 || self_.remaining == 0 || before >= self_.source.types.nodes.len || after >= self_.target.types.nodes.len { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; let a = self_.source.types.node(before); let b = self_.target.types.node(after);
    for pair in self_.pairs[..self_.len] { if pair.before == before && (a.tag == blot_check_types::Tag.variable || pair.opened == opened) { if !equal(self_.target.types, pair.after, after) { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; } }
    if self_.len == self_.pairs.len { return blot_error::Error.invalid_artifact; } self_.pairs[self_.len] = Pair { before, after, opened , ..}; self_.len += 1;
    if a.tag == blot_check_types::Tag.variable { if self_.closing { if before != after { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; } let owned, err = self_.ownedVariable(before); if err != blot_error::Error.none { return err; } if !owned { if !sameOwner(self_.source, self_.target) || before != after { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; } for prior in self_.instances[..self_.instance_len] { if prior.variable == before && (prior.owner.unit != 0 || !equal(self_.target.types, prior.owner.decl, after)) { return blot_error::Error.invalid_artifact; } } return blot_error::Error.none; }
    if a.tag != b.tag { return blot_error::Error.invalid_artifact; }
    match a.tag {
        function => { let err = self_.ty(a.a, b.a, depth + 1); if err != blot_error::Error.none { return err; } let err = self_.tyOpened(a.b, b.b, depth + 1, opened); if err != blot_error::Error.none { return err; } return self_.rowOpened(a.c, b.c, depth + 1, opened); },
        provider => { let err = self_.ty(a.a, b.a, depth + 1); if err != blot_error::Error.none { return err; } return self_.rowOpened(a.c, b.c, depth + 1, opened); },
        array, list, cursor, resolver => { return self_.tyOpened(a.a, b.a, depth + 1, opened && a.tag != blot_check_types::Tag.resolver); },
        state_provider => { let err = self_.ty(a.a, b.a, depth + 1); if err != blot_error::Error.none { return err; } let err = self_.ty(a.b, b.b, depth + 1); if err != blot_error::Error.none { return err; } return self_.ty(a.c, b.c, depth + 1); },
        usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return blot_error::Error.invalid_artifact; } let err = self_.tyOpened(a.a, b.a, depth + 1, opened); if err != blot_error::Error.none { return err; } if a.c != 0 { return self_.ty(a.c, b.c, depth + 1); } },
        scoped => { let err = self_.ty(a.a, b.a, depth + 1); if err != blot_error::Error.none { return err; } if a.b == 0 { if a.c >= self_.source.types.nodes.len { return blot_error::Error.invalid_artifact; } if self_.source.types.node(a.c).tag == blot_check_types::Tag.variable && !self_.closing { return self_.instance(a.c, blot_check_types::NominalIdentity { b.b, b.c , ..}); } if b.b != 0 { return blot_error::Error.invalid_artifact; } return self_.ty(a.c, b.c, depth + 1); } if a.b != b.b || a.c != b.c { return blot_error::Error.invalid_artifact; } },
        product => { if a.b != b.b { return blot_error::Error.invalid_artifact; } let left, err = list(self_.source.types, blot_check_types::List { a.a, a.b , ..}); if err != blot_error::Error.none { return err; } let right, err = list(self_.target.types, blot_check_types::List { b.a, b.b , ..}); if err != blot_error::Error.none { return err; } for child, index in left { let err = self_.tyOpened(child, right[index], depth + 1, opened); if err != blot_error::Error.none { return err; } } },
        record => { if a.b != b.b || a.a > self_.source.types.extra.len || a.b > (self_.source.types.extra.len - a.a) / 2 || b.a > self_.target.types.extra.len || b.b > (self_.target.types.extra.len - b.a) / 2 { return blot_error::Error.invalid_artifact; }
            for index in 0..a.b { let field = self_.source.types.recordField(a, index); var other = blot_support::none<blot_check_types::Field>(); for slot in 0..b.b { let candidate = self_.target.types.recordField(b, slot); if candidate.name == field.name { other = blot_support::some(candidate); break; } } if !other.present { return blot_error::Error.invalid_artifact; } let err = self_.tyOpened(field.ty, other.value.ty, depth + 1, opened); if err != blot_error::Error.none { return err; } }
        },
        nominal, projection, instance_selection => { if a.a != b.a || a.b != b.b { return blot_error::Error.invalid_artifact; } let left, err = arguments(self_.source.types, a); if err != blot_error::Error.none { return err; } let right, err = arguments(self_.target.types, b); if err != blot_error::Error.none { return err; } if left.len != right.len || (a.tag == blot_check_types::Tag.projection && self_.source.types.projectionMember(a) != self_.target.types.projectionMember(b)) { return blot_error::Error.invalid_artifact; } for child, index in left { let err = self_.ty(child, right[index], depth + 1); if err != blot_error::Error.none { return err; } } },
        instance_version => { for version in self_.fresh_versions[..self_.fresh_len] { if sameVersion(self_.source.types.node(version), a) { if !self_.strict_versions && sameVersion(a, b) { return blot_error::Error.none; } if b.a != self_.target.unit || b.b != self_.endpoint || b.c >= 16 { return blot_error::Error.invalid_artifact; } return self_.freshVersion(before, after); } } if !sameVersion(a, b) { return blot_error::Error.invalid_artifact; } },
        forall, existential, bound, rigid, absent => { return blot_error::Error.invalid_artifact; },
        _ => { if a.a != b.a || a.b != b.b || a.c != b.c { return blot_error::Error.invalid_artifact; } },
    } return blot_error::Error.none;
}
fn row(self_: Relocation&, before: u32, after: u32, depth: i64) -> Error { return self_.rowOpened(before, after, depth, false); }
fn rowOpened(self_: Relocation&, before: u32, after: u32, depth: i64, opened: bool) -> Error {
    let left, err = labels(self_.source.types, before); if err != blot_error::Error.none { return err; } let right, err = labels(self_.target.types, after); if err != blot_error::Error.none { return err; } let source = self_.source.types.row(before); var variable = blot_support::none<u32>(); var source_variable = blot_support::none<u32>();
    match source.tail { variable payload => { source_variable = blot_support::some(payload.value); let variables, err = list(self_.source.types, self_.scheme.row_variables); if err != blot_error::Error.none { return err; } for owned in variables { if owned == payload.value { variable = blot_support::some(owned); break; } } }, _ => {}, }
    let target = self_.target.types.row(after);
    if self_.closing { if left.len != right.len { return blot_error::Error.invalid_artifact; } if !blot_structural::equal(source.tail, target.tail) { if !opened || !source_variable.present || target.tail != blot_check_effects::Tail.closed { return blot_error::Error.invalid_artifact; } let closed, err = list(self_.source.types, self_.scheme.closed_rows); if err != blot_error::Error.none { return err; } var owned = false; for value in closed { if value == source_variable.value { owned = true; break; } } if !owned { return blot_error::Error.invalid_artifact; } } }
    else if variable.present { if right.len < left.len { return blot_error::Error.invalid_artifact; } let remainder = blot_check_effects::List { target.labels.start + left.len as u32, (right.len - left.len) as u32 , ..}; var matched = false;
        for prior in self_.rows[..self_.row_len] { if prior.variable != variable.value { continue; } if prior.labels.len != remainder.len || !blot_structural::equal(prior.tail, target.tail) { return blot_error::Error.invalid_artifact; } for a, index in self_.target.types.effects.labels[prior.labels.start..prior.labels.start + prior.labels.len] { let same, err = blot_check_rank_equal::operationEqual(self_.target.types, a, right[left.len + index], true); if err != blot_error::Error.none || !same { return blot_error::Error.invalid_artifact; } } matched = true; break; }
        if !matched { if self_.row_len == self_.rows.len { return blot_error::Error.invalid_artifact; } self_.rows[self_.row_len] = RowInstance { variable.value, remainder, target.tail , ..}; self_.row_len += 1; }
    }
    else if opened && source.tail == blot_check_effects::Tail.closed { if right.len < left.len { return blot_error::Error.invalid_artifact; } }
    else { if left.len != right.len || (source.tail != blot_check_effects::Tail.closed && !sameOwner(self_.source, self_.target)) || !blot_structural::equal(source.tail, target.tail) { return blot_error::Error.invalid_artifact; } }
    for l, index in left { let r = right[index]; if l >= self_.source.types.operations.len || r >= self_.target.types.operations.len { return blot_error::Error.invalid_artifact; } let a = self_.source.types.operation(l); let b = self_.target.types.operation(r); if a.identity != b.identity || a.arguments.len != b.arguments.len { return blot_error::Error.invalid_artifact; }
        if a.instance.unit == 0 && a.instance.decl != 0 { if a.instance.decl >= self_.source.types.nodes.len || b.instance.decl == 0 { return blot_error::Error.invalid_artifact; } if self_.source.types.node(a.instance.decl).tag == blot_check_types::Tag.variable && !self_.closing { let err = self_.instance(a.instance.decl, b.instance); if err != blot_error::Error.none { return err; } } else { if b.instance.unit != 0 { return blot_error::Error.invalid_artifact; } let err = self_.ty(a.instance.decl, b.instance.decl, depth + 1); if err != blot_error::Error.none { return err; } } } else if a.instance != b.instance { return blot_error::Error.invalid_artifact; }
        let largs, err = list(self_.source.types, a.arguments); if err != blot_error::Error.none { return err; } let rargs, err = list(self_.target.types, b.arguments); if err != blot_error::Error.none { return err; } for lty, index in largs { let err = self_.ty(lty, rargs[index], depth + 1); if err != blot_error::Error.none { return err; } }
    } return blot_error::Error.none;
}
