// Temporary ordinary solving keeps caller identities rigid and inquiries private.
namespace blot_check_scheme_equations;
import .frozen_core_validation;
type ModuleRef = blot_check_frozen_core_validation::ModuleRef;
import support.error;
import support.option;
import support.structural;
import .types;
import .check_scheme_import;
type Error = blot_error::Error;
type Id = blot_check_types::Id;
type List = blot_check_types::List;
type Module = blot_check_core::Module;
type Facts = blot_check_package_row_facts::Facts;
type Views = blot_check_package_contracts::Context;
type Import = blot_check_check_scheme_import::Copier;
struct SourceFailure { unit: u32, span: blot_check_core::Span }
struct Body { module: const Module&, binding: u32 }
struct SourceRows { module: const Module&, rows: const u32[:], lease: blot_check_scheme_dependencies::LeaseRef }
struct SourceDefinitions { module: const Module&, values: const u32[:], lease: blot_check_scheme_dependencies::LeaseRef }
struct AdmissionTables { bodies: Body[>..<]&, body_index: dictionary<Body,bool>&, source_rows: SourceRows[>..<]&, source_definitions: SourceDefinitions[>..<]& }
struct Admission {
    workspace: Workspace? = null, remaining: i64&, units: (const Module?)[128] = [null;128], count: i64 = 0, source_bodies: bool = false,
    bodies: Body[>..<]&, body_index: dictionary<Body,bool>&, source_rows: SourceRows[>..<]&, source_definitions: SourceDefinitions[>..<]&,
    source_failure: blot_support::Option<SourceFailure>? = null,
}
fn initAdmission(remaining: i64&, tables: AdmissionTables) -> Admission { return Admission { remaining, bodies: tables.bodies, body_index: tables.body_index, source_rows: tables.source_rows, source_definitions: tables.source_definitions }; }
fn deinitBodies(self: Admission&) { self.body_index.clear(); self.bodies.clear(); }
fn rollbackBodies(self: Admission&, before: i64) { for body in self.bodies[before..] { let removed = self.body_index.remove(body); assert(removed); } self.bodies.resize(before); }
fn deinit(self: Admission&) {
    deinitBodies(self); for entry in self.source_rows { let error = blot_check_scheme_dependencies::releaseSnapshot(entry.lease); assert(error == Error.none); } self.source_rows.clear();
    for entry in self.source_definitions { let error = blot_check_scheme_dependencies::releaseSnapshot(entry.lease); assert(error == Error.none); } self.source_definitions.clear();
}
struct BoundsReceipt { module: const Module&, symbol_count: blot_support::Option<i64>, source_length: blot_support::Option<u32>, forbidden_owner: blot_support::Option<u32> }
struct WorkspaceTables { bounds_units: ModuleRef[>..<]&, bounds_receipts: BoundsReceipt[>..<]& }
struct Workspace {
    oom: bool = false, admission: Admission? = null, modules: (const Module?)[128] = [null;128], module_count: i64 = 0,
    bounds_units: ModuleRef[>..<]&, has_bounds_units: bool = false, bounds_receipts: BoundsReceipt[>..<]&,
}
fn initWorkspace(tables: WorkspaceTables) -> Workspace { return Workspace { bounds_units: tables.bounds_units, bounds_receipts: tables.bounds_receipts }; }
fn deinit(self: Workspace&) { self.bounds_units.clear(); self.bounds_receipts.clear(); self.has_bounds_units = false; self.module_count = 0; self.admission .= null; }
fn proved(self: const Workspace&, module: const Module&) -> bool { if module.owner_id == 0 { return false; } for index in 0..self.module_count { let entry .= self.modules[index]; if entry && entry.owner_id == module.owner_id { return true; } } return false; }
fn convert(error: Error) -> Error { if error == Error.none || error == Error.out_of_memory { return error; } return Error.invalid_artifact; }
struct SharedGoal {
    producer: const Module&, origin: const Module? = null, binding: u32, call_owner: Id, resolver_callback: Id, goal_depth: i64,
    ambient: u32, foreign_allowed: bool, type_count: u8, row_count: u8, arguments: Id[128] = [0; 128],
}
struct SharedAuthority {
    context: u64, pure_rows: Facts, closed_rows: Facts, instance_variables: Facts, instance_rows: Facts,
    schemes: blot_check_types::Scheme[128] = [blot_check_types::Scheme {}; 128], scheme_count: i64,
    generic_variables: List, generic_rows: List, obligations: const blot_check_core::Obligation[:], source_obligations: const blot_check_types::Obligation[:],
    source_instances: bool, executable: bool, large_plain_graph: bool,
}
fn eligible(views: const Views&) -> bool { return views.owner_id != 0 && !views.formal.present && views.formal_count == 0 && views.opening_count == 0 && !views.witness && !views.representation_floor.present && views.projection_resolver == null; }
fn captureAuthority(views: const Views&) -> SharedAuthority {
    var result = SharedAuthority { views.owner_id, views.pure_rows, views.closed_rows, views.instance_variables, views.instance_rows, scheme_count: views.scheme_count,
        generic_variables: views.generic_variables, generic_rows: views.generic_rows, obligations: views.obligations, source_obligations: views.source_obligations,
        source_instances: views.source_instances, executable: views.executable, large_plain_graph: views.large_plain_graph };
    for index in 0..views.scheme_count { result.schemes[index] = views.schemes[index]; } return result;
}
fn matches(self: const SharedAuthority&, views: const Views&) -> bool {
    if !eligible(views) || self.context != views.owner_id || self.scheme_count != views.scheme_count || self.generic_variables != views.generic_variables || self.generic_rows != views.generic_rows || !(self.obligations .== views.obligations) || !(self.source_obligations .== views.source_obligations) || self.source_instances != views.source_instances || self.executable != views.executable || self.large_plain_graph != views.large_plain_graph { return false; }
    for index in 0..self.scheme_count { if self.schemes[index] != views.schemes[index] { return false; } }
    return self.pure_rows.eql(views.pure_rows) && self.closed_rows.eql(views.closed_rows) && self.instance_variables.eql(views.instance_variables) && self.instance_rows.eql(views.instance_rows);
}
struct SolverTables { rigid_type_overflow: dictionary<Id,bool>&, rigid_rows: dictionary<u32,bool>&, shared_goals: dictionary<SharedGoal,i64>& }
struct Solver {
    store: blot_check_types::Store, graph: blot_check_core::Types, view: blot_check_core::Types? = null, scope: u32 = 0, oom: bool = false,
    rigid_types: blot_check_package_contracts::Bits4096 = blot_check_package_contracts::Bits4096 {}, rigid_type_overflow: dictionary<Id,bool>&, rigid_rows: dictionary<u32,bool>&,
    remaining: i64&, prefix_nodes: i64 = 0, prefix_rows: i64 = 0, prefix_operations: i64 = 0, prefix_extra: i64 = 0, prefix_row_variables: i64 = 0,
    shared_authority: blot_support::Option<SharedAuthority> = blot_support::none<SharedAuthority>(), shared_goals: dictionary<SharedGoal,i64>&, shared_goal_hits: i64 = 0,
}
fn init(store: blot_check_types::Store, module: const Module&, views: Views&, remaining: i64&, tables: SolverTables) -> Solver, Error {
    var result = Solver { store, graph: blot_check_core::Types { nodes: [], extra: [] }, rigid_type_overflow: tables.rigid_type_overflow, rigid_rows: tables.rigid_rows, remaining, shared_goals: tables.shared_goals };
    let error = initialize(result, module, views); if error != Error.none { deinit(result); return result, error; } return result, Error.none;
}
fn initialize(self: Solver&, module: const Module&, views: Views&) -> Error {
    let store: blot_check_types::Store& = self.store;
    store.use_resolution_cache = true; store.use_composite_cache = false; store.nodes.clear(); store.nodes.items += module.types.nodes; store.extra.clear(); store.extra.items += module.types.extra;
    store.operations.clear(); store.operations.items += module.types.operations; store.quantifier_goals.items += module.types.quantifier_goals; store.quantifier_obligations.items += module.types.quantifier_obligations;
    store.effects.rows.clear(); store.effects.rows.items += module.types.effects.rows; store.effects.labels.clear(); store.effects.labels.items += module.types.effects.labels;
    let scope, error = store.rigidScope(); if error != Error.none { return convert(error); } self.scope = scope;
    for index in 0..views.scheme_count { let scheme = views.schemes[index];
        if module.types.node(scheme.root).tag != blot_check_types::Tag.forall { for formal in module.types.list(scheme.variables) { if self.remaining == 0 || formal >= module.types.nodes.len { return Error.invalid_artifact; } self.remaining -= 1; if formal < 4096 { self.rigid_types.set(formal); } else { self.rigid_type_overflow.insert(formal, true); } } }
        for formal in module.types.list(scheme.row_variables) { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; self.rigid_rows.insert(formal, true); }
    }
    for &node, id in store.nodes.items { node.closed_height = 0; node.closed_generation = 0;
        if node.tag == blot_check_types::Tag.variable { if views.source_instances && views.instance_variables.contains(id) { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; if id < 4096 { self.rigid_types.set(id); } else { self.rigid_type_overflow.insert(id as u32, true); } } node = blot_check_types::Node { blot_check_types::Tag.rigid, a: scope, b: id as u32 }; }
    }
    for index in 0..module.types.effects.rows.len { let row = store.effects.rows.items[index]; match row.tail { blot_check_effects::Tail.variable match_payload_34 => { let value = match_payload_34.value; 
        if views.closed_rows.contains(index) { store.effects.rows.items[index].tail = blot_check_effects::Tail.closed; }
        else { if views.source_instances && views.instance_rows.contains(value) && !self.rigid_rows.contains(value) { if self.remaining == 0 || value >= module.types.effects.variable_count { return Error.invalid_artifact; } self.remaining -= 1; self.rigid_rows.insert(value, true); }
            let rigid, error = store.rigid(scope, value, 1); if error != Error.none { return convert(error); } store.effects.rows.items[index].tail = blot_check_effects::Tail.formal { rigid };
        }
    }, _ => {}, } }
    store.has_projections = true; store.has_rank_types = true; store.has_usage_types = true;
    self.prefix_nodes = store.nodes.len; self.prefix_rows = store.effects.rows.len; self.prefix_operations = store.operations.len; self.prefix_extra = store.extra.len; self.prefix_row_variables = module.types.effects.variable_count; refresh(self); return Error.none;
}
fn readerError(self: Solver&, error: Error) -> Error { if error == Error.out_of_memory { self.oom = true; } return Error.invalid_artifact; }
fn ownsRigid(self: const Solver&, node: blot_check_types::Node) -> bool { if node.tag != blot_check_types::Tag.rigid || node.a != self.scope { return false; } if node.c == 0 { if node.b < 4096 { return self.rigid_types.isSet(node.b); } return self.rigid_type_overflow.contains(node.b); } return node.c == 1 && self.rigid_rows.contains(node.b); }
fn prefixFacts(facts: Facts, limit: i64) -> bool {
    for page in facts.pages { if page.bits == 0 { continue; } let first = (page.key - 1) * 64; if first >= limit { return false; } let count = limit - first; if count < 64 && page.bits >> count != 0 { return false; } } return true;
}
fn sharedAuthority(self: Solver&, views: Views&) -> bool, Error {
    if !eligible(views) || !prefixFacts(views.pure_rows, self.prefix_rows) || !prefixFacts(views.closed_rows, self.prefix_rows) || !prefixFacts(views.instance_variables, self.prefix_nodes) || !prefixFacts(views.instance_rows, self.prefix_row_variables) { return false, Error.none; }
    for index in 0..views.scheme_count { let scheme = views.schemes[index]; if scheme.root >= self.prefix_nodes || scheme.generative.len != 0 { return false, Error.none; }
        let spans: List[3] = [scheme.variables, scheme.row_variables, scheme.closed_rows]; for span, ordinal in spans { if span.start > self.prefix_extra || span.len > self.prefix_extra - span.start { return false, Error.none; } var maximum = self.prefix_row_variables; if ordinal == 0 { maximum = self.prefix_nodes; } for id in self.store.list(span) { if id >= maximum { return false, Error.none; } } }
    }
    if self.shared_authority.present { return matches(self.shared_authority.value, views), Error.none; } self.shared_authority = blot_support::some(captureAuthority(views)); return true, Error.none;
}
fn sharedGoalHit(self: Solver&, key: SharedGoal, depth: i64) -> bool { if key.producer.owner_id == 0 { return false; } { let optional_binding_78 .= self.shared_goals.get(key); if optional_binding_78 { let proved_depth .= optional_binding_78; if depth > proved_depth { return false; } self.shared_goal_hits += 1; return true;  } } return false; }
fn rememberSharedGoal(self: Solver&, key: SharedGoal, depth: i64) -> Error {
    if key.producer.owner_id == 0 { return Error.none; } { let optional_binding_77 .= self.shared_goals.get(key); if optional_binding_77 { let proved_depth .= optional_binding_77; self.shared_goals.insert(key, max(proved_depth, depth)); return Error.none;  } }
    if self.shared_goals.count >= 65536 { return Error.none; } self.shared_goals.insert(key, depth); return Error.none;
}
fn deinit(self: Solver&) { self.shared_authority.present = false; self.shared_goals.clear(); self.rigid_type_overflow.clear(); self.rigid_rows.clear(); self.store.deinit(); }
fn refresh(self: Solver&) {
    self.graph = blot_check_core::Types { owner_id: self.store.owner_id, nodes: self.store.nodes.items[:], extra: self.store.extra.items[:], effects: blot_check_core::EffectRows { self.store.effects.rows.items[:], self.store.effects.labels.items[:], self.store.effects.variables.len as u32 }, operations: self.store.operations.items[:], quantifier_goals: self.store.quantifier_goals.items[:], quantifier_obligations: self.store.quantifier_obligations.items[:] };
    { let optional_binding_76 .= self.view; if optional_binding_76 { let view .= optional_binding_76; view = self.graph;  } }
}
fn step(self: Solver&) -> Error { if self.remaining == 0 { return Error.invalid_artifact; } self.remaining -= 1; return Error.none; }
fn beginWork(self: Solver&) { self.store.projection_steps = 0; self.store.projection_limit = self.remaining; }
fn endWork(self: Solver&) { self.remaining -= min(self.remaining, self.store.projection_steps); refresh(self); }
fn unify(self: Solver&, left: Id, right: Id) -> Error { let error = step(self); if error != Error.none { return error; } beginWork(self); let error = self.store.unify(left, right); endWork(self); return convert(error); }
fn rows(self: Solver&, left: u32, right: u32) -> Error { let error = step(self); if error != Error.none { return error; } beginWork(self); let error = self.store.unifyEffects(left, right); endWork(self); return convert(error); }
fn resolve(self: Solver&, id: Id) -> Id, Error { let error = step(self); if error != Error.none { return 0, error; } beginWork(self); let value, error = self.store.resolve(id, 0); endWork(self); return value, convert(error); }
fn resolveRow(self: Solver&, id: u32) -> u32, Error { let error = step(self); if error != Error.none { return 0, error; } beginWork(self); let value, error = self.store.resolveEffects(id, 0); endWork(self); return value, convert(error); }
fn rollback(self: Solver&, mark: blot_check_types::Mark) { self.store.rollback(mark); refresh(self); }
fn importer(self: Solver&, module: const Module&, frozen: blot_check_frozen_types::Graph&, scheme: blot_check_types::Scheme, tables: blot_check_check_scheme_import::Tables) -> Import, Error {
    frozen = blot_check_associated_admission::graphView(module.types); var copier = blot_check_check_scheme_import::init(blot_check_frozen_types::Source.frozen { frozen }, self.store, tables); copier.associated = true;
    for formal in module.types.list(scheme.variables) { let fresh, error = self.store.fresh(); if error != Error.none { copier.deinit(); return copier, convert(error); } copier.mapping.insert(formal, fresh); }
    for formal in module.types.list(scheme.row_variables) { let fresh, error = self.store.freshEffects(); if error != Error.none { copier.deinit(); return copier, convert(error); } copier.row_variables.insert(formal, fresh); }
    for formal in module.types.list(scheme.closed_rows) { copier.row_variables.insert(formal, 0); } refresh(self); return copier, Error.none;
}
fn copy(self: Solver&, copier: Import&, root: Id) -> Id, Error { let error = step(self); if error != Error.none { return 0, error; } beginWork(self); let value, error = copier.copy(root, 0); endWork(self); return value, convert(error); }
fn bounds(workspace: Workspace?, module: const Module&, context: blot_check_frozen_core_validation::Context) -> Error {
    { let optional_binding_75 .= workspace; if optional_binding_75 { let owner .= optional_binding_75;
        var same_context = true; if owner.has_bounds_units { same_context = sameUnits(owner.bounds_units, context.units); }
        if same_context { for receipt in owner.bounds_receipts { if receipt.module.owner_id != 0 && receipt.module.owner_id == module.owner_id && receipt.symbol_count == context.symbol_count && receipt.source_length == context.source_length && receipt.forbidden_owner == context.forbidden_owner { return Error.none; } } }
        let error = blot_check_frozen_core_validation::validateBounds(module, context); if error != Error.none { return error; } if !same_context { return Error.none; }
        if !owner.has_bounds_units { owner.bounds_units += context.units; owner.has_bounds_units = true; }
        owner.bounds_receipts += BoundsReceipt { module, context.symbol_count, context.source_length, context.forbidden_owner }; return Error.none;
     } } return blot_check_frozen_core_validation::validateBounds(module, context);
}
fn sameUnits(left: const ModuleRef[:], right: const ModuleRef[:]) -> bool { if left.len != right.len { return false; } for unit, index in left { if unit.owner_id == 0 || unit.owner_id != right[index].owner_id { return false; } } return true; }
struct SolverScope<C,F> { module: const Module&, views: Views&, remaining: i64&, context: C& }
fn withSolver<C,F>(module: const Module&, views: Views&, remaining: i64&, context: C&) -> Error {
    var scope = SolverScope<C,F> { module, views, remaining, context }; return blot_check_types::withStore<SolverScope<C,F>,solverScope>(scope);
}
fn solverScope<C,F>(scope: SolverScope<C,F>&, store: blot_check_types::Store&) -> Error {
    var overflow: dictionary<Id,bool> = dictionary<Id,bool> {}; var rows: dictionary<u32,bool> = dictionary<u32,bool> {}; var goals: dictionary<SharedGoal,i64> = dictionary<SharedGoal,i64> {};
    var solver, error = init(store, scope.module, scope.views, scope.remaining, SolverTables { overflow, rows, goals }); if error != Error.none { return error; }
    let error = F(scope.context, solver); deinit(solver); return error;
}
fn saveSourceRows(self: Admission&, module: const Module&, rows: const u32[:]) -> Error {
    let copied, lease, error = blot_check_scheme_dependencies::copySnapshot(rows); if error != Error.none { return error; } self.source_rows += SourceRows { module, copied, lease }; return Error.none;
}
fn saveSourceDefinitions(self: Admission&, module: const Module&, values: const u32[:]) -> Error {
    let copied, lease, error = blot_check_scheme_dependencies::copySnapshot(values); if error != Error.none { return error; } self.source_definitions += SourceDefinitions { module, copied, lease }; return Error.none;
}
