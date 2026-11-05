// Exact same-ID body projection. Namespace/catalog admission belongs to Gate.
namespace blot_reuse_declaration_projection;
import std;
import check.core;
import check.types;
import check.check;
import support.error;
import support.option;
import support.structural;
type Error = blot_error::Error;
type Module = blot_check_core::Module;
type List = blot_check_core::List;
enum Work { node { id: u32 }, binding { id: u32 }, pattern { id: u32 }, projection { id: u32 } }
reusable[] var owned_words: u32[>..] = [];
reusable[] var owned_work: Work[>..] = [];
fn release(run: const u32[:]) { if run.len != 0 { let first: const u32& = run[0]; let at = owned_words.index_of(first); assert(at >= 0); owned_words.free_slice(owned_words[at..at + run.len]); } }
fn release(run: const Work[:]) { if run.len != 0 { let first: const Work& = run[0]; let at = owned_work.index_of(first); assert(at >= 0); owned_work.free_slice(owned_work[at..at + run.len]); } }
struct Workspace {
    nodes: u32[:] = [], bindings: u32[:] = [], patterns: u32[:] = [], projections: u32[:] = [],
    generation: u32 = 0, scans: i64 = 0, visits: i64 = 0, work: Work[:] = [], count: i64 = 0,
}
fn init(old: const Module&) -> Workspace {
    var result = Workspace { nodes: owned_words.alloc_slice(old.nodes.len), bindings: owned_words.alloc_slice(old.bindings.len), patterns: owned_words.alloc_slice(old.patterns.len), projections: owned_words.alloc_slice(old.projections.len) };
    result.clear(); return result;
}
fn clear(self: Workspace&) { for &v in self.nodes { v = 0; } for &v in self.bindings { v = 0; } for &v in self.patterns { v = 0; } for &v in self.projections { v = 0; } self.generation = 0; }
fn capacityBytes(self: const Workspace&) -> i64 { return (self.nodes.len + self.bindings.len + self.patterns.len + self.projections.len) * 4 + self.work.len * 5; }
fn deinit(self: Workspace&) { release(self.nodes); release(self.bindings); release(self.patterns); release(self.projections); release(self.work); self = Workspace {}; }
fn withWorkspace<C,F>(old: const Module&, context: C) { var workspace = init(old); let result = F(context, workspace); workspace.deinit(); return result; }
fn definitionEqual(self: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]? = null, constant_types: bool = false) -> bool, Error { return self.run(old, current, binding, closures, constant_types, 0, null, []); }
fn definitionEqualWithOrigins(self: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?, constant_types: bool, origins: const bool[:]) -> bool, Error {
    var admitted: const bool[:] = []; if binding < origins.len && origins[binding] { admitted = origins; } return self.run(old, current, binding, closures, constant_types, 0, null, admitted);
}
fn run(self: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?, constant_types: bool, expression: u32, reached: u32[>..<]?, origins: const bool[:]) -> bool, Error {
    if binding == 0 && expression == 0 { return false, Error.none; }
    assert(self.nodes.len == old.nodes.len && self.bindings.len == old.bindings.len && self.patterns.len == old.patterns.len && self.projections.len == old.projections.len);
    if self.generation == 0xffffffff { self.clear(); } self.generation++; self.scans++; self.count = 0;
    var scan = Scan { workspace: self, old: old, current: current, closures: closures, constant_types: constant_types, origins: origins };
    if origins.len != 0 { scan.source_shift = current.sourceNamePoint(binding) as i64 - old.sourceNamePoint(binding) as i64; }
    if expression != 0 { scan.node(expression); scan.drain(); } else { scan.run(binding); }
    self.visits += scan.visits;
    if scan.failure != Error.none { if scan.failure == Error.out_of_memory { return false, scan.failure; } return false, Error.none; }
    if reached { for seen, id in self.nodes { if seen == self.generation { reached.push(id as u32); } } }
    return true, Error.none;
}
struct Scan {
    workspace: Workspace&, old: const Module&, current: const Module&,
    visits: i64 = 0, closures: u32[>..<]? = null, constant_types: bool = false,
    origins: const bool[:] = [], source_shift: i64 = 0, failure: Error = Error.none,
}
fn bindingShift(self: const Scan&, id: i64) -> i64 { if self.old.bindings[id].kind != blot_check_check::Kind.global { return self.source_shift; } if id >= self.origins.len || !self.origins[id] { return 0; } return self.current.sourceNamePoint(id as u32) as i64 - self.old.sourceNamePoint(id as u32) as i64; }
fn shiftedPoint(old: u32, current: u32, shift: i64) -> bool { return (old == 0 && current == 0) || current as i64 - old as i64 == shift; }
fn normalizePositions<T>(old: T&, current: T, shift: i64) -> Error { return Error.none; }
fn normalizePositions(old: blot_check_core::Span&, current: blot_check_core::Span, shift: i64) -> Error {
    if old.start == 0 && old.end == 0 && current.start == 0 && current.end == 0 { return Error.none; }
    if current.start as i64 - old.start as i64 != shift || current.end as i64 - old.end as i64 != shift { return Error.changed; } old = current; return Error.none;
}
fn normalizePositions(old: blot_check_core::Projection&, current: blot_check_core::Projection, shift: i64) -> Error { if !shiftedPoint(old.diagnostic_point, current.diagnostic_point, shift) { return Error.changed; } old.diagnostic_point = current.diagnostic_point; return Error.none; }
fn normalizePositions(old: blot_check_core::ClosureInfo&, current: blot_check_core::ClosureInfo, shift: i64) -> Error { return normalizePositions(old.parameter, current.parameter, shift); }
fn aliases<T>(self: const Scan&, normalized: T&, after: T) -> bool { return true; }
fn alias(self: const Scan&, before: u32&, after: u32) -> bool { if !self.constant_types && before != after { return false; } if !equalConstantType(self.old.types, before, self.current.types, after) { return false; } before = after; return true; }
fn projectedItem<T>(self: Scan&, left: const T[:], right: const T[:], id: i64) -> T {
    if self.failure != Error.none { return default<T>(); }
    if id < 0 || id >= left.len || id >= right.len { self.failure = Error.changed; return default<T>(); }
    var normalized = left[id];
    if !self.constant_types && self.origins.len == 0 { if !blot_structural::equal(normalized, right[id]) { self.failure = Error.changed; return default<T>(); } return normalized; }
    if self.origins.len != 0 { let error = normalizeItemPositions(self, normalized, right[id], id); if error != Error.none { self.failure = error; return default<T>(); } }
    if !self.aliases(normalized, right[id]) || !blot_structural::equal(normalized, right[id]) { self.failure = Error.changed; return default<T>(); } return left[id];
}
fn normalizeItemPositions<T>(self: const Scan&, before: T&, after: T, id: i64) -> Error { return normalizePositions(before, after, self.source_shift); }
fn normalizeItemPositions(self: const Scan&, before: blot_check_core::Binding&, after: blot_check_core::Binding, id: i64) -> Error { return normalizePositions(before, after, self.bindingShift(id)); }
fn projectedSlice<T>(self: Scan&, left: const T[:], right: const T[:], list: List) -> const T[:] {
    if self.failure != Error.none { return []; }
    if list.start > left.len || list.len > left.len - list.start || list.start > right.len || list.len > right.len - list.start { self.failure = Error.changed; return []; }
    let result = left[list.start..list.start + list.len];
    for before, index in result { var normalized = before; let after = right[list.start + index]; if self.origins.len != 0 { let error = normalizePositions(normalized, after, self.source_shift); if error != Error.none { self.failure = error; return []; } } if !blot_structural::equal(normalized, after) { self.failure = Error.changed; return []; } }
    return result;
}
fn enqueue(self: Scan&, item: Work) {
    if self.failure != Error.none { return; } var seen: u32[:] = []; var id: u32 = 0; var projection = false;
    match item { Work.node entry => { seen = self.workspace.nodes; id = entry.id; }, Work.binding entry => { seen = self.workspace.bindings; id = entry.id; }, Work.pattern entry => { seen = self.workspace.patterns; id = entry.id; }, Work.projection entry => { seen = self.workspace.projections; id = entry.id; projection = true; } }
    if id == 0 && !projection { return; } if id >= seen.len { self.failure = Error.changed; return; } if seen[id] == self.workspace.generation { return; }
    let w .= self.workspace;
    if w.count == w.work.len {
        let minimum = w.count + 1; if minimum > 0x5555555555555540 { self.failure = Error.out_of_memory; return; }
        let next = minimum + minimum / 2 + 12; let run = owned_work.alloc_slice(next);
        for index in w.count { run[index] = w.work[index]; } release(w.work); w.work = run;
    }
    w.work[w.count] = item; w.count++; seen[id] = w.generation; self.visits++;
}
fn node(self: Scan&, id: u32) { self.enqueue(Work.node { id }); }
fn binding(self: Scan&, id: u32) { self.enqueue(Work.binding { id }); }
fn pattern(self: Scan&, id: u32) { self.enqueue(Work.pattern { id }); }
fn projection(self: Scan&, id: u32) { self.enqueue(Work.projection { id }); }
fn words(self: Scan&, list: List) -> const u32[:] { return self.projectedSlice(self.old.extra, self.current.extra, list); }
fn children(self: Scan&, list: List) { for id in self.words(list) { self.node(id); } }
fn bindingList(self: Scan&, list: List) { for id in self.words(list) { self.binding(id); } }
fn reference(self: Scan&, ref: blot_check_core::BindingRef) { if ref.unit == 0 || ref.unit == self.old.unit { self.binding(ref.binding); } }
fn carries(self: Scan&, list: List) { for carry in self.projectedSlice(self.old.loop_carries, self.current.loop_carries, list) { self.binding(carry.incoming); self.binding(carry.iteration); self.binding(carry.backedge); self.binding(carry.outgoing); } }
fn erased(self: Scan&, id: u32) {
    var old_count: i64 = 0; var new_count: i64 = 0; for ref in self.old.erased_declaration_references { if ref.node == id { old_count++; } } for ref in self.current.erased_declaration_references { if ref.node == id { new_count++; } }
    if old_count != new_count { self.failure = Error.changed; return; } var at: i64 = 0;
    for old in self.old.erased_declaration_references { if old.node != id { continue; } while self.current.erased_declaration_references[at].node != id { at++; } if !blot_structural::equal(old, self.current.erased_declaration_references[at]) { self.failure = Error.changed; return; } self.reference(old.target); at++; }
}
fn scanNode(self: Scan&, id: u32) {
    let n = self.projectedItem(self.old.nodes, self.current.nodes, id); self.projectedItem(self.old.spans, self.current.spans, id); if self.failure != Error.none { return; }
    if self.old.isTagCall(id) != self.current.isTagCall(id) { self.failure = Error.changed; return; }
    if self.old.dispatch_signatures.len != 0 || self.current.dispatch_signatures.len != 0 { self.projectedItem(self.old.dispatch_signatures, self.current.dispatch_signatures, id); }
    if self.old.merge_ranges.len != 0 || self.current.merge_ranges.len != 0 { let list = self.projectedItem(self.old.merge_ranges, self.current.merge_ranges, id); for merge in self.projectedSlice(self.old.merges, self.current.merges, list) { self.node(merge.node); self.binding(merge.result); self.binding(merge.then_binding); self.binding(merge.else_binding); } }
    self.erased(id); if self.failure != Error.none { return; }
    match n.tag {
        blot_check_core::Tag.contract_method => { self.projectedItem(self.old.member_templates, self.current.member_templates, n.a); self.children(List { n.b, n.c }); },
        blot_check_core::Tag.task, blot_check_core::Tag.resource_acquire, blot_check_core::Tag.resource_release, blot_check_core::Tag.usage_share, blot_check_core::Tag.resource_scope,
        blot_check_core::Tag.usage_read, blot_check_core::Tag.usage_borrow, blot_check_core::Tag.package_pack, blot_check_core::Tag.package_unpack, blot_check_core::Tag.invalid => { self.failure = Error.changed; },
        blot_check_core::Tag.constant, blot_check_core::Tag.panic, blot_check_core::Tag.constructor_function, blot_check_core::Tag.type_constructor => {},
        blot_check_core::Tag.primitive_function => { self.projectedItem(self.old.primitives, self.current.primitives, n.a); },
        blot_check_core::Tag.reference => { self.reference(self.projectedItem(self.old.references, self.current.references, n.a)); },
        blot_check_core::Tag.staging, blot_check_core::Tag.scalar, blot_check_core::Tag.logical, blot_check_core::Tag.associated, blot_check_core::Tag.record_merge,
        blot_check_core::Tag.type_same, blot_check_core::Tag.effect_provider, blot_check_core::Tag.proof_guard => { self.node(n.a); self.node(n.b); },
        blot_check_core::Tag.handle => { self.node(n.a); self.node(n.b); if n.c != 0 { let effects = self.projectedItem(self.old.handle_effects, self.current.handle_effects, n.c - 1); self.node(effects.node); } },
        blot_check_core::Tag.call => { let call = self.projectedItem(self.old.calls, self.current.calls, n.a); self.reference(call.target); self.children(List { n.b, n.c }); },
        blot_check_core::Tag.block_, blot_check_core::Tag.suite, blot_check_core::Tag.product, blot_check_core::Tag.array, blot_check_core::Tag.array_op, blot_check_core::Tag.storage => { self.children(List { n.a, n.b }); },
        blot_check_core::Tag.record => { self.children(List { n.a, n.b }); self.words(List { n.c, n.b }); },
        blot_check_core::Tag.if_value, blot_check_core::Tag.if_stmt, blot_check_core::Tag.state_provider => { self.node(n.a); self.node(n.b); self.node(n.c); },
        blot_check_core::Tag.bind => { self.binding(n.a); self.node(n.b); },
        blot_check_core::Tag.return_ => { self.node(n.a); self.node(n.b); },
        blot_check_core::Tag.computation, blot_check_core::Tag.effect_scope, blot_check_core::Tag.result_associated => { self.node(n.a); },
        blot_check_core::Tag.project => { self.node(n.a); self.projection(n.b); },
        blot_check_core::Tag.construct => { self.node(n.b); },
        blot_check_core::Tag.closure => { let value = self.projectedItem(self.old.closures, self.current.closures, n.a); if self.failure != Error.none { return; } if self.closures { self.closures.push(n.a); } self.binding(value.qualifier); self.binding(value.parameter.binding); self.bindingList(value.captures); self.node(value.body); },
        blot_check_core::Tag.apply => { self.node(n.a); self.node(n.b); },
        blot_check_core::Tag.effect_reflection => { if n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.count) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.has) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.same) { self.node(n.b); self.node(n.c); } },
        blot_check_core::Tag.operation_value => { let value = self.projectedItem(self.old.operation_values, self.current.operation_values, n.a); self.node(value.witness); },
        blot_check_core::Tag.request_decision => { self.node(n.b); self.node(n.c); },
        blot_check_core::Tag.request_loop => { let value = self.projectedItem(self.old.request_loops, self.current.request_loops, n.a); if self.failure != Error.none { return; } self.node(value.computation); self.pattern(value.completion_pattern); self.node(value.completion_body); self.node(value.return_target); self.bindingList(value.completion_state_bindings); self.carries(value.carries); for arm in self.projectedSlice(self.old.request_arms, self.current.request_arms, value.arms) { self.node(arm.callback); self.node(arm.selector); } },
        blot_check_core::Tag.resolver_op => { let value = self.projectedItem(self.old.resolver_ops, self.current.resolver_ops, n.a); if self.failure != Error.none { return; } self.node(value.resolver); if value.method.binding != 0 { self.reference(value.method); } self.children(value.arguments); },
        blot_check_core::Tag.pattern_bind => { self.pattern(n.a); self.node(n.b); self.node(n.c); },
        blot_check_core::Tag.match_ => { let value = self.projectedItem(self.old.matches, self.current.matches, n.a); if self.failure != Error.none { return; } self.children(value.inputs); for arm in self.projectedSlice(self.old.match_arms, self.current.match_arms, value.arms) { self.node(arm.body); self.node(arm.guard); for row in self.projectedSlice(self.old.pattern_rows, self.current.pattern_rows, arm.rows) { for pattern in self.words(row.patterns) { self.pattern(pattern); } } } },
        blot_check_core::Tag.update => { let value = self.projectedItem(self.old.updates, self.current.updates, n.a); if self.failure != Error.none { return; } self.node(value.root); self.node(value.value); self.binding(value.self_binding); for projection in self.words(value.path) { self.projection(projection); } for step in self.projectedSlice(self.old.update_steps, self.current.update_steps, value.selectors) { match step.kind { blot_check_core::UpdateKind.field => { self.projection(step.projection); }, blot_check_core::UpdateKind.index => { self.node(step.index); } } } },
        blot_check_core::Tag.loop_ => { let value = self.projectedItem(self.old.loops, self.current.loops, n.a); if self.failure != Error.none { return; } self.node(value.first); self.node(value.end); self.node(value.body); self.pattern(value.pattern); self.carries(value.carries); },
        blot_check_core::Tag.break_ => { self.node(n.a); self.children(List { n.b, n.c }); },
    }
}
fn run(self: Scan&, binding_id: u32) {
    let binding = self.projectedItem(self.old.bindings, self.current.bindings, binding_id); if self.failure != Error.none { return; }
    if binding.kind != blot_check_check::Kind.global || binding.body_id == 0 { self.failure = Error.changed; return; }
    let body = self.projectedItem(self.old.bodies, self.current.bodies, binding.body_id); let recipe = self.projectedItem(self.old.declaration_dependencies, self.current.declaration_dependencies, binding.body_id); if self.failure != Error.none { return; }
    for ref in self.projectedSlice(self.old.dependency_references, self.current.dependency_references, recipe.references) { self.reference(ref); }
    self.projectedSlice(self.old.dependency_members, self.current.dependency_members, recipe.members); self.node(recipe.runtime_metadata); self.binding(binding_id); self.node(binding.initializer); self.node(body.root);
    for parameter in self.projectedSlice(self.old.parameters, self.current.parameters, body.parameters) { self.binding(parameter.binding); } self.drain();
}
fn drain(self: Scan&) {
    while self.workspace.count != 0 && self.failure == Error.none {
        self.workspace.count--; let work = self.workspace.work[self.workspace.count];
        match work {
            Work.node entry => { self.scanNode(entry.id); },
            Work.binding entry => {
                let id = entry.id; let value = self.referencedBinding(id); if self.failure != Error.none { return; } var shift: i64 = 0; if self.origins.len != 0 { shift = self.bindingShift(id); }
                if !shiftedPoint(self.old.sourceNamePoint(id), self.current.sourceNamePoint(id), shift) || !shiftedPoint(self.old.runtimeNamePoint(id), self.current.runtimeNamePoint(id), shift) { self.failure = Error.changed; return; }
                if value.kind == blot_check_check::Kind.local || value.kind == blot_check_check::Kind.parameter { self.node(value.initializer); }
            },
            Work.pattern entry => { let p = self.projectedItem(self.old.patterns, self.current.patterns, entry.id); if self.failure != Error.none { return; } match p.tag {
                blot_check_core::PatternTag.invalid => { self.failure = Error.changed; }, blot_check_core::PatternTag.wildcard, blot_check_core::PatternTag.constant => {},
                blot_check_core::PatternTag.bind => { self.binding(p.a); }, blot_check_core::PatternTag.value => { self.node(p.a); },
                blot_check_core::PatternTag.constructor, blot_check_core::PatternTag.record_payload => { self.pattern(p.b); }, blot_check_core::PatternTag.product => { for child in self.words(List { p.a, p.b }) { self.pattern(child); } },
            } },
            Work.projection entry => { let p = self.projectedItem(self.old.projections, self.current.projections, entry.id); self.projectedSlice(self.old.projection_variants, self.current.projection_variants, p.variants); },
        }
    }
}
fn referencedBinding(self: Scan&, id: u32) -> blot_check_core::Binding {
    if id >= self.old.bindings.len || id >= self.current.bindings.len { self.failure = Error.changed; return default<blot_check_core::Binding>(); }
    let before = self.old.bindings[id]; let after = self.current.bindings[id];
    if !self.constant_types && before.kind == blot_check_check::Kind.global && after.kind == blot_check_check::Kind.global && id < self.origins.len && self.origins[id] {
        var header = before; header.span = after.span; if !blot_structural::equal(header, after) { self.failure = Error.changed; return default<blot_check_core::Binding>(); }
        let old_body .= self.old.body(id); let new_body .= self.current.body(id); if !old_body || !new_body || !parameterHeadersEqual(self.old, old_body, self.current, new_body) { self.failure = Error.changed; return default<blot_check_core::Binding>(); } return before;
    }
    return self.projectedItem(self.old.bindings, self.current.bindings, id);
}
fn parameterHeadersEqual(old: const Module&, before: blot_check_core::Body, current: const Module&, after: blot_check_core::Body) -> bool {
    if before.is_function != after.is_function || before.parameters.len != after.parameters.len { return false; } let left = before.parameters; let right = after.parameters;
    if left.start > old.parameters.len || left.len > old.parameters.len - left.start || right.start > current.parameters.len || right.len > current.parameters.len - right.start { return false; }
    for a, index in old.parameters[left.start..left.start + left.len] { let b = current.parameters[right.start + index]; if a.binding != b.binding || a.ty != b.ty || a.inferred != b.inferred { return false; } } return true;
}
fn definitionEqual(old: const Module&, current: const Module&, binding: u32) -> bool, Error { return definitionEqualCollecting(old, current, binding, null); }
fn definitionEqualCollecting(old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?) -> bool, Error { return definitionMode(old, current, binding, closures, false, 0, null); }
fn constantDefinitionEqualCollecting(old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?) -> bool, Error { return definitionMode(old, current, binding, closures, true, 0, null); }
fn definitionMode(old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?, constant_types: bool, expression: u32, reached: u32[>..<]?) -> bool, Error {
    var workspace = init(old); let result, error = workspace.run(old, current, binding, closures, constant_types, expression, reached, []); workspace.deinit(); return result, error;
}
fn expressionNodes(old: const Module&, current: const Module&, root: u32) -> blot_support::Option<u32[:]>, Error {
    if root == 0 { return blot_support::none<u32[:]>(), Error.none; } var reached: u32[>..<] = [];
    let same, error = definitionMode(old, current, 0, null, false, root, reached); if error != Error.none || !same { return blot_support::none<u32[:]>(), error; }
    let owned = owned_words.alloc_slice(reached.len); for value, index in reached { owned[index] = value; } return blot_support::some(owned), Error.none;
}
fn equalConstantType(left: blot_check_core::Types, before: u32, right: blot_check_core::Types, after: u32) -> bool {
    if before >= left.nodes.len || after >= right.nodes.len { return false; } if before == after { return true; }
    let a = left.nodes[before]; let b = right.nodes[after]; if !blot_structural::equal(a, b) { return false; }
    match a.tag {
        blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never => { return true; },
        blot_check_types::Tag.array, blot_check_types::Tag.list, blot_check_types::Tag.cursor => {
            if a.a >= left.nodes.len || b.a >= right.nodes.len || a.b != 0 || a.c != 0 || !blot_structural::equal(left.nodes[a.a], right.nodes[b.a]) { return false; }
            match left.nodes[a.a].tag { blot_check_types::Tag.unit, blot_check_types::Tag.boolean, blot_check_types::Tag.unsigned32, blot_check_types::Tag.floating32, blot_check_types::Tag.never => { return true; }, _ => { return false; } }
        }, _ => { return false; },
    }
}

fn normalizePositions(old: blot_check_core::Parameter&, current: blot_check_core::Parameter, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::Binding&, current: blot_check_core::Binding, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::Body&, current: blot_check_core::Body, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::Pattern&, current: blot_check_core::Pattern, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::MatchArm&, current: blot_check_core::MatchArm, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::Obligation&, current: blot_check_core::Obligation, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn normalizePositions(old: blot_check_core::Diagnostic&, current: blot_check_core::Diagnostic, shift: i64) -> Error { return normalizePositions(old.span, current.span, shift); }

fn aliases(self: const Scan&, normalized: blot_check_core::Node&, after: blot_check_core::Node) -> bool { if !self.alias(normalized.ty, after.ty) { return false; } return true; }

fn aliases(self: const Scan&, normalized: blot_check_core::Parameter&, after: blot_check_core::Parameter) -> bool { if !self.alias(normalized.ty, after.ty) { return false; } return true; }

fn aliases(self: const Scan&, normalized: blot_check_core::Binding&, after: blot_check_core::Binding) -> bool { if !self.alias(normalized.ty, after.ty) { return false; } if !self.alias(normalized.scheme.root, after.scheme.root) { return false; } return true; }

fn aliases(self: const Scan&, normalized: blot_check_core::Body&, after: blot_check_core::Body) -> bool { if !self.alias(normalized.scheme.root, after.scheme.root) { return false; } return true; }

fn aliases(self: const Scan&, normalized: blot_check_core::Pattern&, after: blot_check_core::Pattern) -> bool { if !self.alias(normalized.ty, after.ty) { return false; } return true; }
