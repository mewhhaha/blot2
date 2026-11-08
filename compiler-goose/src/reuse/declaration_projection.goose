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
reusable[] var owned_origins:bool[>..]=[];
fn release(run: const u32[:]) { if run.len != 0 { owned_words.free_slice(run); } }
fn release(run: const Work[:]) { if run.len != 0 { owned_work.free_slice(run); } }
struct Workspace {
    nodes: u32[:] = default<u32[:]>(), bindings: u32[:] = default<u32[:]>(), patterns: u32[:] = default<u32[:]>(), projections: u32[:] = default<u32[:]>(),
    origins:bool[:]=default<bool[:]>(),
    generation: u32 = 0, scans: i64 = 0, visits: i64 = 0, work: Work[:] = default<Work[:]>(), count: i64 = 0,
}
fn init(old: const Module&) -> Workspace {
    var result = Workspace { nodes: owned_words.alloc_slice(old.nodes.len), bindings: owned_words.alloc_slice(old.bindings.len), patterns: owned_words.alloc_slice(old.patterns.len), projections: owned_words.alloc_slice(old.projections.len) , ..};
    result.clear(); return result;
}
fn clear(self_: Workspace&) { for &v in self_.nodes { v = 0; } for &v in self_.bindings { v = 0; } for &v in self_.patterns { v = 0; } for &v in self_.projections { v = 0; } self_.generation = 0; }
fn capacityBytes(self_: const Workspace&) -> i64 { return (self_.nodes.len + self_.bindings.len + self_.patterns.len + self_.projections.len) * 4 + self_.work.len * 5 + self_.origins.len; }
fn deinit(self_: Workspace&) { release(self_.nodes); release(self_.bindings); release(self_.patterns); release(self_.projections); release(self_.work); if self_.origins.len!=0 {owned_origins.free_slice(self_.origins);}self_ = Workspace {..}; }
fn withWorkspace<C,F>(old: const Module&, context: C) { var workspace = init(old); let result = F(context, workspace); workspace.deinit(); return result; }
// One immutable origin snapshot serves every definition in this module scan.
fn prepareOrigins(self_:Workspace&,values:const bool[:]) {
 assert(self_.origins.len==0);var any=false;for flag in values {if flag {any=true;break;}}if !any {return;}
 let snapshot=owned_origins.alloc_slice(values.len);for flag,index in values {snapshot[index]=flag;}self_.origins=snapshot;
}
fn definitionEqual(self_: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]? = null, constant_types: bool = false) -> bool, Error { return self_.run(old, current, binding, closures, constant_types, 0, null, []); }
fn definitionEqualWithOrigins(self_: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?, constant_types: bool) -> bool, Error {
    let admitted=selectedOrigins(binding,self_.origins); return self_.run(old, current, binding, closures, constant_types, 0, null, admitted);
}
fn run(self_: Workspace&, old: const Module&, current: const Module&, binding: u32, closures: u32[>..<]?, constant_types: bool, expression: u32, reached: u32[>..<]?, origins: const bool[:]) -> bool, Error {
    if binding == 0 && expression == 0 { return false, blot_error::Error.none; }
    assert(self_.nodes.len == old.nodes.len && self_.bindings.len == old.bindings.len && self_.patterns.len == old.patterns.len && self_.projections.len == old.projections.len);
    if self_.generation == 0xffffffff { self_.clear(); } self_.generation++; self_.scans++; self_.count = 0;
    var scan = Scan { workspace: self_, old: old, current: current, closures: closures, constant_types: constant_types, origins: origins , ..};
    if origins.len != 0 { scan.source_shift = current.sourceNamePoint(binding) as i64 - old.sourceNamePoint(binding) as i64; }
    if expression != 0 { scan.node(expression); scan.drain(); } else { scan.run(binding); }
    self_.visits += scan.visits;
    if scan.failure != blot_error::Error.none { if scan.failure == blot_error::Error.out_of_memory { return false, scan.failure; } return false, blot_error::Error.none; }
    if reached { for seen, id in self_.nodes { if seen == self_.generation { reached.push(id as u32); } } }
    return true, blot_error::Error.none;
}
struct Scan {
    workspace: Workspace&, old: const Module&, current: const Module&,
    visits: i64 = 0, closures: u32[>..<]? = null, constant_types: bool = false,
    origins: const bool[:] = default<const bool[:]>(), source_shift: i64 = 0, failure: Error = blot_error::Error.none,
}
fn bindingShift(self_: const Scan&, id: i64) -> i64 { if self_.old.bindings[id].kind != blot_reuse_principal_interface::Kind.global { return self_.source_shift; } if id >= self_.origins.len || !self_.origins[id] { return 0; } return self_.current.sourceNamePoint(id as u32) as i64 - self_.old.sourceNamePoint(id as u32) as i64; }
fn shiftedPoint(old: u32, current: u32, shift: i64) -> bool { return (old == 0 && current == 0) || current as i64 - old as i64 == shift; }
fn normalizePositions<T>(old: T&, current: T, shift: i64) -> Error { return blot_error::Error.none; }
fn normalizePositions(old: blot_check_core::Span&, current: blot_check_core::Span, shift: i64) -> Error {
    if old.start == 0 && old.end == 0 && current.start == 0 && current.end == 0 { return blot_error::Error.none; }
    if current.start as i64 - old.start as i64 != shift || current.end as i64 - old.end as i64 != shift { return blot_error::Error.changed; } old = current; return blot_error::Error.none;
}
fn normalizePositions(old: blot_check_core::Projection&, current: blot_check_core::Projection, shift: i64) -> Error { if !shiftedPoint(old.diagnostic_point, current.diagnostic_point, shift) { return blot_error::Error.changed; } old.diagnostic_point = current.diagnostic_point; return blot_error::Error.none; }
fn normalizePositions(old: blot_check_core::ClosureInfo&, current: blot_check_core::ClosureInfo, shift: i64) -> Error { return normalizePositions(old.parameter, current.parameter, shift); }
fn aliases<T>(self_: const Scan&, normalized: T&, after: T) -> bool { return true; }
fn alias(self_: const Scan&, before: u32&, after: u32) -> bool { if !self_.constant_types && before != after { return false; } if !equalConstantType(self_.old.types, before, self_.current.types, after) { return false; } before = after; return true; }
fn projectedItem<T>(self_: Scan&, left: const T[:], right: const T[:], id: i64) -> T {
    if self_.failure != blot_error::Error.none { return default<T>(); }
    if id < 0 || id >= left.len || id >= right.len { self_.failure = blot_error::Error.changed; return default<T>(); }
    var normalized = left[id];
    if !self_.constant_types && self_.origins.len == 0 { if !blot_structural::equal(normalized, right[id]) { self_.failure = blot_error::Error.changed; return default<T>(); } return normalized; }
    if self_.origins.len != 0 { let error = normalizeItemPositions(self_, normalized, right[id], id); if error != blot_error::Error.none { self_.failure = error; return default<T>(); } }
    if !self_.aliases(normalized, right[id]) || !blot_structural::equal(normalized, right[id]) { self_.failure = blot_error::Error.changed; return default<T>(); } return left[id];
}
fn normalizeItemPositions<T>(self_: const Scan&, before: T&, after: T, id: i64) -> Error { return normalizePositions(before, after, self_.source_shift); }
fn normalizeItemPositions(self_: const Scan&, before: blot_check_core::Binding&, after: blot_check_core::Binding, id: i64) -> Error { return normalizePositions(before, after, self_.bindingShift(id)); }
fn projectedSlice<T>(self_: Scan&, left: const T[:], right: const T[:], list: List) -> const T[:] {
    if self_.failure != blot_error::Error.none { return default<const T[:]>(); }
    if list.start > left.len || list.len > left.len - list.start || list.start > right.len || list.len > right.len - list.start { self_.failure = blot_error::Error.changed; return default<const T[:]>(); }
    let result = left[list.start..list.start + list.len];
    for before, index in result { var normalized = before; let after = right[list.start + index]; if self_.origins.len != 0 { let error = normalizePositions(normalized, after, self_.source_shift); if error != blot_error::Error.none { self_.failure = error; return default<const T[:]>(); } } if !blot_structural::equal(normalized, after) { self_.failure = blot_error::Error.changed; return default<const T[:]>(); } }
    return result;
}
fn enqueue(self_: Scan&, item: Work) {
    if self_.failure != blot_error::Error.none { return; } let seen,id,projection=selectedSeen(self_.workspace,item);
    if id == 0 && !projection { return; } if id >= seen.len { self_.failure = blot_error::Error.changed; return; } if seen[id] == self_.workspace.generation { return; }
    let w .= self_.workspace;
    if w.count == w.work.len {
        let minimum = w.count + 1; if minimum > 0x5555555555555540 { self_.failure = blot_error::Error.out_of_memory; return; }
        let next = minimum + minimum / 2 + 12; let run = owned_work.alloc_slice(next);
        for index in w.count { run[index] = w.work[index]; } release(w.work); w.work = run;
    }
    w.work[w.count] = item; w.count++; seen[id] = w.generation; self_.visits++;
}
fn node(self_: Scan&, id: u32) { self_.enqueue(Work.node { id , ..}); }
fn binding(self_: Scan&, id: u32) { self_.enqueue(Work.binding { id , ..}); }
fn pattern(self_: Scan&, id: u32) { self_.enqueue(Work.pattern { id , ..}); }
fn projection(self_: Scan&, id: u32) { self_.enqueue(Work.projection { id , ..}); }
fn words(self_: Scan&, list: List) -> const u32[:] { return self_.projectedSlice(self_.old.extra, self_.current.extra, list); }
fn children(self_: Scan&, list: List) { for id in self_.words(list) { self_.node(id); } }
fn bindingList(self_: Scan&, list: List) { for id in self_.words(list) { self_.binding(id); } }
fn reference(self_: Scan&, ref: blot_check_core::BindingRef) { if ref.unit == 0 || ref.unit == self_.old.unit { self_.binding(ref.binding); } }
fn carries(self_: Scan&, list: List) { for carry in self_.projectedSlice(self_.old.loop_carries, self_.current.loop_carries, list) { self_.binding(carry.incoming); self_.binding(carry.iteration); self_.binding(carry.backedge); self_.binding(carry.outgoing); } }
fn erased(self_: Scan&, id: u32) {
    var old_count: i64 = 0; var new_count: i64 = 0; for ref in self_.old.erased_declaration_references { if ref.node == id { old_count++; } } for ref in self_.current.erased_declaration_references { if ref.node == id { new_count++; } }
    if old_count != new_count { self_.failure = blot_error::Error.changed; return; } var at: i64 = 0;
    for old in self_.old.erased_declaration_references { if old.node != id { continue; } while self_.current.erased_declaration_references[at].node != id { at++; } if !blot_structural::equal(old, self_.current.erased_declaration_references[at]) { self_.failure = blot_error::Error.changed; return; } self_.reference(old.target); at++; }
}
fn scanNode(self_: Scan&, id: u32) {
    let n = self_.projectedItem(self_.old.nodes, self_.current.nodes, id); self_.projectedItem(self_.old.spans, self_.current.spans, id); if self_.failure != blot_error::Error.none { return; }
    if self_.old.isTagCall(id) != self_.current.isTagCall(id) { self_.failure = blot_error::Error.changed; return; }
    if self_.old.dispatch_signatures.len != 0 || self_.current.dispatch_signatures.len != 0 { self_.projectedItem(self_.old.dispatch_signatures, self_.current.dispatch_signatures, id); }
    if self_.old.merge_ranges.len != 0 || self_.current.merge_ranges.len != 0 { let list = self_.projectedItem(self_.old.merge_ranges, self_.current.merge_ranges, id); for merge in self_.projectedSlice(self_.old.merges, self_.current.merges, list) { self_.node(merge.node); self_.binding(merge.result); self_.binding(merge.then_binding); self_.binding(merge.else_binding); } }
    self_.erased(id); if self_.failure != blot_error::Error.none { return; }
    match n.tag {
        contract_method => { self_.projectedItem(self_.old.member_templates, self_.current.member_templates, n.a); self_.children(List { n.b, n.c , ..}); },
        task, resource_acquire, resource_release, usage_share, resource_scope,
        usage_read, usage_borrow, package_pack, package_unpack, invalid => { self_.failure = blot_error::Error.changed; },
        constant, panic, constructor_function, type_constructor => {},
        primitive_function => { self_.projectedItem(self_.old.primitives, self_.current.primitives, n.a); },
        reference => { self_.reference(self_.projectedItem(self_.old.references, self_.current.references, n.a)); },
        staging, scalar, logical, associated, record_merge,
        type_same, effect_provider, proof_guard => { self_.node(n.a); self_.node(n.b); },
        handle => { self_.node(n.a); self_.node(n.b); if n.c != 0 { let effects = self_.projectedItem(self_.old.handle_effects, self_.current.handle_effects, n.c - 1); self_.node(effects.node); } },
        call => { let call = self_.projectedItem(self_.old.calls, self_.current.calls, n.a); self_.reference(call.target); self_.children(List { n.b, n.c , ..}); },
        block_, suite, product, array, array_op, storage => { self_.children(List { n.a, n.b , ..}); },
        record => { self_.children(List { n.a, n.b , ..}); self_.words(List { n.c, n.b , ..}); },
        if_value, if_stmt, state_provider => { self_.node(n.a); self_.node(n.b); self_.node(n.c); },
        bind => { self_.binding(n.a); self_.node(n.b); },
        return_ => { self_.node(n.a); self_.node(n.b); },
        computation, effect_scope, result_associated => { self_.node(n.a); },
        project => { self_.node(n.a); self_.projection(n.b); },
        construct => { self_.node(n.b); },
        closure => { let value = self_.projectedItem(self_.old.closures, self_.current.closures, n.a); if self_.failure != blot_error::Error.none { return; } let closures .= self_.closures; if closures { closures.push(n.a); } self_.binding(value.qualifier); self_.binding(value.parameter.binding); self_.bindingList(value.captures); self_.node(value.body); },
        apply => { self_.node(n.a); self_.node(n.b); },
        effect_reflection => { if n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.count) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.has) || n.a == blot_check_check::reflectionKindCode(blot_check_check::ReflectionKind.same) { self_.node(n.b); self_.node(n.c); } },
        operation_value => { let value = self_.projectedItem(self_.old.operation_values, self_.current.operation_values, n.a); self_.node(value.witness); },
        request_decision => { self_.node(n.b); self_.node(n.c); },
        request_loop => { let value = self_.projectedItem(self_.old.request_loops, self_.current.request_loops, n.a); if self_.failure != blot_error::Error.none { return; } self_.node(value.computation); self_.pattern(value.completion_pattern); self_.node(value.completion_body); self_.node(value.return_target); self_.bindingList(value.completion_state_bindings); self_.carries(value.carries); for arm in self_.projectedSlice(self_.old.request_arms, self_.current.request_arms, value.arms) { self_.node(arm.callback); self_.node(arm.selector); } },
        resolver_op => { let value = self_.projectedItem(self_.old.resolver_ops, self_.current.resolver_ops, n.a); if self_.failure != blot_error::Error.none { return; } self_.node(value.resolver); if value.method.binding != 0 { self_.reference(value.method); } self_.children(value.arguments); },
        pattern_bind => { self_.pattern(n.a); self_.node(n.b); self_.node(n.c); },
        match_ => { let value = self_.projectedItem(self_.old.matches, self_.current.matches, n.a); if self_.failure != blot_error::Error.none { return; } self_.children(value.inputs); for arm in self_.projectedSlice(self_.old.match_arms, self_.current.match_arms, value.arms) { self_.node(arm.body); self_.node(arm.guard_); for row in self_.projectedSlice(self_.old.pattern_rows, self_.current.pattern_rows, arm.rows) { for pattern in self_.words(row.patterns) { self_.pattern(pattern); } } } },
        update => { let value = self_.projectedItem(self_.old.updates, self_.current.updates, n.a); if self_.failure != blot_error::Error.none { return; } self_.node(value.root); self_.node(value.value); self_.binding(value.self_binding); for projection in self_.words(value.path) { self_.projection(projection); } for step in self_.projectedSlice(self_.old.update_steps, self_.current.update_steps, value.selectors) { match step.kind { field => { self_.projection(step.projection); }, index => { self_.node(step.index); } } } },
        loop_ => { let value = self_.projectedItem(self_.old.loops, self_.current.loops, n.a); if self_.failure != blot_error::Error.none { return; } self_.node(value.first); self_.node(value.end); self_.node(value.body); self_.pattern(value.pattern); self_.carries(value.carries); },
        break_ => { self_.node(n.a); self_.children(List { n.b, n.c , ..}); },
    }
}
fn run(self_: Scan&, binding_id: u32) {
    let binding = self_.projectedItem(self_.old.bindings, self_.current.bindings, binding_id); if self_.failure != blot_error::Error.none { return; }
    if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 { self_.failure = blot_error::Error.changed; return; }
    let body = self_.projectedItem(self_.old.bodies, self_.current.bodies, binding.body_id); let recipe = self_.projectedItem(self_.old.declaration_dependencies, self_.current.declaration_dependencies, binding.body_id); if self_.failure != blot_error::Error.none { return; }
    for ref in self_.projectedSlice(self_.old.dependency_references, self_.current.dependency_references, recipe.references) { self_.reference(ref); }
    self_.projectedSlice(self_.old.dependency_members, self_.current.dependency_members, recipe.members); self_.node(recipe.runtime_metadata); self_.binding(binding_id); self_.node(binding.initializer); self_.node(body.root);
    for parameter in self_.projectedSlice(self_.old.parameters, self_.current.parameters, body.parameters) { self_.binding(parameter.binding); } self_.drain();
}
fn drain(self_: Scan&) {
    while self_.workspace.count != 0 && self_.failure == blot_error::Error.none {
        self_.workspace.count--; let work = self_.workspace.work[self_.workspace.count];
        match work {
            node entry => { self_.scanNode(entry.id); },
            binding entry => {
                let id = entry.id; let value = self_.referencedBinding(id); if self_.failure != blot_error::Error.none { return; } var shift: i64 = 0; if self_.origins.len != 0 { shift = self_.bindingShift(id); }
                if !shiftedPoint(self_.old.sourceNamePoint(id), self_.current.sourceNamePoint(id), shift) || !shiftedPoint(self_.old.runtimeNamePoint(id), self_.current.runtimeNamePoint(id), shift) { self_.failure = blot_error::Error.changed; return; }
                if value.kind == blot_reuse_principal_interface::Kind.local || value.kind == blot_reuse_principal_interface::Kind.parameter { self_.node(value.initializer); }
            },
            pattern entry => { let p = self_.projectedItem(self_.old.patterns, self_.current.patterns, entry.id); if self_.failure != blot_error::Error.none { return; } match p.tag {
                invalid => { self_.failure = blot_error::Error.changed; }, wildcard, constant => {},
                bind => { self_.binding(p.a); }, value => { self_.node(p.a); },
                constructor, record_payload => { self_.pattern(p.b); }, product => { for child in self_.words(List { p.a, p.b , ..}) { self_.pattern(child); } },
            } },
            projection entry => { let p = self_.projectedItem(self_.old.projections, self_.current.projections, entry.id); self_.projectedSlice(self_.old.projection_variants, self_.current.projection_variants, p.variants); },
        }
    }
}
fn referencedBinding(self_: Scan&, id: u32) -> blot_check_core::Binding {
    if id >= self_.old.bindings.len || id >= self_.current.bindings.len { self_.failure = blot_error::Error.changed; return default<blot_check_core::Binding>(); }
    let before = self_.old.bindings[id]; let after = self_.current.bindings[id];
    if !self_.constant_types && before.kind == blot_reuse_principal_interface::Kind.global && after.kind == blot_reuse_principal_interface::Kind.global && id < self_.origins.len && self_.origins[id] {
        var header = before; header.span = after.span; if !blot_structural::equal(header, after) { self_.failure = blot_error::Error.changed; return default<blot_check_core::Binding>(); }
        let old_body .= self_.old.body(id); let new_body .= self_.current.body(id); if !old_body || !new_body || !parameterHeadersEqual(self_.old, old_body, self_.current, new_body) { self_.failure = blot_error::Error.changed; return default<blot_check_core::Binding>(); } return before;
    }
    return self_.projectedItem(self_.old.bindings, self_.current.bindings, id);
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
    if root == 0 { return blot_support::none<u32[:]>(), blot_error::Error.none; } var reached: u32[>..<] = [];
    let same, error = definitionMode(old, current, 0, null, false, root, reached); if error != blot_error::Error.none || !same { return blot_support::none<u32[:]>(), error; }
    let owned = owned_words.alloc_slice(reached.len); for value, index in reached { owned[index] = value; } return blot_support::some(owned), blot_error::Error.none;
}
fn equalConstantType(left: blot_check_core::Types, before: u32, right: blot_check_core::Types, after: u32) -> bool {
    if before >= left.nodes.len || after >= right.nodes.len { return false; } if before == after { return true; }
    let a = left.nodes[before]; let b = right.nodes[after]; if !blot_structural::equal(a, b) { return false; }
    match a.tag {
        unit, boolean, unsigned32, floating32, never => { return true; },
        array, list, cursor => {
            if a.a >= left.nodes.len || b.a >= right.nodes.len || a.b != 0 || a.c != 0 || !blot_structural::equal(left.nodes[a.a], right.nodes[b.a]) { return false; }
            match left.nodes[a.a].tag { unit, boolean, unsigned32, floating32, never => { return true; }, _ => { return false; } }
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

fn aliases(self_: const Scan&, normalized: blot_check_core::Node&, after: blot_check_core::Node) -> bool { if !self_.alias(normalized.ty, after.ty) { return false; } return true; }

fn aliases(self_: const Scan&, normalized: blot_check_core::Parameter&, after: blot_check_core::Parameter) -> bool { if !self_.alias(normalized.ty, after.ty) { return false; } return true; }

fn aliases(self_: const Scan&, normalized: blot_check_core::Binding&, after: blot_check_core::Binding) -> bool { if !self_.alias(normalized.ty, after.ty) { return false; } if !self_.alias(normalized.scheme.root, after.scheme.root) { return false; } return true; }

fn aliases(self_: const Scan&, normalized: blot_check_core::Body&, after: blot_check_core::Body) -> bool { if !self_.alias(normalized.scheme.root, after.scheme.root) { return false; } return true; }

fn aliases(self_: const Scan&, normalized: blot_check_core::Pattern&, after: blot_check_core::Pattern) -> bool { if !self_.alias(normalized.ty, after.ty) { return false; } return true; }

fn selectedOrigins(binding:u32,origins:const bool[:])->const bool[:] {if binding<origins.len && origins[binding] {return origins;}return default<const bool[:]>();}
fn selectedSeen(workspace:Workspace&,item:Work)->u32[:],u32,bool {match item {node entry=>{return workspace.nodes,entry.id,false;},binding entry=>{return workspace.bindings,entry.id,false;},pattern entry=>{return workspace.patterns,entry.id,false;},projection entry=>{return workspace.projections,entry.id,true;},}}
