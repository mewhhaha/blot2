// Temporary ordinary solving keeps caller identities rigid and inquiries private.
namespace blot_check_scheme_equations;
import check.associated_admission;
import check.check_scheme_import;
import check.core;
import check.effects;
import check.frozen_core_scopes;
import check.frozen_types;
import check.package_contracts;
import check.package_row_facts;
import check.scheme_dependencies;
import check.types;
import support.error;
import support.option;
import support.pooled_buffer;
import support.pooled_map;

import .frozen_core_validation;
import support.structural;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type List = blot_check_types::List;
type Module = blot_check_core::Module;
type Facts = blot_check_package_row_facts::Facts;
type Views = blot_check_package_contracts::Context;
type Import = blot_check_check_scheme_import::Copier;
struct SourceFailure { unit: u32, span: blot_check_core::Span }
// Admission-local identity for immutable source headers, never a mutable-view certificate.
struct Body { module_owner: u64, unit: u32, binding: u32 }
struct SourceRows { module_owner: u64, lease: blot_check_scheme_dependencies::LeaseRef }
struct SourceDefinitions { module_owner: u64, lease: blot_check_scheme_dependencies::LeaseRef }
struct AdmissionTables { bodies: BodyBuffer=BodyBuffer{..}, body_index: BodyMap=BodyMap{..}, source_rows: SourceRowsBuffer=SourceRowsBuffer{..}, source_definitions: SourceDefinitionsBuffer=SourceDefinitionsBuffer{..} }
struct Admission {
    workspace: Workspace? = null, remaining: i64&, units: u64[128] = [0;128], count: i64 = 0, source_bodies: bool = false,
    bodies: BodyBuffer=BodyBuffer{..}, body_index: BodyMap=BodyMap{..}, source_rows: SourceRowsBuffer=SourceRowsBuffer{..}, source_definitions: SourceDefinitionsBuffer=SourceDefinitionsBuffer{..},
    source_failure: blot_support::Option<SourceFailure>? = null,
}
fn initAdmission(remaining: i64&, tables: AdmissionTables) -> Admission { return Admission { remaining: remaining, bodies: tables.bodies, body_index: tables.body_index, source_rows: tables.source_rows, source_definitions: tables.source_definitions , ..}; }
fn deinitBodies(self_: Admission&) { self_.body_index.clear(); self_.bodies.clear(); }
fn rollbackBodies(self_: Admission&, before: i64) { for body in self_.bodies.items[before..] { let removed = self_.body_index.remove(body); assert(removed); } self_.bodies.resize(before); }
fn deinit(self_: Admission&) {
    deinitBodies(self_); for entry in self_.source_rows.items { let error = blot_check_scheme_dependencies::releaseSnapshot(entry.lease); assert(error == blot_error::Error.none); } self_.source_rows.deinit();
    for entry in self_.source_definitions.items { let error = blot_check_scheme_dependencies::releaseSnapshot(entry.lease); assert(error == blot_error::Error.none); } self_.source_definitions.deinit();self_.bodies.deinit();self_.body_index.deinit();
}
struct Workspace {
    oom: bool = false, admission: Admission? = null, modules: u64[128] = [0;128], module_count: i64 = 0,
}
fn initWorkspace() -> Workspace { return Workspace {..}; }
fn deinit(self_: Workspace&) { self_.module_count = 0; self_.admission .= null; }
fn proved(self_: const Workspace&, module: const Module&) -> bool {return provedOwner(self_,module.owner_id);}
fn provedOwner(self_:const Workspace&,owner_id:u64)->bool {if owner_id==0 {return false;}for index in 0..self_.module_count {if self_.modules[index]==owner_id {return true;}}return false;}
fn convert(error: Error) -> Error { if error == blot_error::Error.none || error == blot_error::Error.out_of_memory { return error; } return blot_error::Error.invalid_artifact; }
// These identities are scoped to immutable source admission and the solver's checked prefix.
// They do not certify revisions of mutable module views.
struct SharedGoal {
    producer_owner: u64, origin_owner: blot_support::Option<u64> = blot_support::none<u64>(), binding: u32, call_owner: Id, resolver_callback: Id, goal_depth: i64,
    ambient: u32, foreign_allowed: bool, type_count: u8, row_count: u8, arguments: Id[128] = [0; 128],
}
fn hash(key:Body)->u64 {return ::hash_combine(::hash_combine(::hash(key.module_owner),::hash(key.unit)),::hash(key.binding));}
fn hash(key:SharedGoal)->u64 {
 var value=::hash(key.producer_owner);
 value=::hash_combine(value,::hash(key.origin_owner.present));
 if key.origin_owner.present {value=::hash_combine(value,::hash(key.origin_owner.value));}
 value=::hash_combine(value,::hash(key.binding));
 value=::hash_combine(value,::hash(key.call_owner));
 value=::hash_combine(value,::hash(key.resolver_callback));
 value=::hash_combine(value,::hash(key.goal_depth));
 value=::hash_combine(value,::hash(key.ambient));
 value=::hash_combine(value,::hash(key.foreign_allowed));
 value=::hash_combine(value,::hash(key.type_count));
 value=::hash_combine(value,::hash(key.row_count));
 for argument in key.arguments {value=::hash_combine(value,::hash(argument));}
 return value;
}
struct SharedAuthority {
    context: u64, pure_rows: Facts, closed_rows: Facts, instance_variables: Facts, instance_rows: Facts,
    schemes: blot_check_types::Scheme[128] = [blot_check_types::Scheme {..}; 128], scheme_count: i64,
    generic_variables: List, generic_rows: List,
    source_instances: bool, executable: bool, large_plain_graph: bool,
}
fn eligible(views: const Views&) -> bool { return views.owner_id != 0 && !views.formal.present && views.formal_count == 0 && views.opening_count == 0 && !views.witness && !views.representation_floor.present && views.projection_resolver == null; }
fn captureAuthority(views: const Views&) -> SharedAuthority {
    var result = SharedAuthority { context: views.owner_id, pure_rows: views.pure_rows, closed_rows: views.closed_rows, instance_variables: views.instance_variables, instance_rows: views.instance_rows, scheme_count: views.scheme_count,
        generic_variables: views.generic_variables, generic_rows: views.generic_rows,
        source_instances: views.source_instances, executable: views.executable, large_plain_graph: views.large_plain_graph , ..};
    for index in 0..views.scheme_count { result.schemes[index] = views.schemes[index]; } return result;
}
fn matches(self_: const SharedAuthority&, views: const Views&, obligations: const blot_check_core::Obligation[:], source_obligations: const blot_check_types::Obligation[:]) -> bool {
    if !eligible(views) || self_.context != views.owner_id || self_.scheme_count != views.scheme_count || self_.generic_variables != views.generic_variables || self_.generic_rows != views.generic_rows || !(blot_support::same_slice_identity(obligations,views.obligations)) || !(blot_support::same_slice_identity(source_obligations,views.source_obligations)) || self_.source_instances != views.source_instances || self_.executable != views.executable || self_.large_plain_graph != views.large_plain_graph { return false; }
    for index in 0..self_.scheme_count { if self_.schemes[index] != views.schemes[index] { return false; } }
    return self_.pure_rows.eql(views.pure_rows) && self_.closed_rows.eql(views.closed_rows) && self_.instance_variables.eql(views.instance_variables) && self_.instance_rows.eql(views.instance_rows);
}
struct SolverTables { rigid_type_overflow: IdMap=IdMap{..}, rigid_rows: IdMap=IdMap{..}, shared_goals: GoalMap=GoalMap{..} }
struct Solver {
    store: blot_check_types::Store, graph: blot_check_core::Types, view: blot_check_core::Types? = null,
    authority_obligations: const blot_check_core::Obligation[:], authority_source_obligations: const blot_check_types::Obligation[:],
    scope: u32 = 0, oom: bool = false,
    rigid_types: blot_check_package_contracts::Bits4096 = blot_check_package_contracts::Bits4096 {..}, rigid_type_overflow: IdMap=IdMap{..}, rigid_rows: IdMap=IdMap{..},
    remaining: i64&, prefix_nodes: i64 = 0, prefix_rows: i64 = 0, prefix_operations: i64 = 0, prefix_extra: i64 = 0, prefix_row_variables: i64 = 0,
    shared_authority: blot_support::Option<SharedAuthority>   = blot_support::none<SharedAuthority>(), shared_goals: GoalMap=GoalMap{..}, shared_goal_hits: i64 = 0,
}
fn init(store: blot_check_types::Store, module: const Module&, views: Views&, remaining: i64&, tables: SolverTables, view: blot_check_core::Types&) -> Solver, Error {
    var result = Solver { store: store, graph: blot_check_core::emptyTypes(), view: view, authority_obligations: views.obligations, authority_source_obligations: views.source_obligations, rigid_type_overflow: tables.rigid_type_overflow, rigid_rows: tables.rigid_rows, remaining: remaining, shared_goals: tables.shared_goals , ..};
    let error = initialize(result, module, views); if error != blot_error::Error.none { result.view .= null; deinit(result); return result, error; } return result, blot_error::Error.none;
}
fn initialize(self_: Solver&, module: const Module&, views: Views&) -> Error {
    let store: blot_check_types::Store&  = self_.store;
    store.use_resolution_cache = true; store.use_composite_cache = false; store.nodes.clear(); store.nodes.append(module.types.nodes); store.extra.clear(); store.extra.append(module.types.extra);
    store.operations.clear(); store.operations.append(module.types.operations); store.quantifier_goals.append(module.types.quantifier_goals); store.quantifier_obligations.append(module.types.quantifier_obligations);
    store.effects.rows.clear(); store.effects.rows.append(module.types.effects.rows); store.effects.labels.clear(); store.effects.labels.append(module.types.effects.labels);
    let scope, error = store.rigidScope(); if error != blot_error::Error.none { return convert(error); } self_.scope = scope;
    for index in 0..views.scheme_count { let scheme = views.schemes[index];
        if module.types.node(scheme.root).tag != blot_check_types::Tag.forall { for formal in module.types.list(scheme.variables) { if self_.remaining == 0 || formal >= module.types.nodes.len { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; if formal < 4096 { self_.rigid_types.set(formal); } else { self_.rigid_type_overflow.insert(formal, true); } } }
        for formal in module.types.list(scheme.row_variables) { if self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; self_.rigid_rows.insert(formal, true); }
    }
    for &node, id in store.nodes.items { node.closed_height = 0; node.closed_generation = 0;
        if node.tag == blot_check_types::Tag.variable { if views.source_instances && views.instance_variables.contains(id) { if self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; if id < 4096 { self_.rigid_types.set(id); } else { self_.rigid_type_overflow.insert(id as u32, true); } } node = blot_check_types::Node { tag: blot_check_types::Tag.rigid, a: scope, b: id as u32 , ..}; }
    }
    for index in 0..module.types.effects.rows.len { let row = store.effects.rows.items[index]; match row.tail { variable match_payload_34 => { let value = match_payload_34.value;
        if views.closed_rows.contains(index) { store.effects.rows.items[index].tail = blot_check_effects::Tail.closed; }
        else { if views.source_instances && views.instance_rows.contains(value) && !self_.rigid_rows.contains(value) { if self_.remaining == 0 || value >= module.types.effects.variable_count { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; self_.rigid_rows.insert(value, true); }
            let rigid, error = store.rigid(scope, value, 1); if error != blot_error::Error.none { return convert(error); } store.effects.rows.items[index].tail = blot_check_effects::Tail.formal { rigid , ..};
        }
    }, _ => {}, } }
    store.has_projections = true; store.has_rank_types = true; store.has_usage_types = true;
    self_.prefix_nodes = store.nodes.len; self_.prefix_rows = store.effects.rows.len; self_.prefix_operations = store.operations.len; self_.prefix_extra = store.extra.len; self_.prefix_row_variables = module.types.effects.variable_count; refresh(self_); return blot_error::Error.none;
}
fn readerError(self_: Solver&, error: Error) -> Error { if error == blot_error::Error.out_of_memory { self_.oom = true; } return blot_error::Error.invalid_artifact; }
fn ownsRigid(self_: const Solver&, node: blot_check_types::Node) -> bool { if node.tag != blot_check_types::Tag.rigid || node.a != self_.scope { return false; } if node.c == 0 { if node.b < 4096 { return self_.rigid_types.isSet(node.b); } return self_.rigid_type_overflow.contains(node.b); } return node.c == 1 && self_.rigid_rows.contains(node.b); }
fn prefixFacts(facts: Facts, limit: i64) -> bool {
    for page in facts.pages { if page.bits == 0 { continue; } let first = (page.key - 1) * 64; if first >= limit { return false; } let count = limit - first; if count < 64 && page.bits >> count != 0 { return false; } } return true;
}
fn sharedAuthority(self_: Solver&, views: Views&) -> bool, Error {
    if !eligible(views) || !prefixFacts(views.pure_rows, self_.prefix_rows) || !prefixFacts(views.closed_rows, self_.prefix_rows) || !prefixFacts(views.instance_variables, self_.prefix_nodes) || !prefixFacts(views.instance_rows, self_.prefix_row_variables) { return false, blot_error::Error.none; }
    for index in 0..views.scheme_count { let scheme = views.schemes[index]; if scheme.root >= self_.prefix_nodes || scheme.generative.len != 0 { return false, blot_error::Error.none; }
        let spans: List[3] = [scheme.variables, scheme.row_variables, scheme.closed_rows]; for span, ordinal in spans { if span.start > self_.prefix_extra || span.len > self_.prefix_extra - span.start { return false, blot_error::Error.none; } var maximum = self_.prefix_row_variables; if ordinal == 0 { maximum = self_.prefix_nodes; } for id in self_.store.list(span) { if id >= maximum { return false, blot_error::Error.none; } } }
    }
    if self_.shared_authority.present { return matches(self_.shared_authority.value, views, self_.authority_obligations, self_.authority_source_obligations), blot_error::Error.none; }
    // Solver contexts keep the constructor's obligation slices: solverViews only
    // replaces types/solver, and no checker operation rebinds either slice.
    // First eligible capture may observe changed owned facts, never new roots.
    assert(blot_support::same_slice_identity(self_.authority_obligations, views.obligations));
    assert(blot_support::same_slice_identity(self_.authority_source_obligations, views.source_obligations));
    self_.shared_authority = blot_support::some(captureAuthority(views)); return true, blot_error::Error.none;
}
fn sharedGoalOwners(key:const SharedGoal&)->bool {return key.producer_owner!=0 && (!key.origin_owner.present || key.origin_owner.value!=0);}
fn sharedGoalHit(self_: Solver&, key: SharedGoal, depth: i64) -> bool { if !sharedGoalOwners(key) { return false; } { let scalar_lookup_1 .= self_.shared_goals.get(key); if scalar_lookup_1 {let optional_binding_78:i64=scalar_lookup_1; let proved_depth .= optional_binding_78; if depth > proved_depth { return false; } self_.shared_goal_hits += 1; return true;  } } return false; }
fn rememberSharedGoal(self_: Solver&, key: SharedGoal, depth: i64) -> Error {
    if !sharedGoalOwners(key) { return blot_error::Error.none; } { let scalar_lookup_2 .= self_.shared_goals.get(key); if scalar_lookup_2 {let optional_binding_77:i64=scalar_lookup_2; let proved_depth .= optional_binding_77; self_.shared_goals.insert(key, max(proved_depth, depth)); return blot_error::Error.none;  } }
    if self_.shared_goals.count >= 65536 { return blot_error::Error.none; } self_.shared_goals.insert(key, depth); return blot_error::Error.none;
}
fn deinit(self_: Solver&) { self_.shared_authority.present = false; self_.shared_goals.deinit(); self_.rigid_type_overflow.deinit(); self_.rigid_rows.deinit(); self_.store.deinit(); }
fn refresh(self_: Solver&) {
    let nodes=blot_check_types::pool_Table_nodes.realloc_slice(self_.store.nodes.storage,self_.store.nodes.storage.len);
    let extra=blot_check_types::pool_Table_extra.realloc_slice(self_.store.extra.storage,self_.store.extra.storage.len);
    let rows=blot_check_effects::pool_Table_rows.realloc_slice(self_.store.effects.rows.storage,self_.store.effects.rows.storage.len);
    let labels=blot_check_effects::pool_Table_labels.realloc_slice(self_.store.effects.labels.storage,self_.store.effects.labels.storage.len);
    let operations=blot_check_types::pool_Table_operations.realloc_slice(self_.store.operations.storage,self_.store.operations.storage.len);
    let goals=blot_check_types::pool_Table_quantifier_goals.realloc_slice(self_.store.quantifier_goals.storage,self_.store.quantifier_goals.storage.len);
    let obligations=blot_check_types::pool_Table_quantifier_obligations.realloc_slice(self_.store.quantifier_obligations.storage,self_.store.quantifier_obligations.storage.len);
    let refreshed = blot_check_core::Types { owner_id: self_.store.owner_id, nodes: nodes[..self_.store.nodes.len], extra: extra[..self_.store.extra.len], effects: blot_check_core::EffectRows { rows[..self_.store.effects.rows.len], labels[..self_.store.effects.labels.len], self_.store.effects.variables.len as u32 , ..}, operations: operations[..self_.store.operations.len], quantifier_goals: goals[..self_.store.quantifier_goals.len], quantifier_obligations: obligations[..self_.store.quantifier_obligations.len] , ..};
    self_.graph=refreshed;
    { let optional_binding_76 .= self_.view; if optional_binding_76 { let view .= optional_binding_76; view = refreshed;  } }
}
fn step(self_: Solver&) -> Error { if self_.remaining == 0 { return blot_error::Error.invalid_artifact; } self_.remaining -= 1; return blot_error::Error.none; }
fn beginWork(self_: Solver&) { self_.store.projection_steps = 0; self_.store.projection_limit = self_.remaining; }
fn endWork(self_: Solver&) { self_.remaining -= min(self_.remaining, self_.store.projection_steps); refresh(self_); }
fn unify(self_: Solver&, left: Id, right: Id) -> Error { let error = step(self_); if error != blot_error::Error.none { return error; } beginWork(self_); let error = self_.store.unify(left, right); endWork(self_); return convert(error); }
fn rows(self_: Solver&, left: u32, right: u32) -> Error { let error = step(self_); if error != blot_error::Error.none { return error; } beginWork(self_); let error = self_.store.unifyEffects(left, right); endWork(self_); return convert(error); }
fn resolve(self_: Solver&, id: Id) -> Id, Error { let error = step(self_); if error != blot_error::Error.none { return 0, error; } beginWork(self_); let value, error = self_.store.resolve(id, 0); endWork(self_); return value, convert(error); }
fn resolveRow(self_: Solver&, id: u32) -> u32, Error { let error = step(self_); if error != blot_error::Error.none { return 0, error; } beginWork(self_); let value, error = self_.store.resolveEffects(id, 0); endWork(self_); return value, convert(error); }
fn rollback(self_: Solver&, mark: blot_check_types::Mark) { self_.store.rollback(mark); refresh(self_); }
fn importer(self_: Solver&, module: const Module&, frozen: blot_check_frozen_types::Graph&, scheme: blot_check_types::Scheme, tables: blot_check_check_scheme_import::Tables) -> Import, Error {
    frozen = blot_check_associated_admission::graphView(module.types); var copier = blot_check_check_scheme_import::init(blot_check_frozen_types::Source.frozen { frozen , ..}, self_.store, tables); copier.associated = true;
    for formal in module.types.list(scheme.variables) { let fresh, error = self_.store.fresh(); if error != blot_error::Error.none { copier.deinit(); return copier, convert(error); } copier.mapping.insert(formal, fresh); }
    for formal in module.types.list(scheme.row_variables) { let fresh, error = self_.store.freshEffects(); if error != blot_error::Error.none { copier.deinit(); return copier, convert(error); } copier.row_variables.insert(formal, fresh); }
    for formal in module.types.list(scheme.closed_rows) { copier.row_variables.insert(formal, 0); } refresh(self_); return copier, blot_error::Error.none;
}
fn copy(self_: Solver&, copier: Import&, root: Id) -> Id, Error { let error = step(self_); if error != blot_error::Error.none { return 0, error; } beginWork(self_); let value, error = copier.copy(root, 0); endWork(self_); return value, convert(error); }
// Revalidate bounds directly: retaining caller-owned Module headers in a
// process-wide metadata pool would extend their borrowed slice lifetimes.
fn bounds(module: const Module&, context: blot_check_frozen_core_validation::Context) -> Error {
    return blot_check_frozen_core_validation::validateBounds(module, context);
}
// The temporary header and its Solver view share one invocation scope.
fn solverModule(module:const Module&)->Module {return module;}
recursive fn withSolver<C,F>(module:const Module&,views:Views&,remaining:i64&,context:C&)->Error {
 let initialized,error=blot_check_types::initPooled();if error!=blot_error::Error.none {return error;}
 var temporary=solverModule(module);
 var solver,error=init(initialized,module,views,remaining,SolverTables{..},temporary.types);
 if error!=blot_error::Error.none {return error;}
 let failure=F(context,solver,temporary);
 solver.view .= null;
 deinit(solver);
 return failure;
}
fn saveSourceRows(self_: Admission&, module: const Module&, rows: const u32[:]) -> Error {
    let copied, lease, error = blot_check_scheme_dependencies::copySnapshot(rows); if error != blot_error::Error.none { return error; } self_.source_rows.push(SourceRows { module.owner_id, lease , ..});if self_.source_rows.failure!=blot_error::Error.none {let released=blot_check_scheme_dependencies::releaseSnapshot(lease);assert(released==blot_error::Error.none);return self_.source_rows.failure;}return blot_error::Error.none;
}
fn saveSourceDefinitions(self_: Admission&, module: const Module&, values: const u32[:]) -> Error {
    let copied, lease, error = blot_check_scheme_dependencies::copySnapshot(values); if error != blot_error::Error.none { return error; } self_.source_definitions.push(SourceDefinitions { module.owner_id, lease , ..});if self_.source_definitions.failure!=blot_error::Error.none {let released=blot_check_scheme_dependencies::releaseSnapshot(lease);assert(released==blot_error::Error.none);return self_.source_definitions.failure;}return blot_error::Error.none;
}

struct BodyBuffer {storage:Body[:]=default<Body[:]>(),items:Body[:]=default<Body[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var bodybuffer_runs:Body[>..];
fn push(self_:BodyBuffer&,value:Body) {let error=blot_support_pooled_buffer::push(self_,value,bodybuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn append(self_:BodyBuffer&,values:const Body[:]) {let error=blot_support_pooled_buffer::append(self_,values,bodybuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn resize(self_:BodyBuffer&,length:i64) {assert(length<=self_.items.len);self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:BodyBuffer&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:BodyBuffer&) {blot_support_pooled_buffer::deinit(self_,bodybuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct SourceRowsBuffer {storage:SourceRows[:]=default<SourceRows[:]>(),items:SourceRows[:]=default<SourceRows[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var sourcerowsbuffer_runs:SourceRows[>..];
fn push(self_:SourceRowsBuffer&,value:SourceRows) {let error=blot_support_pooled_buffer::push(self_,value,sourcerowsbuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn append(self_:SourceRowsBuffer&,values:const SourceRows[:]) {let error=blot_support_pooled_buffer::append(self_,values,sourcerowsbuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn resize(self_:SourceRowsBuffer&,length:i64) {assert(length<=self_.items.len);self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:SourceRowsBuffer&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:SourceRowsBuffer&) {blot_support_pooled_buffer::deinit(self_,sourcerowsbuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct SourceDefinitionsBuffer {storage:SourceDefinitions[:]=default<SourceDefinitions[:]>(),items:SourceDefinitions[:]=default<SourceDefinitions[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var sourcedefinitionsbuffer_runs:SourceDefinitions[>..];
fn push(self_:SourceDefinitionsBuffer&,value:SourceDefinitions) {let error=blot_support_pooled_buffer::push(self_,value,sourcedefinitionsbuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn append(self_:SourceDefinitionsBuffer&,values:const SourceDefinitions[:]) {let error=blot_support_pooled_buffer::append(self_,values,sourcedefinitionsbuffer_runs);if error!=blot_error::Error.none {self_.failure=error;}self_.len=self_.items.len;}
fn resize(self_:SourceDefinitionsBuffer&,length:i64) {assert(length<=self_.items.len);self_.items=self_.storage[..length];self_.len=length;}
fn clear(self_:SourceDefinitionsBuffer&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:SourceDefinitionsBuffer&) {blot_support_pooled_buffer::deinit(self_,sourcedefinitionsbuffer_runs);self_.len=0;self_.failure=blot_error::Error.none;}
struct BodyMap {count:i64=0,slots:dictionary_slot<Body,bool>[:]=default<dictionary_slot<Body,bool>[:]>(),failure:Error=blot_error::Error.none}
reusable[] var bodymap_slots:dictionary_slot<Body,bool>[>..];
fn contains(self_:const BodyMap&,key:Body)->bool {return blot_support_pooled_map::contains(self_,key);}
fn get(self_:const BodyMap&,key:Body)->bool? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:BodyMap&,key:Body,value:bool)->bool {if self_.count>=0x1555555555555555 {self_.failure=blot_error::Error.out_of_memory;return false;}return blot_support_pooled_map::insert(self_,key,value,bodymap_slots);}
fn remove(self_:BodyMap&,key:Body)->bool {return blot_support_pooled_map::remove(self_,key,bodymap_slots);}
fn clear(self_:BodyMap&) {blot_support_pooled_map::clear(self_);self_.failure=blot_error::Error.none;}
fn deinit(self_:BodyMap&) {blot_support_pooled_map::deinit(self_,bodymap_slots);self_.failure=blot_error::Error.none;}
struct IdMap {count:i64=0,slots:dictionary_slot<u32,bool>[:]=default<dictionary_slot<u32,bool>[:]>(),failure:Error=blot_error::Error.none}
reusable[] var idmap_slots:dictionary_slot<u32,bool>[>..];
fn contains(self_:const IdMap&,key:u32)->bool {return blot_support_pooled_map::contains(self_,key);}
fn get(self_:const IdMap&,key:u32)->bool? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:IdMap&,key:u32,value:bool)->bool {if self_.count>=0x1555555555555555 {self_.failure=blot_error::Error.out_of_memory;return false;}return blot_support_pooled_map::insert(self_,key,value,idmap_slots);}
fn remove(self_:IdMap&,key:u32)->bool {return blot_support_pooled_map::remove(self_,key,idmap_slots);}
fn clear(self_:IdMap&) {blot_support_pooled_map::clear(self_);self_.failure=blot_error::Error.none;}
fn deinit(self_:IdMap&) {blot_support_pooled_map::deinit(self_,idmap_slots);self_.failure=blot_error::Error.none;}
struct GoalMap {count:i64=0,slots:dictionary_slot<SharedGoal,i64>[:]=default<dictionary_slot<SharedGoal,i64>[:]>(),failure:Error=blot_error::Error.none}
reusable[] var goalmap_slots:dictionary_slot<SharedGoal,i64>[>..];
fn contains(self_:const GoalMap&,key:SharedGoal)->bool {return blot_support_pooled_map::contains(self_,key);}
fn get(self_:const GoalMap&,key:SharedGoal)->i64? {return blot_support_pooled_map::get(self_,key);}
fn insert(self_:GoalMap&,key:SharedGoal,value:i64)->bool {if self_.count>=0x1555555555555555 {self_.failure=blot_error::Error.out_of_memory;return false;}return blot_support_pooled_map::insert(self_,key,value,goalmap_slots);}
fn remove(self_:GoalMap&,key:SharedGoal)->bool {return blot_support_pooled_map::remove(self_,key,goalmap_slots);}
fn clear(self_:GoalMap&) {blot_support_pooled_map::clear(self_);self_.failure=blot_error::Error.none;}
fn deinit(self_:GoalMap&) {blot_support_pooled_map::deinit(self_,goalmap_slots);self_.failure=blot_error::Error.none;}
fn initPooledAdmission(remaining:i64&)->Admission,Error {return Admission{remaining:remaining, ..},blot_error::Error.none;}
fn initPooledWorkspace()->Workspace,Error {return Workspace{..},blot_error::Error.none;}
