// Structural source dependencies survive metadata erased by execution lowering.
namespace blot_reuse_declaration_dependencies;
import std;
import dictionary;
import check.core;
import check.types;
import check.check;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type BindingRef = blot_check_core::BindingRef;
type Member = blot_check_core::DependencyMember;
type Recipe = blot_check_core::DeclarationDependencies;
enum Work { node { id: u32 }, pattern { id: u32 } }
struct SchemeFrame { scheme: blot_check_types::Scheme, next: u32 = 0 }
let scan_limit: i64 = 16777216;
struct Capture {
    module: const Module&, work: Work[>..<]&, references: BindingRef[>..<]&, locations: u32[>..<]&, members: Member[>..<]&,
    schemes_seen: dictionary<u32,bool>&, runtime_metadata: u32 = 0, watched_binding: u32 = 0,
    watched_used: bool = false, selection: bool = false, failure: Error = Error.none,
}
fn withCapture<C,F>(module: const Module&, context: C, selection: bool = false, watched: u32 = 0) {
    var work: Work[>..<] = []; var references: BindingRef[>..<] = []; var locations: u32[>..<] = []; var members: Member[>..<] = [];
    var schemes: dictionary<u32,bool> = default<dictionary<u32,bool>>();
    var scan = Capture { module: module, work: work, references: references, locations: locations, members: members, schemes_seen: schemes, watched_binding: watched, selection: selection };
    return F(scan, context);
}
fn node(self: Capture&, id: u32) { if self.failure == Error.none && id != 0 { self.work.push(Work.node { id }); } }
fn pattern(self: Capture&, id: u32) { if self.failure == Error.none && id != 0 { self.work.push(Work.pattern { id }); } }
fn nodes(self: Capture&, ids: const u32[:]) { var index = ids.len; while index != 0 { index--; self.node(ids[index]); } }
fn reference(self: Capture&, target: BindingRef, source: u32) {
    if self.failure != Error.none { return; } if target.binding == 0 { self.failure = Error.core_limit; return; }
    if target.unit == 0 || target.unit == self.module.unit {
        if target.binding >= self.module.bindings.len { self.failure = Error.core_limit; return; }
        let kind = self.module.binding(target.binding).kind;
        if kind == blot_check_check::Kind.local || kind == blot_check_check::Kind.parameter { if target.binding == self.watched_binding { self.watched_used = true; } return; }
    }
    self.references.push(target); self.locations.push(source);
}
fn member(self: Capture&, name: u32, op: blot_check_types::Operator) { if self.failure == Error.none && (name != 0 || op != blot_check_types::Operator.none) { self.members.push(Member { name, op }); } }
fn member(self: Capture&, name: u32) { self.member(name, blot_check_types::Operator.none); }
fn scheme(self: Capture&, value: blot_check_types::Scheme) {
    if self.failure != Error.none || value.obligations.len == 0 { return; }
    var pending: SchemeFrame[>..<] = []; pending.push(SchemeFrame { value }); var remaining = scan_limit;
    while pending.len != 0 {
        let last = pending.len - 1; let frame = pending[last]; if frame.next == frame.scheme.obligations.len { pending.pop(); continue; }
        if remaining == 0 { self.failure = Error.core_limit; return; } remaining--; pending[last].next++;
        let obligation = self.module.obligations[frame.scheme.obligations.start + frame.next];
        if obligation.kind == blot_check_types::ObligationKind.callee_use {
            if obligation.identity.unit != 0 && obligation.identity.unit != self.module.unit { self.failure = Error.core_limit; return; }
            let binding = obligation.identity.decl; if binding == 0 || binding >= self.module.bindings.len { self.failure = Error.core_limit; return; }
            if !self.schemes_seen.contains(binding) { self.schemes_seen.insert(binding, true); pending.push(SchemeFrame { self.module.binding(binding).scheme }); } continue;
        }
        if self.selection { self.member(obligation.name, obligation.operator); continue; } if !obligation.explicit { continue; }
        match obligation.kind {
            blot_check_types::ObligationKind.dispatch, blot_check_types::ObligationKind.result_dispatch, blot_check_types::ObligationKind.resolver_dispatch,
            blot_check_types::ObligationKind.receiver, blot_check_types::ObligationKind.field, blot_check_types::ObligationKind.writable_field, blot_check_types::ObligationKind.update => { self.member(obligation.name, obligation.operator); },
            _ => {},
        }
    }
}
fn scan(self: Capture&, body: blot_check_core::Body) -> Recipe, Error {
    let first_reference = self.references.len; let first_member = self.members.len;
    self.schemes_seen.clear(); self.runtime_metadata = 0; self.scheme(body.scheme); self.node(body.root); var remaining = scan_limit;
    while self.work.len != 0 {
        if self.failure != Error.none { return Recipe {}, self.failure; } if remaining == 0 { return Recipe {}, Error.core_limit; } remaining--;
        let item = self.work.pop(); match item {
            Work.node entry => { self.scanNode(entry.id); },
            Work.pattern entry => { self.scanPattern(entry.id); },
        }
    }
    if self.failure != Error.none { return Recipe {}, self.failure; }
    if self.references.len > 0xffffffff || self.members.len > 0xffffffff { return Recipe {}, Error.core_limit; }
    return Recipe { references: blot_check_core::List { first_reference as u32, (self.references.len - first_reference) as u32 }, members: blot_check_core::List { first_member as u32, (self.members.len - first_member) as u32 }, runtime_metadata: self.runtime_metadata }, Error.none;
}
fn scanNode(self: Capture&, id: u32) {
    if id >= self.module.nodes.len { self.failure = Error.core_limit; return; }
    let m .= self.module; let n = m.node(id);
    var low: i64 = 0; var high = m.erased_declaration_references.len;
    while low < high { let middle = low + (high - low) / 2; if m.erased_declaration_references[middle].node < id { low = middle + 1; } else { high = middle; } }
    if low < m.erased_declaration_references.len && m.erased_declaration_references[low].node == id { self.reference(m.erased_declaration_references[low].target, id); }
    match n.tag {
        blot_check_core::Tag.package_pack => { self.nodes(m.children(id)); },
        blot_check_core::Tag.resource_release, blot_check_core::Tag.usage_share, blot_check_core::Tag.usage_read => { self.node(n.a); },
        blot_check_core::Tag.package_unpack => { self.node(m.packageOpening(id).body); self.node(n.a); },
        blot_check_core::Tag.contract_method => {
            self.nodes(m.children(id)); let template = m.member_templates[n.a];
            for implementation in m.implementations {
                if !blot_structural::equal(implementation.contract, template.contract) { continue; }
                for method in m.implementation_members[implementation.members.start..implementation.members.start + implementation.members.len] { if method.kind == blot_check_core::ImplementationMemberKind.value && method.name == template.name { self.reference(BindingRef { method.target.unit, method.target.binding }, id); } }
            }
        },
        blot_check_core::Tag.constant, blot_check_core::Tag.primitive_function, blot_check_core::Tag.panic, blot_check_core::Tag.constructor_function, blot_check_core::Tag.type_constructor => {},
        blot_check_core::Tag.reference => { self.reference(m.reference(id), id); },
        blot_check_core::Tag.staging, blot_check_core::Tag.scalar, blot_check_core::Tag.logical, blot_check_core::Tag.associated, blot_check_core::Tag.record_merge,
        blot_check_core::Tag.type_same, blot_check_core::Tag.effect_provider, blot_check_core::Tag.handle, blot_check_core::Tag.proof_guard, blot_check_core::Tag.resource_acquire, blot_check_core::Tag.usage_borrow => {
            self.node(n.b); self.node(n.a); if n.tag == blot_check_core::Tag.associated { self.member(n.c); }
            if n.tag == blot_check_core::Tag.scalar && n.c != 0 { let op = operator(n.op); if op.present { self.member(0, op.value); } }
        },
        blot_check_core::Tag.call => { self.reference(m.call(id).target, id); self.nodes(m.children(id)); },
        blot_check_core::Tag.task, blot_check_core::Tag.block_, blot_check_core::Tag.suite, blot_check_core::Tag.product, blot_check_core::Tag.record,
        blot_check_core::Tag.array, blot_check_core::Tag.array_op, blot_check_core::Tag.storage => { self.nodes(m.children(id)); },
        blot_check_core::Tag.resource_scope, blot_check_core::Tag.if_value, blot_check_core::Tag.if_stmt, blot_check_core::Tag.state_provider => { self.node(n.c); self.node(n.b); self.node(n.a); },
        blot_check_core::Tag.bind => { self.scheme(m.binding(n.a).scheme); self.node(n.b); },
        blot_check_core::Tag.return_, blot_check_core::Tag.project, blot_check_core::Tag.computation, blot_check_core::Tag.effect_scope => {
            if self.selection && n.tag == blot_check_core::Tag.project { if n.b >= m.projections.len { self.failure = Error.core_limit; return; } self.member(m.projection(n.b).field); } self.node(n.a);
        },
        blot_check_core::Tag.result_associated => { self.member(n.b); self.node(n.a); },
        blot_check_core::Tag.construct => { self.node(n.b); },
        blot_check_core::Tag.closure => { let metadata = m.closures[n.a]; if metadata.qualifier != 0 { self.scheme(m.binding(metadata.qualifier).scheme); } self.node(metadata.body); },
        blot_check_core::Tag.apply => { self.node(n.b); self.node(n.a); },
        blot_check_core::Tag.effect_reflection => {
            if self.runtime_metadata == 0 { self.runtime_metadata = id; }
            if n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.count) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.has) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.same) { self.node(n.c); self.node(n.b); }
        },
        blot_check_core::Tag.operation_value => { self.node(m.operation_values[n.a].witness); },
        blot_check_core::Tag.request_decision => { self.node(n.c); self.node(n.b); },
        blot_check_core::Tag.request_loop => {
            let metadata = m.requestLoopInfo(id); self.node(metadata.completion_body); self.pattern(metadata.completion_pattern);
            let arms = m.requestArms(id); var index = arms.len; while index != 0 { index--; self.node(arms[index].callback); self.node(arms[index].selector); } self.node(metadata.computation);
        },
        blot_check_core::Tag.resolver_op => { let metadata = m.resolverInfo(id); self.member(metadata.member); if metadata.method.binding != 0 { self.reference(metadata.method, id); } self.nodes(m.resolverArguments(id)); self.node(metadata.resolver); },
        blot_check_core::Tag.pattern_bind => { self.node(n.c); self.node(n.b); self.pattern(n.a); },
        blot_check_core::Tag.match_ => {
            let arms = m.matchArms(id); var index = arms.len;
            while index != 0 { index--; let arm = arms[index]; self.node(arm.body); self.node(arm.guard); let rows = m.armRows(arm); var row = rows.len;
                while row != 0 { row--; let patterns = m.rowPatterns(rows[row]); var item = patterns.len; while item != 0 { item--; self.pattern(patterns[item]); } }
            }
            self.nodes(m.matchInputs(id));
        },
        blot_check_core::Tag.update => {
            let metadata = m.updateInfo(id); self.node(metadata.value); let selectors = m.updateSelectors(id);
            if self.selection {
                for name in m.updatePath(id) { self.member(name); }
                for step in selectors { if step.kind == blot_check_core::UpdateKind.field { if step.projection >= m.projections.len { self.failure = Error.core_limit; return; } self.member(m.projection(step.projection).field); } }
            }
            var index = selectors.len; while index != 0 { index--; if selectors[index].kind == blot_check_core::UpdateKind.index { self.node(selectors[index].index); } } self.node(metadata.root);
        },
        blot_check_core::Tag.loop_ => { let metadata = m.loopInfo(id); self.node(metadata.body); self.pattern(metadata.pattern); self.node(metadata.end); self.node(metadata.first); },
        blot_check_core::Tag.break_ => { self.nodes(m.breakValues(id)); },
        blot_check_core::Tag.invalid => { self.failure = Error.core_limit; },
    }
}
fn scanPattern(self: Capture&, id: u32) {
    if id >= self.module.patterns.len { self.failure = Error.core_limit; return; } let pattern = self.module.pattern(id);
    match pattern.tag {
        blot_check_core::PatternTag.wildcard, blot_check_core::PatternTag.bind, blot_check_core::PatternTag.constant => {},
        blot_check_core::PatternTag.value => { self.node(pattern.a); },
        blot_check_core::PatternTag.constructor, blot_check_core::PatternTag.record_payload => { self.pattern(pattern.b); },
        blot_check_core::PatternTag.product => { let children = self.module.patternChildren(id); var index = children.len; while index != 0 { index--; self.pattern(children[index]); } },
        blot_check_core::PatternTag.invalid => { self.failure = Error.core_limit; },
    }
}
fn operator(op: blot_check_core::Op) -> blot_support::Option<blot_check_types::Operator> {
    match op {
        blot_check_core::Op.add => { return blot_support::some(blot_check_types::Operator.add); }, blot_check_core::Op.sub => { return blot_support::some(blot_check_types::Operator.sub); },
        blot_check_core::Op.mul => { return blot_support::some(blot_check_types::Operator.mul); }, blot_check_core::Op.div => { return blot_support::some(blot_check_types::Operator.div); },
        blot_check_core::Op.rem => { return blot_support::some(blot_check_types::Operator.rem); }, blot_check_core::Op.equal => { return blot_support::some(blot_check_types::Operator.equal); },
        blot_check_core::Op.not_equal => { return blot_support::some(blot_check_types::Operator.not_equal); }, blot_check_core::Op.less => { return blot_support::some(blot_check_types::Operator.less); },
        blot_check_core::Op.less_equal => { return blot_support::some(blot_check_types::Operator.less_equal); }, blot_check_core::Op.greater => { return blot_support::some(blot_check_types::Operator.greater); },
        blot_check_core::Op.greater_equal => { return blot_support::some(blot_check_types::Operator.greater_equal); }, blot_check_core::Op.bit_and => { return blot_support::some(blot_check_types::Operator.bit_and); },
        blot_check_core::Op.bit_or => { return blot_support::some(blot_check_types::Operator.bit_or); }, blot_check_core::Op.bit_xor => { return blot_support::some(blot_check_types::Operator.bit_xor); },
        blot_check_core::Op.shift_left => { return blot_support::some(blot_check_types::Operator.shift_left); }, blot_check_core::Op.shift_right => { return blot_support::some(blot_check_types::Operator.shift_right); },
        _ => { return blot_support::none<blot_check_types::Operator>(); },
    }
}
fn capture(module: Module&, declarations: Recipe[>..<]&, references: BindingRef[>..<]&, members: Member[>..<]&) -> Error {
    assert(module.declaration_dependencies.len == 0); assert(declarations.len == 0 && references.len == 0 && members.len == 0);
    var work: Work[>..<] = []; var locations: u32[>..<] = []; var seen: dictionary<u32,bool> = default<dictionary<u32,bool>>();
    var scan = Capture { module: module, work: work, references: references, locations: locations, members: members, schemes_seen: seen };
    for index in module.bodies.len { declarations.push(Recipe {}); }
    for body, offset in module.bodies[1..] { let recipe, error = scan.scan(body); if error != Error.none { declarations.clear(); references.clear(); members.clear(); return error; } declarations[offset + 1] = recipe; }
    module.declaration_dependencies = declarations[..]; module.dependency_references = references[..]; module.dependency_members = members[..]; return Error.none;
}
struct Selection { body: blot_check_core::Body, output: Member[>..<]& }
fn selectionMembers(module: const Module&, body: blot_check_core::Body, output: Member[>..<]&) -> Error { return withCapture(module, Selection { body, output }, true, 0, select); }
fn select(scan: Capture&, context: Selection) -> Error { let recipe, error = scan.scan(context.body); if error != Error.none { return error; } context.output.append(scan.members[..]); return Error.none; }
reusable[] var owned_references: BindingRef[>..] = [];
reusable[] var owned_locations: u32[>..] = [];
fn copyReferences(source: const BindingRef[:]) -> BindingRef[:] { if source.len == 0 { return []; } let out = owned_references.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn copyLocations(source: const u32[:]) -> u32[:] { if source.len == 0 { return []; } let out = owned_locations.alloc_slice(source.len); for value, index in source { out[index] = value; } return out; }
fn releaseReferences(source: const BindingRef[:]) { if source.len != 0 { let first: const BindingRef& = source[0]; let at = owned_references.index_of(first); assert(at >= 0); owned_references.free_slice(owned_references[at..at + source.len]); } }
fn releaseLocations(source: const u32[:]) { if source.len != 0 { let first: const u32& = source[0]; let at = owned_locations.index_of(first); assert(at >= 0); owned_locations.free_slice(owned_locations[at..at + source.len]); } }
struct Expression { references: BindingRef[:] = [], locations: u32[:] = [], runtime_metadata: u32 = 0 }
fn deinit(self: Expression&) { releaseReferences(self.references); releaseLocations(self.locations); self = Expression {}; }
fn expression(module: const Module&, root: u32) -> Expression, Error { return withCapture(module, root, false, 0, captureExpression); }
fn captureExpression(scan: Capture&, root: u32) -> Expression, Error { let recipe, error = scan.scan(blot_check_core::Body { root: root }); if error != Error.none { return Expression {}, error; } return Expression { copyReferences(scan.references[..]), copyLocations(scan.locations[..]), recipe.runtime_metadata }, Error.none; }
fn expressionReferences(module: const Module&, root: u32) -> BindingRef[:], Error { return withCapture(module, root, false, 0, captureReferences); }
fn captureReferences(scan: Capture&, root: u32) -> BindingRef[:], Error { let recipe, error = scan.scan(blot_check_core::Body { root: root }); if error != Error.none { return [], error; } return copyReferences(scan.references[..]), Error.none; }
fn usesBinding(module: const Module&, root: u32, binding: u32) -> bool, Error { return withCapture(module, root, false, binding, checkBinding); }
fn checkBinding(scan: Capture&, root: u32) -> bool, Error { let recipe, error = scan.scan(blot_check_core::Body { root: root }); return scan.watched_used, error; }
