// Read-only execution keeps values, mutable locations and call edges distinct.
namespace blot_check_capability_lifetimes;
import reuse.principal_interface;

import check.check_packet_owner;
import check.cleanup_contracts;
import check.core;
import check.effect_evidence;
import check.frozen_core_scopes;
import check.generative_relocation;
import check.lifetime_report_pool;
import check.package_contracts;
import check.rank_equal;
import check.task_regions;
import check.task_types;
import check.types;
import eval.type_evidence;
import parse.ast;
import support.error;
import support.option;
import support.structural_adapters;

import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import support.structural;
type Error = blot_error::Error;
type Id = u32;
type Module = blot_check_core::Module;
type CoreId = blot_check_core::Id;
type Evidence = blot_eval_type_evidence::Store;
type Mapping = blot_eval_type_evidence::Mapping;
type OptionId = blot_support::Option<Id>;
struct Site { unit: u32 = 0, binding: u32 = 0, node: CoreId = 0 }
struct TypeOrigin { unit: u32, ty: blot_check_types::Id }
enum Kind { scalar, unknown, capability, product, record, wrapper, selection, callable, operation, provider, state_provider, cell, scope, activation, nominal, event, external }
struct Node {
    site: Site, context: u32 = 0, invocation: OptionId = blot_support::none<Id>(), closure: OptionId = blot_support::none<Id>(),
    kind: Kind, owner: Id, depth: u32, field: u32 = 0, contents: Id = 0, first_edge: OptionId = blot_support::none<Id>(),
    nominal: blot_check_types::NominalIdentity = blot_check_types::NominalIdentity { 0, 0 , ..}, target: blot_support::Option<Site>   = blot_support::none<Site>(),
    signature: blot_support::Option<TypeOrigin>   = blot_support::none<TypeOrigin>(), mappings: blot_check_core::List = blot_check_core::List {..}, actual_mappings: blot_check_core::List = blot_check_core::List {..},
}
enum EdgeKind { value, capture, store, result, call }
struct Edge { from: Id, to: Id, kind: EdgeKind, field: u32 = 0, next: OptionId = blot_support::none<Id>() }
struct Invocation { parent: OptionId, caller: Site, callable: Id }
struct Boundary { site: Site, owner: Id, result: Id }
struct Report {
    nodes: const Node[:], edges: const Edge[:], evidence: blot_eval_type_evidence::Snapshot,
    mappings: const Mapping[:], boundaries: const Boundary[:], invocations: const Invocation[:], complete: bool, work: i64,
    lease_index: u32 = 0, generation: u64 = 0,
}
struct Entry { binding: u32, value: Id, depth: u32 }
struct Environment { entries: Entry[256], len: i64 = 0, types: Mapping[64], type_len: i64 = 0 }
fn get(self_: const Environment&, binding: u32, remaining: i64&) -> blot_support::Option<Entry>, Error {
    var index = self_.len; while index != 0 { if remaining == 0 { return blot_support::none<Entry>(), blot_error::Error.analysis_limit; } remaining -= 1; index -= 1; if self_.entries[index].binding == binding { return blot_support::some(self_.entries[index]), blot_error::Error.none; } } return blot_support::none<Entry>(), blot_error::Error.none;
}
fn bind(self_: Environment&, binding: u32, value: Id, depth: u32) -> Error { if binding == 0 { return blot_error::Error.none; } if self_.len == self_.entries.len { return blot_error::Error.analysis_limit; } self_.entries[self_.len] = Entry { binding, value, depth , ..}; self_.len += 1; return blot_error::Error.none; }
struct ActiveCall { module: const Module&, body: CoreId, parent: const ActiveCall? }
enum Parameters { closure { catalog: u32 }, body { span: blot_check_core::List } }
struct Callable { value: Id, module: const Module&, binding: u32, body: CoreId, parameters: Parameters, environment: Environment, arguments: Id[16], count: i64 = 0, runtime: bool = false }
fn parameterCount(self_: const Callable&) -> i64 { match self_.parameters { closure match_payload_37 => { let catalog = match_payload_37.catalog;  return 1; }, body match_payload_38 => { let span = match_payload_38.span;  return span.len; }, } }
fn parameterAt(self_: const Callable&, index: i64) -> blot_check_core::Parameter { match self_.parameters { closure match_payload_35 => { let catalog = match_payload_35.catalog;  assert(index == 0); return self_.module.closures[catalog].parameter; }, body match_payload_36 => { let span = match_payload_36.span;  return self_.module.parameters[span.start + index]; }, } }
struct Operation { value: Id, module: const Module&, metadata: blot_check_core::OperationValue, receiver: Id, arguments: Id[16], argument_count: i64 = 0 }
struct Provider { read: Id, write: Id = 0, initial: Id, callback: Id = 0 }
struct ProviderEntry { value: Id, provider: Provider }
struct Frame { read: Id, write: Id, cell: Id, depth: u32, callback: Id, outer: i64 }
struct Exit { module: const Module&, target: CoreId, value: Id }
struct Control { module: const Module&, target: CoreId, depth: u32 }
struct Locations { before: const Id[:], joined: Id[:], started: bool = false }
fn locations(scan: Scan&, before: Id[>..]&, joined: Id[>..]&) -> Locations, Error {
    if scan.nodes.len > scan.remaining { return default<Locations>(), blot_error::Error.analysis_limit; } scan.remaining -= scan.nodes.len;
    for value in scan.nodes { before += value.contents; } joined.resize(before.len, 0); return Locations { before, joined , ..}, blot_error::Error.none;
}
fn reset(self_: Locations, scan: Scan&) -> Error { for slot, index in self_.before { let error = scan.step(0); if error != blot_error::Error.none { return error; } scan.nodes[index].contents = slot; } return blot_error::Error.none; }
fn collect(self_: Locations&, scan: Scan&, module: const Module&, source: CoreId) -> Error {
    for index in 0..self_.before.len { let error = scan.step(0); if error != blot_error::Error.none { return error; } let actual = scan.nodes[index].contents;
        if !self_.started || self_.joined[index] == actual { self_.joined[index] = actual; } else { let children: Id[2] = [self_.joined[index], actual]; let id, error = scan.aggregate(module, source, Kind.selection, children); if error != blot_error::Error.none { return error; } self_.joined[index] = id; }
    } self_.started = true; return blot_error::Error.none;
}
fn finish(self_: Locations, scan: Scan&) -> Error { if !self_.started { return blot_error::Error.none; } for slot, index in self_.joined { let error = scan.step(0); if error != blot_error::Error.none { return error; } scan.nodes[index].contents = slot; } return blot_error::Error.none; }
struct Tables {
    type_mappings: Mapping[>..<]&, nodes: Node[>..<]&, edges: Edge[>..<]&, boundaries: Boundary[>..<]&, invocations: Invocation[>..<]&, callables: Callable[>..<]&, operations: Operation[>..<]&, providers: ProviderEntry[>..<]&, frames: Frame[>..<]&, exits: Exit[>..<]&, controls: Control[>..<]&, checked_owners: (const Module&)[>..<]&,
}
struct Scan {
    module: const Module&, evidence: Evidence&, owners: const ModuleRef[:], type_mappings: Mapping[>..<]&, nodes: Node[>..<]&, edges: Edge[>..<]&, boundaries: Boundary[>..<]&, invocations: Invocation[>..<]&, context: u32 = 0,
    callables: Callable[>..<]&, operations: Operation[>..<]&, providers: ProviderEntry[>..<]&, frames: Frame[>..<]&, exits: Exit[>..<]&, controls: Control[>..<]&, remaining: i64 = 65536, owner: Id = 0, scope_depth: u32 = 0, binding: u32 = 0, complete: bool = true, scope_validation: bool = false, checked_owners: (const Module&)[>..<]&, active_calls: const ActiveCall? = null,
}
fn init(module: const Module&, owners: const ModuleRef[:], evidence: Evidence&, tables: Tables) -> Scan { return Scan { module: module, evidence: evidence, owners: owners, type_mappings: tables.type_mappings, nodes: tables.nodes, edges: tables.edges, boundaries: tables.boundaries, invocations: tables.invocations, callables: tables.callables, operations: tables.operations, providers: tables.providers, frames: tables.frames, exits: tables.exits, controls: tables.controls, checked_owners: tables.checked_owners , ..}; }
fn deinit(self_: Scan&) { self_.type_mappings.clear(); self_.nodes.clear(); self_.edges.clear(); self_.boundaries.clear(); self_.invocations.clear(); self_.callables.clear(); self_.operations.clear(); self_.providers.clear(); self_.frames.clear(); self_.exits.clear(); self_.controls.clear(); self_.checked_owners.clear(); }
fn step(self_: Scan&, depth: i64) -> Error { if self_.remaining == 0 || depth >= 128 { return blot_error::Error.analysis_limit; } self_.remaining -= 1; return blot_error::Error.none; }
fn site(self_: const Scan&, module: const Module&, source: CoreId) -> Site { return Site { module.unit, self_.binding, source , ..}; }
fn value(self_: Scan&, module: const Module&, source: CoreId, kind: Kind) -> Id, Error {
    let error = self_.step(0); if error != blot_error::Error.none { return 0, error; } if self_.nodes.len >= 4096 { return 0, blot_error::Error.analysis_limit; } let id = self_.nodes.len as u32;
    self_.nodes += Node { site: self_.site(module, source), context: self_.context, kind: kind, owner: self_.owner, depth: self_.scope_depth , ..}; return id, blot_error::Error.none;
}
fn mappings(self_: Scan&, values: const Mapping[:]) -> blot_check_core::List, Error {
    let error = self_.step(0); if error != blot_error::Error.none { return blot_check_core::List {..}, error; } if values.len > self_.remaining || self_.type_mappings.len > 65536 || values.len > 65536 - self_.type_mappings.len { return blot_check_core::List {..}, blot_error::Error.analysis_limit; }
    self_.remaining -= values.len; let start = self_.type_mappings.len as u32; self_.type_mappings += values; return blot_check_core::List { start, values.len as u32 , ..}, blot_error::Error.none;
}
fn edge(self_: Scan&, from: Id, to: Id, kind: EdgeKind, field: u32) -> Error {
    let error = self_.step(0); if error != blot_error::Error.none { return error; } if from >= self_.nodes.len || to >= self_.nodes.len { return blot_error::Error.invalid_artifact; } if self_.edges.len >= 65536 { return blot_error::Error.analysis_limit; }
    let index = self_.edges.len as u32; self_.edges += Edge { from, to, kind, field, self_.nodes[from].first_edge , ..}; self_.nodes[from].first_edge = blot_support::some(index); return blot_error::Error.none;
}
fn ownerModule(self_: Scan&, current: const Module&, unit: u32) -> const Module?, Error {
    if unit == 0 || unit == current.unit { return current, blot_error::Error.none; } var found: const Module? = null;
    for candidate_owner_ref in self_.owners { let candidate: const blot_check_core::Module&  = candidate_owner_ref.value; let error = self_.step(0); if error != blot_error::Error.none { return null, error; } if candidate.unit != unit { continue; } { let optional_binding_83 .= found; if optional_binding_83 { let prior .= optional_binding_83; if prior.owner_id == 0 || prior.owner_id != candidate.owner_id { return null, blot_error::Error.invalid_artifact; }  } } found .= candidate; }
    { let optional_binding_82 .= found; if optional_binding_82 { let selected .= optional_binding_82; for prior in self_.checked_owners { let error = self_.step(0); if error != blot_error::Error.none { return null, error; } if prior.owner_id != 0 && prior.owner_id == selected.owner_id { return selected, blot_error::Error.none; } }
        let error = blot_check_frozen_core_validation::validateBounds(selected, blot_check_frozen_core_validation::Context { units: self_.owners , ..}); if error != blot_error::Error.none { return null, error; } self_.checked_owners += selected; return selected, blot_error::Error.none;
     } } return null, blot_error::Error.unsupported;
}
fn node(self_: Scan&, module: const Module&, id: CoreId, depth: i64) -> blot_check_core::Node, Error { let error = self_.step(depth); if error != blot_error::Error.none { return default<blot_check_core::Node>(), error; } if id == 0 || id >= module.nodes.len || module.nodes[id].ty >= module.types.nodes.len { return default<blot_check_core::Node>(), blot_error::Error.invalid_artifact; } return module.nodes[id], blot_error::Error.none; }
fn span(self_: Scan&, module: const Module&, start: u32, len: u32) -> const u32[:], Error { let error = self_.step(0); if error != blot_error::Error.none { return default<const u32[:]>(), error; } if start > module.extra.len || len > module.extra.len - start { return default<const u32[:]>(), blot_error::Error.invalid_artifact; } return module.extra[start..start + len], blot_error::Error.none; }
fn reaches(self_: Scan&, root: Id, owner: OptionId, younger: blot_support::Option<u32>) -> bool, Error {
    if root >= self_.nodes.len { return false, blot_error::Error.invalid_artifact; } var pending: Id[4096]; var seen: bool[4096] = [false; 4096]; var len: i64 = 1; pending[0] = root; seen[root] = true;
    while len != 0 { len -= 1; let id = pending[len]; let current = self_.nodes[id]; let error = self_.step(0); if error != blot_error::Error.none { return false, error; }
        if current.kind == Kind.capability { if owner.present && current.owner == owner.value { return true, blot_error::Error.none; } if younger.present && current.depth > younger.value { return true, blot_error::Error.none; } }
        if current.kind == Kind.cell && !seen[current.contents] { seen[current.contents] = true; pending[len] = current.contents; len += 1; }
        var cursor = current.first_edge; while cursor.present { let error = self_.step(0); if error != blot_error::Error.none { return false, error; } let edge = self_.edges[cursor.value]; cursor = edge.next; if edge.kind == EdgeKind.call || edge.kind == EdgeKind.store || seen[edge.to] { continue; } seen[edge.to] = true; pending[len] = edge.to; len += 1; }
    } return false, blot_error::Error.none;
}
fn sink(self_: Scan&, module: const Module&, source: CoreId, arguments: const Id[:]) -> Id, Error {
    self_.complete = false; let result, error = self_.value(module, source, Kind.external); if error != blot_error::Error.none { return 0, error; }
    for argument in arguments { let error = self_.edge(result, argument, EdgeKind.store, 0); if error != blot_error::Error.none { return 0, error; } let escapes, error = self_.reaches(argument, blot_support::none<Id>(), blot_support::some(0 as u32)); if error != blot_error::Error.none { return 0, error; } if escapes { return 0, blot_error::Error.lifetime_escape; } } return result, blot_error::Error.none;
}
fn aggregate(self_: Scan&, module: const Module&, source: CoreId, kind: Kind, children: const Id[:]) -> Id, Error { let result, error = self_.value(module, source, kind); if error != blot_error::Error.none { return 0, error; } for child, index in children { let error = self_.edge(result, child, EdgeKind.value, index as u32); if error != blot_error::Error.none { return 0, error; } } return result, blot_error::Error.none; }
recursive fn select(self_: Scan&, module: const Module&, source: CoreId, value: Id, field: u32, depth: i64) -> Id, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if value >= self_.nodes.len { return 0, blot_error::Error.invalid_artifact; } let kind = self_.nodes[value].kind;
    if kind == Kind.selection { var alternatives: Id[256]; var len: i64 = 0; var cursor = self_.nodes[value].first_edge;
        while cursor.present { let item = self_.edges[cursor.value]; cursor = item.next; let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if item.kind != EdgeKind.value { continue; } if len == alternatives.len { return 0, blot_error::Error.analysis_limit; } let id, error = select(self_, module, source, item.to, field, depth + 1); if error != blot_error::Error.none { return 0, error; } alternatives[len] = id; len += 1; } return aggregate(self_, module, source, Kind.selection, alternatives[..len]);
    }
    var cursor = self_.nodes[value].first_edge; while cursor.present { let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } let item = self_.edges[cursor.value]; cursor = item.next; if item.field == field && item.kind == EdgeKind.value { return item.to, blot_error::Error.none; } }
    if kind == Kind.scalar { return 0, blot_error::Error.none; } let children: Id[1] = [value]; return aggregate(self_, module, source, Kind.unknown, children);
}
fn captureReference(self_: Scan&, module: const Module&, source: CoreId, environment: const Environment&, result: Id, depth: i64) -> Error {
    let n = module.node(source); if n.a >= module.references.len { return blot_error::Error.invalid_artifact; } let reference = module.references[n.a];
    if reference.unit == 0 || reference.unit == module.unit { let entry, error = environment.get(reference.binding, self_.remaining); if error != blot_error::Error.none { return error; }
        if entry.present { return self_.edge(result, entry.value.value, EdgeKind.capture, entry.value.binding); }
        if self_.scope_validation && reference.binding < module.bindings.len && (module.bindings[reference.binding].kind == blot_reuse_principal_interface::Kind.local || module.bindings[reference.binding].kind == blot_reuse_principal_interface::Kind.parameter) { var nested = environment; let actual, error = freeScopeValue(self_, module, reference.binding, nested, depth + 1); if error != blot_error::Error.none { return error; } return self_.edge(result, actual, EdgeKind.capture, reference.binding); }
    } return blot_error::Error.none;
}
fn capture(self_: Scan&, module: const Module&, source: CoreId, environment: const Environment&, result: Id, depth: i64) -> Error {
    let n, error = self_.node(module, source, depth); if error != blot_error::Error.none { return error; } if n.tag == blot_check_core::Tag.reference { return captureReference(self_, module, source, environment, result, depth); }
    let graph, error = blot_check_frozen_core_validation::initGraph(module); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return captureVertex(self_, module, graph, graph.vertex(blot_check_frozen_core_validation::Kind.node, source), environment, result, depth + 1);
}
recursive fn captureVertex(self_: Scan&, module: const Module&, graph: blot_check_frozen_core_validation::Graph, vertex: i64, environment: const Environment&, result: Id, depth: i64) -> Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return error; } let item = graph.item(vertex);
    if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 && module.nodes[item.id].tag == blot_check_core::Tag.reference { return captureReference(self_, module, item.id, environment, result, depth); }
    var slot: i64 = 0; while true { let child = graph.edge(vertex, slot); if !child.present { break; } slot += 1; let error = captureVertex(self_, module, graph, child.value, environment, result, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
recursive fn captureBindings(self_: Scan&, graph: blot_check_frozen_core_validation::Graph, vertex: i64, environment: Environment&, depth: i64) -> Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return error; } let item = graph.item(vertex);
    if item.kind == blot_check_frozen_core_validation::Kind.node && item.id != 0 { let n = graph.m.nodes[item.id]; if n.tag == blot_check_core::Tag.bind { let error = environment.bind(n.a, 0, self_.scope_depth); if error != blot_error::Error.none { return error; } } }
    else if item.kind == blot_check_frozen_core_validation::Kind.closure { let error = environment.bind(graph.m.closures[item.id].parameter.binding, 0, self_.scope_depth); if error != blot_error::Error.none { return error; } }
    else if item.kind == blot_check_frozen_core_validation::Kind.pattern && graph.m.patterns[item.id].tag == blot_check_core::PatternTag.bind { let error = environment.bind(graph.m.patterns[item.id].a, 0, self_.scope_depth); if error != blot_error::Error.none { return error; } }
    var slot: i64 = 0; while true { let child = graph.edge(vertex, slot); if !child.present { break; } slot += 1; let error = captureBindings(self_, graph, child.value, environment, depth + 1); if error != blot_error::Error.none { return error; } } return blot_error::Error.none;
}
fn closure(self_: Scan&, module: const Module&, source: CoreId, catalog: u32, environment: const Environment&, depth: i64) -> Id, Error {
    if catalog >= module.closures.len { return 0, blot_error::Error.invalid_artifact; } let closure = module.closures[catalog]; let result, error = self_.value(module, source, Kind.callable); if error != blot_error::Error.none { return 0, error; }
    let mappings, error = self_.mappings(environment.types[..environment.type_len]); if error != blot_error::Error.none { return 0, error; }
    self_.nodes[result].closure = blot_support::some(catalog); self_.nodes[result].target = blot_support::some(Site { module.unit, self_.binding, closure.body , ..}); self_.nodes[result].signature = blot_support::some(TypeOrigin { module.unit, module.nodes[source].ty , ..}); self_.nodes[result].mappings = mappings; self_.nodes[result].actual_mappings = mappings;
    if self_.scope_validation { var captures = environment; let error = captures.bind(closure.parameter.binding, 0, self_.scope_depth); if error != blot_error::Error.none { return 0, error; } let graph, error = blot_check_frozen_core_validation::initGraph(module); if error != blot_error::Error.none { return 0, blot_error::Error.invalid_artifact; }
        let error = captureBindings(self_, graph, graph.vertex(blot_check_frozen_core_validation::Kind.node, closure.body), captures, depth + 1); if error != blot_error::Error.none { return 0, error; }
        let error = capture(self_, module, closure.body, captures, result, depth + 1); if error != blot_error::Error.none { return 0, error; }
    } else { let error = capture(self_, module, closure.body, environment, result, depth + 1); if error != blot_error::Error.none { return 0, error; } }
    self_.callables += Callable { result, module, self_.binding, closure.body, Parameters.closure { catalog , ..}, environment , ..}; return result, blot_error::Error.none;
}
fn projectEvidence(self_: Scan&, module: const Module&, root: u32, environment: const Environment&) -> Id, Error {
    let id, error = self_.evidence.projectWithBudget(module.types, root, environment.types[..environment.type_len], [], self_.remaining); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return 0, error; } return 0, blot_error::Error.unsupported; } return id, blot_error::Error.none;
}
fn named(self_: Scan&, module: const Module&, source: CoreId, original: blot_check_core::BindingRef, actual: u32, environment: const Environment&) -> Id, Error {
    var producer: const Module&  = module; var target = original;
    for attempt in 0..128 { let error = self_.step(0); if error != blot_error::Error.none { return 0, error; } let owner, error = self_.ownerModule(producer, target.unit); if error != blot_error::Error.none { return 0, error; } { let optional_binding_81 .= owner; if optional_binding_81 { let owner .= optional_binding_81; producer .= owner;  } else { return 0, blot_error::Error.unsupported; } }
        if target.binding == 0 || target.binding >= producer.bindings.len { return 0, blot_error::Error.invalid_artifact; } let binding = producer.bindings[target.binding]; if binding.kind == blot_reuse_principal_interface::Kind.external { target = binding.target; continue; }
        if binding.kind != blot_reuse_principal_interface::Kind.global || binding.body_id == 0 || binding.body_id >= producer.bodies.len { return 0, blot_error::Error.unsupported; } let body = producer.bodies[binding.body_id]; if !body.is_function { return 0, blot_error::Error.unsupported; }
        if body.parameters.start > producer.parameters.len || body.parameters.len > producer.parameters.len - body.parameters.start || body.parameters.len > 16 { return 0, blot_error::Error.invalid_artifact; } var imported = Environment {..};
        if producer.types.node(binding.ty).tag == blot_check_types::Tag.forall {
            var views = blot_check_package_contracts::Context { types: module.types, remaining: self_.remaining , ..}; let error = views.initialize(); if error != blot_error::Error.none { return 0, error; }
            var instance = blot_check_package_contracts::Principal { left: producer.types, right: module.types, remaining: self_.remaining, views: views, foreign_views: true, left_rows: body.closed_rows, .. }; let error = instance.instantiate(binding.ty, actual); if error != blot_error::Error.none { return 0, error; }
            let quantifier = producer.types.node(binding.ty);
            for formal, index in producer.types.list(blot_check_types::List { quantifier.b, quantifier.c , ..}) { let error = self_.step(0); if error != blot_error::Error.none { return 0, error; } let witness = instance.witnesses[index]; if producer.types.node(formal).b != 0 || witness == 0 { continue; } if imported.type_len == imported.types.len { return 0, blot_error::Error.analysis_limit; }
                let evidence, error = projectEvidence(self_, module, witness, environment); if error != blot_error::Error.none { return 0, error; } imported.types[imported.type_len] = Mapping { formal, evidence , ..}; imported.type_len += 1;
            }
        } else {
            let relation, error = blot_check_generative_relocation::init(producer, module, binding.scheme, actual, actual, 0, 0); if error != blot_error::Error.none { return 0, blot_error::Error.invalid_artifact; } let spent = 65536 - relation.remaining; if spent > self_.remaining { return 0, blot_error::Error.analysis_limit; } self_.remaining -= spent;
            for index in 0..relation.len { let pair = relation.pairs[index]; let error = self_.step(0); if error != blot_error::Error.none { return 0, error; } if producer.types.node(pair.before).tag != blot_check_types::Tag.variable { continue; } if imported.type_len == imported.types.len { return 0, blot_error::Error.analysis_limit; }
                let evidence, error = projectEvidence(self_, module, pair.after, environment); if error != blot_error::Error.none { return 0, error; } imported.types[imported.type_len] = Mapping { pair.before, evidence , ..}; imported.type_len += 1;
            }
        }
        let result, error = self_.value(module, source, Kind.callable); if error != blot_error::Error.none { return 0, error; } let mappings, error = self_.mappings(imported.types[..imported.type_len]); if error != blot_error::Error.none { return 0, error; } let actual_mappings, error = self_.mappings(environment.types[..environment.type_len]); if error != blot_error::Error.none { return 0, error; }
        self_.nodes[result].target = blot_support::some(Site { producer.unit, body.binding, body.root , ..}); self_.nodes[result].signature = blot_support::some(TypeOrigin { module.unit, actual , ..}); self_.nodes[result].mappings = mappings; self_.nodes[result].actual_mappings = actual_mappings;
        self_.callables += Callable { value: result, module: producer, binding: body.binding, body: body.root, parameters: Parameters.body { body.parameters , ..}, environment: imported, runtime: body.runtime , ..}; return result, blot_error::Error.none;
    } return 0, blot_error::Error.analysis_limit;
}
fn operationEqual(self_: Scan&, left: Id, right: Id) -> bool, Error {
    if left == right { return true, blot_error::Error.none; } var lhs = blot_support::none<Operation>(); var rhs = blot_support::none<Operation>();
    for item in self_.operations { let error = self_.step(0); if error != blot_error::Error.none { return false, error; } if item.value == left { lhs = blot_support::some(item); } if item.value == right { rhs = blot_support::some(item); } }
    if !lhs.present || !rhs.present { return false, blot_error::Error.none; } let a = lhs.value; let b = rhs.value;
    if a.metadata.identity != b.metadata.identity || a.receiver != b.receiver || (a.receiver == 0 && a.metadata.instance != b.metadata.instance) || a.metadata.arguments.len != b.metadata.arguments.len { return false, blot_error::Error.none; }
    let error = self_.step(0); if error != blot_error::Error.none { return false, error; } return a.arguments[..a.argument_count] == b.arguments[..b.argument_count], blot_error::Error.none;
}
recursive fn invoke(self_: Scan&, module: const Module&, source: CoreId, function: Id, argument: Id, depth: i64) -> Id, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; }
    for operation in self_.operations { let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if operation.value != function { continue; } var index = self_.frames.len;
        while index != 0 { let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } index -= 1; let frame = self_.frames[index]; let same_read, error = operationEqual(self_, frame.read, function); if error != blot_error::Error.none { return 0, error; }
            if same_read {
                if frame.cell == 0 { let escapes, error = self_.reaches(argument, blot_support::none<Id>(), blot_support::some(0 as u32)); if error != blot_error::Error.none { return 0, error; } if escapes { return 0, blot_error::Error.lifetime_escape; }
                    var saved: Frame[>..] = []; saved += self_.frames[index..]; self_.frames.resize(index); let result, error = invoke(self_, module, source, frame.callback, argument, depth + 1); self_.frames += saved[..]; return result, error;
                }
                let call, error = self_.value(module, source, Kind.event); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, function, EdgeKind.call, 0); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, frame.cell, EdgeKind.call, 1); if error != blot_error::Error.none { return 0, error; } let result = self_.nodes[frame.cell].contents; let error = self_.edge(call, result, EdgeKind.result, 0); if error != blot_error::Error.none { return 0, error; } return result, blot_error::Error.none;
            }
            if frame.write != 0 { let same_write, error = operationEqual(self_, frame.write, function); if error != blot_error::Error.none { return 0, error; } if same_write {
                let escapes, error = self_.reaches(argument, blot_support::none<Id>(), blot_support::some(frame.depth)); if error != blot_error::Error.none { return 0, error; } if escapes { return 0, blot_error::Error.lifetime_escape; }
                let call, error = self_.value(module, source, Kind.event); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, function, EdgeKind.call, 0); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, frame.cell, EdgeKind.call, 1); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, argument, EdgeKind.call, 2); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(frame.cell, argument, EdgeKind.store, 0); if error != blot_error::Error.none { return 0, error; } self_.nodes[frame.cell].contents = argument; return 0, blot_error::Error.none;
            } }
        } let arguments: Id[2] = [function, argument]; return self_.sink(module, source, arguments);
    }
    for callable in self_.callables { let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if callable.value != function { continue; } var invocation = callable;
        if invocation.count >= parameterCount(invocation) || invocation.count == invocation.arguments.len { return 0, blot_error::Error.invalid_artifact; } invocation.arguments[invocation.count] = argument; invocation.count += 1;
        if invocation.count < parameterCount(invocation) { return partialCall(self_, module, source, callable, invocation, function, argument, depth); }
        if callable.runtime { return self_.sink(module, source, invocation.arguments[..invocation.count]); }
        var active .= self_.active_calls; while true { { let optional_binding_80 .= active; if optional_binding_80 { let prior .= optional_binding_80; let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if prior.module.owner_id != 0 && prior.module.owner_id == callable.module.owner_id && prior.body == callable.body { return 0, blot_error::Error.unsupported; } active .= prior.parent;  } else { break; } } }
        var current = ActiveCall { callable.module, callable.body, self_.active_calls , ..}; self_.active_calls .= current;
        let result, error = executeCall(self_, module, source, callable, invocation, function, depth); self_.active_calls .= current.parent; return result, error;
    } let arguments: Id[2] = [function, argument]; return self_.sink(module, source, arguments);
}
fn partialCall(self_: Scan&, module: const Module&, source: CoreId, callable: Callable, invocation: Callable, function: Id, argument: Id, depth: i64) -> Id, Error {
    let partial, error = self_.value(module, source, Kind.callable); if error != blot_error::Error.none { return 0, error; } var invocation = invocation; invocation.value = partial; let origin = self_.nodes[function]; self_.nodes[partial].target = origin.target; self_.nodes[partial].closure = origin.closure; self_.nodes[partial].signature = origin.signature; self_.nodes[partial].mappings = origin.mappings; self_.nodes[partial].actual_mappings = origin.actual_mappings;
    if self_.scope_validation {
        var captures = callable.environment; for ordinal in 0..parameterCount(invocation) { var actual: Id = 0; if ordinal < invocation.count { actual = invocation.arguments[ordinal]; } let error = captures.bind(parameterAt(invocation, ordinal).binding, actual, self_.scope_depth); if error != blot_error::Error.none { return 0, error; } }
        let graph, error = blot_check_frozen_core_validation::initGraph(callable.module); if error != blot_error::Error.none { return 0, blot_error::Error.invalid_artifact; } let error = captureBindings(self_, graph, graph.vertex(blot_check_frozen_core_validation::Kind.node, callable.body), captures, depth + 1); if error != blot_error::Error.none { return 0, error; }
        let error = capture(self_, callable.module, callable.body, captures, partial, depth + 1); if error != blot_error::Error.none { return 0, error; }
    } else { let error = self_.edge(partial, function, EdgeKind.capture, 0); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(partial, argument, EdgeKind.capture, 1); if error != blot_error::Error.none { return 0, error; } }
    self_.callables += invocation; return partial, blot_error::Error.none;
}
fn executeCall(self_: Scan&, module: const Module&, source: CoreId, callable: Callable, invocation: Callable, function: Id, depth: i64) -> Id, Error {
    var nested = callable.environment; for index in 0..parameterCount(invocation) { let error = nested.bind(parameterAt(invocation, index).binding, invocation.arguments[index], self_.scope_depth); if error != blot_error::Error.none { return 0, error; } }
    let call, error = self_.value(module, source, Kind.event); if error != blot_error::Error.none { return 0, error; } let error = self_.edge(call, function, EdgeKind.call, 0); if error != blot_error::Error.none { return 0, error; }
    for ordinal in 0..invocation.count { let error = self_.edge(call, invocation.arguments[ordinal], EdgeKind.call, (ordinal + 1) as u32); if error != blot_error::Error.none { return 0, error; } }
    let caller = self_.site(module, source); let saved_binding = self_.binding; let saved_context = self_.context; self_.context = self_.invocations.len as u32; self_.invocations += Invocation { blot_support::some(saved_context), caller, function , ..}; self_.nodes[call].invocation = blot_support::some(self_.context); self_.binding = callable.binding;
    let evaluated, error = expression(self_, callable.module, callable.body, nested, depth + 1); self_.binding = saved_binding; self_.context = saved_context; if error != blot_error::Error.none { return 0, error; }
    if !evaluated.present { self_.complete = false; } var result: Id = 0; if evaluated.present { result = evaluated.value; } let error = self_.edge(call, result, EdgeKind.result, 0); if error != blot_error::Error.none { return 0, error; } return result, blot_error::Error.none;
}
recursive fn pattern(self_: Scan&, module: const Module&, id: u32, origin: Id, environment: Environment&, depth: i64) -> Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return error; } if id == 0 || id >= module.patterns.len { return blot_error::Error.invalid_artifact; } let pattern_value = module.patterns[id];
    match pattern_value.tag {
        wildcard, constant => {},
        bind => { return environment.bind(pattern_value.a, origin, self_.scope_depth); },
        record_payload => { if pattern_value.b != 0 { return pattern(self_, module, pattern_value.b, origin, environment, depth + 1); } },
        constructor => { if pattern_value.b != 0 { let selected, error = self_.select(module, 0, origin, 0, depth + 1); if error != blot_error::Error.none { return error; } return pattern(self_, module, pattern_value.b, selected, environment, depth + 1); } },
        product => {
            if pattern_value.ty >= module.types.nodes.len { return blot_error::Error.invalid_artifact; } let shape = module.types.node(pattern_value.ty); if shape.tag == blot_check_types::Tag.record && (shape.a > module.types.extra.len || shape.b > (module.types.extra.len - shape.a) / 2) { return blot_error::Error.invalid_artifact; }
            let children, error = self_.span(module, pattern_value.a, pattern_value.b); if error != blot_error::Error.none { return error; } for child, index in children { var field = index as u32; if shape.tag == blot_check_types::Tag.record { if index >= shape.b { return blot_error::Error.invalid_artifact; } field = module.types.extra[shape.a + index * 2]; }
                let selected, error = self_.select(module, 0, origin, field, depth + 1); if error != blot_error::Error.none { return error; } let error = pattern(self_, module, child, selected, environment, depth + 1); if error != blot_error::Error.none { return error; }
            }
        },
        _ => { return blot_error::Error.unsupported; },
    } return blot_error::Error.none;
}
fn branches(self_: Scan&, module: const Module&, source: CoreId, first: CoreId, second: CoreId, environment: const Environment&, depth: i64) -> OptionId, Error {
    var before: Id[>..] = []; var joined: Id[>..] = []; var locations, error = locations(self_, before, joined); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    var left = environment; let lhs, error = expression(self_, module, first, left, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = locations.collect(self_, module, source); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let error = locations.reset(self_); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var right = environment; var rhs = blot_support::some(0 as Id);
    if second != 0 { let result, error = expression(self_, module, second, right, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } rhs = result; }
    let error = locations.collect(self_, module, source); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = locations.finish(self_); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    if !lhs.present { return rhs, blot_error::Error.none; } if !rhs.present { return lhs, blot_error::Error.none; } let values: Id[2] = [lhs.value, rhs.value]; let id, error = self_.aggregate(module, source, Kind.selection, values); return blot_support::some(id), error;
}
recursive fn matches(self_: Scan&, module: const Module&, pattern_id: u32, origin: Id, environment: Environment&, start: i64, depth: i64) -> bool, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return false, error; } if pattern_id == 0 || pattern_id >= module.patterns.len || origin >= self_.nodes.len { return false, blot_error::Error.invalid_artifact; } let pattern_value = module.patterns[pattern_id]; let actual = self_.nodes[origin];
    if actual.kind == Kind.selection { var matched = false; var cursor = actual.first_edge; while cursor.present { let error = self_.step(depth); if error != blot_error::Error.none { return false, error; } let edge = self_.edges[cursor.value]; cursor = edge.next; if edge.kind != EdgeKind.value { continue; } let result, error = matches(self_, module, pattern_id, edge.to, environment, start, depth + 1); if error != blot_error::Error.none { return false, error; } matched = result || matched; } return matched, blot_error::Error.none; }
    match pattern_value.tag {
        wildcard, constant, value => { return true, blot_error::Error.none; },
        bind => { for index in start..environment.len { let error = self_.step(depth); if error != blot_error::Error.none { return false, error; } let entry: Entry&  = environment.entries[index]; if entry.binding != pattern_value.a { continue; } if entry.value != origin { let values: Id[2] = [entry.value, origin]; let id, error = self_.aggregate(module, 0, Kind.selection, values); if error != blot_error::Error.none { return false, error; } entry.value = id; } return true, blot_error::Error.none; } let error = environment.bind(pattern_value.a, origin, self_.scope_depth); return error == blot_error::Error.none, error; },
        constructor => {
            if pattern_value.a >= module.constructors.len { return false, blot_error::Error.invalid_artifact; } let constructor = module.constructors[pattern_value.a]; if constructor.nominal >= module.nominals.len { return false, blot_error::Error.invalid_artifact; }
            if actual.kind == Kind.nominal && (actual.nominal != module.nominals[constructor.nominal].identity || actual.field != constructor.tag) { return false, blot_error::Error.none; } if actual.kind != Kind.nominal { return false, blot_error::Error.unsupported; } if pattern_value.b == 0 { return true, blot_error::Error.none; }
            let selected, error = self_.select(module, 0, origin, 0, depth + 1); if error != blot_error::Error.none { return false, error; } return matches(self_, module, pattern_value.b, selected, environment, start, depth + 1);
        },
        record_payload => { if pattern_value.b == 0 { return true, blot_error::Error.none; } return matches(self_, module, pattern_value.b, origin, environment, start, depth + 1); },
        product => {
            if pattern_value.ty >= module.types.nodes.len { return false, blot_error::Error.invalid_artifact; } let shape = module.types.node(pattern_value.ty); if shape.tag == blot_check_types::Tag.record && (shape.a > module.types.extra.len || shape.b > (module.types.extra.len - shape.a) / 2) { return false, blot_error::Error.invalid_artifact; }
            let children, error = self_.span(module, pattern_value.a, pattern_value.b); if error != blot_error::Error.none { return false, error; }
            for child, index in children { var field = index as u32; if shape.tag == blot_check_types::Tag.record { if index >= shape.b { return false, blot_error::Error.invalid_artifact; } field = module.types.extra[shape.a + index * 2]; }
                let selected, error = self_.select(module, 0, origin, field, depth + 1); if error != blot_error::Error.none { return false, error; } let result, error = matches(self_, module, child, selected, environment, start, depth + 1); if error != blot_error::Error.none || !result { return result, error; }
            } return true, blot_error::Error.none;
        },
        invalid => { return false, blot_error::Error.invalid_artifact; },
    }
}
fn freeScopeValue(self_: Scan&, module: const Module&, binding_id: u32, environment: Environment&, depth: i64) -> Id, Error {
    let error = self_.step(depth); if error != blot_error::Error.none { return 0, error; } if binding_id == 0 || binding_id >= module.bindings.len { return 0, blot_error::Error.invalid_artifact; } let binding = module.bindings[binding_id];
    if binding.initializer != 0 { let initial, error = self_.node(module, binding.initializer, depth + 1); if error != blot_error::Error.none { return 0, error; }
        match initial.tag { constant, type_constructor, reference, closure, record, product, array, construct => {}, _ => { return 0, blot_error::Error.unsupported; }, }
        let actual, error = expression(self_, module, binding.initializer, environment, depth + 1); if error != blot_error::Error.none { return 0, error; } if !actual.present { return 0, blot_error::Error.unsupported; } let error = environment.bind(binding_id, actual.value, 0); return actual.value, error;
    }
    let tag = module.types.node(binding.ty).tag; let primitive = tag == blot_check_types::Tag.unit || tag == blot_check_types::Tag.boolean || tag == blot_check_types::Tag.unsigned32 || tag == blot_check_types::Tag.floating32 || tag == blot_check_types::Tag.never; var actual: Id = 0;
    if !primitive { self_.complete = false; let id, error = self_.value(module, 0, Kind.unknown); if error != blot_error::Error.none { return 0, error; } actual = id; } let error = environment.bind(binding_id, actual, 0); return actual, error;
}
fn sameType(self_: Scan&, module: const Module&, left: u32, right: u32) -> bool, Error {
    if left >= module.types.nodes.len || right >= module.types.nodes.len { return false, blot_error::Error.invalid_artifact; } let result, error = blot_check_rank_equal::equalWithBudget(module.types, left, right, true, self_.remaining); if error != blot_error::Error.none { if self_.remaining == 0 { return false, blot_error::Error.analysis_limit; } return false, blot_error::Error.invalid_artifact; } return result, blot_error::Error.none;
}
fn resourceClosure(self_: Scan&, module: const Module&, source: CoreId, kind: blot_check_types::UsageKind, depth: i64) -> blot_check_types::Node, Error {
    let n, error = self_.node(module, source, depth); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; } if n.tag != blot_check_core::Tag.closure { return default<blot_check_types::Node>(), blot_error::Error.unsupported; }
    if n.a >= module.closures.len || n.op != blot_check_core::Op.none || n.b != 0 || n.c != 0 { return default<blot_check_types::Node>(), blot_error::Error.invalid_artifact; } let wrapper = module.types.node(n.ty);
    if wrapper.tag != blot_check_types::Tag.usage || wrapper.b != blot_check_types::usageCode(kind) || wrapper.c != 0 || wrapper.a >= module.types.nodes.len { return default<blot_check_types::Node>(), blot_error::Error.invalid_artifact; }
    let arrow = module.types.node(wrapper.a); let closure = module.closures[n.a]; let body, error = self_.node(module, closure.body, depth + 1); if error != blot_error::Error.none { return default<blot_check_types::Node>(), error; }
    if arrow.tag != blot_check_types::Tag.function { return arrow, blot_error::Error.invalid_artifact; } let equal, error = sameType(self_, module, arrow.a, closure.parameter.ty); if error != blot_error::Error.none || !equal { return arrow, blot_error::Error.invalid_artifact; }
    if body.ty != blot_check_types::never { let equal, error = sameType(self_, module, body.ty, arrow.b); if error != blot_error::Error.none || !equal { return arrow, blot_error::Error.invalid_artifact; } } return arrow, blot_error::Error.none;
}
fn resource(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    let acquire, error = resourceClosure(self_, module, n.a, blot_parse_ast::usagekind_once, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let release, error = resourceClosure(self_, module, n.b, blot_parse_ast::usagekind_cleanup, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let callback, error = resourceClosure(self_, module, n.c, blot_parse_ast::usagekind_once, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    if acquire.a != blot_check_types::unit || acquire.b >= module.types.nodes.len || release.b != blot_check_types::unit || callback.a >= module.types.nodes.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let equal, error = sameType(self_, module, release.a, acquire.b); if error != blot_error::Error.none || !equal { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let equal, error = sameType(self_, module, callback.b, n.ty); if error != blot_error::Error.none || !equal { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let owner = module.types.node(acquire.b); let loan = module.types.node(callback.a); if owner.tag != blot_check_types::Tag.usage || owner.b != blot_parse_ast::usagekind_unique || owner.c != 0 || owner.a >= module.types.nodes.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let payload = module.types.node(owner.a); if payload.tag != blot_check_types::Tag.unit && payload.tag != blot_check_types::Tag.boolean && payload.tag != blot_check_types::Tag.unsigned32 && payload.tag != blot_check_types::Tag.floating32 { return blot_support::none<Id>(), blot_error::Error.unsupported; }
    if payload.a != 0 || payload.b != 0 || payload.c != 0 || loan.tag != blot_check_types::Tag.usage || loan.b != blot_parse_ast::usagekind_borrow_mut || loan.a != owner.a || loan.c == 0 || loan.c >= module.types.nodes.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let region = module.types.node(loan.c); if region.tag != blot_check_types::Tag.bound || region.a != 0 || region.b != 2 || region.c != module.closures[module.node(n.c).a].parameter.binding { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } if release.c != 0 { return blot_support::none<Id>(), blot_error::Error.unsupported; }
    let error = blot_check_cleanup_contracts::immutableScalarWithBudget(module, n.b, self_.remaining); if error != blot_error::Error.none { if self_.remaining == 0 { return blot_support::none<Id>(), blot_error::Error.analysis_limit; } return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let acquisition, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !acquisition.present { return acquisition, error; } let cleanup, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !cleanup.present { return cleanup, error; } let body, error = expression(self_, module, n.c, environment, depth + 1); if error != blot_error::Error.none || !body.present { return body, error; }
    let acquired, error = invoke(self_, module, n.a, acquisition.value, 0, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if acquired != 0 { return blot_support::none<Id>(), blot_error::Error.unsupported; }
    let resource_owner, error = self_.value(module, source, Kind.scope); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.scope_depth += 1;
    let result, error = resourceBody(self_, module, source, n, body.value, cleanup.value, acquired, resource_owner, depth); self_.scope_depth -= 1; return result, error;
}
fn resourceBody(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, body: Id, cleanup: Id, acquired: Id, owner: Id, depth: i64) -> OptionId, Error {
    let borrowed, error = self_.value(module, source, Kind.capability); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.nodes[borrowed].owner = owner;
    let result, error = invoke(self_, module, n.c, body, borrowed, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let cleaned, error = invoke(self_, module, n.b, cleanup, acquired, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if cleaned != 0 { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let escapes, error = self_.reaches(result, blot_support::some(owner), blot_support::none<u32>()); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if escapes { return blot_support::none<Id>(), blot_error::Error.lifetime_escape; }
    self_.boundaries += Boundary { self_.site(module, source), owner, result , ..}; return blot_support::some(result), blot_error::Error.none;
}
fn taskScope(self_: Scan&, module: const Module&, source: CoreId, callback_id: CoreId, environment: Environment&, depth: i64) -> OptionId, Error {
    let callback, error = self_.node(module, callback_id, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    if callback.tag != blot_check_core::Tag.closure && !blot_check_task_types::scopeCallback(module.types, callback.ty).present { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    let function, error = expression(self_, module, callback_id, environment, depth + 1); if error != blot_error::Error.none || !function.present { return function, error; }
    if self_.nodes[function.value].kind == Kind.unknown && blot_check_task_types::scopeCallback(module.types, callback.ty).present { self_.complete = false; let values: Id[1] = [function.value]; let result, error = self_.aggregate(module, source, Kind.unknown, values); return blot_support::some(result), error; }
    let saved_owner = self_.owner; let owner, error = self_.value(module, source, Kind.scope); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.owner = owner; self_.scope_depth += 1;
    let result, error = taskScopeBody(self_, module, source, callback_id, function.value, owner, depth); self_.scope_depth -= 1; self_.owner = saved_owner; return result, error;
}
fn taskScopeBody(self_: Scan&, module: const Module&, source: CoreId, callback_id: CoreId, function: Id, owner: Id, depth: i64) -> OptionId, Error {
    let capability, error = self_.value(module, callback_id, Kind.capability); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let result, error = invoke(self_, module, callback_id, function, capability, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let escapes, error = self_.reaches(result, blot_support::some(owner), blot_support::none<u32>()); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if escapes { return blot_support::none<Id>(), blot_error::Error.lifetime_escape; } self_.boundaries += Boundary { self_.site(module, source), owner, result , ..}; return blot_support::some(result), blot_error::Error.none;
}
fn taskReceive(self_: Scan&, module: const Module&, source: CoreId, input: Id, collect: bool) -> Id, Error {
    if !collect { if input >= self_.nodes.len || self_.nodes[input].kind != Kind.wrapper { return 0, blot_error::Error.unsupported; } return self_.nodes[input].contents, blot_error::Error.none; }
    if input >= self_.nodes.len || self_.nodes[input].kind != Kind.product { return 0, blot_error::Error.unsupported; } let result, error = self_.value(module, source, Kind.product); if error != blot_error::Error.none { return 0, error; } var next = self_.nodes[input].first_edge;
    while next.present { let item = self_.edges[next.value]; next = item.next; let handle = self_.nodes[item.to]; if handle.kind != Kind.wrapper { return 0, blot_error::Error.unsupported; } let error = self_.edge(result, handle.contents, EdgeKind.value, item.field); if error != blot_error::Error.none { return 0, error; } } return result, blot_error::Error.none;
}
recursive fn expression(self_: Scan&, module: const Module&, source: CoreId, environment: Environment&, depth: i64) -> OptionId, Error {
    let n, error = self_.node(module, source, depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    match n.tag {
        constant, type_constructor => { return blot_support::some(0 as Id), blot_error::Error.none; },
        type_same, proof_guard => {
            let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let value, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } return blot_support::some(0 as Id), blot_error::Error.none;
        },
        reference => {
            if n.a >= module.references.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let reference = module.references[n.a];
            if reference.unit == 0 || reference.unit == module.unit { let entry, error = environment.get(reference.binding, self_.remaining); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if entry.present { return blot_support::some(entry.value.value), blot_error::Error.none; }
                if self_.scope_validation && reference.binding < module.bindings.len && (module.bindings[reference.binding].kind == blot_reuse_principal_interface::Kind.local || module.bindings[reference.binding].kind == blot_reuse_principal_interface::Kind.parameter) { let id, error = freeScopeValue(self_, module, reference.binding, environment, depth + 1); return blot_support::some(id), error; }
            } let id, error = named(self_, module, source, reference, n.ty, environment); return blot_support::some(id), error;
        },
        scalar => {
            if n.c != 0 { return blot_support::none<Id>(), blot_error::Error.unsupported; } let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; }
            if n.b != 0 { let value, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } } return blot_support::some(0 as Id), blot_error::Error.none;
        },
        logical => { let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } return branches(self_, module, source, n.b, 0, environment, depth + 1); },
        closure => { let id, error = closure(self_, module, source, n.a, environment, depth); return blot_support::some(id), error; },
        apply => {
            let function, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !function.present { return function, error; } let argument, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !argument.present { return argument, error; }
            let result, error = invoke(self_, module, source, function.value, argument.value, depth + 1); return blot_support::some(result), error;
        },
        call => {
            if n.a >= module.calls.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let call = module.calls[n.a]; var function, error = named(self_, module, source, call.target, call.callee_type, environment); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
            let arguments, error = self_.span(module, n.b, n.c); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
            for argument in arguments { let actual, error = expression(self_, module, argument, environment, depth + 1); if error != blot_error::Error.none || !actual.present { return actual, error; } let id, error = invoke(self_, module, source, function, actual.value, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } function = id; } return blot_support::some(function), blot_error::Error.none;
        },
        operation_value => { return operationValue(self_, module, source, n, environment, depth); },
        effect_provider, state_provider => { return providerValue(self_, module, source, n, environment, depth); },
        handle => { return handleValue(self_, module, source, n, environment, depth); },
        effect_scope => { return taskScope(self_, module, source, n.a, environment, depth); },
        task => { return taskValue(self_, module, source, n, environment, depth); },
        resource_scope => { return resource(self_, module, source, n, environment, depth + 1); },
        computation, usage_share, usage_read => { let result, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !result.present { return result, error; } if n.tag == blot_check_core::Tag.usage_read { return blot_support::some(0 as Id), blot_error::Error.none; } return result, blot_error::Error.none; },
        product, array, record => { return aggregateValue(self_, module, source, n, environment, depth); },
        construct => {
            if n.a >= module.constructors.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let constructor = module.constructors[n.a]; if n.a == 0 || (constructor.payload == 0) != (n.b == 0) || constructor.nominal >= module.nominals.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
            let result, error = self_.value(module, source, Kind.nominal); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.nodes[result].nominal = module.nominals[constructor.nominal].identity; self_.nodes[result].field = constructor.tag;
            if n.b != 0 { let child, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !child.present { return child, error; } let error = self_.edge(result, child.value, EdgeKind.value, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } } return blot_support::some(result), blot_error::Error.none;
        },
        package_pack => { let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let values: Id[1] = [value.value]; let id, error = self_.aggregate(module, source, Kind.wrapper, values); return blot_support::some(id), error; },
        project => {
            if n.b >= module.projections.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let projection = module.projections[n.b]; var field = projection.field;
            if field == 0 { if projection.variants.len != 1 || projection.variants.start >= module.projection_variants.len { return blot_support::none<Id>(), blot_error::Error.unsupported; } field = module.projection_variants[projection.variants.start].field; }
            let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let result, error = self_.select(module, source, value.value, field, depth + 1); return blot_support::some(result), error;
        },
        if_value, if_stmt => { let value, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } return branches(self_, module, source, n.b, n.c, environment, depth + 1); },
        match_ => { return matchValue(self_, module, source, n, environment, depth); },
        block_, suite => { return blockValue(self_, module, source, n, environment, depth); },
        pattern_bind => { if n.c != 0 { return blot_support::none<Id>(), blot_error::Error.unsupported; } let result, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !result.present { return result, error; } let error = pattern(self_, module, n.a, result.value, environment, depth + 1); return blot_support::some(0 as Id), error; },
        bind => { let result, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !result.present { return result, error; } let error = environment.bind(n.a, result.value, self_.scope_depth); return blot_support::some(0 as Id), error; },
        return_ => {
            let result, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !result.present { return result, error; } var target_depth = blot_support::none<u32>();
            for control in self_.controls { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if control.module.owner_id != 0 && control.module.owner_id == module.owner_id && control.target == n.b { target_depth = blot_support::some(control.depth); } }
            if !target_depth.present { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let escapes, error = self_.reaches(result.value, blot_support::none<Id>(), target_depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if escapes { return blot_support::none<Id>(), blot_error::Error.lifetime_escape; }
            self_.exits += Exit { module, n.b, result.value , ..}; return blot_support::none<Id>(), blot_error::Error.none;
        },
        panic => { return blot_support::none<Id>(), blot_error::Error.none; },
        _ => { return blot_support::none<Id>(), blot_error::Error.unsupported; },
    }
}
fn operationValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    if n.a >= module.operation_values.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let metadata = module.operation_values[n.a];
    if metadata.witness != 0 { let value, error = expression(self_, module, metadata.witness, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } }
    var receiver: Id = 0; if metadata.capability != 0 { let value, error = expression(self_, module, metadata.capability, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } receiver = value.value; }
    let result, error = self_.value(module, source, Kind.operation); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = self_.edge(result, receiver, EdgeKind.capture, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    var operation = Operation { result, module, metadata, receiver , ..}; let arguments = metadata.arguments;
    if arguments.len > operation.arguments.len || arguments.start > module.types.extra.len || arguments.len > module.types.extra.len - arguments.start { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    for argument, index in module.types.extra[arguments.start..arguments.start + arguments.len] { let evidence, error = projectEvidence(self_, module, argument, environment); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } operation.arguments[index] = evidence; }
    operation.argument_count = arguments.len; self_.operations += operation; return blot_support::some(result), blot_error::Error.none;
}
fn providerValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    let read, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !read.present { return read, error; } let second, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !second.present { return second, error; }
    var initial: Id = 0; var kind = Kind.provider; var write: Id = 0; var callback = second.value;
    if n.tag == blot_check_core::Tag.state_provider { let value, error = expression(self_, module, n.c, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } initial = value.value; kind = Kind.state_provider; write = second.value; callback = 0; }
    let values: Id[3] = [read.value, second.value, initial]; let result, error = self_.aggregate(module, source, kind, values); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    self_.providers += ProviderEntry { result, Provider { read.value, write, initial, callback , ..} , ..}; return blot_support::some(result), blot_error::Error.none;
}
fn handleValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    let provider, error = expression(self_, module, n.a, environment, depth + 1); if error != blot_error::Error.none || !provider.present { return provider, error; } var definition = blot_support::none<Provider>();
    for item in self_.providers { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if item.value == provider.value { definition = blot_support::some(item.provider); break; } } if !definition.present { return blot_support::none<Id>(), blot_error::Error.unsupported; }
    let mark = self_.frames.len; let result, error = handleBody(self_, module, source, n, environment, definition.value, mark, depth); self_.frames.resize(mark); return result, error;
}
fn handleBody(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, definition: Provider, mark: i64, depth: i64) -> OptionId, Error {
    var cell: Id = 0; if definition.write != 0 { let id, error = self_.value(module, source, Kind.cell); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } cell = id; self_.nodes[cell].contents = definition.initial; }
    self_.frames += Frame { definition.read, definition.write, cell, self_.scope_depth, definition.callback, mark , ..};
    let result, error = expression(self_, module, n.b, environment, depth + 1); if error != blot_error::Error.none || !result.present { return result, error; } if cell == 0 { return result, blot_error::Error.none; } let values: Id[2] = [self_.nodes[cell].contents, result.value]; let id, error = self_.aggregate(module, source, Kind.product, values); return blot_support::some(id), error;
}
fn aggregateValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    var kind = Kind.product; if n.tag == blot_check_core::Tag.record { kind = Kind.record; } let result, error = self_.value(module, source, kind); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let children, error = self_.span(module, n.a, n.b); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } var record = blot_check_types::Node { blot_check_types::Tag.absent , ..};
    if n.tag == blot_check_core::Tag.record { record = module.types.node(n.ty); if record.tag != blot_check_types::Tag.record || record.a > module.types.extra.len || record.b > (module.types.extra.len - record.a) / 2 { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let fields, error = self_.span(module, n.c, n.b); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    for child, index in children { var field = index as u32; if n.tag == blot_check_core::Tag.record { let destination = module.extra[n.c + index]; if destination >= record.b { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } field = module.types.extra[record.a + destination * 2]; }
        let value, error = expression(self_, module, child, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let error = self_.edge(result, value.value, EdgeKind.value, field); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    } return blot_support::some(result), blot_error::Error.none;
}
fn taskValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    let operation, error = blot_check_task_types::opFromCode(n.c); if error != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let operands = module.children(source);
    match operation {
        scope => { return taskScope(self_, module, source, operands[0], environment, depth); },
        spawn => { let group, error = expression(self_, module, operands[0], environment, depth + 1); if error != blot_error::Error.none || !group.present { return group, error; } let thunk, error = expression(self_, module, operands[1], environment, depth + 1); if error != blot_error::Error.none || !thunk.present { return thunk, error; }
            let result, error = invoke(self_, module, source, thunk.value, 0, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let values: Id[2] = [group.value, result]; let handle, error = self_.aggregate(module, source, Kind.wrapper, values); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.nodes[handle].contents = result; return blot_support::some(handle), blot_error::Error.none;
        },
        join, cancel, receive => {
            let handle, error = expression(self_, module, operands[0], environment, depth + 1); if error != blot_error::Error.none || !handle.present { return handle, error; }
            if operation == blot_check_task_types::Op.cancel { let result, error = self_.value(module, source, Kind.scalar); return blot_support::some(result), error; }
            let result, error = taskReceive(self_, module, source, handle.value, operation == blot_check_task_types::Op.receive && self_.nodes[handle.value].kind == Kind.product); return blot_support::some(result), error;
        },
        collect => { let input, error = expression(self_, module, operands[0], environment, depth + 1); if error != blot_error::Error.none || !input.present { return input, error; } let result, error = taskReceive(self_, module, source, input.value, true); return blot_support::some(result), error; },
        split => { return splitValue(self_, module, source, operands, environment, depth); },
        read, write => {
            let value, error = expression(self_, module, operands[0], environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let value, error = expression(self_, module, operands[1], environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; }
            if operation == blot_check_task_types::Op.write { let value, error = expression(self_, module, operands[2], environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } let escapes, error = self_.reaches(value.value, blot_support::none<Id>(), blot_support::some(0 as u32)); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if escapes { return blot_support::none<Id>(), blot_error::Error.lifetime_escape; } return blot_support::some(0 as Id), blot_error::Error.none; }
            let ty = module.types.node(n.ty); if ty.tag == blot_check_types::Tag.unit || ty.tag == blot_check_types::Tag.boolean || ty.tag == blot_check_types::Tag.unsigned32 || ty.tag == blot_check_types::Tag.floating32 { return blot_support::some(0 as Id), blot_error::Error.none; } return blot_support::none<Id>(), blot_error::Error.unsupported;
        },
    }
}
fn splitValue(self_: Scan&, module: const Module&, source: CoreId, operands: const CoreId[:], environment: Environment&, depth: i64) -> OptionId, Error {
    let owner_value, error = expression(self_, module, operands[0], environment, depth + 1); if error != blot_error::Error.none || !owner_value.present { return owner_value, error; }
    let plan, error = blot_check_task_regions::partition(module, source); if error != blot_error::Error.none { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let saved_owner = self_.owner; let owner, error = self_.value(module, source, Kind.scope); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.owner = owner; self_.scope_depth += 1;
    let result, error = splitBody(self_, module, source, operands, environment, owner_value.value, owner, plan.len, depth); self_.scope_depth -= 1; self_.owner = saved_owner; return result, error;
}
fn splitBody(self_: Scan&, module: const Module&, source: CoreId, operands: const CoreId[:], environment: Environment&, owner_value: Id, owner: Id, count: i64, depth: i64) -> OptionId, Error {
    let arguments, error = self_.value(module, source, Kind.product); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    for ordinal in 0..count { let view, error = self_.value(module, source, Kind.capability); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } self_.nodes[view].contents = owner_value; let error = self_.edge(view, owner_value, EdgeKind.value, 0); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let error = self_.edge(arguments, view, EdgeKind.value, ordinal as u32); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
    let callback, error = expression(self_, module, operands[2], environment, depth + 1); if error != blot_error::Error.none || !callback.present { return callback, error; } let result, error = invoke(self_, module, source, callback.value, arguments, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    let escapes, error = self_.reaches(result, blot_support::some(owner), blot_support::none<u32>()); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if escapes { return blot_support::none<Id>(), blot_error::Error.lifetime_escape; } let values: Id[2] = [owner_value, result]; let id, error = self_.aggregate(module, source, Kind.product, values); return blot_support::some(id), error;
}
fn matchValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: Environment&, depth: i64) -> OptionId, Error {
    if n.a >= module.matches.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let info = module.matches[n.a];
    if info.inputs.len > 16 || info.arms.start > module.match_arms.len || info.arms.len > module.match_arms.len - info.arms.start { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
    var inputs: Id[16]; let sources, error = self_.span(module, info.inputs.start, info.inputs.len); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    for input, index in sources { let value, error = expression(self_, module, input, environment, depth + 1); if error != blot_error::Error.none || !value.present { return value, error; } inputs[index] = value.value; }
    var before: Id[>..] = []; var joined: Id[>..] = []; var locations, error = locations(self_, before, joined); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    var values: Id[256]; var count: i64 = 0;
    for arm in module.match_arms[info.arms.start..info.arms.start + info.arms.len] { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if arm.guard_ != 0 { return blot_support::none<Id>(), blot_error::Error.unsupported; }
        if arm.rows.start > module.pattern_rows.len || arm.rows.len > module.pattern_rows.len - arm.rows.start { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } var nested = environment; var possible = false;
        for row in module.pattern_rows[arm.rows.start..arm.rows.start + arm.rows.len] { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if row.patterns.len != info.inputs.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; }
            var alternative = environment; var matched = true; let patterns, error = self_.span(module, row.patterns.start, row.patterns.len); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
            for pattern, index in patterns { let result, error = matches(self_, module, pattern, inputs[index], alternative, environment.len, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } matched = result && matched; } if !matched { continue; }
            for entry in alternative.entries[environment.len..alternative.len] { var found .= false;
                for index in environment.len..nested.len { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let prior: Entry&  = nested.entries[index]; if prior.binding != entry.binding { continue; }
                    if prior.value != entry.value { let children: Id[2] = [prior.value, entry.value]; let id, error = self_.aggregate(module, source, Kind.selection, children); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } prior.value = id; } found .= true; break;
                } if !found { let error = nested.bind(entry.binding, entry.value, entry.depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } }
            } possible = true;
        }
        if !possible { continue; } let error = locations.reset(self_); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
        let result, error = expression(self_, module, arm.body, nested, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if result.present { if count == values.len { return blot_support::none<Id>(), blot_error::Error.analysis_limit; } values[count] = result.value; count += 1; }
        let error = locations.collect(self_, module, source); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    }
    let error = locations.finish(self_); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if count == 0 { return blot_support::none<Id>(), blot_error::Error.none; } if count == 1 { return blot_support::some(values[0]), blot_error::Error.none; }
    let result, error = self_.aggregate(module, source, Kind.selection, values[..count]); return blot_support::some(result), error;
}
fn blockValue(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, environment: const Environment&, depth: i64) -> OptionId, Error {
    var nested = environment; self_.controls += Control { module, source, self_.scope_depth , ..}; let mark = self_.exits.len;
    let result, error = blockBody(self_, module, source, n, nested, mark, depth); self_.controls.resize(self_.controls.len - 1); return result, error;
}
fn blockBody(self_: Scan&, module: const Module&, source: CoreId, n: blot_check_core::Node, nested: Environment&, mark: i64, depth: i64) -> OptionId, Error {
    var current = blot_support::some(0 as Id); let children, error = self_.span(module, n.a, n.b); if error != blot_error::Error.none { return blot_support::none<Id>(), error; }
    for child in children { if !current.present { break; } let result, error = expression(self_, module, child, nested, depth + 1); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } current = result; }
    var results: Id[256]; var len: i64 = 0; if current.present { results[0] = current.value; len = 1; } var index = mark;
    while index < self_.exits.len { let error = self_.step(depth); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } let exit = self_.exits[index];
        if exit.module.owner_id != 0 && exit.module.owner_id == module.owner_id && exit.target == source { if len == results.len { return blot_support::none<Id>(), blot_error::Error.analysis_limit; } results[len] = exit.value; len += 1; self_.exits[index] = self_.exits[self_.exits.len - 1]; self_.exits.resize(self_.exits.len - 1); }
        else { index += 1; }
    }
    if len == 0 { return blot_support::none<Id>(), blot_error::Error.none; } if len == 1 { return blot_support::some(results[0]), blot_error::Error.none; } let result, error = self_.aggregate(module, source, Kind.selection, results[..len]); return blot_support::some(result), error;
}
fn takeReport(scan: Scan&, initial: i64) -> Report, Error {
    let evidence = blot_eval_type_evidence::Snapshot { owner_id: scan.evidence.owner_id, nodes: scan.evidence.nodes.items, extra: scan.evidence.extra.items, effects: blot_check_effect_evidence::Snapshot { scan.evidence.effects.operations.items, scan.evidence.effects.arguments.items, scan.evidence.effects.rows.items, scan.evidence.effects.labels.items, scan.evidence.effects.owner_id , ..}, quantifier_goals: scan.evidence.quantifier_goals.items, quantifier_obligations: scan.evidence.quantifier_obligations.items , ..};
    return blot_check_lifetime_report_pool::own(Report { scan.nodes[..], scan.edges[..], evidence, scan.type_mappings[..], scan.boundaries[..], scan.invocations[..], scan.complete, initial - scan.remaining , ..});
}
fn deinit(self_: Report&) { let error = blot_check_lifetime_report_pool::deinit(self_); assert(error == blot_error::Error.none); }
struct ScanScope<C,F> { module: const Module&, owners: const ModuleRef[:], context: C& }
fn withScan<C,F>(module: const Module&, owners: const ModuleRef[:], context: C&) -> Error { var scope = ScanScope<C,F> { module, owners, context , ..}; return blot_eval_type_evidence::withStore<ScanScope<C,F>>(scope,scanScope); }
fn scanScope<C,F>(scope: ScanScope<C,F>&, evidence: Evidence&) -> Error {
    var type_mappings: Mapping[>..<] = []; var nodes: Node[>..<] = []; var edges: Edge[>..<] = []; var boundaries: Boundary[>..<] = []; var invocations: Invocation[>..<] = []; var callables: Callable[>..<] = []; var operations: Operation[>..<] = []; var providers: ProviderEntry[>..<] = []; var frames: Frame[>..<] = []; var exits: Exit[>..<] = []; var controls: Control[>..<] = []; var checked_owners: (const Module&)[>..<] = [];
    var scan = init(scope.module, scope.owners, evidence, Tables { type_mappings, nodes, edges, boundaries, invocations, callables, operations, providers, frames, exits, controls, checked_owners , ..}); let error = F(scope.context, scan); deinit(scan); return error;
}
struct Analysis { boundary: blot_check_core::BindingRef, remaining: i64 = 65536, scope: CoreId = 0, scope_only: bool = false, report: blot_support::Option<Report>   = blot_support::none<Report>() }
fn ownerContext(module: const Module&, owners: const ModuleRef[:], all: ModuleRef[>..]&, remaining: i64&) -> Error {
    all.push(ModuleRef{value:module});
    for owner_owner_ref in owners { let owner: const blot_check_core::Module&  = owner_owner_ref.value; if owner.owner_id != 0 && owner.owner_id == module.owner_id { continue; } for prior in all { let error = reportStep(remaining); if error != blot_error::Error.none { return error; } if prior.value.unit == owner.unit { return blot_error::Error.invalid_artifact; } } all.push(ModuleRef{value:owner}); } return blot_error::Error.none;
}
fn analyze(module: const Module&, owners: const ModuleRef[:], boundary: blot_check_core::BindingRef) -> Report, Error {
    var all: ModuleRef[>..] = []; var context = Analysis { boundary , ..}; let error = ownerContext(module, owners, all, context.remaining); if error != blot_error::Error.none { return default<Report>(), error; }
    let error = blot_check_frozen_core_validation::validateBounds(module, blot_check_frozen_core_validation::Context { units: all , ..}); if error != blot_error::Error.none { return default<Report>(), error; }
    let error = withScan<Analysis>(module, all, context,analyzeScan); if error != blot_error::Error.none { return default<Report>(), error; } if !context.report.present { return default<Report>(), blot_error::Error.invalid_artifact; } return context.report.value, blot_error::Error.none;
}
fn analyzeScan(context: Analysis&, scan: Scan&) -> Error {
    scan.remaining = context.remaining; scan.scope_validation = context.scope_only; let initial = scan.remaining;
    let error = executeAnalysis(context, scan); context.remaining = scan.remaining; if error != blot_error::Error.none { return error; }
    var origin: i64 = 65536; if context.scope_only { origin = initial; } let report, error = takeReport(scan, origin); if error != blot_error::Error.none { return error; } context.report = blot_support::some(report); return blot_error::Error.none;
}
fn executeAnalysis(context: Analysis&, scan: Scan&) -> Error {
    if context.scope_only { scan.invocations += Invocation { blot_support::none<Id>(), Site { unit: scan.module.unit, node: context.scope , ..}, 0 , ..}; let zero, error = scan.value(scan.module, 0, Kind.scalar); if error != blot_error::Error.none { return error; }
        var environment = Environment {..}; let result, error = expression(scan, scan.module, context.scope, environment, 0); if error != blot_error::Error.none { return error; } if scan.exits.len != 0 { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
    }
    scan.invocations += Invocation { blot_support::none<Id>(), Site { unit: scan.module.unit, binding: context.boundary.binding , ..}, 0 , ..}; let zero, error = scan.value(scan.module, 0, Kind.scalar); if error != blot_error::Error.none { return error; } scan.binding = context.boundary.binding;
    let optional_owner, error = scan.ownerModule(scan.module, context.boundary.unit); if error != blot_error::Error.none { return error; }
    { let optional_binding_79 .= optional_owner; if optional_binding_79 { let owner .= optional_binding_79;
        if context.boundary.binding == 0 || context.boundary.binding >= owner.bindings.len { return blot_error::Error.invalid_artifact; } let binding = owner.bindings[context.boundary.binding]; if binding.body_id == 0 || binding.body_id >= owner.bodies.len { return blot_error::Error.invalid_artifact; } let body = owner.bodies[binding.body_id];
        if body.parameters.start > owner.parameters.len || body.parameters.len > owner.parameters.len - body.parameters.start { return blot_error::Error.invalid_artifact; } var environment = Environment {..};
        for parameter in owner.parameters[body.parameters.start..body.parameters.start + body.parameters.len] { let unknown, error = scan.value(owner, body.root, Kind.unknown); if error != blot_error::Error.none { return error; } let error = environment.bind(parameter.binding, unknown, 0); if error != blot_error::Error.none { return error; } }
        let activation, error = scan.value(owner, body.root, Kind.activation); if error != blot_error::Error.none { return error; } scan.owner = activation;
        let result, error = expression(scan, owner, body.root, environment, 0); if error != blot_error::Error.none { return error; } if !result.present || scan.exits.len != 0 { return blot_error::Error.invalid_artifact; } scan.boundaries += Boundary { scan.site(owner, body.root), scan.owner, result.value , ..}; return blot_error::Error.none;
     } } return blot_error::Error.invalid_artifact;
}
fn analyzeScope(module: const Module&, owners: const ModuleRef[:], root: CoreId, remaining: i64&) -> Report, Error {
    if root == 0 || root >= module.nodes.len || !isScope(module.node(root)) { return default<Report>(), blot_error::Error.invalid_artifact; }
    var all: ModuleRef[>..] = []; let error = ownerContext(module, owners, all, remaining); if error != blot_error::Error.none { return default<Report>(), error; }
    let error = blot_check_frozen_core_validation::validateBounds(module, blot_check_frozen_core_validation::Context { units: all , ..}); if error != blot_error::Error.none { return default<Report>(), error; }
    var context = Analysis { boundary: blot_check_core::BindingRef {..}, remaining: remaining, scope: root, scope_only: true , ..}; let error = withScan<Analysis>(module, all, context,analyzeScan); remaining = context.remaining; if error != blot_error::Error.none { return default<Report>(), error; }
    if !context.report.present { return default<Report>(), blot_error::Error.invalid_artifact; } return context.report.value, blot_error::Error.none;
}
struct RejectContext { remaining: i64 }
fn rejectSupportedEscapes(module: const Module&, owners: const ModuleRef[:]) -> Error {
    var active = false; for node in module.nodes { if isScope(node) { active = true; break; } } if !active { return blot_error::Error.none; }
    var all: ModuleRef[>..] = []; var context = RejectContext { 65536 , ..}; let error = ownerContext(module, owners, all, context.remaining); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
    let error = blot_check_frozen_core_validation::validateBounds(module, blot_check_frozen_core_validation::Context { units: all , ..}); if error != blot_error::Error.none { return error; } let error = withScan<RejectContext>(module, all, context,rejectScan); if error == blot_error::Error.out_of_memory { return error; } if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return blot_error::Error.none;
}
fn rejectScan(context: RejectContext&, scan: Scan&) -> Error {
    scan.remaining = context.remaining; scan.scope_validation = true;
    for n, id in scan.module.nodes { if !isScope(n) { continue; } let error = scan.step(0); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
        scan.nodes.clear(); scan.edges.clear(); scan.callables.clear(); scan.operations.clear(); scan.providers.clear(); scan.frames.clear(); scan.exits.clear(); scan.controls.clear(); scan.invocations.clear(); scan.type_mappings.clear(); scan.complete = true;
        let zero, error = scan.value(scan.module, 0, Kind.scalar); if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.invalid_artifact; }
        var environment = Environment {..}; let result, error = expression(scan, scan.module, id as u32, environment, 0); if error == blot_error::Error.unsupported { continue; } if error == blot_error::Error.out_of_memory { return error; } if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; }
    } return blot_error::Error.none;
}
fn rejectSupportedEscapesWithScratch(module: const Module&, owners: const ModuleRef[:]) -> Error { let error = rejectSupportedEscapes(module, owners); if error != blot_error::Error.none { return blot_error::Error.invalid_artifact; } return blot_error::Error.none; }
fn reportStep(remaining: i64&) -> Error { if remaining == 0 { return blot_error::Error.analysis_limit; } remaining -= 1; return blot_error::Error.none; }
fn callArgument(report: const Report&, event: Id, field: u32, remaining: i64&) -> OptionId, Error {
    if event >= report.nodes.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } var edge = report.nodes[event].first_edge;
    while edge.present { let error = reportStep(remaining); if error != blot_error::Error.none { return blot_support::none<Id>(), error; } if edge.value >= report.edges.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } let item = report.edges[edge.value]; if item.from != event || item.to >= report.nodes.len { return blot_support::none<Id>(), blot_error::Error.invalid_artifact; } if item.kind == EdgeKind.call && item.field == field { return blot_support::some(item.to), blot_error::Error.none; } edge = item.next; }
    return blot_support::none<Id>(), blot_error::Error.none;
}
fn localStateInvocation(report: const Report&, unit: u32, call: CoreId, callback: u8, argument: u8, remaining: i64&) -> bool, Error {
    if !report.complete { return false, blot_error::Error.none; } var found .= false;
    for node, index in report.nodes { let error = reportStep(remaining); if error != blot_error::Error.none { return false, error; } if node.kind != Kind.event || node.site.unit != unit || node.site.node != call || !node.invocation.present { continue; }
        let invocation = node.invocation.value; if invocation >= report.invocations.len { return false, blot_error::Error.invalid_artifact; } let operation, error = callArgument(report, index as u32, callback as u32 + 1, remaining); if error != blot_error::Error.none { return false, error; } if !operation.present { return false, blot_error::Error.none; }
        let value, error = callArgument(report, index as u32, argument as u32 + 1, remaining); if error != blot_error::Error.none { return false, error; } if !value.present || report.nodes[operation.value].kind != Kind.operation { return false, blot_error::Error.none; } var stored = false;
        for write, write_index in report.nodes { let error = reportStep(remaining); if error != blot_error::Error.none { return false, error; } if write.kind != Kind.event { continue; }
            let called, error = callArgument(report, write_index as u32, 0, remaining); if error != blot_error::Error.none { return false, error; } if called != operation { continue; }
            let argument, error = callArgument(report, write_index as u32, 2, remaining); if error != blot_error::Error.none { return false, error; } if argument != value { continue; }
            let cell, error = callArgument(report, write_index as u32, 1, remaining); if error != blot_error::Error.none { return false, error; } if !cell.present || report.nodes[cell.value].kind != Kind.cell { continue; }
            var context = blot_support::some(write.context);
            while context.present { let error = reportStep(remaining); if error != blot_error::Error.none { return false, error; } let current = context.value; if current >= report.invocations.len { return false, blot_error::Error.invalid_artifact; } if current == invocation { stored = true; break; } context = report.invocations[current].parent; }
            if stored { break; }
        } if !stored { return false, blot_error::Error.none; } found .= true;
    } return found, blot_error::Error.none;
}
fn isScope(node: blot_check_core::Node) -> bool { return node.tag == blot_check_core::Tag.effect_scope || (node.tag == blot_check_core::Tag.task && (node.c == blot_check_task_types::opCode(blot_check_task_types::Op.scope) || node.c == blot_check_task_types::opCode(blot_check_task_types::Op.split))); }

fn kindCode(value: Kind) -> u32 {
    match value {
        scalar => { return 0; },
        unknown => { return 1; },
        capability => { return 2; },
        product => { return 3; },
        record => { return 4; },
        wrapper => { return 5; },
        selection => { return 6; },
        callable => { return 7; },
        operation => { return 8; },
        provider => { return 9; },
        state_provider => { return 10; },
        cell => { return 11; },
        scope => { return 12; },
        activation => { return 13; },
        nominal => { return 14; },
        event => { return 15; },
        external => { return 16; },
    }
}
fn kindFromCode(code: u32) -> Kind, blot_error::Error {
    match code {
        0 => { return Kind.scalar, blot_error::Error.none; },
        1 => { return Kind.unknown, blot_error::Error.none; },
        2 => { return Kind.capability, blot_error::Error.none; },
        3 => { return Kind.product, blot_error::Error.none; },
        4 => { return Kind.record, blot_error::Error.none; },
        5 => { return Kind.wrapper, blot_error::Error.none; },
        6 => { return Kind.selection, blot_error::Error.none; },
        7 => { return Kind.callable, blot_error::Error.none; },
        8 => { return Kind.operation, blot_error::Error.none; },
        9 => { return Kind.provider, blot_error::Error.none; },
        10 => { return Kind.state_provider, blot_error::Error.none; },
        11 => { return Kind.cell, blot_error::Error.none; },
        12 => { return Kind.scope, blot_error::Error.none; },
        13 => { return Kind.activation, blot_error::Error.none; },
        14 => { return Kind.nominal, blot_error::Error.none; },
        15 => { return Kind.event, blot_error::Error.none; },
        16 => { return Kind.external, blot_error::Error.none; },
        _ => { return Kind.scalar, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_lifetimes::Kind, right: blot_check_capability_lifetimes::Kind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_capability_lifetimes::Kind) { blot_structural::hash(sink, blot_check_capability_lifetimes::kindCode(value) as! u8); }
fn edgeKindCode(value: EdgeKind) -> u32 {
    match value {
        value => { return 0; },
        capture => { return 1; },
        store => { return 2; },
        result => { return 3; },
        call => { return 4; },
    }
}
fn edgeKindFromCode(code: u32) -> EdgeKind, blot_error::Error {
    match code {
        0 => { return EdgeKind.value, blot_error::Error.none; },
        1 => { return EdgeKind.capture, blot_error::Error.none; },
        2 => { return EdgeKind.store, blot_error::Error.none; },
        3 => { return EdgeKind.result, blot_error::Error.none; },
        4 => { return EdgeKind.call, blot_error::Error.none; },
        _ => { return EdgeKind.value, blot_error::Error.invalid_artifact; },
    }
}
fn blot_structural::equal(left: blot_check_capability_lifetimes::EdgeKind, right: blot_check_capability_lifetimes::EdgeKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_capability_lifetimes::EdgeKind) { blot_structural::hash(sink, blot_check_capability_lifetimes::edgeKindCode(value) as! u8); }


