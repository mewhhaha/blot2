// Read-only invocation relocation preserves captured owner/version identities.
namespace blot_check_generative_relocation;
import support.error;
import support.option;
import support.structural;
import .core;
import .types;
import .effects;
import .rank_equal;
type Error = blot_error::Error;
type Types = blot_check_core::Types;
type Module = blot_check_core::Module;
type Tag = blot_check_types::Tag;
type Tail = blot_check_effects::Tail;
fn list(types: const Types&, span: blot_check_types::List) -> const u32[:], Error { if span.start > types.extra.len || span.len > types.extra.len - span.start { return [], Error.invalid_artifact; } return types.list(span), Error.none; }
fn arguments(types: const Types&, node: blot_check_types::Node) -> const u32[:], Error { if node.c >= types.extra.len { return [], Error.invalid_artifact; } let count = types.extra[node.c]; if count > types.extra.len - node.c - 1 || (node.tag == Tag.projection && count >= types.extra.len - node.c - 1) { return [], Error.invalid_artifact; } return types.nominalArguments(node), Error.none; }
fn labels(types: const Types&, row: u32) -> const u32[:], Error { if row >= types.effects.rows.len { return [], Error.invalid_artifact; } let span = types.row(row).labels; if span.start > types.effects.labels.len || span.len > types.effects.labels.len - span.start { return [], Error.invalid_artifact; } return types.rowLabels(row), Error.none; }
fn sameVersion(left: blot_check_types::Node, right: blot_check_types::Node) -> bool { return left.a == right.a && left.b == right.b && left.c == right.c; }
fn sameOwner(left: const Module&, right: const Module&) -> bool { return left .== right; }
fn equal(types: const Types&, left: u32, right: u32) -> bool { let value, err = blot_check_rank_equal::equal(types, left, right, true); return err == Error.none && value; }
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
    if scheme.generative.len > 32 || scheme.generative.len % 2 != 0 { return result, Error.invalid_artifact; } let words, err = list(source.types, scheme.generative); if err != Error.none { return result, err; } var arrow = scheme.root;
    for ignored in 0..consumed { if arrow >= source.types.nodes.len { return result, Error.invalid_artifact; } let n = source.types.node(arrow); if n.tag != Tag.function { return result, Error.invalid_artifact; }
        for index in 0..words.len / 2 { if words[index * 2] != arrow { continue; } if words[index * 2 + 1] >= source.types.nodes.len { return result, Error.invalid_artifact; } let selected = source.types.node(words[index * 2 + 1]); if selected.tag != Tag.scoped || selected.b != 0 || selected.c >= source.types.nodes.len { return result, Error.invalid_artifact; } let term = source.types.node(selected.c); if term.tag != Tag.instance_selection { return result, Error.invalid_artifact; } let children, err = arguments(source.types, term); if err != Error.none { return result, err; }
            if children.len != 3 || result.fresh_len == result.fresh_versions.len || children[2] >= source.types.nodes.len || source.types.node(children[2]).tag != Tag.instance_version { return result, Error.invalid_artifact; } result.fresh_versions[result.fresh_len] = children[2]; result.fresh_len += 1;
        } arrow = n.b;
    }
    let err = result.tyOpened(scheme.root, actual, 0, true); if err != Error.none { return result, err; } var kept: i64 = 0;
    for pair in result.pairs[..result.len] { if source.types.node(pair.before).tag == Tag.variable { result.pairs[kept] = pair; kept += 1; } }
    result.len = kept; result.strict_versions = true; let err = result.tyOpened(arrow, output, 0, true); return result, err;
}
fn Relocation::applications(self: Relocation&, id: u32) -> Error {
    if id == 0 || id >= self.target.nodes.len { return Error.invalid_artifact; } var chain: u32[16]; var count: i64 = 0; var callee = id;
    while self.target.node(callee).tag == blot_check_core::Tag.apply { if count == chain.len { return Error.invalid_artifact; } chain[count] = callee; count += 1; callee = self.target.node(callee).a; if callee == 0 || callee >= self.target.nodes.len { return Error.invalid_artifact; } }
    var arrow = self.scheme.root; for index in 0..count { let function = self.source.types.node(arrow); if function.tag != Tag.function { return Error.invalid_artifact; } arrow = function.b; let err = self.tyOpened(arrow, self.target.node(chain[count - index - 1]).ty, 0, true); if err != Error.none { return err; } } return Error.none;
}
fn invoked(module: const Module&, variables: blot_check_types::List, before: u32, after: u32, versions: const u32[:], endpoint: u32) -> Error {
    var relation = Relocation { source: module, target: module, scheme: blot_check_types::Scheme { root: before, variables: variables , ..}, endpoint: endpoint, strict_versions: true , ..};
    if versions.len > relation.fresh_versions.len { return Error.invalid_artifact; } for version, index in versions { if version >= module.types.nodes.len || module.types.node(version).tag != Tag.instance_version { return Error.invalid_artifact; } relation.fresh_versions[index] = version; } relation.fresh_len = versions.len; return relation.ty(before, after, 0);
}
fn generalized(module: const Module&, scheme: blot_check_types::Scheme, raw: u32) -> Error {
    var relation = Relocation { source: module, target: module, scheme: scheme, endpoint: 0, strict_versions: true, closing: true , ..}; let closed, err = list(module.types, scheme.closed_rows); if err != Error.none { return err; }
    for variable in closed { let safe, err = relation.safeClosing(raw, variable, 0); if err != Error.none { return err; } if !safe { return Error.invalid_artifact; } } return relation.tyOpened(raw, scheme.root, 0, true);
}
fn Relocation::hasRow(self: Relocation&, root: u32, variable: u32, depth: i64) -> bool, Error {
    if depth >= 128 || self.remaining == 0 || root >= self.source.types.nodes.len { return false, Error.invalid_artifact; } self.remaining -= 1; let node = self.source.types.node(root);
    match node.tag {
        Tag.function, Tag.provider => { if node.c >= self.source.types.effects.rows.len { return false, Error.invalid_artifact; } let row = self.source.types.row(node.c); match row.tail { Tail.variable payload => { if payload.value == variable { return true, Error.none; } }, _ => {}, }
            let row_labels, err = labels(self.source.types, node.c); if err != Error.none { return false, err; } for label in row_labels { if label >= self.source.types.operations.len { return false, Error.invalid_artifact; } let operation = self.source.types.operation(label); if operation.instance.unit == 0 && operation.instance.decl != 0 { let found, err = self.hasRow(operation.instance.decl, variable, depth + 1); if err != Error.none || found { return found, err; } } let args, err = list(self.source.types, operation.arguments); if err != Error.none { return false, err; } for argument in args { let found, err = self.hasRow(argument, variable, depth + 1); if err != Error.none || found { return found, err; } } }
            let found, err = self.hasRow(node.a, variable, depth + 1); if err != Error.none || found { return found, err; } if node.tag == Tag.function { return self.hasRow(node.b, variable, depth + 1); }
        },
        Tag.array, Tag.list, Tag.cursor, Tag.resolver => { return self.hasRow(node.a, variable, depth + 1); },
        Tag.usage => { let found, err = self.hasRow(node.a, variable, depth + 1); if err != Error.none || found { return found, err; } if node.c != 0 { return self.hasRow(node.c, variable, depth + 1); } },
        Tag.state_provider => { for child in [node.a, node.b, node.c] { let found, err = self.hasRow(child, variable, depth + 1); if err != Error.none || found { return found, err; } } },
        Tag.scoped => { let found, err = self.hasRow(node.a, variable, depth + 1); if err != Error.none || found { return found, err; } if node.b == 0 { return self.hasRow(node.c, variable, depth + 1); } },
        Tag.product => { let children, err = list(self.source.types, blot_check_types::List { node.a, node.b , ..}); if err != Error.none { return false, err; } for child in children { let found, err = self.hasRow(child, variable, depth + 1); if err != Error.none || found { return found, err; } } },
        Tag.record => { if node.a > self.source.types.extra.len || node.b > (self.source.types.extra.len - node.a) / 2 { return false, Error.invalid_artifact; } for index in 0..node.b { let found, err = self.hasRow(self.source.types.recordField(node, index).ty, variable, depth + 1); if err != Error.none || found { return found, err; } } },
        Tag.nominal, Tag.projection, Tag.instance_selection => { let children, err = arguments(self.source.types, node); if err != Error.none { return false, err; } for child in children { let found, err = self.hasRow(child, variable, depth + 1); if err != Error.none || found { return found, err; } } },
        Tag.forall, Tag.existential, Tag.bound, Tag.rigid, Tag.absent => { return false, Error.invalid_artifact; },
        _ => {},
    } return false, Error.none;
}
fn Relocation::safeClosing(self: Relocation&, root: u32, variable: u32, depth: i64) -> bool, Error {
    if depth >= 128 || self.remaining == 0 || root >= self.source.types.nodes.len { return false, Error.invalid_artifact; } self.remaining -= 1; let node = self.source.types.node(root);
    match node.tag {
        Tag.function => { let found, err = self.hasRow(node.a, variable, depth + 1); if err != Error.none { return false, err; } if found { return false, Error.none; } if node.c >= self.source.types.effects.rows.len { return false, Error.invalid_artifact; } let tail = self.source.types.row(node.c).tail;
            match tail { Tail.variable payload => { if payload.value == variable { let found, err = self.hasRow(node.b, variable, depth + 1); if err != Error.none { return false, err; } if found { return false, Error.none; } } }, _ => {}, } return self.safeClosing(node.b, variable, depth + 1);
        },
        Tag.provider => { let found, err = self.hasRow(node.a, variable, depth + 1); return !found, err; },
        Tag.array, Tag.list, Tag.cursor, Tag.usage => { return self.safeClosing(node.a, variable, depth + 1); },
        Tag.product => { let children, err = list(self.source.types, blot_check_types::List { node.a, node.b , ..}); if err != Error.none { return false, err; } for child in children { let safe, err = self.safeClosing(child, variable, depth + 1); if err != Error.none || !safe { return safe, err; } } },
        Tag.record => { if node.a > self.source.types.extra.len || node.b > (self.source.types.extra.len - node.a) / 2 { return false, Error.invalid_artifact; } for index in 0..node.b { let safe, err = self.safeClosing(self.source.types.recordField(node, index).ty, variable, depth + 1); if err != Error.none || !safe { return safe, err; } } },
        _ => { let found, err = self.hasRow(root, variable, depth + 1); return !found, err; },
    } return true, Error.none;
}
fn Relocation::get(self: const Relocation&, before: u32) -> blot_support::Option<u32> { for pair in self.pairs[..self.len] { if pair.before == before { return blot_support::some(pair.after); } } return blot_support::none<u32>(); }
fn Relocation::ownedVariable(self: const Relocation&, id: u32) -> bool, Error { let variables, err = list(self.source.types, self.scheme.variables); if err != Error.none { return false, err; } for variable in variables { if variable == id { return true, Error.none; } } return false, Error.none; }
fn Relocation::instance(self: Relocation&, variable: u32, actual: blot_check_types::NominalIdentity) -> Error {
    let owned, err = self.ownedVariable(variable); if err != Error.none { return err; } if !owned { if !sameOwner(self.source, self.target) || actual.unit != 0 || actual.decl != variable { return Error.invalid_artifact; } return Error.none; }
    if actual.unit == 0 { if actual.decl >= self.target.types.nodes.len { return Error.invalid_artifact; } let node = self.target.types.node(actual.decl); if node.tag != Tag.variable && node.tag != Tag.instance_selection { return Error.invalid_artifact; } } else if actual.decl == 0 { return Error.invalid_artifact; }
    let mapped = self.get(variable); if mapped.present && (actual.unit != 0 || !equal(self.target.types, mapped.value, actual.decl)) { return Error.invalid_artifact; }
    for prior in self.instances[..self.instance_len] { if prior.variable == variable { if prior.owner.unit == 0 && actual.unit == 0 { if !equal(self.target.types, prior.owner.decl, actual.decl) { return Error.invalid_artifact; } } else if prior.owner != actual { return Error.invalid_artifact; } return Error.none; } }
    if self.instance_len == self.instances.len { return Error.invalid_artifact; } self.instances[self.instance_len] = Instance { variable, actual , ..}; self.instance_len += 1; return Error.none;
}
fn Relocation::freshVersion(self: Relocation&, before: u32, after: u32) -> Error { let source = self.source.types.node(before); let target = self.target.types.node(after); for pair in self.fresh_pairs[..self.fresh_pair_len] { let same_source = sameVersion(source, self.source.types.node(pair.before)); let same_target = sameVersion(target, self.target.types.node(pair.after)); if same_source { if !same_target { return Error.invalid_artifact; } return Error.none; } if same_target { return Error.invalid_artifact; } } if self.fresh_pair_len == self.fresh_pairs.len { return Error.invalid_artifact; } self.fresh_pairs[self.fresh_pair_len] = Pair { before, after , ..}; self.fresh_pair_len += 1; return Error.none; }
fn Relocation::ty(self: Relocation&, before: u32, after: u32, depth: i64) -> Error { return self.tyOpened(before, after, depth, false); }
fn Relocation::tyOpened(self: Relocation&, before: u32, after: u32, depth: i64, opened: bool) -> Error {
    if depth >= 128 || self.remaining == 0 || before >= self.source.types.nodes.len || after >= self.target.types.nodes.len { return Error.invalid_artifact; } self.remaining -= 1; let a = self.source.types.node(before); let b = self.target.types.node(after);
    for pair in self.pairs[..self.len] { if pair.before == before && (a.tag == Tag.variable || pair.opened == opened) { if !equal(self.target.types, pair.after, after) { return Error.invalid_artifact; } return Error.none; } }
    if self.len == self.pairs.len { return Error.invalid_artifact; } self.pairs[self.len] = Pair { before, after, opened , ..}; self.len += 1;
    if a.tag == Tag.variable { if self.closing { if before != after { return Error.invalid_artifact; } return Error.none; } let owned, err = self.ownedVariable(before); if err != Error.none { return err; } if !owned { if !sameOwner(self.source, self.target) || before != after { return Error.invalid_artifact; } return Error.none; } for prior in self.instances[..self.instance_len] { if prior.variable == before && (prior.owner.unit != 0 || !equal(self.target.types, prior.owner.decl, after)) { return Error.invalid_artifact; } } return Error.none; }
    if a.tag != b.tag { return Error.invalid_artifact; }
    match a.tag {
        Tag.function => { let err = self.ty(a.a, b.a, depth + 1); if err != Error.none { return err; } let err = self.tyOpened(a.b, b.b, depth + 1, opened); if err != Error.none { return err; } return self.rowOpened(a.c, b.c, depth + 1, opened); },
        Tag.provider => { let err = self.ty(a.a, b.a, depth + 1); if err != Error.none { return err; } return self.rowOpened(a.c, b.c, depth + 1, opened); },
        Tag.array, Tag.list, Tag.cursor, Tag.resolver => { return self.tyOpened(a.a, b.a, depth + 1, opened && a.tag != Tag.resolver); },
        Tag.state_provider => { let err = self.ty(a.a, b.a, depth + 1); if err != Error.none { return err; } let err = self.ty(a.b, b.b, depth + 1); if err != Error.none { return err; } return self.ty(a.c, b.c, depth + 1); },
        Tag.usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return Error.invalid_artifact; } let err = self.tyOpened(a.a, b.a, depth + 1, opened); if err != Error.none { return err; } if a.c != 0 { return self.ty(a.c, b.c, depth + 1); } },
        Tag.scoped => { let err = self.ty(a.a, b.a, depth + 1); if err != Error.none { return err; } if a.b == 0 { if a.c >= self.source.types.nodes.len { return Error.invalid_artifact; } if self.source.types.node(a.c).tag == Tag.variable && !self.closing { return self.instance(a.c, blot_check_types::NominalIdentity { b.b, b.c , ..}); } if b.b != 0 { return Error.invalid_artifact; } return self.ty(a.c, b.c, depth + 1); } if a.b != b.b || a.c != b.c { return Error.invalid_artifact; } },
        Tag.product => { if a.b != b.b { return Error.invalid_artifact; } let left, err = list(self.source.types, blot_check_types::List { a.a, a.b , ..}); if err != Error.none { return err; } let right, err = list(self.target.types, blot_check_types::List { b.a, b.b , ..}); if err != Error.none { return err; } for child, index in left { let err = self.tyOpened(child, right[index], depth + 1, opened); if err != Error.none { return err; } } },
        Tag.record => { if a.b != b.b || a.a > self.source.types.extra.len || a.b > (self.source.types.extra.len - a.a) / 2 || b.a > self.target.types.extra.len || b.b > (self.target.types.extra.len - b.a) / 2 { return Error.invalid_artifact; }
            for index in 0..a.b { let field = self.source.types.recordField(a, index); var other = blot_support::none<blot_check_types::Field>(); for slot in 0..b.b { let candidate = self.target.types.recordField(b, slot); if candidate.name == field.name { other = blot_support::some(candidate); break; } } if !other.present { return Error.invalid_artifact; } let err = self.tyOpened(field.ty, other.value.ty, depth + 1, opened); if err != Error.none { return err; } }
        },
        Tag.nominal, Tag.projection, Tag.instance_selection => { if a.a != b.a || a.b != b.b { return Error.invalid_artifact; } let left, err = arguments(self.source.types, a); if err != Error.none { return err; } let right, err = arguments(self.target.types, b); if err != Error.none { return err; } if left.len != right.len || (a.tag == Tag.projection && self.source.types.projectionMember(a) != self.target.types.projectionMember(b)) { return Error.invalid_artifact; } for child, index in left { let err = self.ty(child, right[index], depth + 1); if err != Error.none { return err; } } },
        Tag.instance_version => { for version in self.fresh_versions[..self.fresh_len] { if sameVersion(self.source.types.node(version), a) { if !self.strict_versions && sameVersion(a, b) { return Error.none; } if b.a != self.target.unit || b.b != self.endpoint || b.c >= 16 { return Error.invalid_artifact; } return self.freshVersion(before, after); } } if !sameVersion(a, b) { return Error.invalid_artifact; } },
        Tag.forall, Tag.existential, Tag.bound, Tag.rigid, Tag.absent => { return Error.invalid_artifact; },
        _ => { if a.a != b.a || a.b != b.b || a.c != b.c { return Error.invalid_artifact; } },
    } return Error.none;
}
fn Relocation::row(self: Relocation&, before: u32, after: u32, depth: i64) -> Error { return self.rowOpened(before, after, depth, false); }
fn Relocation::rowOpened(self: Relocation&, before: u32, after: u32, depth: i64, opened: bool) -> Error {
    let left, err = labels(self.source.types, before); if err != Error.none { return err; } let right, err = labels(self.target.types, after); if err != Error.none { return err; } let source = self.source.types.row(before); var variable = blot_support::none<u32>(); var source_variable = blot_support::none<u32>();
    match source.tail { Tail.variable payload => { source_variable = blot_support::some(payload.value); let variables, err = list(self.source.types, self.scheme.row_variables); if err != Error.none { return err; } for owned in variables { if owned == payload.value { variable = blot_support::some(owned); break; } } }, _ => {}, }
    let target = self.target.types.row(after);
    if self.closing { if left.len != right.len { return Error.invalid_artifact; } if !blot_structural::equal(source.tail, target.tail) { if !opened || !source_variable.present || target.tail != Tail.closed { return Error.invalid_artifact; } let closed, err = list(self.source.types, self.scheme.closed_rows); if err != Error.none { return err; } var owned = false; for value in closed { if value == source_variable.value { owned = true; break; } } if !owned { return Error.invalid_artifact; } } }
    else if variable.present { if right.len < left.len { return Error.invalid_artifact; } let remainder = blot_check_effects::List { target.labels.start + left.len as u32, (right.len - left.len) as u32 , ..}; var matched = false;
        for prior in self.rows[..self.row_len] { if prior.variable != variable.value { continue; } if prior.labels.len != remainder.len || !blot_structural::equal(prior.tail, target.tail) { return Error.invalid_artifact; } for a, index in self.target.types.effects.labels[prior.labels.start..prior.labels.start + prior.labels.len] { let same, err = blot_check_rank_equal::operationEqual(self.target.types, a, right[left.len + index], true); if err != Error.none || !same { return Error.invalid_artifact; } } matched = true; break; }
        if !matched { if self.row_len == self.rows.len { return Error.invalid_artifact; } self.rows[self.row_len] = RowInstance { variable.value, remainder, target.tail , ..}; self.row_len += 1; }
    }
    else if opened && source.tail == Tail.closed { if right.len < left.len { return Error.invalid_artifact; } }
    else { if left.len != right.len || (source.tail != Tail.closed && !sameOwner(self.source, self.target)) || !blot_structural::equal(source.tail, target.tail) { return Error.invalid_artifact; } }
    for l, index in left { let r = right[index]; if l >= self.source.types.operations.len || r >= self.target.types.operations.len { return Error.invalid_artifact; } let a = self.source.types.operation(l); let b = self.target.types.operation(r); if a.identity != b.identity || a.arguments.len != b.arguments.len { return Error.invalid_artifact; }
        if a.instance.unit == 0 && a.instance.decl != 0 { if a.instance.decl >= self.source.types.nodes.len || b.instance.decl == 0 { return Error.invalid_artifact; } if self.source.types.node(a.instance.decl).tag == Tag.variable && !self.closing { let err = self.instance(a.instance.decl, b.instance); if err != Error.none { return err; } } else { if b.instance.unit != 0 { return Error.invalid_artifact; } let err = self.ty(a.instance.decl, b.instance.decl, depth + 1); if err != Error.none { return err; } } } else if a.instance != b.instance { return Error.invalid_artifact; }
        let largs, err = list(self.source.types, a.arguments); if err != Error.none { return err; } let rargs, err = list(self.target.types, b.arguments); if err != Error.none { return err; } for lty, index in largs { let err = self.ty(lty, rargs[index], depth + 1); if err != Error.none { return err; } }
    } return Error.none;
}
