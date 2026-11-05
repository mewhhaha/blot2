// Dense owned types with chronological, non-collapsing substitution history.
namespace blot_check_types;
import support.structural;
import std;
import dictionary;
import support.error;
import support.option;
import support.native;
import .type_store_snapshot;
type Error = blot_error::Error;
type Id = u32;
type Cursor = u32;
type UsageKind = blot_parse_ast::UsageKind;
let absent: Id = 0; let unit: Id = 1; let boolean: Id = 2;
let u32_type: Id = 3; let f32_type: Id = 4; let never: Id = 5;
let none: u32 = 0xffffffff;
let opaque_name_bit: u32 = 0x80000000;
enum Tag { absent, unit, boolean, unsigned32, floating32, never, variable, function, product, record, nominal, array, list, cursor, type_constructor, resolver, provider, state_provider, projection, scoped, instance_selection, erased_proof, forall, existential, bound, rigid, usage, instance_version }
struct Node { tag: Tag, closed_height: u8 = 0, closed_generation: u16 = 0, a: u32 = 0, b: u32 = 0, c: u32 = 0 }
struct NominalIdentity { unit: u32, decl: u32 }
struct List { start: u32 = 0, len: u32 = 0 }
struct Field { name: u32, ty: Id }
struct Operation { identity: NominalIdentity, arguments: List = List {}, instance: NominalIdentity = NominalIdentity { 0, 0 } }
let foreign_operation: blot_check_effects::Label = 1;
let builtin_state_read = NominalIdentity { 0xffffffff, 1 };
let builtin_state_write = NominalIdentity { 0xffffffff, 2 };
let effect_set_identity = NominalIdentity { 0xffffffff, 3 };
let effect_descriptor_identity = NominalIdentity { 0xffffffff, 4 };
struct Scheme { root: Id = absent, variables: List = List {}, row_variables: List = List {}, closed_rows: List = List {}, obligations: List = List {}, generative: List = List {} }
struct ClosedCovariant { root: Id, closed_rows: List }
enum Operator { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right }
enum ObligationKind { arithmetic, ordered, equality, integer, field, writable_field, dispatch, result_dispatch, monad_factory, resolver_dispatch, resolver_shape, effect_operation, effect_handler, receiver, update, type_rep, effect_rep, type_head, collection, record_merge, callee_use, type_eq, contract, task_receive }
struct QuantifierGoals { owner: Id, goals: List }
struct Obligation {
    ty: Id, kind: ObligationKind, source: u32, name: u32 = 0, result: Id = 0,
    other: Id = 0, signature: Id = 0, operator: Operator = Operator.none,
    identity: NominalIdentity = NominalIdentity { 0, 0 }, explicit: bool = false,
    qualification_span: blot_support::Option<blot_parse_ast::Span> = blot_support::Option<blot_parse_ast::Span> { false, default<blot_parse_ast::Span>() },
    qualification_unit: u32 = 0,
}
struct Version { variable: u32, replacement: Id, position: Cursor, previous: u32, next: u32 = none }
struct Variable { first: u32 = none, last: u32 = none, region: bool = false, row_effect: blot_check_effects::Id = none }
struct Mark { nodes: i64, extra: i64, variables: i64, versions: i64, operations: i64, quantifier_goals: i64 = 0, quantifier_obligations: i64 = 0, effects: blot_check_effects::Mark }
struct ProjectionResolution { root: Id, at: Cursor, depth: u32 }
struct OperationKey { identity: NominalIdentity, instance: NominalIdentity, arity: u32, shape: u64 }
struct OperationChain { first: blot_check_effects::Label, last: blot_check_effects::Label }
struct OperationLink { next: blot_check_effects::Label = none, previous: blot_check_effects::Label = none, shape: u64 = 0 }
struct RowCertificate { generation: u16 = 0, argument_height: u8 = 0, has_arguments: bool = false }
struct ClosedRow { row: blot_check_effects::Id = 0, generation: u16 = 0, argument_height: u8 = 0, has_arguments: bool = false }
struct OperationRow { row: blot_check_effects::Id = 0, result: blot_check_effects::Id = 0, at: Cursor = 0, depth: i64 = 0, limit: i64 = 0, mutation: u64 = 0xffffffffffffffff, effects: u64 = 0xffffffffffffffff }

struct Store {lease:u32=0,owner_generation:u64=0,
nodes:Table_nodes&=inactive_nodes,
extra:Table_extra&=inactive_extra,
variables:Table_variables&=inactive_variables,
versions:Table_versions&=inactive_versions,
operations:Table_operations&=inactive_operations,
operation_links:Table_operation_links&=inactive_operation_links,
quantifier_goals:Table_quantifier_goals&=inactive_quantifier_goals,
quantifier_obligations:Table_quantifier_obligations&=inactive_quantifier_obligations,
occurs_seen:Table_occurs_seen&=inactive_occurs_seen,
closed_row_index:Table_closed_row_index&=inactive_closed_row_index,
closed_operation_index:Table_closed_operation_index&=inactive_closed_operation_index,
variable_views:Map_variable_views&=inactive_variable_views,
associated_equations:Map_associated_equations&=inactive_associated_equations,
projection_resolutions:Map_projection_resolutions&=inactive_projection_resolutions,
operation_chains:Map_operation_chains&=inactive_operation_chains,
effects:blot_check_effects::Store&=inactive_effects,
resolved:blot_reuse_epoch_resolution_cache::Cache&=inactive_resolved,
composites:blot_reuse_composite_resolution_cache::Cache&=inactive_composites,
owner_id:(u64)&=inactive_scalars.owner_id,
use_closed_rows:(bool)&=inactive_scalars.use_closed_rows,
closed_rows:(ClosedRow[4])&=inactive_scalars.closed_rows,
use_operation_rows:(bool)&=inactive_scalars.use_operation_rows,
operation_rows:(OperationRow[64])&=inactive_scalars.operation_rows,
has_usage_types:(bool)&=inactive_scalars.has_usage_types,
has_rank_types:(bool)&=inactive_scalars.has_rank_types,
next_rigid_scope:(u32)&=inactive_scalars.next_rigid_scope,
use_closed_graphs:(bool)&=inactive_scalars.use_closed_graphs,
has_proof_kinds:(bool)&=inactive_scalars.has_proof_kinds,
has_projections:(bool)&=inactive_scalars.has_projections,
projection_limit:(i64)&=inactive_scalars.projection_limit,
projection_steps:(i64)&=inactive_scalars.projection_steps,
resolution_depth_limit:(i64)&=inactive_scalars.resolution_depth_limit,
projection_exhausted:(bool)&=inactive_scalars.projection_exhausted,
projection_resolution_types:(u64)&=inactive_scalars.projection_resolution_types,
projection_resolution_rows:(u64)&=inactive_scalars.projection_resolution_rows,
projection_resolution_limit:(i64)&=inactive_scalars.projection_resolution_limit,
closed_generation:(u16)&=inactive_scalars.closed_generation,
closed_effect_physical_epoch:(u64)&=inactive_scalars.closed_effect_physical_epoch,
mutation_epoch:(u64)&=inactive_scalars.mutation_epoch,
occurs_steps:(u64)&=inactive_scalars.occurs_steps,
normalization:(blot_work_counters::Normalization)&=inactive_scalars.normalization,
resolution_steps:(u64)&=inactive_scalars.resolution_steps,
occurs_generation:(u32)&=inactive_scalars.occurs_generation,
use_resolution_cache:(bool)&=inactive_scalars.use_resolution_cache,
use_composite_cache:(bool)&=inactive_scalars.use_composite_cache,
composite_min_growth:(i64)&=inactive_scalars.composite_min_growth,
use_operation_shapes:(bool)&=inactive_scalars.use_operation_shapes,
operation_shape_generation:(u16)&=inactive_scalars.operation_shape_generation,
operation_shape_enabled:(bool)&=inactive_scalars.operation_shape_enabled,
}
struct Options { resolution_cache: bool = true, closed_graphs: bool = false, composite_cache: bool = true, composite_min_growth: i64 = 4 }



fn node(self: const Store&, id: Id) -> Node { return self.nodes.items[id]; }
fn list(self: const Store&, span: List) -> const Id[:] { return self.extra.items[span.start..span.start + span.len]; }
fn saveList(self: Store&, values: const Id[:]) -> List, Error {
    if values.len > none - self.extra.len { return List {}, Error.type_limit; }
    let start = self.extra.len as u32; self.extra.append(values);if self.extra.failure!=Error.none {return default<List>(),self.extra.failure;}
    return List { start, values.len as u32 }, Error.none;
}
fn tick(self: Store&) { if self.mutation_epoch != 0xffffffffffffffff { self.mutation_epoch += 1; } }
fn invalidateClosedGraphs(self: Store&) { if self.closed_generation != 0xffff { self.closed_generation += 1; } }
fn synchronizeClosedGraphs(self: Store&) {
    if self.closed_effect_physical_epoch == self.effects.physical_epoch { return; }
    invalidateClosedGraphs(self); self.closed_effect_physical_epoch = self.effects.physical_epoch;
}
fn replaceListItem(self: Store&, span: List, index: i64, value: Id) {
    assert(index < span.len && value < self.nodes.len); let slot = span.start + index;
    if self.extra.items[slot] == value { return; } self.extra.items[slot] = value;
    invalidateClosedGraphs(self); tick(self);
}
fn add(self: Store&, value: Node) -> Id, Error {
    if self.nodes.len == none { return 0, Error.type_limit; }
    let id = self.nodes.len as u32; var owned = value;
    if self.use_closed_graphs { synchronizeClosedGraphs(self); owned.closed_height = closedNodeHeight(self, value); owned.closed_generation = self.closed_generation; }
    self.nodes.push(owned);if self.nodes.failure!=Error.none {return 0,self.nodes.failure;} return id, Error.none;
}
fn formalRowKey(binder: Id) -> u32, Error {
    if binder == 0 || binder >= blot_check_effects::formal_key_bit { return 0, Error.type_limit; }
    return blot_check_effects::formal_key_bit | binder, Error.none;
}
fn rowKeyFormal(key: u32) -> blot_support::Option<Id> {
    if key & blot_check_effects::formal_key_bit == 0 { return blot_support::Option<Id> { false, 0 }; }
    return blot_support::Option<Id> { true, key & ~blot_check_effects::formal_key_bit };
}
fn effectError(error: Error) -> Error { if error == Error.effect_limit { return Error.type_limit; } return error; }
fn receiverIdentity(value: Node) -> blot_support::Option<NominalIdentity> {
    match value.tag {
        nominal => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { value.a, value.b } }; },
        unsigned32 => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, u32_type } }; },
        floating32 => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, f32_type } }; },
        boolean => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, boolean } }; },
        unit => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, unit } }; },
        array => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none } }; },
        list => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none - 1 } }; },
        cursor => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none - 2 } }; },
        _ => { return blot_support::Option<NominalIdentity> { false, default<NominalIdentity>() }; },
    }
}
fn isReflectionIdentity(unit_: u32, decl: u32) -> bool { return unit_ == none && (decl == 3 || decl == 4); }
fn compilerNominalArity(identity: NominalIdentity) -> blot_support::Option<u32> {
    if identity.unit != none { return blot_support::Option<u32> { false, 0 }; }
    match identity.decl {
        3, 4, 16 => { return blot_support::Option<u32> { true, 0 }; },
        5, 9, 20, 21, 22, 23, 24 => { return blot_support::Option<u32> { true, 1 }; },
        6 => { return blot_support::Option<u32> { true, 3 }; },
        8, 17, 18 => { return blot_support::Option<u32> { true, 2 }; },
        _ => { return blot_support::Option<u32> { false, 0 }; },
    }
}
fn compilerNominalVersionArgument(identity: NominalIdentity) -> blot_support::Option<u32> {
    if identity.unit == none && identity.decl == 18 { return blot_support::Option<u32> { true, 1 }; }
    return blot_support::Option<u32> { false, 0 };
}
fn closedHeight(self: const Store&, id: Id) -> u8 {
    if !self.use_closed_graphs || self.closed_generation == 0xffff || self.effects.physical_epoch == 0xffffffffffffffff || self.closed_effect_physical_epoch != self.effects.physical_epoch { return 0; }
    if id <= never { if id == absent { return 0; } return 1; }
    let value = node(self, id);
    if value.closed_generation == self.closed_generation { return value.closed_height; }
    return 0;
}
fn knownClosed(self: const Store&, id: Id) -> bool { return closedHeight(self, id) != 0; }
fn spanSlot(labels: blot_check_effects::List) -> i64 { return ((labels.start ^ (labels.start >> 8) ^ labels.len) % 4) as i64; }
fn closedRow(self: const Store&, id: blot_check_effects::Id) -> blot_support::Option<ClosedRow> {
    if !self.use_closed_rows || !self.use_closed_graphs || self.closed_generation == 0xffff || self.effects.physical_epoch == 0xffffffffffffffff || self.closed_effect_physical_epoch != self.effects.physical_epoch { return blot_support::Option<ClosedRow> { false, ClosedRow {} }; }
    var value = self.closed_rows[id % self.closed_rows.len];
    if id < self.closed_row_index.len {
        let proof = self.closed_row_index.items[id];
        value = ClosedRow { id, proof.generation, proof.argument_height, proof.has_arguments };
    }
    if value.row == id && value.generation == self.closed_generation { return blot_support::Option<ClosedRow> { true, value }; }
    let labels = row(self, id).labels; let shared = self.closed_rows[spanSlot(labels)];
    if shared.generation != self.closed_generation || shared.row >= self.effects.rows.len { return blot_support::Option<ClosedRow> { false, ClosedRow {} }; }
    let old = row(self, shared.row).labels;
    if old.start == labels.start && old.len == labels.len { return blot_support::Option<ClosedRow> { true, ClosedRow { id, shared.generation, shared.argument_height, shared.has_arguments } }; }
    return blot_support::Option<ClosedRow> { false, ClosedRow {} };
}
fn saveClosedRow(self: Store&, id: blot_check_effects::Id, height: u8, has_arguments: bool) {
    if !self.use_closed_rows || !self.use_closed_graphs || self.closed_generation == 0xffff || self.effects.physical_epoch == 0xffffffffffffffff || self.closed_effect_physical_epoch != self.effects.physical_epoch { return; }
    if id < self.closed_row_index.len { self.closed_row_index.items[id] = RowCertificate { self.closed_generation, height, has_arguments }; }
    let slot = spanSlot(row(self, id).labels);
    if self.closed_rows[slot].generation == self.closed_generation && self.closed_rows[slot].row != id { self.normalization.closed_row_evictions += 1; }
    self.closed_rows[slot] = ClosedRow { id, self.closed_generation, height, has_arguments };
}
fn closedOperation(self: const Store&, label: blot_check_effects::Label) -> blot_support::Option<RowCertificate> {
    if !self.use_closed_rows || !self.use_closed_graphs || self.closed_generation == 0xffff || self.effects.physical_epoch == 0xffffffffffffffff || self.closed_effect_physical_epoch != self.effects.physical_epoch || label >= self.closed_operation_index.len { return blot_support::Option<RowCertificate> { false, RowCertificate {} }; }
    let proof = self.closed_operation_index.items[label];
    return blot_support::Option<RowCertificate> { proof.generation == self.closed_generation, proof };
}
fn saveClosedOperation(self: Store&, label: blot_check_effects::Label, height: u8, has_arguments: bool) {
    if !self.use_closed_rows || !self.use_closed_graphs || self.closed_generation == 0xffff || self.effects.physical_epoch == 0xffffffffffffffff || self.closed_effect_physical_epoch != self.effects.physical_epoch || label >= self.closed_operation_index.len { return; }
    self.closed_operation_index.items[label] = RowCertificate { self.closed_generation, height, has_arguments };
}
fn closedRowHeight(self: Store&, id: blot_check_effects::Id) -> u8 {
    let value = self.effects.node(id);
    if value.tail != blot_check_effects::Tail.closed { return 0; }
    if value.labels.len == 0 { return 1; }
    let cached = closedRow(self, id);
    if cached.present { if cached.value.argument_height == 255 { return 0; } return cached.value.argument_height + 1; }
    var height: u8 = 0; var has_arguments = false;
    for label in self.effects.list(value.labels) {
        if label >= self.operations.len { return 0; }
        let proof = closedOperation(self, label);
        if proof.present { height = max(height, proof.value.argument_height); has_arguments = has_arguments || proof.value.has_arguments; continue; }
        let instance = self.operations.items[label].instance;
        if instance.unit == 0 && instance.decl != 0 { return 0; }
        var operation_height: u8 = 0;
        for arg in list(self, self.operations.items[label].arguments) {
            has_arguments = true; let argument_height = closedHeight(self, arg);
            if argument_height == 0 { return 0; }
            height = max(height, argument_height); operation_height = max(operation_height, argument_height);
        }
        saveClosedOperation(self, label, operation_height, self.operations.items[label].arguments.len != 0);
    }
    saveClosedRow(self, id, height, has_arguments);
    if height == 255 { return 0; } return height + 1;
}
fn closedNodeHeight(self: Store&, value: Node) -> u8 {
    var height: u8 = 0;
    match value.tag {
        absent, variable, forall, existential, bound, rigid => { return 0; },
        function, provider => {
            let row_height = closedRowHeight(self, value.c); if row_height == 0 { return 0; }
            height = closedHeight(self, value.a); if height == 0 { return 0; } height = max(height, row_height);
            if value.tag == Tag.function { let result = closedHeight(self, value.b); if result == 0 { return 0; } height = max(height, result); }
        },
        usage, scoped, array, list, cursor, resolver => {
            if (value.tag == Tag.scoped && value.b == 0) || (value.tag == Tag.usage && value.c != 0) { return 0; }
            height = closedHeight(self, value.a); if height == 0 { return 0; }
        },
        state_provider => {
            for child in [value.a, value.b, value.c] { let child_height = closedHeight(self, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        product => {
            for child in list(self, List { value.a, value.b }) { let child_height = closedHeight(self, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        record => {
            for index in value.b { let child_height = closedHeight(self, recordField(self, value, index).ty); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        projection => { return 0; },
        nominal, instance_selection => {
            for child in nominalArguments(self, value) { let child_height = closedHeight(self, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        _ => {},
    }
    if height == 255 { return 0; } return height + 1;
}
fn boundType(self: Store&, ordinal: u32, sort: u32) -> Id, Error { self.has_rank_types = true; return add(self, Node { Tag.bound, a: ordinal, b: sort }); }
fn rigidScope(self: Store&) -> u32, Error {
    if self.next_rigid_scope == none { return 0, Error.type_limit; }
    let scope = self.next_rigid_scope; self.next_rigid_scope += 1; return scope, Error.none;
}
fn rigid(self: Store&, scope: u32, ordinal: u32, sort: u32) -> Id, Error { self.has_rank_types = true; return add(self, Node { Tag.rigid, a: scope, b: ordinal, c: sort }); }
fn quantifierGoals(self: const Store&, owner: Id) -> const Obligation[:] { return blot_check_quantifier_goals::get(self.quantifier_goals.items, self.quantifier_obligations.items, owner); }
fn quantified(self: Store&, tag: Tag, body: Id, binders: const Id[:]) -> Id, Error { return quantifiedWithGoals(self, tag, body, binders, []); }
fn quantifiedWithGoals(self: Store&, tag: Tag, body: Id, binders: const Id[:], goals: const Obligation[:]) -> Id, Error {
    assert(tag == Tag.forall || tag == Tag.existential);
    if binders.len == 0 || binders.len > 4096 { return 0, Error.type_limit; }
    for binder, ordinal in binders {
        if binder >= self.nodes.len { return 0, Error.type_mismatch; }
        let leaf = node(self, binder);
        if leaf.tag != Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 { return 0, Error.type_mismatch; }
    }
    self.has_rank_types = true;
    var owned_goals: Obligation[>..] = []; owned_goals.append(goals);
    for goal in owned_goals { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child >= self.nodes.len { return 0, Error.type_mismatch; } } }
    let point = mark(self);
    let span, se = saveList(self, binders); if se != Error.none { rollback(self, point); return 0, se; }
    let owner, oe = add(self, Node { tag, a: body, b: span.start, c: span.len }); if oe != Error.none { rollback(self, point); return 0, oe; }
    if owned_goals.len != 0 {
        let stored, error = saveQuantifierGoals(self, owned_goals); if error != Error.none { rollback(self, point); return 0, error; }
        self.quantifier_goals.push(QuantifierGoals { owner, stored });if self.quantifier_goals.failure!=Error.none {return 0,self.quantifier_goals.failure;}
    }
    return owner, Error.none;
}
fn bindRankAnnotation(self: Store&, slot: Id, required: Id) -> Error {
    let root, error = resolve(self, slot, 0); if error != Error.none { return error; }
    if node(self, root).tag != Tag.variable { return unify(self, root, required); }
    var quantified_root = required;
    if node(self, quantified_root).tag == Tag.usage { quantified_root = node(self, quantified_root).a; }
    if node(self, quantified_root).tag != Tag.forall { return Error.type_mismatch; }
    let recursive_, recursion_error = occurs(self, node(self, root).a, required); if recursion_error != Error.none { return recursion_error; }
    if recursive_ { return Error.infinite_type; }
    return appendVersion(self, root, required);
}
fn reownQuantified(self: Store&, tag: Tag, body: Id, binders: const Id[:], goals: Obligation[:]) -> Id, Error {
    var replacements: Id[>..] = [];
    for binder in binders { let leaf = node(self, binder); let replacement, error = boundType(self, leaf.a, leaf.b); if error != Error.none { return 0, error; } replacements.push(replacement); }
    let owned_body, be = substitute(self, body, binders, replacements); if be != Error.none { return 0, be; }
    for &goal in goals { let replaced, error = substituteGoal(self, goal, binders, replacements); if error != Error.none { return 0, error; } goal = replaced; }
    return quantifiedWithGoals(self, tag, owned_body, replacements, goals);
}
fn saveQuantifierGoals(self: Store&, goals: const Obligation[:]) -> List, Error {
    if goals.len > 4096 || goals.len > none - self.quantifier_obligations.len { return List {}, Error.type_limit; }
    let start = self.quantifier_obligations.len as u32; self.quantifier_obligations.append(goals);if self.quantifier_obligations.failure!=Error.none {return default<List>(),self.quantifier_obligations.failure;} return List { start, goals.len as u32 }, Error.none;
}
fn substituteGoal(self: Store&, goal: Obligation, old: const Id[:], fresh_ids: const Id[:]) -> Obligation, Error {
    var result = goal;
    if goal.ty != 0 { let value, error = substitute(self, goal.ty, old, fresh_ids); if error != Error.none { return default<Obligation>(), error; } result.ty = value; }
    if goal.other != 0 { let value, error = substitute(self, goal.other, old, fresh_ids); if error != Error.none { return default<Obligation>(), error; } result.other = value; }
    if goal.result != 0 { let value, error = substitute(self, goal.result, old, fresh_ids); if error != Error.none { return default<Obligation>(), error; } result.result = value; }
    if goal.signature != 0 { let value, error = substitute(self, goal.signature, old, fresh_ids); if error != Error.none { return default<Obligation>(), error; } result.signature = value; }
    if goal.identity.unit == 0 && goal.identity.decl != 0 { let value, error = substitute(self, goal.identity.decl, old, fresh_ids); if error != Error.none { return default<Obligation>(), error; } result.identity.decl = value; }
    return result, Error.none;
}
struct RankInstance { body: Id, scope: u32 = 0, goals: List = List {} }
fn instantiateRank(self: Store&, root: Id, skolemize: bool) -> RankInstance, Error {
    let resolved, error = resolve(self, root, 0); if error != Error.none { return default<RankInstance>(), error; }
    let value = node(self, resolved);
    if value.tag != Tag.forall && value.tag != Tag.existential { return default<RankInstance>(), Error.type_mismatch; }
    var binders: Id[>..] = []; binders.append(list(self, List { value.b, value.c }));
    var replacements: Id[>..] = []; var scope: u32 = 0;
    if skolemize { let id, error = rigidScope(self); if error != Error.none { return default<RankInstance>(), error; } scope = id; }
    for binder in binders {
        let leaf = node(self, binder); if leaf.tag != Tag.bound || leaf.b > 2 { return default<RankInstance>(), Error.type_mismatch; }
        var id: Id = 0; var error = Error.none;
        if skolemize { let result, failure = rigid(self, scope, leaf.a, leaf.b); id = result; error = failure; }
        else if leaf.b == 1 { let result, failure = freshRowType(self); id = result; error = failure; }
        else if leaf.b == 2 { let result, failure = freshRegion(self); id = result; error = failure; }
        else { let result, failure = fresh(self); id = result; error = failure; }
        if error != Error.none { return default<RankInstance>(), error; } replacements.push(id);
    }
    var source_goals: Obligation[>..] = []; source_goals.append(quantifierGoals(self, resolved));
    for &goal in source_goals { let replaced, error = substituteGoal(self, goal, binders, replacements); if error != Error.none { return default<RankInstance>(), error; } goal = replaced; }
    let goals, ge = saveQuantifierGoals(self, source_goals); if ge != Error.none { return default<RankInstance>(), ge; }
    let body, be = substitute(self, value.a, binders, replacements); if be != Error.none { return default<RankInstance>(), be; }
    return RankInstance { body, scope, goals }, Error.none;
}
fn containsQuantifier(self: Store&, root: Id) -> bool, Error { if !self.has_rank_types { return false, Error.none; } return blot_check_rank_walk::quantified(self, root); }
fn containsRigidRow(self: Store&, root: blot_check_effects::Id, scope: u32) -> bool, Error { if !self.has_rank_types { return false, Error.none; } return blot_check_rank_walk::containsRow(self, root, scope); }
fn containsRigid(self: Store&, root: Id, scope: u32) -> bool, Error { if !self.has_rank_types { return false, Error.none; } return blot_check_rank_walk::contains(self, root, scope, false); }
fn freeBound(self: Store&, root: Id) -> bool, Error { if !self.has_rank_types { return false, Error.none; } return blot_check_rank_walk::contains(self, root, 0, true); }
fn increment(value: u64&) { if value != 0xffffffffffffffff { value += 1; } }
fn fresh(self: Store&) -> Id, Error {
    if self.variables.len >= none { return 0, Error.type_limit; } let index = self.variables.len as u32;
    self.variables.push(Variable {});if self.variables.failure!=Error.none {return 0,self.variables.failure;} increment(self.normalization.type_binders_created);
    let id, error = variableView(self, index, 0); if error != Error.none { self.variables.pop(); } return id, error;
}
fn freshRegion(self: Store&) -> Id, Error {
    if self.variables.len >= none { return 0, Error.type_limit; } let index = self.variables.len as u32;
    self.variables.push(Variable { region: true });if self.variables.failure!=Error.none {return 0,self.variables.failure;} increment(self.normalization.type_binders_created); self.has_rank_types = true;
    let id, error = variableView(self, index, 0); if error != Error.none { self.variables.pop(); } return id, error;
}
fn freshRowType(self: Store&) -> Id, Error {
    let point = mark(self); let row_, re = freshEffects(self); if re != Error.none { rollback(self, point); return 0, re; }
    if self.variables.len >= none { rollback(self, point); return 0, Error.type_limit; }
    let index = self.variables.len as u32; self.variables.push(Variable { row_effect: row_ });if self.variables.failure!=Error.none {return 0,self.variables.failure;} increment(self.normalization.type_binders_created); self.has_rank_types = true;
    let id, error = variableView(self, index, 0); if error != Error.none { rollback(self, point); } return id, error;
}
fn rowType(self: Store&, root: Id) -> blot_check_effects::Id, Error {
    let resolved, error = resolve(self, root, 0); if error != Error.none { return 0, error; } let leaf = node(self, resolved);
    if leaf.tag == Tag.variable && self.variables.items[leaf.a].row_effect != none { return self.variables.items[leaf.a].row_effect, Error.none; }
    if (leaf.tag == Tag.bound && leaf.b == 1 && leaf.c == 0) || (leaf.tag == Tag.rigid && leaf.c == 1) {
        let id, error = self.effects.row([], blot_check_effects::Tail.formal { resolved }); return id, effectError(error);
    }
    return 0, Error.type_mismatch;
}
fn rowIdentity(self: const Store&, root: Id) -> bool {
    if root >= self.nodes.len { return false; } let leaf = node(self, head(self, root, 0));
    match leaf.tag { variable => { return self.variables.items[leaf.a].row_effect != none; }, bound => { return leaf.b == 1 && leaf.c == 0; }, rigid => { return leaf.c == 1; }, _ => { return false; }, }
}
fn regionIdentity(self: const Store&, root: Id) -> bool {
    if root >= self.nodes.len { return false; } let leaf = node(self, head(self, root, 0));
    match leaf.tag { variable => { return self.variables.items[leaf.a].region; }, bound => { return leaf.b == 2; }, rigid => { return leaf.c == 2; }, _ => { return false; }, }
}
fn usage(self: Store&, payload: Id, kind: UsageKind, region: Id) -> Id, Error {
    if payload == absent || payload >= self.nodes.len || node(self, head(self, payload, 0)).tag == Tag.erased_proof { return 0, Error.type_mismatch; }
    if kind == blot_parse_ast::usagekind_shared { let affine, error = blot_check_usage_check::affine(self, payload); if error != Error.none { return 0, error; } if affine { return 0, Error.type_mismatch; } }
    let loan = kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut;
    if loan != (region != 0) || (loan && !regionIdentity(self, region)) { return 0, Error.type_mismatch; }
    self.has_usage_types = true; return add(self, Node { Tag.usage, a: payload, b: kind as u32, c: region });
}
fn proofKind(self: Store&) -> Id, Error { let marker, error = add(self, Node { Tag.erased_proof }); if error != Error.none { return 0, error; } self.has_proof_kinds = true; return marker, Error.none; }
fn dataKind(self: const Store&, root: Id) -> Error {
    if self.has_rank_types && (regionIdentity(self, root) || rowIdentity(self, root)) { return Error.type_mismatch; }
    if self.has_proof_kinds && node(self, head(self, root, 0)).tag == Tag.erased_proof { return Error.type_mismatch; }
    return Error.none;
}
fn variableView(self: Store&, index: u32, at: Cursor) -> Id, Error {
    var position = at; if self.variables.items[index].first == none && at <= cursor(self) { position = 0; }
    let key = ((index as u64) << 32) | position;
    block { let saved = self.variable_views.get(key); if saved { return saved, Error.none; } }
    let id, error = add(self, Node { Tag.variable, a: index, b: position }); if error != Error.none { return 0, error; }
    self.variable_views.insert(key, id);if self.variable_views.failure!=Error.none {return 0,self.variable_views.failure;} increment(self.normalization.variable_views_created); return id, Error.none;
}
fn function(self: Store&, parameter: Id, result: Id) -> Id, Error { return functionWithEffects(self, parameter, result, 0); }
fn functionWithEffects(self: Store&, parameter: Id, result: Id, effect_row: blot_check_effects::Id) -> Id, Error {
    if self.has_rank_types && (regionIdentity(self, parameter) || regionIdentity(self, result) || rowIdentity(self, parameter) || rowIdentity(self, result)) { return 0, Error.type_mismatch; }
    return add(self, Node { Tag.function, a: parameter, b: result, c: effect_row });
}
fn product(self: Store&, fields: const Id[:]) -> Id, Error {
    for field in fields { let error = dataKind(self, field); if error != Error.none { return 0, error; } }
    let span, error = saveList(self, fields); if error != Error.none { return 0, error; }
    return add(self, Node { Tag.product, a: span.start, b: span.len });
}
fn array(self: Store&, element: Id) -> Id, Error { let error = dataKind(self, element); if error != Error.none { return 0, error; } return add(self, Node { Tag.array, a: element }); }
fn sequence(self: Store&, tag: Tag, element: Id) -> Id, Error { assert(tag == Tag.array || tag == Tag.list || tag == Tag.cursor); let error = dataKind(self, element); if error != Error.none { return 0, error; } return add(self, Node { tag, a: element }); }
fn typeConstructor(self: Store&, identity: NominalIdentity) -> Id, Error { return add(self, Node { Tag.type_constructor, a: identity.unit, b: identity.decl }); }
fn resolver(self: Store&, token: Id) -> Id, Error { let error = dataKind(self, token); if error != Error.none { return 0, error; } return add(self, Node { Tag.resolver, a: token }); }
fn provider(self: Store&, operation_type: Id, implementation_effects: blot_check_effects::Id) -> Id, Error { let error = dataKind(self, operation_type); if error != Error.none { return 0, error; } return add(self, Node { Tag.provider, a: operation_type, c: implementation_effects }); }
fn stateProvider(self: Store&, read: Id, write: Id, state_type: Id) -> Id, Error { let error = dataKind(self, state_type); if error != Error.none { return 0, error; } return add(self, Node { Tag.state_provider, a: read, b: write, c: state_type }); }
fn record(self: Store&, fields: const Field[:]) -> Id, Error {
    var words: Id[>..] = [];
    for field in fields { let error = dataKind(self, field.ty); if error != Error.none { return 0, error; } words.push(field.name); words.push(field.ty); }
    let span, error = saveList(self, words); if error != Error.none { return 0, error; }
    return add(self, Node { Tag.record, a: span.start, b: fields.len as u32 });
}
fn scoped(self: Store&, descriptor: Id, instance: NominalIdentity) -> Id, Error { let error = dataKind(self, descriptor); if error != Error.none { return 0, error; } return add(self, Node { Tag.scoped, a: descriptor, b: instance.unit, c: instance.decl }); }
fn capabilityParameter(self: Store&, descriptor: Id) -> Id, Error { let variable, error = fresh(self); if error != Error.none { return 0, error; } return scoped(self, descriptor, NominalIdentity { 0, variable }); }
fn resolveInstance(self: Store&, instance: NominalIdentity, at: Cursor, depth: i64) -> NominalIdentity, Error {
    if instance.unit != 0 || instance.decl == 0 { return instance, Error.none; }
    let bound, error = resolveDepth(self, instance.decl, at, depth + 1); if error != Error.none { return default<NominalIdentity>(), error; }
    let value = node(self, bound);
    if value.tag == Tag.variable || value.tag == Tag.instance_selection || regionIdentity(self, bound) { return NominalIdentity { 0, bound }, Error.none; }
    if value.tag != Tag.scoped { return default<NominalIdentity>(), Error.type_mismatch; }
    return NominalIdentity { value.b, value.c }, Error.none;
}
fn instanceVersion(self: Store&, identity: NominalIdentity, ordinal: u32) -> Id, Error {
    if identity.unit == 0 || identity.decl == 0 || identity.decl >= 0x04000000 || ordinal >= 16 { return 0, Error.type_mismatch; }
    return add(self, Node { Tag.instance_version, a: identity.unit, b: identity.decl, c: ordinal });
}
fn instanceSelection(self: Store&, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error {
    if identity.unit == 0 || identity.decl == 0 || (arguments.len != 2 && arguments.len != 3) { return 0, Error.type_mismatch; }
    for argument in arguments[..2] { if argument >= self.nodes.len || node(self, argument).tag != Tag.scoped { return 0, Error.type_mismatch; } }
    if arguments.len == 3 && (arguments[2] >= self.nodes.len || node(self, arguments[2]).tag != Tag.instance_version) { return 0, Error.type_mismatch; }
    if self.nodes.len > 65536 { return 0, Error.type_limit; }
    for value, index in self.nodes.items {
        if value.tag != Tag.instance_selection || value.a != identity.unit || value.b != identity.decl { continue; }
        let choices = nominalArguments(self, value); if choices.len != arguments.len { continue; }
        if choices.len == 3 && node(self, choices[2]) != node(self, arguments[2]) { continue; }
        var same = true;
        for choice, i in choices[..2] { let old = node(self, choice); let next = node(self, arguments[i]); same = same && old.b == next.b && old.c == next.c; }
        if same { return index as u32, Error.none; }
    }
    return nominalLike(self, Tag.instance_selection, identity, arguments);
}
fn nominal(self: Store&, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error { return nominalLike(self, Tag.nominal, identity, arguments); }
fn nominalLike(self: Store&, tag: Tag, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error {
    for argument in arguments { let error = dataKind(self, argument); if error != Error.none { return 0, error; } }
    if arguments.len >= none || self.extra.len > none - arguments.len - 1 { return 0, Error.type_limit; }
    var owned: Id[>..] = []; owned.append(arguments); let start = self.extra.len as u32;
    self.extra.push(owned.len as u32);if self.extra.failure!=Error.none {return 0,self.extra.failure;} self.extra.append(owned);if self.extra.failure!=Error.none {return 0,self.extra.failure;}
    return add(self, Node { tag, a: identity.unit, b: identity.decl, c: start });
}
fn chargeProjection(self: Store&) -> Error { if self.projection_steps >= self.projection_limit { self.projection_exhausted = true; return Error.type_limit; } self.projection_steps += 1; return Error.none; }
fn projection(self: Store&, identity: NominalIdentity, member: u32, arguments: const Id[:]) -> Id, Error {
    for argument in arguments { let error = dataKind(self, argument); if error != Error.none { return 0, error; } }
    self.has_projections = true; let id, error = nominal(self, identity, arguments); if error != Error.none { return 0, error; }
    self.extra.push(member);if self.extra.failure!=Error.none {return 0,self.extra.failure;} self.nodes.items[id].tag = Tag.projection; self.nodes.items[id].closed_height = 0; return id, Error.none;
}
fn projectionMember(self: const Store&, value: Node) -> u32 { assert(value.tag == Tag.projection); return self.extra.items[value.c + 1 + self.extra.items[value.c]]; }
fn nominalArguments(self: const Store&, value: Node) -> const Id[:] { assert(value.tag == Tag.nominal || value.tag == Tag.projection || value.tag == Tag.instance_selection); return self.extra.items[value.c + 1..value.c + 1 + self.extra.items[value.c]]; }
fn recordField(self: const Store&, value: Node, index: i64) -> Field { assert(value.tag == Tag.record && index < value.b); return Field { self.extra.items[value.a + index * 2], self.extra.items[value.a + index * 2 + 1] }; }
fn mergeRecords(self: Store&, left: Id, right: Id) -> blot_support::Option<Id>, Error {
    let a = node(self, head(self, left, 0)); let b = node(self, head(self, right, 0));
    if a.tag == Tag.never || b.tag == Tag.never { return blot_support::Option<Id> { true, never }, Error.none; }
    if (a.tag != Tag.record && a.tag != Tag.variable) || (b.tag != Tag.record && b.tag != Tag.variable) { return blot_support::Option<Id> { false, 0 }, Error.type_mismatch; }
    if a.tag == Tag.variable || b.tag == Tag.variable { return blot_support::Option<Id> { false, 0 }, Error.none; }
    if a.b == 0 { return blot_support::Option<Id> { true, right }, Error.none; } if b.b == 0 { return blot_support::Option<Id> { true, left }, Error.none; }
    var fields: Field[>..] = []; var slots = dictionary<u32, i64> {};
    for shape in [a, b] { for index in shape.b {
        let field = recordField(self, shape, index); var found = false; var slot: i64 = 0;
        block { let previous = slots.get(field.name); if previous { found = true; slot = previous; } }
        if found { fields[slot] = field; } else { slots.insert(field.name, fields.len); fields.push(field); }
    } }
    let result, error = record(self, fields); return blot_support::Option<Id> { error == Error.none, result }, error;
}
fn cursor(self: const Store&) -> Cursor { return self.effects.next_position; }
fn mark(self: const Store&) -> Mark { return Mark { self.nodes.len, self.extra.len, self.variables.len, self.versions.len, self.operations.len, self.quantifier_goals.len, self.quantifier_obligations.len, self.effects.mark() }; }
fn rollback(self: Store&, point: Mark) {
    var discarded: Id[>..] = [];
    for slot in self.associated_equations.slots { if slot.tag != 0 && (slot.key >= point.nodes || slot.val >= point.nodes) { discarded.push(slot.key); } }
    for key in discarded { self.associated_equations.remove(key); }
    invalidateClosedGraphs(self); tick(self);
    while self.versions.len > point.versions {
        let write = self.versions.pop(); self.variables.items[write.variable].last = write.previous;
        if write.previous == none { self.variables.items[write.variable].first = none; } else { self.versions.items[write.previous].next = none; }
    }
    for value in self.nodes.items[point.nodes..] { if value.tag == Tag.variable { self.variable_views.remove(((value.a as u64) << 32) | value.b); } }
    self.nodes.pop_n(self.nodes.len - point.nodes); self.extra.pop_n(self.extra.len - point.extra); self.variables.pop_n(self.variables.len - point.variables);
    unlinkOperations(self, point.operations); self.operations.pop_n(self.operations.len - point.operations);
    self.quantifier_goals.pop_n(self.quantifier_goals.len - point.quantifier_goals); self.quantifier_obligations.pop_n(self.quantifier_obligations.len - point.quantifier_obligations);
    self.effects.rollback(point.effects); self.closed_effect_physical_epoch = self.effects.physical_epoch;
}
fn appendVersion(self: Store&, variable: Id, replacement_id: Id) -> Error {
    let value = node(self, variable); assert(value.tag == Tag.variable); let old = self.variables.items[value.a];
    if old.row_effect != none { if !rowIdentity(self, replacement_id) { return Error.type_mismatch; } }
    else if old.region { if !regionIdentity(self, replacement_id) { return Error.type_mismatch; } }
    else { let error = dataKind(self, replacement_id); if error != Error.none { return error; } }
    if self.versions.len == none || cursor(self) == none { return Error.type_limit; }
    let index = self.versions.len as u32; self.versions.push(Version { value.a, replacement_id, cursor(self), old.last });if self.versions.failure!=Error.none {return self.versions.failure;}
    if old.last == none { self.variables.items[value.a].first = index; } else { self.versions.items[old.last].next = index; }
    self.variables.items[value.a].last = index; self.effects.next_position += 1; tick(self); return Error.none;
}
fn replacement(self: const Store&, index: u32, at: Cursor) -> blot_support::Option<Version> {
    var version = self.variables.items[index].first;
    if version == none { return blot_support::Option<Version> { false, default<Version>() }; }
    let first = self.versions.items[version]; if first.position >= at { return blot_support::Option<Version> { true, first }; }
    if self.versions.items[self.variables.items[index].last].position < at { return blot_support::Option<Version> { false, default<Version>() }; }
    version = first.next;
    while version != none { let value = self.versions.items[version]; if value.position >= at { return blot_support::Option<Version> { true, value }; } version = value.next; }
    return blot_support::Option<Version> { false, default<Version>() };
}
fn bindAssociated(self: Store&, projection_: Id, result: Id) -> Error {
    let kind = dataKind(self, result); if kind != Error.none { return kind; } let charged = chargeProjection(self); if charged != Error.none { return charged; }
    if node(self, projection_).tag != Tag.projection { return Error.type_mismatch; }
    self.associated_equations.insert(projection_, result);if self.associated_equations.failure!=Error.none {return self.associated_equations.failure;} tick(self); return Error.none;
}
fn head(self: const Store&, root: Id, at: Cursor) -> Id {
    var id = root; var position = at;
    while node(self, id).tag == Tag.variable {
        let variable = node(self, id); position = max(position, variable.b); let write = replacement(self, variable.a, position);
        if !write.present { break; } id = write.value.replacement; position = write.value.position + 1;
    }
    block { let equation = self.associated_equations.get(id); if equation { id = equation; } }
    let value = node(self, id);
    if value.tag == Tag.variable { let saved = self.variable_views.get(((value.a as u64) << 32) | position); if saved { return saved; } }
    return id;
}

fn tagCode(value: Tag) -> u32 {
    match value {
        absent => { return 0; },
        unit => { return 1; },
        boolean => { return 2; },
        unsigned32 => { return 3; },
        floating32 => { return 4; },
        never => { return 5; },
        variable => { return 6; },
        function => { return 7; },
        product => { return 8; },
        record => { return 9; },
        nominal => { return 10; },
        array => { return 11; },
        list => { return 12; },
        cursor => { return 13; },
        type_constructor => { return 14; },
        resolver => { return 15; },
        provider => { return 16; },
        state_provider => { return 17; },
        projection => { return 18; },
        scoped => { return 19; },
        instance_selection => { return 20; },
        erased_proof => { return 21; },
        forall => { return 22; },
        existential => { return 23; },
        bound => { return 24; },
        rigid => { return 25; },
        usage => { return 26; },
        instance_version => { return 27; },
    }
}
fn tagFromCode(code: u32) -> Tag, Error {
    match code {
        0 => { return Tag.absent, Error.none; },
        1 => { return Tag.unit, Error.none; },
        2 => { return Tag.boolean, Error.none; },
        3 => { return Tag.unsigned32, Error.none; },
        4 => { return Tag.floating32, Error.none; },
        5 => { return Tag.never, Error.none; },
        6 => { return Tag.variable, Error.none; },
        7 => { return Tag.function, Error.none; },
        8 => { return Tag.product, Error.none; },
        9 => { return Tag.record, Error.none; },
        10 => { return Tag.nominal, Error.none; },
        11 => { return Tag.array, Error.none; },
        12 => { return Tag.list, Error.none; },
        13 => { return Tag.cursor, Error.none; },
        14 => { return Tag.type_constructor, Error.none; },
        15 => { return Tag.resolver, Error.none; },
        16 => { return Tag.provider, Error.none; },
        17 => { return Tag.state_provider, Error.none; },
        18 => { return Tag.projection, Error.none; },
        19 => { return Tag.scoped, Error.none; },
        20 => { return Tag.instance_selection, Error.none; },
        21 => { return Tag.erased_proof, Error.none; },
        22 => { return Tag.forall, Error.none; },
        23 => { return Tag.existential, Error.none; },
        24 => { return Tag.bound, Error.none; },
        25 => { return Tag.rigid, Error.none; },
        26 => { return Tag.usage, Error.none; },
        27 => { return Tag.instance_version, Error.none; },
        _ => { return Tag.absent, Error.type_mismatch; },
    }
}

fn operatorCode(value: Operator) -> u32 {
    match value {
        none => { return 0; },
        add => { return 1; },
        sub => { return 2; },
        mul => { return 3; },
        div => { return 4; },
        rem => { return 5; },
        equal => { return 6; },
        not_equal => { return 7; },
        less => { return 8; },
        less_equal => { return 9; },
        greater => { return 10; },
        greater_equal => { return 11; },
        bit_and => { return 12; },
        bit_or => { return 13; },
        bit_xor => { return 14; },
        shift_left => { return 15; },
        shift_right => { return 16; },
    }
}
fn operatorFromCode(code: u32) -> Operator, Error {
    match code {
        0 => { return Operator.none, Error.none; },
        1 => { return Operator.add, Error.none; },
        2 => { return Operator.sub, Error.none; },
        3 => { return Operator.mul, Error.none; },
        4 => { return Operator.div, Error.none; },
        5 => { return Operator.rem, Error.none; },
        6 => { return Operator.equal, Error.none; },
        7 => { return Operator.not_equal, Error.none; },
        8 => { return Operator.less, Error.none; },
        9 => { return Operator.less_equal, Error.none; },
        10 => { return Operator.greater, Error.none; },
        11 => { return Operator.greater_equal, Error.none; },
        12 => { return Operator.bit_and, Error.none; },
        13 => { return Operator.bit_or, Error.none; },
        14 => { return Operator.bit_xor, Error.none; },
        15 => { return Operator.shift_left, Error.none; },
        16 => { return Operator.shift_right, Error.none; },
        _ => { return Operator.none, Error.type_mismatch; },
    }
}

fn obligationKindCode(value: ObligationKind) -> u32 {
    match value {
        arithmetic => { return 0; },
        ordered => { return 1; },
        equality => { return 2; },
        integer => { return 3; },
        field => { return 4; },
        writable_field => { return 5; },
        dispatch => { return 6; },
        result_dispatch => { return 7; },
        monad_factory => { return 8; },
        resolver_dispatch => { return 9; },
        resolver_shape => { return 10; },
        effect_operation => { return 11; },
        effect_handler => { return 12; },
        receiver => { return 13; },
        update => { return 14; },
        type_rep => { return 15; },
        effect_rep => { return 16; },
        type_head => { return 17; },
        collection => { return 18; },
        record_merge => { return 19; },
        callee_use => { return 20; },
        type_eq => { return 21; },
        contract => { return 22; },
        task_receive => { return 23; },
    }
}
fn obligationKindFromCode(code: u32) -> ObligationKind, Error {
    match code {
        0 => { return ObligationKind.arithmetic, Error.none; },
        1 => { return ObligationKind.ordered, Error.none; },
        2 => { return ObligationKind.equality, Error.none; },
        3 => { return ObligationKind.integer, Error.none; },
        4 => { return ObligationKind.field, Error.none; },
        5 => { return ObligationKind.writable_field, Error.none; },
        6 => { return ObligationKind.dispatch, Error.none; },
        7 => { return ObligationKind.result_dispatch, Error.none; },
        8 => { return ObligationKind.monad_factory, Error.none; },
        9 => { return ObligationKind.resolver_dispatch, Error.none; },
        10 => { return ObligationKind.resolver_shape, Error.none; },
        11 => { return ObligationKind.effect_operation, Error.none; },
        12 => { return ObligationKind.effect_handler, Error.none; },
        13 => { return ObligationKind.receiver, Error.none; },
        14 => { return ObligationKind.update, Error.none; },
        15 => { return ObligationKind.type_rep, Error.none; },
        16 => { return ObligationKind.effect_rep, Error.none; },
        17 => { return ObligationKind.type_head, Error.none; },
        18 => { return ObligationKind.collection, Error.none; },
        19 => { return ObligationKind.record_merge, Error.none; },
        20 => { return ObligationKind.callee_use, Error.none; },
        21 => { return ObligationKind.type_eq, Error.none; },
        22 => { return ObligationKind.contract, Error.none; },
        23 => { return ObligationKind.task_receive, Error.none; },
        _ => { return ObligationKind.arithmetic, Error.type_mismatch; },
    }
}

fn selectionAtom(source, original: NominalIdentity) -> NominalIdentity {
    if original.unit != 0 || original.decl == 0 { return original; }
    let value = source.node(original.decl);
    if value.tag != Tag.instance_selection { return original; }
    let choices = source.nominalArguments(value);
    if choices.len == 3 { let version = source.node(choices[2]); return NominalIdentity { version.a, 0x40000000 | (version.b << 4) | version.c }; }
    return NominalIdentity { value.a, value.b };
}
fn saturatedAdd(value: u64&, added: u64) { if added > 0xffffffffffffffff - value { value = 0xffffffffffffffff; } else { value += added; } }
fn compositeWindow(self: Store&, root: Id, at: Cursor) -> Id, Error {
    let enabled = self.use_composite_cache && self.mutation_epoch < none && self.effects.mutation_epoch < none;
    if enabled { let result = compositeResult(self, root, at); if result.present { return result.value, Error.none; } }
    let before_nodes = self.nodes.len;
    let result, error = resolveDepth(self, root, at, 0); if error != Error.none { return 0, error; }
    if enabled && (result != root || self.composites.entries.len != 0) && self.nodes.len - before_nodes >= self.composite_min_growth && self.composites.activate(self.closed_generation, self.effects.physical_epoch) {
        let error = saveComposite(self, root, at, result); if error != Error.none { return 0, error; }
    }
    return result, Error.none;
}
fn compositeResult(self: Store&, root: Id, at: Cursor) -> blot_support::Option<Id> {
    self.normalization.composite_probes += 1;
    if self.composites.entries.len == 0 || !self.composites.activate(self.closed_generation, self.effects.physical_epoch) { return blot_support::Option<Id> { false, 0 }; }
    let certificate = self.composites.get(root, at);
    if !certificate.present { if self.composites.occupied(root, at) { self.normalization.composite_collisions += 1; } return blot_support::Option<Id> { false, 0 }; }
    if !validResolution(self, certificate.value) { return blot_support::Option<Id> { false, 0 }; }
    self.normalization.composite_hits += 1; return blot_support::Option<Id> { true, certificate.value.result };
}
fn saveComposite(self: Store&, root: Id, at: Cursor, result: Id) -> Error {
    let certificate = resolutionDependencies(self, result);
    if !certificate.present { self.normalization.composite_frontier_declines += 1; return Error.none; }
    let error = self.composites.put(root, at, certificate.value); if error != Error.none { return error; }
    self.normalization.composite_publications += 1; return Error.none;
}
fn validResolution(self: Store&, certificate: blot_reuse_composite_resolution_cache::Record) -> bool {
    if certificate.future_clock.present && certificate.future_clock.value != cursor(self) { self.normalization.composite_future_clock_misses += 1; return false; }
    for dependency in certificate.dependencies[..certificate.count] {
        var last: u32 = 0; if dependency.effect { last = self.effects.variables[dependency.variable].last; } else { last = self.variables.items[dependency.variable].last; }
        if last != dependency.last { self.normalization.composite_stale_dependencies += 1; return false; }
    }
    return true;
}
fn resolutionDependencies(self: const Store&, result: Id) -> blot_support::Option<blot_reuse_composite_resolution_cache::Record> {
    var certificate = blot_reuse_composite_resolution_cache::Record { result: result };
    var pending: Id[128] = [0; 128]; pending[0] = result; var count: i64 = 1; var budget: i64 = 256;
    while count != 0 {
        count -= 1; let id = pending[count]; if closedHeight(self, id) != 0 || id <= never { continue; }
        if budget == 0 { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; } budget -= 1;
        let value = node(self, id);
        if value.tag == Tag.variable {
            let variable = self.variables.items[value.a];
            if !certificate.add(blot_reuse_composite_resolution_cache::Dependency { value.a, variable.last }) { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; }
            if variable.first == none && value.b > cursor(self) { certificate.future_clock = blot_support::Option<u32> { true, cursor(self) }; }
            continue;
        }
        if value.tag == Tag.function || value.tag == Tag.provider {
            let row_ = row(self, value.c);
            for label in rowLabels(self, value.c) {
                let arguments = operationArguments(self, label);
                if arguments.len > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; }
                for argument in arguments { pending[count] = argument; count += 1; }
                let instance = operation(self, label).instance;
                if instance.unit == 0 && instance.decl != 0 { if count == pending.len { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; } pending[count] = instance.decl; count += 1; }
            }
            match row_.tail { variable v => {
                if !certificate.add(blot_reuse_composite_resolution_cache::Dependency { v.value, self.effects.variables[v.value].last, true }) { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; }
            }, _ => {}, }
        }
        var children: Id[3] = [0; 3]; var length: i64 = 0; var tail: const Id[:] = [];
        match value.tag {
            function => { children = [value.a, value.b, 0]; length = 2; },
            usage => { children = [value.a, value.c, 0]; length = 1; if value.c != 0 { length = 2; } },
            scoped => { children = [value.a, value.c, 0]; length = 1; if value.b == 0 { length = 2; } },
            array, list, cursor, resolver, provider => { children[0] = value.a; length = 1; },
            state_provider => { children = [value.a, value.b, value.c]; length = 3; },
            product => { tail = list(self, List { value.a, value.b }); },
            nominal, projection, instance_selection => { tail = nominalArguments(self, value); },
            record => {
                if value.b > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; }
                for i in value.b { pending[count + i] = recordField(self, value, i).ty; } count += value.b;
            },
            _ => {},
        }
        if length + tail.len > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate }; }
        for child in children[..length] { pending[count] = child; count += 1; }
        for child in tail { pending[count] = child; count += 1; }
    }
    return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { true, certificate };
}
fn resolve(self: Store&, root: Id, at: Cursor) -> Id, Error {
    let attribution_start = self.nodes.len; let result, error = resolveRoot(self, root, at);
    saturatedAdd(self.normalization.resolve_nodes_added, (self.nodes.len - attribution_start) as u64);
    return result, error;
}
fn resolveRoot(self: Store&, root: Id, at: Cursor) -> Id, Error {
    if self.use_closed_graphs {
        synchronizeClosedGraphs(self); if closedHeight(self, root) != 0 { return root, Error.none; }
        let raw = node(self, root);
        if self.use_resolution_cache && at == 0 && raw.tag == Tag.variable && raw.b == 0 && raw.c != 0 && raw.closed_generation == self.closed_generation && self.closed_generation != 0xffff && self.effects.physical_epoch != 0xffffffffffffffff {
            let remaining = node(self, raw.c); if closedHeight(self, raw.c) != 0 { return raw.c, Error.none; }
            if remaining.tag == Tag.variable {
                let last = self.variables.items[remaining.a].last;
                if last == none { if remaining.b == 0 || remaining.b > cursor(self) { return raw.c, Error.none; } }
                else if self.versions.items[last].position < remaining.b { return raw.c, Error.none; }
            }
        }
    }
    if !self.use_resolution_cache || root <= never { return resolveDepth(self, root, at, 0); }
    if at != 0 { return compositeWindow(self, root, at); }
    if self.mutation_epoch >= none || self.effects.mutation_epoch >= none { return resolveDepth(self, root, at, 0); }
    if !self.resolved.activate(self.mutation_epoch as u32, self.effects.mutation_epoch as u32) { return resolveDepth(self, root, at, 0); }
    let cached = self.resolved.get(root); if cached.present { return cached.value, Error.none; }
    let composite = self.use_composite_cache;
    if composite { let cached = compositeResult(self, root, at); if cached.present {
        if cached.value != root || root < self.resolved.high_water { let error = self.resolved.put(root, cached.value); if error != Error.none { return 0, error; } }
        return cached.value, Error.none;
    } }
    let before_nodes = self.nodes.len; let result, error = resolveDepth(self, root, at, 0); if error != Error.none { return 0, error; }
    if self.use_closed_graphs && self.closed_generation != 0xffff && self.effects.physical_epoch != 0xffffffffffffffff && (closedHeight(self, result) != 0 || node(self, result).tag == Tag.variable) && node(self, root).tag == Tag.variable && node(self, root).b == 0 {
        self.nodes.items[root].c = result; self.nodes.items[root].closed_generation = self.closed_generation; return result, Error.none;
    }
    if result == root && root >= self.resolved.high_water { return result, Error.none; }
    let publication = self.resolved.put(root, result); if publication != Error.none { return 0, publication; }
    if composite && self.nodes.len - before_nodes >= self.composite_min_growth && self.composites.activate(self.closed_generation, self.effects.physical_epoch) {
        let error = saveComposite(self, root, at, result); if error != Error.none { return 0, error; }
    }
    return result, Error.none;
}
recursive fn resolveDepth(self: Store&, root: Id, at: Cursor, depth: i64) -> Id, Error {
    increment(self.normalization.resolve_depth_entries);
    if (self.has_projections || self.use_closed_graphs) && self.use_resolution_cache && depth != 0 && root > never {
        if closedHeight(self, root) != 0 || self.mutation_epoch == 0xffffffffffffffff || self.effects.mutation_epoch == 0xffffffffffffffff { return resolveNode(self, root, at, depth); }
        if self.projection_resolution_types != self.mutation_epoch || self.projection_resolution_rows != self.effects.mutation_epoch || self.projection_resolution_limit != self.resolution_depth_limit {
            self.projection_resolutions.clear(); self.projection_resolution_types = self.mutation_epoch; self.projection_resolution_rows = self.effects.mutation_epoch; self.projection_resolution_limit = self.resolution_depth_limit;
        }
        if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
        let key = ProjectionResolution { root, at, depth as u32 };
        block { let cached = self.projection_resolutions.get(key); if cached { return cached, Error.none; } }
        let result, error = resolveNode(self, root, at, depth); if error != Error.none { return 0, error; }
        if self.projection_resolutions.count < 65536 { self.projection_resolutions.insert(key, result);if self.projection_resolutions.failure!=Error.none {return 0,self.projection_resolutions.failure;} }
        return result, Error.none;
    }
    return resolveNode(self, root, at, depth);
}
recursive fn resolveNode(self: Store&, root: Id, at: Cursor, depth: i64) -> Id, Error {
    block { let equation = self.associated_equations.get(root); if equation { return resolveDepth(self, equation, at, depth + 1); } }
    if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
    if depth >= self.resolution_depth_limit { return 0, Error.type_limit; }
    let height = closedHeight(self, root);
    if height != 0 { if depth + height > self.resolution_depth_limit { return 0, Error.type_limit; } return root, Error.none; }
    var id = root; var position = at;
    while node(self, id).tag == Tag.variable {
        let variable = node(self, id); position = max(position, variable.b); let write = replacement(self, variable.a, position);
        if !write.present { break; } id = write.value.replacement; position = write.value.position + 1;
    }
    if id != root { let height = closedHeight(self, id); if height != 0 { if depth + height > self.resolution_depth_limit { return 0, Error.type_limit; } return id, Error.none; } }
    let value = node(self, id); let result, error = resolveSelected(self, id, value, position, depth);
    if self.use_closed_graphs && value.tag != Tag.variable && self.closed_generation != 0xffff {
        let refreshed = closedNodeHeight(self, value); if refreshed != 0 { self.nodes.items[id].closed_height = refreshed; self.nodes.items[id].closed_generation = self.closed_generation; }
    }
    return result, error;
}
recursive fn resolveSelected(self: Store&, id: Id, value: Node, position: Cursor, depth: i64) -> Id, Error {
    match value.tag {
        forall, existential => {
            var binders: Id[>..] = []; binders.append(list(self, List { value.b, value.c }));
            let body, error = resolveDepth(self, value.a, position, depth + 1); if error != Error.none { return 0, error; }
            var goals: Obligation[>..] = []; goals.append(quantifierGoals(self, id)); var changed = body != value.a;
            for &goal in goals {
                if goal.ty != 0 { let child, error = resolveDepth(self, goal.ty, position, depth + 1); if error != Error.none { return 0, error; } changed = changed || child != goal.ty; goal.ty = child; }
                if goal.other != 0 { let child, error = resolveDepth(self, goal.other, position, depth + 1); if error != Error.none { return 0, error; } changed = changed || child != goal.other; goal.other = child; }
                if goal.result != 0 { let child, error = resolveDepth(self, goal.result, position, depth + 1); if error != Error.none { return 0, error; } changed = changed || child != goal.result; goal.result = child; }
                if goal.signature != 0 { let child, error = resolveDepth(self, goal.signature, position, depth + 1); if error != Error.none { return 0, error; } changed = changed || child != goal.signature; goal.signature = child; }
            }
            if !changed { return id, Error.none; } return reownQuantified(self, value.tag, body, binders, goals);
        },
        usage => {
            let payload, pe = resolveDepth(self, value.a, position, depth + 1); if pe != Error.none { return 0, pe; }
            var region = value.c; if region != 0 { let next, error = resolveDepth(self, region, position, depth + 1); if error != Error.none { return 0, error; } region = next; }
            if payload == value.a && region == value.c { return id, Error.none; } return usage(self, payload, value.b as UsageKind, region);
        },
        scoped => {
            let child, ce = resolveDepth(self, value.a, position, depth + 1); if ce != Error.none { return 0, ce; }
            let instance, ie = resolveInstance(self, NominalIdentity { value.b, value.c }, position, depth + 1); if ie != Error.none { return 0, ie; }
            if child == value.a && instance.unit == value.b && instance.decl == value.c { return id, Error.none; } return scoped(self, child, instance);
        },
        variable => { return variableView(self, value.a, position); },
        function => {
            let parameter, pe = resolveDepth(self, value.a, position, depth + 1); if pe != Error.none { return 0, pe; }
            let result, re = resolveDepth(self, value.b, position, depth + 1); if re != Error.none { return 0, re; }
            let effect_row, ee = resolveOperationRow(self, value.c, position, depth + 1); if ee != Error.none { return 0, ee; }
            if parameter == value.a && result == value.b && effect_row == value.c { return id, Error.none; }
            return functionWithEffects(self, parameter, result, effect_row);
        },
        product => {
            var fields: Id[>..] = []; var changed = false;
            for i in value.b {
                let old = self.extra.items[value.a + i]; let child, error = resolveDepth(self, old, position, depth + 1); if error != Error.none { return 0, error; }
                if !changed && child != old { fields.append(self.extra.items[value.a..value.a + i]); changed = true; }
                if changed { fields.push(child); }
            }
            if changed { return product(self, fields); } return id, Error.none;
        },
        array, list, cursor, resolver => {
            let child, error = resolveDepth(self, value.a, position, depth + 1); if error != Error.none { return 0, error; }
            if child == value.a { return id, Error.none; } if value.tag == Tag.resolver { return resolver(self, child); } return sequence(self, value.tag, child);
        },
        provider => {
            let child, ce = resolveDepth(self, value.a, position, depth + 1); if ce != Error.none { return 0, ce; }
            let effect_row, ee = resolveOperationRow(self, value.c, position, depth + 1); if ee != Error.none { return 0, ee; }
            if child == value.a && effect_row == value.c { return id, Error.none; } return provider(self, child, effect_row);
        },
        state_provider => {
            let read, re = resolveDepth(self, value.a, position, depth + 1); if re != Error.none { return 0, re; }
            let write, we = resolveDepth(self, value.b, position, depth + 1); if we != Error.none { return 0, we; }
            let state_type, se = resolveDepth(self, value.c, position, depth + 1); if se != Error.none { return 0, se; }
            if read == value.a && write == value.b && state_type == value.c { return id, Error.none; } return stateProvider(self, read, write, state_type);
        },
        record => {
            var fields: Field[>..] = []; var changed = false;
            for i in value.b {
                let field = recordField(self, value, i); let child, error = resolveDepth(self, field.ty, position, depth + 1); if error != Error.none { return 0, error; }
                if !changed && child != field.ty { for prefix in i { fields.push(recordField(self, value, prefix)); } changed = true; }
                if changed { fields.push(Field { field.name, child }); }
            }
            if changed { return record(self, fields); } return id, Error.none;
        },
        nominal, projection, instance_selection => {
            var args: Id[>..] = []; var changed = false; let count = self.extra.items[value.c];
            for i in count {
                let child = self.extra.items[value.c + 1 + i]; let next, error = resolveDepth(self, child, position, depth + 1); if error != Error.none { return 0, error; }
                if !changed && child != next { args.append(self.extra.items[value.c + 1..value.c + 1 + i]); changed = true; } if changed { args.push(next); }
            }
            if !changed { return id, Error.none; }
            if value.tag == Tag.projection { return projection(self, NominalIdentity { value.a, value.b }, projectionMember(self, value), args); }
            if value.tag == Tag.instance_selection { return instanceSelection(self, NominalIdentity { value.a, value.b }, args); }
            return nominal(self, NominalIdentity { value.a, value.b }, args);
        },
        _ => { return id, Error.none; },
    }
}
fn occurs(self: Store&, variable: u32, root: Id) -> bool, Error {
    let resolved_root, error = resolve(self, root, 0); if error != Error.none { return false, error; }
    if closedHeight(self, resolved_root) != 0 || resolved_root <= never { self.occurs_steps += 1; return false, Error.none; }
    if self.occurs_seen.len < self.nodes.len { self.occurs_seen.resize(self.nodes.len, 0);if self.occurs_seen.failure!=Error.none {return false,self.occurs_seen.failure;} }
    self.occurs_generation += 1;
    if self.occurs_generation == 0 { for &value in self.occurs_seen.items { value = 0; } self.occurs_generation = 1; }
    var pending: Id[>..<] = []; pending.push(resolved_root); var budget: i64 = 1000000;
    while pending.len > 0 {
        let id = pending.pop(); if self.occurs_seen.items[id] == self.occurs_generation { continue; } self.occurs_seen.items[id] = self.occurs_generation;
        if budget == 0 { return false, Error.type_limit; } budget -= 1; self.occurs_steps += 1; if closedHeight(self, id) != 0 { continue; }
        let value = node(self, id);
        if value.tag == Tag.function || value.tag == Tag.provider { for label in rowLabels(self, value.c) {
            pending.append(operationArguments(self, label)); let instance = operation(self, label).instance;
            if instance.unit == 0 && instance.decl != 0 { pending.push(instance.decl); }
        } }
        match value.tag {
            variable => { if value.a == variable { return true, Error.none; } },
            function => { pending.append([value.a, value.b]); },
            product => { pending.append(list(self, List { value.a, value.b })); },
            usage => { pending.push(value.a); if value.c != 0 { pending.push(value.c); } },
            scoped => { pending.push(value.a); if value.b == 0 { pending.push(value.c); } },
            forall, existential => { pending.push(value.a); for goal in quantifierGoals(self, id) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { pending.push(child); } } } },
            array, list, cursor, resolver, provider => { pending.push(value.a); },
            state_provider => { pending.append([value.a, value.b, value.c]); },
            record => { for i in value.b { pending.push(recordField(self, value, i).ty); } },
            nominal, projection, instance_selection => { pending.append(nominalArguments(self, value)); },
            _ => {},
        }
    }
    return false, Error.none;
}
fn unifyEffects(self: Store&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    let point = mark(self); let error = unifyEffectsInner(self, left, right); if error != Error.none { rollback(self, point); } return error;
}
fn unifyEffectsInner(self: Store&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    let a, ae = resolveEffects(self, left, 0); if ae != Error.none { return ae; }
    let b, be = resolveEffects(self, right, 0); if be != Error.none { return be; }
    var symbolic = false;
    for label in rowLabels(self, a) { if symbolic { break; } let result, error = symbolicOperation(self, label); if error != Error.none { return error; } symbolic = result; }
    for label in rowLabels(self, b) { if symbolic { break; } let result, error = symbolicOperation(self, label); if error != Error.none { return error; } symbolic = result; }
    if !symbolic { return effectError(self.effects.unify(a, b)); }
    var labels: blot_check_effects::Label[>..] = []; labels.append(rowLabels(self, a));
    var candidates: blot_check_effects::Label[>..] = []; candidates.append(rowLabels(self, b));
    for label in labels {
        var exact = false; for candidate in candidates { exact = exact || candidate == label; } if exact { continue; }
        let operation_ = operation(self, label); var selected: blot_support::Option<blot_check_effects::Label> = blot_support::Option<blot_check_effects::Label> { false, 0 };
        for candidate in candidates {
            let other = operation(self, candidate);
            if operation_.identity != other.identity || operation_.instance != other.instance || operation_.arguments.len != other.arguments.len { continue; }
            let trial = mark(self); let matched, error = unifyOperationArguments(self, label, candidate); rollback(self, trial);
            if error != Error.none { if error == Error.out_of_memory || error == Error.type_limit { return error; } continue; }
            if !matched { continue; }
            if selected.present { if selected.value != candidate { return Error.effect_mismatch; } }
            else { selected = blot_support::Option<blot_check_effects::Label> { true, candidate }; }
        }
        if selected.present { let matched, error = unifyOperationArguments(self, label, selected.value); if error != Error.none { return error; } }
    }
    let ar, are = resolveEffects(self, a, 0); if are != Error.none { return are; }
    let br, bre = resolveEffects(self, b, 0); if bre != Error.none { return bre; }
    return effectError(self.effects.unify(ar, br));
}
fn symbolicOperation(self: Store&, label: blot_check_effects::Label) -> bool, Error {
    for argument in operationArguments(self, label) { if closedHeight(self, argument) != 0 { continue; } let same, error = equalClosed(self, argument, argument); if error != Error.none { return false, error; } if !same { return true, Error.none; } }
    return false, Error.none;
}
fn unifyOperationArguments(self: Store&, left: blot_check_effects::Label, right: blot_check_effects::Label) -> bool, Error {
    let ls, le = symbolicOperation(self, left); if le != Error.none { return false, le; }
    if !ls { let rs, re = symbolicOperation(self, right); if re != Error.none { return false, re; } if !rs { return false, Error.none; } }
    var a: Id[>..] = []; a.append(operationArguments(self, left)); var b: Id[>..] = []; b.append(operationArguments(self, right));
    for first, i in a { let error = unify(self, first, b[i]); if error != Error.none { return false, error; } }
    return true, Error.none;
}
fn freshEffects(self: Store&) -> blot_check_effects::Id, Error { let id, error = self.effects.fresh(); return id, effectError(error); }
fn resolveEffects(self: Store&, effect_row: blot_check_effects::Id, at: Cursor) -> blot_check_effects::Id, Error { if self.use_closed_graphs { synchronizeClosedGraphs(self); } return resolveOperationRow(self, effect_row, at, 0); }
recursive fn resolveOperationRow(self: Store&, root: blot_check_effects::Id, at: Cursor, depth: i64) -> blot_check_effects::Id, Error {
    self.normalization.row_requests += 1; if depth >= 1024 { return 0, Error.type_limit; }
    let id, error = self.effects.resolve(root, at); if error != Error.none { return 0, effectError(error); }
    let row_ = row(self, id); if row_.labels.len == 0 { return id, Error.none; }
    if self.use_closed_rows && self.use_closed_graphs && id >= self.closed_row_index.len {
        let previous = self.closed_row_index.len; self.closed_row_index.resize(self.effects.rows.len, RowCertificate {});if self.closed_row_index.failure!=Error.none {return default<blot_check_effects::Id>(),self.closed_row_index.failure;}
        for value in self.closed_rows { if value.row >= previous && value.row < self.closed_row_index.len { self.closed_row_index.items[value.row] = RowCertificate { value.generation, value.argument_height, value.has_arguments }; } }
    }
    let cached = closedRow(self, id);
    if cached.present { self.normalization.closed_row_hits += 1; if cached.value.has_arguments && depth + 1 + cached.value.argument_height > self.resolution_depth_limit { return 0, Error.type_limit; } return id, Error.none; }
    let mutation = self.mutation_epoch; let effects = self.effects.mutation_epoch;
    let cacheable = self.use_operation_rows && self.use_resolution_cache && mutation != 0xffffffffffffffff && effects != 0xffffffffffffffff;
    let slot = id % self.operation_rows.len;
    if cacheable {
        self.normalization.epoch_row_probes += 1; let saved = self.operation_rows[slot];
        if saved.row == id && saved.at == at && saved.depth == depth && saved.limit == self.resolution_depth_limit && saved.mutation == mutation && saved.effects == effects { self.normalization.epoch_row_hits += 1; return saved.result, Error.none; }
        if saved.row != id { if saved.row != 0 { self.normalization.epoch_row_collisions += 1; } }
        else if saved.mutation != mutation || saved.effects != effects { self.normalization.epoch_row_stale += 1; }
        else { self.normalization.epoch_row_context_misses += 1; }
    }
    let result, error = resolveOperationArguments(self, id, at, depth); if error != Error.none { return 0, error; }
    if cacheable && self.mutation_epoch == mutation && self.effects.mutation_epoch == effects {
        self.operation_rows[slot] = OperationRow { id, result, at, depth, self.resolution_depth_limit, mutation, effects }; self.normalization.epoch_row_publications += 1;
    }
    return result, Error.none;
}
recursive fn resolveOperationArguments(self: Store&, id: blot_check_effects::Id, at: Cursor, depth: i64) -> blot_check_effects::Id, Error {
    self.normalization.argument_rows += 1;
    if self.use_closed_rows && self.use_closed_graphs && self.closed_operation_index.len < self.operations.len { self.closed_operation_index.resize(self.operations.len, RowCertificate {});if self.closed_operation_index.failure!=Error.none {return default<blot_check_effects::Id>(),self.closed_operation_index.failure;} }
    let row_ = row(self, id); var all_closed = true; var argument_height: u8 = 0; var has_arguments = false;
    var labels: blot_check_effects::Label[>..] = []; var changed = false;
    for index in row_.labels.len {
        let label = self.effects.list(row_.labels)[index]; let operation_ = operation(self, label);
        self.normalization.labels += 1; self.normalization.arguments += operation_.arguments.len;
        let proof = closedOperation(self, label);
        if proof.present {
            self.normalization.closed_operation_hits += 1; has_arguments = has_arguments || proof.value.has_arguments; argument_height = max(argument_height, proof.value.argument_height);
            if proof.value.has_arguments && depth + 1 + proof.value.argument_height > self.resolution_depth_limit { return 0, Error.type_limit; }
            if changed { labels.push(label); } continue;
        }
        var closed = operation_.instance.unit != 0 || operation_.instance.decl == 0; var operation_height: u8 = 0;
        for argument in list(self, operation_.arguments) {
            has_arguments = true; let height = closedHeight(self, argument); self.normalization.argument_height_checks += 1;
            argument_height = max(argument_height, height); operation_height = max(operation_height, height);
            if height == 0 { closed = false; } if height != 0 && depth + 1 + height > self.resolution_depth_limit { return 0, Error.type_limit; }
        }
        all_closed = all_closed && closed;
        if closed { saveClosedOperation(self, label, operation_height, operation_.arguments.len != 0); if changed { labels.push(label); } continue; }
        var arguments: Id[>..] = []; var argument_changed = false;
        for offset in operation_.arguments.len {
            let argument = list(self, operation_.arguments)[offset]; let resolved, error = resolveDepth(self, argument, at, depth + 1); if error != Error.none { return 0, error; }
            if !argument_changed && resolved != argument { arguments.append(list(self, operation_.arguments)[..offset]); argument_changed = true; }
            if argument_changed { arguments.push(resolved); }
        }
        let instance, ie = resolveInstance(self, operation_.instance, at, depth + 1); if ie != Error.none { return 0, ie; }
        var next = label;
        if argument_changed || instance != operation_.instance {
            var selected_arguments = list(self, operation_.arguments); if argument_changed { selected_arguments = arguments; }
            let result, error = internResolvedOperation(self, operation_.identity, instance, selected_arguments, true); if error != Error.none { return 0, error; } next = result;
        }
        if !changed && next != label { labels.append(self.effects.list(row_.labels)[..index]); changed = true; }
        if changed { labels.push(next); }
    }
    if !changed { if all_closed { saveClosedRow(self, id, argument_height, has_arguments); } return id, Error.none; }
    self.normalization.changed_rows += 1; let result, error = self.effects.rowAt(labels, row_.tail, row_.cursor); return result, effectError(error);
}
fn row(self: const Store&, id: blot_check_effects::Id) -> blot_check_effects::Row { return self.effects.node(id); }
fn rowLabels(self: const Store&, id: blot_check_effects::Id) -> const blot_check_effects::Label[:] { return self.effects.list(row(self, id).labels); }
fn operation(self: const Store&, label: blot_check_effects::Label) -> Operation { return self.operations.items[label]; }
fn operationArguments(self: const Store&, label: blot_check_effects::Label) -> const Id[:] { return list(self, operation(self, label).arguments); }
fn internOperation(self: Store&, identity: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error { return internOperationMode(self, identity, NominalIdentity { 0, 0 }, arguments, false); }
fn internSymbolicOperation(self: Store&, identity: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error { return internOperationMode(self, identity, NominalIdentity { 0, 0 }, arguments, true); }
fn internScopedOperation(self: Store&, identity: NominalIdentity, instance: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error {
    if identity.unit == 0 && identity.decl == 1 && (instance.unit != 0 || instance.decl != 0) { return 0, Error.type_mismatch; }
    let resolved, error = resolveInstance(self, instance, 0, 0); if error != Error.none { return 0, error; }
    return internOperationMode(self, identity, resolved, arguments, true);
}
fn internOperationMode(self: Store&, identity: NominalIdentity, instance: NominalIdentity, arguments: const Id[:], symbolic: bool) -> blot_check_effects::Label, Error {
    let point = mark(self); var borrowed: Id[>..] = []; borrowed.append(arguments); var resolved: Id[>..] = [];
    for argument in borrowed {
        let ty, error = resolve(self, argument, 0); if error != Error.none { rollback(self, point); return 0, error; }
        let kind = dataKind(self, ty); if kind != Error.none { rollback(self, point); return 0, kind; }
        if !symbolic { let same, error = equalClosed(self, ty, ty); if error != Error.none { rollback(self, point); return 0, error; } if !same { rollback(self, point); return 0, Error.type_mismatch; } }
        resolved.push(ty);
    }
    let label, error = internResolvedOperation(self, identity, instance, resolved, symbolic); if error != Error.none { rollback(self, point); } return label, error;
}
fn internResolvedOperation(self: Store&, identity: NominalIdentity, instance: NominalIdentity, resolved: const Id[:], symbolic: bool) -> blot_check_effects::Label, Error {
    self.normalization.interner_requests += 1; let point = mark(self); let linked = linkOperations(self); if linked != Error.none { rollback(self, point); return 0, linked; }
    if resolved.len <= none {
        let key = OperationKey { identity, instance, resolved.len as u32, operationShape(self, resolved) };
        var first = none; block { let chain = self.operation_chains.get(key); if chain { first = chain.first; } }
        var index = first;
        while index != none {
            self.normalization.interner_candidates += 1; let old = list(self, self.operations.items[index].arguments); var same = true;
            for a, i in old { if !same { break; } self.normalization.interner_arguments += 1; let result, error = equalGraph(self, a, resolved[i], symbolic); if error != Error.none { rollback(self, point); return 0, error; } same = result; }
            if same { return index, Error.none; } index = self.operation_links.items[index].next;
        }
    }
    if self.operations.len == none { rollback(self, point); return 0, Error.type_limit; }
    let span, error = saveList(self, resolved); if error != Error.none { rollback(self, point); return 0, error; }
    let id = self.operations.len as u32; self.operations.push(Operation { identity, span, instance });if self.operations.failure!=Error.none {return default<blot_check_effects::Label>(),self.operations.failure;} return id, Error.none;
}
fn operationShape(self: const Store&, arguments: const Id[:]) -> u64 {
    if !self.operation_shape_enabled { return 0; } var value = arguments.len as u64;
    for argument in arguments[..min(arguments.len, 4)] { value = mixShape(value, operationTypeShape(self, argument, 2)); } return value;
}
fn mixShape(left: u64, right: u64) -> u64 { return (left ^ right) * 0x9e3779b97f4a7c15 + 0x85ebca6b; }
recursive fn operationTypeShape(self: const Store&, id: Id, depth: i64) -> u64 {
    let value = node(self, id); var fingerprint = tagCode(value.tag) as u64;
    match value.tag {
        variable, nominal, type_constructor, instance_selection => { fingerprint = mixShape(mixShape(fingerprint, value.a), value.b); },
        rigid, instance_version => { fingerprint = mixShape(mixShape(mixShape(fingerprint, value.a), value.b), value.c); },
        record, product => { fingerprint = mixShape(fingerprint, value.b); },
        usage => { var has_region: u64 = 0; if value.c != 0 { has_region = 1; } fingerprint = mixShape(mixShape(fingerprint, value.b), has_region); },
        scoped => { var region: u64 = 0; if value.b != 0 { region = value.c; } fingerprint = mixShape(mixShape(fingerprint, value.b), region); },
        _ => {},
    }
    if depth == 0 { return fingerprint; }
    match value.tag {
        array, list, cursor, resolver, provider, usage, scoped => { fingerprint = mixShape(fingerprint, operationTypeShape(self, value.a, depth - 1)); },
        function => { fingerprint = mixShape(fingerprint, operationTypeShape(self, value.a, depth - 1)); fingerprint = mixShape(fingerprint, operationTypeShape(self, value.b, depth - 1)); },
        product => { for child in list(self, List { value.a, min(value.b, 2) }) { fingerprint = mixShape(fingerprint, operationTypeShape(self, child, depth - 1)); } },
        _ => {},
    }
    return fingerprint;
}
fn linkOperations(self: Store&) -> Error {
    let enabled = self.use_operation_shapes && !self.has_projections && self.closed_generation != 0xffff;
    if self.operation_links.len > self.operations.len || self.operation_shape_generation != self.closed_generation || self.operation_shape_enabled != enabled {
        self.normalization.interner_rebuilds += 1; self.operation_chains.clear(); self.operation_links.clear();
    }
    self.operation_shape_generation = self.closed_generation; self.operation_shape_enabled = enabled;
    if self.operation_links.len == 0 { self.operation_links.push(OperationLink {});if self.operation_links.failure!=Error.none {return self.operation_links.failure;} }
    while self.operation_links.len < self.operations.len {
        self.normalization.interner_linked += 1; let index = self.operation_links.len as u32; let operation_ = self.operations.items[index];
        let shape = operationShape(self, list(self, operation_.arguments)); let key = OperationKey { operation_.identity, operation_.instance, operation_.arguments.len, shape };
        var found = false; var last = none;
        block { let entry = self.operation_chains.get(key); if entry { found = true; last = entry.last; entry.last = index; } }
        if found { self.operation_links.items[last].next = index; self.operation_links.push(OperationLink { previous: last, shape: shape });if self.operation_links.failure!=Error.none {return self.operation_links.failure;} }
        else { self.operation_links.push(OperationLink { shape: shape });if self.operation_links.failure!=Error.none {return self.operation_links.failure;} self.operation_chains.insert(key, OperationChain { index, index });if self.operation_chains.failure!=Error.none {return self.operation_chains.failure;} }
    }
    return Error.none;
}
fn unlinkOperations(self: Store&, length: i64) {
    if self.operation_links.len > self.operations.len { self.operation_chains.clear(); self.operation_links.clear(); }
    while self.operation_links.len > max(length, 1) {
        let index = self.operation_links.len - 1; let operation_ = self.operations.items[index];
        let key = OperationKey { operation_.identity, operation_.instance, operation_.arguments.len, self.operation_links.items[index].shape };
        let previous = self.operation_links.pop().previous;
        if previous == none { self.operation_chains.remove(key); }
        else { self.operation_links.items[previous].next = none; let chain = self.operation_chains.get(key); assert(chain); chain.last = previous; }
    }
}
struct Pair { a: Id, b: Id, effect_row: bool = false }
fn hash(value: Pair) -> u64 { var row: u64 = 0; if value.effect_row { row = 1; } return ::hash_combine(::hash_combine(::hash(value.a), ::hash(value.b)), ::hash(row)); }
fn hash(value: ProjectionResolution) -> u64 { return ::hash_combine(::hash_combine(::hash(value.root), ::hash(value.at)), ::hash(value.depth)); }
fn hash(value: OperationKey) -> u64 {
    return ::hash_combine(::hash_combine(::hash_combine(::hash_combine(::hash_combine(::hash(value.identity.unit), ::hash(value.identity.decl)), ::hash(value.instance.unit)), ::hash(value.instance.decl)), ::hash(value.arity)), ::hash(value.shape));
}
fn equalClosed(self: Store&, left: Id, right: Id) -> bool, Error { return equalGraph(self, left, right, false); }
fn equalSymbolic(self: Store&, left: Id, right: Id) -> bool, Error { return equalGraph(self, left, right, true); }
fn equalGraph(self: Store&, left: Id, right: Id, symbolic: bool) -> bool, Error {
    if !self.has_projections {
        if symbolic && left == right { return true, Error.none; } if !symbolic && left == right && closedHeight(self, left) != 0 { return true, Error.none; }
        let l = node(self, left); let r = node(self, right); if l.tag != r.tag { return false, Error.none; }
        match l.tag {
            absent, bound => { return false, Error.none; }, unit, boolean, unsigned32, floating32, never => { return true, Error.none; },
            nominal, instance_selection, type_constructor => { if l.a != r.a || l.b != r.b { return false, Error.none; } }, _ => {},
        }
    }
    return equalGraphWalk(self, left, right, symbolic);
}
fn equalLabelMultisets(left: const blot_check_effects::Label[:], right: const blot_check_effects::Label[:]) -> bool, Error {
    if left.len != right.len { return false, Error.none; } if left == right { return true, Error.none; }
    if left.len <= 16 {
        for label in left { var before: i64 = 0; var after: i64 = 0; for value in left { if value == label { before += 1; } } for value in right { if value == label { after += 1; } } if before != after { return false, Error.none; } }
        return true, Error.none;
    }
    var counts = dictionary<blot_check_effects::Label, i64> {};
    for label in left { let count = counts.get_or_insert(label, 0); count += 1; }
    for label in right { let count = counts.get(label); if !count { return false, Error.none; } if count == 0 { return false, Error.none; } count -= 1; }
    return true, Error.none;
}
fn equalGraphWalk(self: Store&, left: Id, right: Id, symbolic: bool) -> bool, Error {
    let shared_closed = !symbolic && !self.has_projections && closedHeight(self, left) != 0 && closedHeight(self, right) != 0;
    var pending: Pair[>..<] = []; pending.push(Pair { left, right }); var seen = dictionary<Pair, bool> {};
    var few: Pair[16] = [default<Pair>(); 16]; var few_count: i64 = 0; var budget: i64 = 1000000;
    while pending.len > 0 {
        let pair = pending.pop();
        if self.has_projections { let error = chargeProjection(self); if error != Error.none { return false, error; } }
        if symbolic && pair.a == pair.b { continue; }
        if symbolic || self.has_projections || shared_closed {
            if few_count < few.len {
                var repeated = false; for prior in few[..few_count] { if prior.a == pair.a && prior.b == pair.b { repeated = true; break; } }
                if repeated { continue; } few[few_count] = pair; few_count += 1;
            } else {
                if seen.count == 0 { for prior in few { seen.insert(prior, true); } }
                if seen.contains(pair) { continue; } seen.insert(pair, true);
            }
        }
        if budget == 0 { return false, Error.type_limit; } budget -= 1;
        let a = node(self, pair.a); let b = node(self, pair.b); if a.tag != b.tag { return false, Error.none; }
        match a.tag {
            bound, absent => { return false, Error.none; },
            rigid => { if !symbolic || a.a != b.a || a.b != b.b || a.c != b.c { return false, Error.none; } },
            usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return false, Error.none; } pending.push(Pair { a.a, b.a }); if a.c != 0 { pending.push(Pair { a.c, b.c }); } },
            forall, existential => { let same, error = blot_check_rank_equal::equal(self, pair.a, pair.b, symbolic); if error != Error.none || !same { return same, error; } },
            variable => { if !symbolic || a.a != b.a || a.b != b.b { return false, Error.none; } },
            function, provider => {
                let ar = self.effects.node(a.c); let br = self.effects.node(b.c);
                if symbolic { if ar.tail != br.tail || ar.cursor != br.cursor { return false, Error.none; } }
                else if ar.tail != blot_check_effects::Tail.closed || br.tail != blot_check_effects::Tail.closed { return false, Error.none; }
                let same, error = equalLabelMultisets(self.effects.list(ar.labels), self.effects.list(br.labels)); if error != Error.none || !same { return same, error; }
                for label in self.effects.list(ar.labels) {
                    for argument in operationArguments(self, label) { pending.push(Pair { argument, argument }); }
                    let instance = operation(self, label).instance; if instance.unit == 0 && instance.decl != 0 { pending.push(Pair { instance.decl, instance.decl }); }
                }
                if a.tag == Tag.function { pending.push(Pair { a.b, b.b }); } pending.push(Pair { a.a, b.a });
            },
            array, list, cursor, resolver => { pending.push(Pair { a.a, b.a }); },
            state_provider => { pending.append([Pair { a.a, b.a }, Pair { a.b, b.b }, Pair { a.c, b.c }]); },
            scoped => { if a.b != b.b { return false, Error.none; } if a.b == 0 { pending.push(Pair { a.c, b.c }); } else if a.c != b.c { return false, Error.none; } pending.push(Pair { a.a, b.a }); },
            instance_version => { if a.a != b.a || a.b != b.b || a.c != b.c { return false, Error.none; } },
            type_constructor => { if a.a != b.a || a.b != b.b { return false, Error.none; } },
            product => { if a.b != b.b { return false, Error.none; } for av, i in list(self, List { a.a, a.b }) { pending.push(Pair { av, list(self, List { b.a, b.b })[i] }); } },
            nominal, projection, instance_selection => {
                if a.a != b.a || a.b != b.b { return false, Error.none; } if a.tag == Tag.projection && projectionMember(self, a) != projectionMember(self, b) { return false, Error.none; }
                let aa = nominalArguments(self, a); let ba = nominalArguments(self, b); if aa.len != ba.len { return false, Error.none; }
                for av, i in aa { pending.push(Pair { av, ba[i] }); }
            },
            record => {
                if a.b != b.b { return false, Error.none; } var fields = dictionary<u32, Id> {};
                if b.b > 16 { for j in b.b { let other = recordField(self, b, j); if !fields.contains(other.name) { fields.insert(other.name, other.ty); } } }
                for i in a.b {
                    let field = recordField(self, a, i); var found = false; var ty: Id = 0;
                    if b.b > 16 { let saved = fields.get(field.name); if saved { found = true; ty = saved; } }
                    else { for j in b.b { let other = recordField(self, b, j); if field.name == other.name { ty = other.ty; found = true; break; } } }
                    if !found { return false, Error.none; } pending.push(Pair { field.ty, ty });
                }
            },
            _ => {},
        }
    }
    return true, Error.none;
}
struct SilentReporter {}
fn report(self: SilentReporter, store: const Store&, left: Id, right: Id) -> Error { return Error.none; }
fn mismatch(self: const Store&, reporter, left: Id, right: Id) -> Error { let error = reporter.report(self, left, right); if error != Error.none { return Error.out_of_memory; } return Error.type_mismatch; }
fn unify(self: Store&, left: Id, right: Id) -> Error { return unifyMode(self, left, right, SilentReporter {}, false); }
fn unifyWithReporter(self: Store&, left: Id, right: Id, reporter) -> Error { return unifyMode(self, left, right, reporter, false); }
fn unifyPattern(self: Store&, left: Id, right: Id) -> Error { return unifyMode(self, left, right, SilentReporter {}, true); }
fn resolveUnification(self: Store&, root: Id) -> Id, Error {
    let entries = self.normalization.resolve_depth_entries; let nodes = self.nodes.len; increment(self.normalization.unify_resolve_calls);
    let result, error = resolve(self, root, 0); saturatedAdd(self.normalization.unify_resolve_entries, self.normalization.resolve_depth_entries - entries); saturatedAdd(self.normalization.unify_resolve_nodes, (self.nodes.len - nodes) as u64); return result, error;
}
fn unifyMode(self: Store&, left: Id, right: Id, reporter, associated: bool) -> Error {
    let point = mark(self); let error = unifyInner(self, left, right, reporter, associated); if error != Error.none { rollback(self, point); } return error;
}
fn unifyInner(self: Store&, left: Id, right: Id, reporter, associated: bool) -> Error {
    var seen = dictionary<Pair, bool> {}; var pending: Pair[>..<] = []; pending.push(Pair { left, right });
    let bounded = associated || self.has_projections; var rank_active = false; var rank_remaining: i64 = 4096;
    while pending.len > 0 {
        let pair = pending.pop();
        if rank_active { if rank_remaining == 0 { return Error.type_limit; } rank_remaining -= 1; }
        if bounded { let error = chargeProjection(self); if error != Error.none { return error; } }
        if pair.effect_row {
            if bounded { for label in rowLabels(self, pair.a) { let error = chargeProjection(self); if error != Error.none { return error; } } for label in rowLabels(self, pair.b) { let error = chargeProjection(self); if error != Error.none { return error; } } }
            let error = unifyEffects(self, pair.a, pair.b); if error != Error.none { return error; } continue;
        }
        increment(self.normalization.unify_pairs); if self.has_projections { increment(self.normalization.unify_projected_pairs); }
        let a, ae = resolveUnification(self, pair.a); if ae != Error.none { return ae; }
        let b, be = resolveUnification(self, pair.b); if be != Error.none { return be; }
        let an = node(self, a); let bn = node(self, b);
        if rowIdentity(self, a) || rowIdentity(self, b) {
            if !rowIdentity(self, a) || !rowIdentity(self, b) { return mismatch(self, reporter, a, b); }
            let ar, are = rowType(self, a); if are != Error.none { return are; } let br, bre = rowType(self, b); if bre != Error.none { return bre; }
            let error = unifyEffects(self, ar, br); if error != Error.none { return error; } continue;
        }
        if an.tag == Tag.variable && self.variables.items[an.a].region && !regionIdentity(self, b) { return mismatch(self, reporter, a, b); }
        if bn.tag == Tag.variable && self.variables.items[bn.a].region && !regionIdentity(self, a) { return mismatch(self, reporter, a, b); }
        if a == b || a == never || b == never { continue; }
        if self.has_rank_types && (isRank(an.tag) || isRank(bn.tag)) { rank_active = true; }
        if bounded || rank_active { let key = Pair { a, b }; if seen.contains(key) { continue; } seen.insert(key, true); }
        if an.tag == Tag.variable && bn.tag == Tag.variable && an.a == bn.a { continue; }
        if an.tag == Tag.variable {
            if bn.tag == Tag.forall { return mismatch(self, reporter, a, b); }
            if !self.variables.items[an.a].region { let free, error = freeBound(self, b); if error != Error.none { return error; } if free { return mismatch(self, reporter, a, b); } }
            let infinite, error = occurs(self, an.a, b); if error != Error.none { return error; } if infinite { return Error.infinite_type; }
            let error = appendVersion(self, a, b); if error != Error.none { return error; } continue;
        }
        if bn.tag == Tag.variable {
            if an.tag == Tag.forall { return mismatch(self, reporter, a, b); }
            if !self.variables.items[bn.a].region { let free, error = freeBound(self, a); if error != Error.none { return error; } if free { return mismatch(self, reporter, a, b); } }
            let infinite, error = occurs(self, bn.a, a); if error != Error.none { return error; } if infinite { return Error.infinite_type; }
            let error = appendVersion(self, b, a); if error != Error.none { return error; } continue;
        }
        if an.tag != bn.tag { return mismatch(self, reporter, a, b); }
        match an.tag {
            usage => { if an.b != bn.b || (an.c == 0) != (bn.c == 0) { return mismatch(self, reporter, a, b); } pending.push(Pair { an.a, bn.a }); if an.c != 0 { pending.push(Pair { an.c, bn.c }); } },
            bound => { return mismatch(self, reporter, a, b); },
            rigid, instance_version => { if an.a != bn.a || an.b != bn.b || an.c != bn.c { return mismatch(self, reporter, a, b); } },
            forall, existential => {
                if an.c != bn.c { return mismatch(self, reporter, a, b); }
                var old: Id[>..] = []; old.append(list(self, List { bn.b, bn.c })); var fresh_ids: Id[>..] = []; fresh_ids.append(list(self, List { an.b, an.c }));
                for left_, i in old { if node(self, left_).b != node(self, fresh_ids[i]).b { return mismatch(self, reporter, a, b); } }
                var left_goals: Obligation[>..] = []; left_goals.append(quantifierGoals(self, a)); var right_goals: Obligation[>..] = []; right_goals.append(quantifierGoals(self, b));
                if left_goals.len != right_goals.len { return mismatch(self, reporter, a, b); }
                for left_goal, i in left_goals {
                    let right_goal = right_goals[i]; if !blot_check_quantifier_goals::sameHead(left_goal, right_goal) { return mismatch(self, reporter, a, b); }
                    let replaced, error = substituteGoal(self, right_goal, old, fresh_ids); if error != Error.none { return error; }
                    let first = [left_goal.ty, left_goal.other, left_goal.result, left_goal.signature]; let second = [replaced.ty, replaced.other, replaced.result, replaced.signature];
                    for left_child, j in first { let right_child = second[j]; if (left_child == 0) != (right_child == 0) { return mismatch(self, reporter, a, b); } if left_child != 0 { pending.push(Pair { left_child, right_child }); } }
                }
                let body, error = substitute(self, bn.a, old, fresh_ids); if error != Error.none { return error; } pending.push(Pair { an.a, body });
            },
            function => { pending.append([Pair { an.c, bn.c, true }, Pair { an.b, bn.b }, Pair { an.a, bn.a }]); },
            product => { if an.b != bn.b { return mismatch(self, reporter, a, b); } var i = an.b; while i != 0 { i -= 1; pending.push(Pair { self.extra.items[an.a + i], self.extra.items[bn.a + i] }); } },
            array, list, cursor, resolver => { pending.push(Pair { an.a, bn.a }); },
            provider => { pending.append([Pair { an.c, bn.c, true }, Pair { an.a, bn.a }]); },
            state_provider => { pending.append([Pair { an.c, bn.c }, Pair { an.b, bn.b }, Pair { an.a, bn.a }]); },
            scoped => {
                if an.b == 0 && node(self, an.c).tag == Tag.variable && !regionIdentity(self, an.c) { if bn.b != 0 || an.c != bn.c { pending.push(Pair { an.c, b }); } }
                else if bn.b == 0 && node(self, bn.c).tag == Tag.variable && !regionIdentity(self, bn.c) { pending.push(Pair { bn.c, a }); }
                else if an.b == 0 && bn.b == 0 { pending.push(Pair { an.c, bn.c }); }
                else if an.b != bn.b || an.c != bn.c { return mismatch(self, reporter, a, b); }
                pending.push(Pair { an.a, bn.a });
            },
            type_constructor => { if an.a != bn.a || an.b != bn.b { return mismatch(self, reporter, a, b); } },
            projection => {
                if an.a != bn.a || an.b != bn.b || projectionMember(self, an) != projectionMember(self, bn) { return mismatch(self, reporter, a, b); }
                var aa: Id[>..] = []; aa.append(nominalArguments(self, an)); var bb: Id[>..] = []; bb.append(nominalArguments(self, bn));
                if aa.len != bb.len { return mismatch(self, reporter, a, b); }
                for left_arg, i in aa {
                    let al, ae = resolve(self, left_arg, 0); if ae != Error.none { return ae; } let bl, be = resolve(self, bb[i], 0); if be != Error.none { return be; }
                    if al == bl { continue; } let same, error = equalSymbolic(self, al, bl); if error != Error.none { return error; } if !same { return mismatch(self, reporter, a, b); }
                }
            },
            nominal, instance_selection => {
                if an.a != bn.a || an.b != bn.b { return mismatch(self, reporter, a, b); } let aa = nominalArguments(self, an); let bb = nominalArguments(self, bn);
                if aa.len != bb.len { return mismatch(self, reporter, a, b); } var i = aa.len; while i != 0 { i -= 1; pending.push(Pair { aa[i], bb[i] }); }
            },
            record => {
                if an.b != bn.b { return mismatch(self, reporter, a, b); }
                for i in an.b { let af = recordField(self, an, i); var found = false; var ty: Id = 0; for j in bn.b { let bf = recordField(self, bn, j); if af.name == bf.name { ty = bf.ty; found = true; break; } } if !found { return mismatch(self, reporter, a, b); } pending.push(Pair { af.ty, ty }); }
            },
            _ => {},
        }
    }
    return Error.none;
}
fn isRank(tag: Tag) -> bool { match tag { forall, existential, bound, rigid => { return true; }, _ => { return false; }, } }
fn usageCode(kind: UsageKind) -> u32 { return kind; }
fn usageFromCode(code: u32) -> UsageKind, Error { if code > 7 { return 0, Error.type_mismatch; } return code, Error.none; }
fn appendChildren(self: const Store&, pending: Id[>..<]&, id: Id, scoped_identity: bool) {
    let value = node(self, id);
    match value.tag {
        function => { pending.append([value.a, value.b]); }, product => { pending.append(list(self, List { value.a, value.b })); },
        usage => { pending.push(value.a); if value.c != 0 { pending.push(value.c); } },
        scoped => { pending.push(value.a); if scoped_identity && value.b == 0 { pending.push(value.c); } },
        forall, existential => { pending.push(value.a); for goal in quantifierGoals(self, id) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { pending.push(child); } } } },
        array, list, cursor, resolver, provider => { pending.push(value.a); }, state_provider => { pending.append([value.a, value.b, value.c]); },
        record => { for i in value.b { pending.push(recordField(self, value, i).ty); } },
        nominal, projection, instance_selection => { pending.append(nominalArguments(self, value)); }, _ => {},
    }
}
fn freeVariables(self: Store&, root: Id) -> Id[>..], Error { return freeVariablesMode(self, root, true); }
fn freeVariablesMode(self: Store&, root: Id, bounded: bool) -> Id[>..], Error {
    var values: Id[>..] = []; var pending: Id[>..<] = [];
    let resolved, error = resolve(self, root, 0); if error != Error.none { return [], error; }
    if bounded && (resolved <= never || closedHeight(self, resolved) != 0) { return [], Error.none; }
    if bounded && node(self, resolved).tag == Tag.variable { values.push(resolved); return values, Error.none; }
    self.normalization.free_type_queries += 1; pending.push(resolved); var seen = dictionary<Id, bool> {};
    while pending.len > 0 {
        let id = pending.pop(); self.normalization.free_type_visits += 1;
        if self.has_projections { let error = chargeProjection(self); if error != Error.none { return [], error; } }
        if bounded && closedHeight(self, id) != 0 { continue; } if seen.contains(id) { continue; } seen.insert(id, true);
        let value = node(self, id);
        if value.tag == Tag.function || value.tag == Tag.provider { for label in rowLabels(self, value.c) { pending.append(operationArguments(self, label)); let instance = operation(self, label).instance; if instance.unit == 0 && instance.decl != 0 { pending.push(instance.decl); } } }
        if value.tag == Tag.variable { values.push(id); } else { appendChildren(self, pending, id, true); }
    }
    return values, Error.none;
}
struct ProjectionWork { root: Id, row: bool = false }
fn hash(value: ProjectionWork) -> u64 { var row: u64 = 0; if value.row { row = 1; } return ::hash_combine(::hash(value.root), ::hash(row)); }
fn containsProjection(self: Store&, root: Id) -> bool, Error {
    if !self.has_projections || root == 0 { return false, Error.none; }
    var pending: ProjectionWork[>..<] = []; var seen = dictionary<ProjectionWork, bool> {}; pending.push(ProjectionWork { root }); var remaining: i64 = 1000000;
    while pending.len > 0 {
        let item = pending.pop(); if self.has_projections { let error = chargeProjection(self); if error != Error.none { return false, error; } }
        if remaining == 0 { return false, Error.type_limit; } remaining -= 1;
        if seen.contains(item) { continue; } seen.insert(item, true);
        if item.row { for label in rowLabels(self, item.root) { for argument in operationArguments(self, label) { pending.push(ProjectionWork { argument }); } } continue; }
        let id = head(self, item.root, 0); if closedHeight(self, id) != 0 { continue; } let value = node(self, id);
        if value.tag == Tag.projection { return true, Error.none; }
        if value.tag == Tag.function { pending.append([ProjectionWork { value.a }, ProjectionWork { value.b }, ProjectionWork { value.c, true }]); continue; }
        if value.tag == Tag.provider { pending.append([ProjectionWork { value.a }, ProjectionWork { value.c, true }]); continue; }
        var children: Id[>..<] = []; appendChildren(self, children, id, false); for child in children { pending.push(ProjectionWork { child }); }
    }
    return false, Error.none;
}
fn has(values: const u32[:], value: u32) -> bool { for item in values { if item == value { return true; } } return false; }
fn unionInto(self: Store&, values: u32[>..]&, added: const u32[:]) -> Error { for item in added { if !has(values, item) { values.push(item); } } return Error.none; }
struct RowWork { id: Id, at: Cursor, depth: u32 = 0 }
fn freeRowVariables(self: Store&, root: Id) -> u32[>..], Error { return freeRowVariablesMode(self, root, true); }
fn freeRowVariablesMode(self: Store&, root: Id, bounded: bool) -> u32[>..], Error {
    if bounded && (root <= never || closedHeight(self, root) != 0) { return [], Error.none; }
    if bounded { let selected = head(self, root, 0); if selected <= never || node(self, selected).tag == Tag.variable || node(self, selected).tag == Tag.type_constructor { return [], Error.none; } }
    self.normalization.free_row_queries += 1; var result: u32[>..] = []; var pending: RowWork[>..<] = []; var seen = dictionary<u64, bool> {}; pending.push(RowWork { root, 0 });
    while pending.len > 0 {
        let work = pending.pop(); self.normalization.free_row_visits += 1;
        if self.has_projections { let error = chargeProjection(self); if error != Error.none { return [], error; } }
        if work.depth >= 1024 { return [], Error.type_limit; } var id = work.id; var at = work.at;
        while node(self, id).tag == Tag.variable { let variable = node(self, id); at = max(at, variable.b); let write = replacement(self, variable.a, at); if !write.present { break; } id = write.value.replacement; at = write.value.position + 1; }
        if bounded {
            if id <= never || node(self, id).tag == Tag.variable || node(self, id).tag == Tag.type_constructor { continue; }
            let height = closedHeight(self, id); if height != 0 { if work.depth + height > 1024 { return [], Error.type_limit; } continue; }
        }
        let key = ((id as u64) << 32) | at; if seen.contains(key) { continue; } seen.insert(key, true); let value = node(self, id);
        if value.tag == Tag.function || value.tag == Tag.provider {
            var row_ = self.effects.node(value.c); var row_at = max(at, row_.cursor);
            loop {
                for label in self.effects.list(row_.labels) { for argument in operationArguments(self, label) { pending.push(RowWork { argument, at, work.depth + 1 }); } }
                var variable = none; match row_.tail { variable v => { variable = v.value; }, _ => { break; }, }
                row_at = max(row_at, row_.cursor); let write, found = self.effects.replacementAt(variable, row_at); if !found { break; }
                row_ = self.effects.node(write.replacement); row_at = write.position + 1;
            }
            match row_.tail { variable v => { if !has(result, v.value) { result.push(v.value); } }, _ => {}, }
        }
        var children: Id[>..<] = []; appendChildren(self, children, id, false);
        for child in children { pending.push(RowWork { child, at, work.depth + 1 }); }
    }
    return result, Error.none;
}
struct KindStamp { mutation_epoch: u64, rank_types: bool, proof_kinds: bool }
struct Substitution {
    old: const Id[:], fresh_ids: const Id[:], old_rows: const u32[:], fresh_rows: const blot_check_effects::Id[:],
    leaves: dictionary<Id, u32>&, row_leaves: dictionary<u32, u32>&,
    checked: blot_support::Option<KindStamp> = blot_support::Option<KindStamp> { false, default<KindStamp>() },
}
fn deinit(self: Substitution&) { self.leaves.clear(); self.row_leaves.clear(); self.checked.present = false; }
fn typeIndex(self: const Substitution&, root: Id) -> i64, bool {
    if self.leaves.count != 0 { let index = self.leaves.get(root); if index { return index as i64, true; } return 0, false; }
    for before, index in self.old { if before == root { return index, true; } } return 0, false;
}
fn rowIndex(self: const Substitution&, variable: u32, from: i64) -> i64, bool {
    if from == 0 && self.row_leaves.count != 0 { let index = self.row_leaves.get(variable); if index { return index as i64, true; } return 0, false; }
    for before, offset in self.old_rows[from..] { if before == variable { return from + offset, true; } } return 0, false;
}
fn prepareSubstitution(self: Store&, old: const Id[:], fresh_ids: const Id[:], old_rows: const u32[:], fresh_rows: const blot_check_effects::Id[:],
                       leaves: dictionary<Id, u32>&, row_leaves: dictionary<u32, u32>&) -> Substitution, Error {
    assert(old.len == fresh_ids.len && old_rows.len == fresh_rows.len);
    var result = Substitution { old, fresh_ids, old_rows, fresh_rows, leaves, row_leaves };
    if old.len > 16 { for before, index in old { if !leaves.contains(before) { leaves.insert(before, index as u32); } } }
    if old_rows.len > 16 { for before, index in old_rows { if !row_leaves.contains(before) { row_leaves.insert(before, index as u32); } } }
    return result, Error.none;
}
fn substitute(self: Store&, root: Id, old: const Id[:], fresh_ids: const Id[:]) -> Id, Error { return substituteWithRows(self, root, old, fresh_ids, [], []); }
fn substituteWithRows(self: Store&, root: Id, old: const Id[:], fresh_ids: const Id[:], old_rows: const u32[:], fresh_rows: const blot_check_effects::Id[:]) -> Id, Error {
    assert(old.len == fresh_ids.len && old_rows.len == fresh_rows.len);
    var leaves = dictionary<Id, u32> {}; var row_leaves = dictionary<u32, u32> {};
    var substitution = Substitution { old, fresh_ids, old_rows, fresh_rows, leaves, row_leaves };
    return substitutePrepared(self, substitution, root);
}
fn substitutePrepared(self: Store&, substitution: Substitution&, root: Id) -> Id, Error {
    let attribution_start = self.nodes.len; let result, error = substitutePreparedInner(self, substitution, root);
    saturatedAdd(self.normalization.substitute_nodes_added, (self.nodes.len - attribution_start) as u64); return result, error;
}
fn substitutePreparedInner(self: Store&, substitution: Substitution&, root: Id) -> Id, Error {
    let error = checkReplacementKinds(self, substitution); if error != Error.none { return 0, error; }
    if substitution.old.len == 0 && substitution.old_rows.len == 0 { return root, Error.none; }
    var copied = dictionary<Id, Id> {}; return substituteDepth(self, root, substitution, copied, 0);
}
fn checkReplacementKinds(self: Store&, substitution: Substitution&) -> Error {
    let stamp = KindStamp { self.mutation_epoch, self.has_rank_types, self.has_proof_kinds };
    if substitution.checked.present && stamp.mutation_epoch != 0xffffffffffffffff && substitution.checked.value == stamp { return Error.none; }
    for original, i in substitution.old {
        let replacement_id = substitution.fresh_ids[i]; let leaf = node(self, original);
        if (leaf.tag == Tag.bound && leaf.b == 1) || (leaf.tag == Tag.rigid && leaf.c == 1) { if !rowIdentity(self, replacement_id) { return Error.type_mismatch; } }
        else if (leaf.tag == Tag.bound && leaf.b == 2) || (leaf.tag == Tag.rigid && leaf.c == 2) { if !regionIdentity(self, replacement_id) { return Error.type_mismatch; } }
        else { let error = dataKind(self, replacement_id); if error != Error.none { return error; } }
    }
    substitution.checked = blot_support::Option<KindStamp> { true, stamp }; return Error.none;
}
recursive fn substitutedRow(self: Store&, root: blot_check_effects::Id, substitution: const Substitution&, copied: dictionary<Id, Id>&, depth: i64) -> blot_check_effects::Id, Error {
    if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
    let row_ = row(self, root); var labels: blot_check_effects::Label[>..] = []; var changed = false;
    for index in row_.labels.len {
        let label = self.effects.list(row_.labels)[index]; if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
        let operation_ = operation(self, label); var arguments: Id[>..] = []; var argument_changed = false;
        for offset in operation_.arguments.len {
            let argument = list(self, operation_.arguments)[offset]; let next, error = substituteDepth(self, argument, substitution, copied, depth + 1); if error != Error.none { return 0, error; }
            argument_changed = argument_changed || next != argument; arguments.push(next);
        }
        var instance = operation_.instance;
        if instance.unit == 0 && instance.decl != 0 { let next, error = substituteDepth(self, instance.decl, substitution, copied, depth + 1); if error != Error.none { return 0, error; } instance.decl = next; }
        var next = label;
        if argument_changed || instance != operation_.instance { let result, error = internResolvedOperation(self, operation_.identity, instance, arguments, true); if error != Error.none { return 0, error; } next = result; }
        changed = changed || next != label; labels.push(next);
    }
    var result = root;
    match row_.tail { formal v => {
        let index, found = typeIndex(substitution, v.value);
        if found { let replacement_row, re = rowType(self, substitution.fresh_ids[index]); if re != Error.none { return 0, re; }
            let next, error = self.effects.substituteFormal(root, substitution.old[index], replacement_row); if error != Error.none { return 0, effectError(error); } result = next; }
    }, _ => {}, }
    if changed {
        let replaced = row(self, result); if result != root { labels.append(self.effects.list(replaced.labels)[row_.labels.len..]); }
        let next, error = self.effects.rowAt(labels, replaced.tail, max(row_.cursor, replaced.cursor)); if error != Error.none { return 0, effectError(error); } result = next;
    }
    var from: i64 = 0;
    while from < substitution.old_rows.len {
        var variable = none; match self.effects.node(result).tail { variable v => { variable = v.value; }, _ => { break; }, }
        let index, found = rowIndex(substitution, variable, from); if !found { break; }
        let next, error = self.effects.substitute(result, substitution.old_rows[index], substitution.fresh_rows[index]); if error != Error.none { return 0, effectError(error); } result = next; from = index + 1;
    }
    return result, Error.none;
}
recursive fn substituteDepth(self: Store&, root: Id, substitution: const Substitution&, copied: dictionary<Id, Id>&, depth: i64) -> Id, Error {
    increment(self.normalization.substitute_depth_entries); if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
    if depth >= 1024 { return 0, Error.type_limit; }
    let index, found = typeIndex(substitution, root); if found { return substitution.fresh_ids[index], Error.none; }
    if root <= never || node(self, root).tag == Tag.variable { return root, Error.none; }
    if depth != 0 { let known = copied.get(root); if known { increment(self.normalization.substitute_memo_hits); return known, Error.none; } }
    let result, error = substituteNode(self, root, substitution, copied, depth); if error != Error.none { return 0, error; }
    if result == root { increment(self.normalization.substitute_unchanged); } if depth != 0 { copied.insert(root, result); }
    return result, Error.none;
}
recursive fn substituteNode(self: Store&, root: Id, substitution: const Substitution&, copied: dictionary<Id, Id>&, depth: i64) -> Id, Error {
    if depth >= 1024 { return 0, Error.type_limit; } let value = node(self, root);
    match value.tag {
        forall, existential => {
            var binders: Id[>..] = []; binders.append(list(self, List { value.b, value.c }));
            let body, be = substituteDepth(self, value.a, substitution, copied, depth + 1); if be != Error.none { return 0, be; }
            var goals: Obligation[>..] = []; goals.append(quantifierGoals(self, root)); var changed = body != value.a;
            for &goal in goals {
                if goal.ty != 0 { let next, error = substituteDepth(self, goal.ty, substitution, copied, depth + 1); if error != Error.none { return 0, error; } changed = changed || next != goal.ty; goal.ty = next; }
                if goal.other != 0 { let next, error = substituteDepth(self, goal.other, substitution, copied, depth + 1); if error != Error.none { return 0, error; } changed = changed || next != goal.other; goal.other = next; }
                if goal.result != 0 { let next, error = substituteDepth(self, goal.result, substitution, copied, depth + 1); if error != Error.none { return 0, error; } changed = changed || next != goal.result; goal.result = next; }
                if goal.signature != 0 { let next, error = substituteDepth(self, goal.signature, substitution, copied, depth + 1); if error != Error.none { return 0, error; } changed = changed || next != goal.signature; goal.signature = next; }
            }
            if !changed { return root, Error.none; } return reownQuantified(self, value.tag, body, binders, goals);
        },
        usage => {
            let payload, pe = substituteDepth(self, value.a, substitution, copied, depth + 1); if pe != Error.none { return 0, pe; }
            var region: Id = 0; if value.c != 0 { let next, error = substituteDepth(self, value.c, substitution, copied, depth + 1); if error != Error.none { return 0, error; } region = next; }
            return usage(self, payload, value.b, region);
        },
        scoped => {
            let descriptor, de = substituteDepth(self, value.a, substitution, copied, depth + 1); if de != Error.none { return 0, de; }
            var instance = NominalIdentity { value.b, value.c }; if instance.unit == 0 { let next, error = substituteDepth(self, instance.decl, substitution, copied, depth + 1); if error != Error.none { return 0, error; } instance.decl = next; }
            return scoped(self, descriptor, instance);
        },
        function => {
            let parameter, pe = substituteDepth(self, value.a, substitution, copied, depth + 1); if pe != Error.none { return 0, pe; }
            let result, re = substituteDepth(self, value.b, substitution, copied, depth + 1); if re != Error.none { return 0, re; }
            let row_, ee = substitutedRow(self, value.c, substitution, copied, depth + 1); if ee != Error.none { return 0, ee; }
            return functionWithEffects(self, parameter, result, row_);
        },
        product => {
            var fields: Id[>..] = []; for i in value.b { let next, error = substituteDepth(self, self.extra.items[value.a + i], substitution, copied, depth + 1); if error != Error.none { return 0, error; } fields.push(next); } return product(self, fields);
        },
        array, list, cursor, resolver => {
            let next, error = substituteDepth(self, value.a, substitution, copied, depth + 1); if error != Error.none { return 0, error; }
            if value.tag == Tag.resolver { return resolver(self, next); } return sequence(self, value.tag, next);
        },
        provider => {
            let child, ce = substituteDepth(self, value.a, substitution, copied, depth + 1); if ce != Error.none { return 0, ce; }
            let row_, re = substitutedRow(self, value.c, substitution, copied, depth + 1); if re != Error.none { return 0, re; }
            return provider(self, child, row_);
        },
        state_provider => {
            let read, re = substituteDepth(self, value.a, substitution, copied, depth + 1); if re != Error.none { return 0, re; }
            let write, we = substituteDepth(self, value.b, substitution, copied, depth + 1); if we != Error.none { return 0, we; }
            let state, se = substituteDepth(self, value.c, substitution, copied, depth + 1); if se != Error.none { return 0, se; }
            return stateProvider(self, read, write, state);
        },
        record => {
            var fields: Field[>..] = []; for i in value.b { let field = recordField(self, value, i); let next, error = substituteDepth(self, field.ty, substitution, copied, depth + 1); if error != Error.none { return 0, error; } fields.push(Field { field.name, next }); } return record(self, fields);
        },
        nominal, projection, instance_selection => {
            var prior: Id[>..] = []; prior.append(nominalArguments(self, value)); var args: Id[>..] = [];
            for child in prior { let next, error = substituteDepth(self, child, substitution, copied, depth + 1); if error != Error.none { return 0, error; } args.push(next); }
            if value.tag == Tag.projection { return projection(self, NominalIdentity { value.a, value.b }, projectionMember(self, value), args); }
            if value.tag == Tag.instance_selection { return instanceSelection(self, NominalIdentity { value.a, value.b }, args); }
            return nominal(self, NominalIdentity { value.a, value.b }, args);
        },
        _ => { return root, Error.none; },
    }
}
struct CovariantInput { root: Id, depth: i64 }
fn hash(value: CovariantInput) -> u64 { return ::hash_combine(::hash(value.root), ::hash(value.depth)); }
struct CovariantEntry { root: Id, depth: i64, protected: List, result: Id }
struct CovariantMemo { entries: CovariantEntry[>..]&, protected_values: u32[>..]& }
fn closeCovariant(self: Store&, root: Id, generalized: const u32[:], protected: const u32[:]) -> Id, Error {
    let attribution_start = self.nodes.len;
    var entries: CovariantEntry[>..] = []; var protected_values: u32[>..] = []; var memo = CovariantMemo { entries, protected_values }; var decisions: u32[>..] = [];
    let result, error = closeCovariantDepth(self, root, generalized, protected, decisions, false, memo, 0);
    saturatedAdd(self.normalization.close_nodes_added, (self.nodes.len - attribution_start) as u64); return result, error;
}
fn closeCovariantCertified(self: Store&, root: Id, generalized: const u32[:], protected: const u32[:]) -> ClosedCovariant, Error {
    let attribution_start = self.nodes.len;
    var entries: CovariantEntry[>..] = []; var protected_values: u32[>..] = []; var memo = CovariantMemo { entries, protected_values }; var decisions: u32[>..] = [];
    let closed, error = closeCovariantDepth(self, root, generalized, protected, decisions, true, memo, 0);
    saturatedAdd(self.normalization.close_nodes_added, (self.nodes.len - attribution_start) as u64);
    if error != Error.none { return default<ClosedCovariant>(), error; }
    let rows, error = saveList(self, decisions); if error != Error.none { return default<ClosedCovariant>(), error; }
    return ClosedCovariant { closed, rows }, Error.none;
}
recursive fn closeCovariantDepth(self: Store&, root: Id, generalized: const u32[:], protected: const u32[:],
                                 decisions: u32[>..]&, record_decisions: bool, memo: CovariantMemo&, depth: i64) -> Id, Error {
    increment(self.normalization.close_depth_entries); if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } }
    if depth >= 1024 { return 0, Error.type_limit; } if generalized.len == 0 { return root, Error.none; }
    if self.has_projections || self.use_closed_graphs {
        for entry in memo.entries { if entry.root == root && entry.depth == depth && memo.protected_values[entry.protected.start..entry.protected.start + entry.protected.len] == protected { return entry.result, Error.none; } }
        let rows, error = freeRowVariables(self, root); if error != Error.none { return 0, error; }
        var changes = false; for row_id in rows { if has(generalized, row_id) && !has(protected, row_id) { changes = true; break; } }
        if !changes { return root, Error.none; }
    }
    let result, error = closeCovariantNode(self, root, generalized, protected, decisions, record_decisions, memo, depth); if error != Error.none { return 0, error; }
    if (self.has_projections || self.use_closed_graphs) && memo.entries.len < 65536 {
        let span = List { memo.protected_values.len as u32, protected.len as u32 }; memo.protected_values.append(protected); memo.entries.push(CovariantEntry { root, depth, span, result });
    }
    return result, Error.none;
}
recursive fn closeCovariantNode(self: Store&, root: Id, generalized: const u32[:], protected: const u32[:],
                                decisions: u32[>..]&, record_decisions: bool, memo: CovariantMemo&, depth: i64) -> Id, Error {
    if depth >= 1024 { return 0, Error.type_limit; } let value = node(self, root);
    match value.tag {
        provider => {
            var effect_row = value.c; let tail = self.effects.node(effect_row).tail;
            let token_rows, error = freeRowVariables(self, value.a); if error != Error.none { return 0, error; }
            match tail { variable v => { if has(generalized, v.value) && !has(protected, v.value) && !has(token_rows, v.value) {
                if record_decisions && !has(decisions, v.value) { decisions.push(v.value); }
                let next, error = self.effects.row(rowLabels(self, effect_row), blot_check_effects::Tail.closed); if error != Error.none { return 0, effectError(error); } effect_row = next;
            } }, _ => {}, }
            if effect_row == value.c { return root, Error.none; } return provider(self, value.a, effect_row);
        },
        function => {
            let parameter_free, pe = freeRowVariables(self, value.a); if pe != Error.none { return 0, pe; }
            let result_free, re = freeRowVariables(self, value.b); if re != Error.none { return 0, re; }
            var effect_row = value.c; let tail = self.effects.node(effect_row).tail;
            match tail { variable v => { if has(generalized, v.value) && !has(protected, v.value) && !has(parameter_free, v.value) && !has(result_free, v.value) {
                if record_decisions && !has(decisions, v.value) { decisions.push(v.value); }
                let next, error = self.effects.row(rowLabels(self, effect_row), blot_check_effects::Tail.closed); if error != Error.none { return 0, effectError(error); } effect_row = next;
            } }, _ => {}, }
            var nested: u32[>..] = []; nested.append(protected); let union = unionInto(self, nested, parameter_free); if union != Error.none { return 0, union; }
            match self.effects.node(effect_row).tail { variable v => { let error = unionInto(self, nested, [v.value]); if error != Error.none { return 0, error; } }, _ => {}, }
            let result, error = closeCovariantDepth(self, value.b, generalized, nested, decisions, record_decisions, memo, depth + 1); if error != Error.none { return 0, error; }
            if result == value.b && effect_row == value.c { return root, Error.none; } return functionWithEffects(self, value.a, result, effect_row);
        },
        product, record => {
            var protected_siblings: u32[>..] = []; protected_siblings.append(protected);
            for i in value.b { var child = self.extra.items[value.a + i]; if value.tag == Tag.record { child = recordField(self, value, i).ty; } let error = covariantInputs(self, child, protected_siblings, depth + 1); if error != Error.none { return 0, error; } }
            var children: Id[>..] = []; var fields: Field[>..] = []; var changed = false;
            for i in value.b {
                var field = Field { 0, self.extra.items[value.a + i] }; if value.tag == Tag.record { field = recordField(self, value, i); }
                let child, error = closeCovariantDepth(self, field.ty, generalized, protected_siblings, decisions, record_decisions, memo, depth + 1); if error != Error.none { return 0, error; }
                changed = changed || child != field.ty; if value.tag == Tag.record { fields.push(Field { field.name, child }); } else { children.push(child); }
            }
            if !changed { return root, Error.none; } if value.tag == Tag.record { return record(self, fields); } return product(self, children);
        },
        usage => {
            let child, error = closeCovariantDepth(self, value.a, generalized, protected, decisions, record_decisions, memo, depth + 1); if error != Error.none { return 0, error; }
            if child == value.a { return root, Error.none; } return usage(self, child, value.b, value.c);
        },
        array, list, cursor => {
            let child, error = closeCovariantDepth(self, value.a, generalized, protected, decisions, record_decisions, memo, depth + 1); if error != Error.none { return 0, error; }
            if child == value.a { return root, Error.none; } return sequence(self, value.tag, child);
        },
        _ => { return root, Error.none; },
    }
}
fn covariantInputs(self: Store&, root: Id, out: u32[>..]&, depth: i64) -> Error { var seen = dictionary<CovariantInput, bool> {}; return covariantInputsSeen(self, root, out, depth, seen); }
recursive fn covariantInputsSeen(self: Store&, root: Id, out: u32[>..]&, depth: i64, seen: dictionary<CovariantInput, bool>&) -> Error {
    if self.has_projections { let error = chargeProjection(self); if error != Error.none { return error; } }
    if depth >= 1024 { return Error.type_limit; }
    if self.has_projections || self.use_closed_graphs { let key = CovariantInput { root, depth }; if seen.contains(key) { return Error.none; } seen.insert(key, true); }
    let value = node(self, root);
    match value.tag {
        function => { let free, error = freeRowVariables(self, value.a); if error != Error.none { return error; } let added = unionInto(self, out, free); if added != Error.none { return added; } return covariantInputsSeen(self, value.b, out, depth + 1, seen); },
        nominal, state_provider => { let free, error = freeRowVariables(self, root); if error != Error.none { return error; } return unionInto(self, out, free); },
        provider => { let free, error = freeRowVariables(self, value.a); if error != Error.none { return error; } return unionInto(self, out, free); },
        product, record => { for i in value.b { var child = self.extra.items[value.a + i]; if value.tag == Tag.record { child = recordField(self, value, i).ty; } let error = covariantInputsSeen(self, child, out, depth + 1, seen); if error != Error.none { return error; } } },
        usage, array, list, cursor => { return covariantInputsSeen(self, value.a, out, depth + 1, seen); }, _ => {},
    }
    return Error.none;
}
fn openCovariant(self: Store&, root: Id) -> Id, Error {
    let attribution_start = self.nodes.len; var memo = dictionary<CovariantInput, Id> {}; let result, error = openCovariantDepth(self, root, memo, 0);
    saturatedAdd(self.normalization.open_nodes_added, (self.nodes.len - attribution_start) as u64); return result, error;
}
recursive fn openCovariantDepth(self: Store&, root: Id, memo: dictionary<CovariantInput, Id>&, depth: i64) -> Id, Error {
    increment(self.normalization.open_depth_entries);
    if !self.has_projections { if depth >= 1024 { return 0, Error.type_limit; } match node(self, root).tag { function, provider, product, record, usage, array, list, cursor => {}, _ => { return root, Error.none; }, } }
    var query = CovariantInput { root, depth }; if self.has_projections { query.depth = 0; }
    block { let known = memo.get(query); if known { return known, Error.none; } }
    let result, error = openCovariantNode(self, root, memo, depth); if error != Error.none { return 0, error; }
    if (self.has_projections || result == root) && memo.count < 65536 { memo.insert(query, result); } return result, Error.none;
}
recursive fn openCovariantNode(self: Store&, root: Id, memo: dictionary<CovariantInput, Id>&, depth: i64) -> Id, Error {
    if self.has_projections { let error = chargeProjection(self); if error != Error.none { return 0, error; } } if depth >= 1024 { return 0, Error.type_limit; }
    let value = node(self, root);
    match value.tag {
        provider => {
            var effect_row = value.c; if self.effects.node(effect_row).tail == blot_check_effects::Tail.closed {
                let opened, oe = freshEffects(self); if oe != Error.none { return 0, oe; }
                let next, error = self.effects.row(rowLabels(self, effect_row), self.effects.node(opened).tail); if error != Error.none { return 0, effectError(error); } effect_row = next;
            }
            if effect_row == value.c { return root, Error.none; } return provider(self, value.a, effect_row);
        },
        function => {
            let result, re = openCovariantDepth(self, value.b, memo, depth + 1); if re != Error.none { return 0, re; }
            var effect_row = value.c; if self.effects.node(effect_row).tail == blot_check_effects::Tail.closed {
                let opened, oe = freshEffects(self); if oe != Error.none { return 0, oe; }
                let next, error = self.effects.row(rowLabels(self, effect_row), self.effects.node(opened).tail); if error != Error.none { return 0, effectError(error); } effect_row = next;
            }
            if result == value.b && effect_row == value.c { return root, Error.none; } return functionWithEffects(self, value.a, result, effect_row);
        },
        product, record => {
            var children: Id[>..] = []; var fields: Field[>..] = []; var changed = false;
            for i in value.b { var field = Field { 0, self.extra.items[value.a + i] }; if value.tag == Tag.record { field = recordField(self, value, i); }
                let child, error = openCovariantDepth(self, field.ty, memo, depth + 1); if error != Error.none { return 0, error; }
                changed = changed || child != field.ty; if value.tag == Tag.record { fields.push(Field { field.name, child }); } else { children.push(child); }
            }
            if !changed { return root, Error.none; } if value.tag == Tag.record { return record(self, fields); } return product(self, children);
        },
        usage => {
            if value.b == blot_parse_ast::usagekind_cleanup || value.b == blot_parse_ast::usagekind_concurrent { return root, Error.none; }
            let child, error = openCovariantDepth(self, value.a, memo, depth + 1); if error != Error.none { return 0, error; }
            if child == value.a { return root, Error.none; } return usage(self, child, value.b, value.c);
        },
        array, list, cursor => {
            let child, error = openCovariantDepth(self, value.a, memo, depth + 1); if error != Error.none { return 0, error; }
            if child == value.a { return root, Error.none; } return sequence(self, value.tag, child);
        },
        _ => { return root, Error.none; },
    }
}

fn blot_structural::equal(left: blot_check_types::Tag, right: blot_check_types::Tag) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_types::Tag) { blot_structural::hash(sink, blot_check_types::tagCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_types::Operator, right: blot_check_types::Operator) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_types::Operator) { blot_structural::hash(sink, blot_check_types::operatorCode(value) as! u8); }

fn blot_structural::equal(left: blot_check_types::ObligationKind, right: blot_check_types::ObligationKind) -> bool { return left == right; }
fn blot_structural::hash<S>(sink: S&, value: blot_check_types::ObligationKind) { blot_structural::hash(sink, blot_check_types::obligationKindCode(value) as! u8); }
fn usageKindFromCode(code: u32) -> UsageKind, bool { if code > 7 { return 0, false; } return code, true; }




fn usageKindCode(kind: UsageKind) -> u32 { return usageCode(kind); }
// Suspension transfers one live logical owner into typed reusable backing.
type StoreSnapshot = blot_check_type_store_snapshot::Snapshot;
fn suspendStore(store: Store&) -> StoreSnapshot, Error { return blot_check_type_store_snapshot::suspendStore(store); }
fn restoreStore(snapshot: StoreSnapshot&, store: Store&) -> Error { return blot_check_type_store_snapshot::restoreStore(snapshot, store); }
fn deinit(snapshot: StoreSnapshot&) -> Error { return blot_check_type_store_snapshot::deinit(snapshot); }
fn cloneSnapshot(snapshot: const StoreSnapshot&) -> StoreSnapshot, Error { return blot_check_type_store_snapshot::cloneSnapshot(snapshot); }
fn snapshotOwnedBytes(snapshot: const StoreSnapshot&) -> i64 { return blot_check_type_store_snapshot::snapshotOwnedBytes(snapshot); }
fn snapshotMetadataBytes() -> i64 { return blot_check_type_store_snapshot::snapshotMetadataBytes(); }

import support.pooled_buffer;
struct ScalarDefaults {
owner_id:u64=default<u64>(),
use_closed_rows:bool=true,
closed_rows:ClosedRow[4]=[ClosedRow {}; 4],
use_operation_rows:bool=true,
operation_rows:OperationRow[64]=[OperationRow {}; 64],
has_usage_types:bool=false,
has_rank_types:bool=false,
next_rigid_scope:u32=1,
use_closed_graphs:bool=false,
has_proof_kinds:bool=false,
has_projections:bool=false,
projection_limit:i64=1000000,
projection_steps:i64=0,
resolution_depth_limit:i64=1024,
projection_exhausted:bool=false,
projection_resolution_types:u64=0,
projection_resolution_rows:u64=0,
projection_resolution_limit:i64=0,
closed_generation:u16=1,
closed_effect_physical_epoch:u64=0,
mutation_epoch:u64=0,
occurs_steps:u64=0,
normalization:blot_work_counters::Normalization=blot_work_counters::Normalization {},
resolution_steps:u64=0,
occurs_generation:u32=0,
use_resolution_cache:bool=true,
use_composite_cache:bool=true,
composite_min_growth:i64=4,
use_operation_shapes:bool=true,
operation_shape_generation:u16=0,
operation_shape_enabled:bool=false,
}
var inactive_scalars=ScalarDefaults{};
struct OwnerState {generation:u64=0,live:bool=false,
nodes:Table_nodes=Table_nodes{},
extra:Table_extra=Table_extra{},
variables:Table_variables=Table_variables{},
versions:Table_versions=Table_versions{},
operations:Table_operations=Table_operations{},
operation_links:Table_operation_links=Table_operation_links{},
quantifier_goals:Table_quantifier_goals=Table_quantifier_goals{},
quantifier_obligations:Table_quantifier_obligations=Table_quantifier_obligations{},
occurs_seen:Table_occurs_seen=Table_occurs_seen{},
closed_row_index:Table_closed_row_index=Table_closed_row_index{},
closed_operation_index:Table_closed_operation_index=Table_closed_operation_index{},
variable_views:Map_variable_views=Map_variable_views{},
associated_equations:Map_associated_equations=Map_associated_equations{},
projection_resolutions:Map_projection_resolutions=Map_projection_resolutions{},
operation_chains:Map_operation_chains=Map_operation_chains{},
effects:blot_check_effects::Store=blot_check_effects::Store{},
resolved:blot_reuse_epoch_resolution_cache::Cache=blot_reuse_epoch_resolution_cache::Cache{},
composites:blot_reuse_composite_resolution_cache::Cache=blot_reuse_composite_resolution_cache::Cache{},
owner_id:u64=default<u64>(),
use_closed_rows:bool=true,
closed_rows:ClosedRow[4]=[ClosedRow {}; 4],
use_operation_rows:bool=true,
operation_rows:OperationRow[64]=[OperationRow {}; 64],
has_usage_types:bool=false,
has_rank_types:bool=false,
next_rigid_scope:u32=1,
use_closed_graphs:bool=false,
has_proof_kinds:bool=false,
has_projections:bool=false,
projection_limit:i64=1000000,
projection_steps:i64=0,
resolution_depth_limit:i64=1024,
projection_exhausted:bool=false,
projection_resolution_types:u64=0,
projection_resolution_rows:u64=0,
projection_resolution_limit:i64=0,
closed_generation:u16=1,
closed_effect_physical_epoch:u64=0,
mutation_epoch:u64=0,
occurs_steps:u64=0,
normalization:blot_work_counters::Normalization=blot_work_counters::Normalization {},
resolution_steps:u64=0,
occurs_generation:u32=0,
use_resolution_cache:bool=true,
use_composite_cache:bool=true,
composite_min_growth:i64=4,
use_operation_shapes:bool=true,
operation_shape_generation:u16=0,
operation_shape_enabled:bool=false,
}
var inactive_nodes=Table_nodes{};
var inactive_extra=Table_extra{};
var inactive_variables=Table_variables{};
var inactive_versions=Table_versions{};
var inactive_operations=Table_operations{};
var inactive_operation_links=Table_operation_links{};
var inactive_quantifier_goals=Table_quantifier_goals{};
var inactive_quantifier_obligations=Table_quantifier_obligations{};
var inactive_occurs_seen=Table_occurs_seen{};
var inactive_closed_row_index=Table_closed_row_index{};
var inactive_closed_operation_index=Table_closed_operation_index{};
var inactive_variable_views=Map_variable_views{};
var inactive_associated_equations=Map_associated_equations{};
var inactive_projection_resolutions=Map_projection_resolutions{};
var inactive_operation_chains=Map_operation_chains{};
var inactive_effects=blot_check_effects::Store{};
var inactive_resolved=blot_reuse_epoch_resolution_cache::Cache{};
var inactive_composites=blot_reuse_composite_resolution_cache::Cache{};































reusable var owner_states:OwnerState[>..]=[];
var next_owner_generation:u64=1;

struct Table_nodes {storage:Node[:]=[],items:Node[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_nodes:Node[>..];
fn ensure(self:Table_nodes&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_nodes);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_nodes&,value:Node) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_nodes);self.len=self.items.len;}
fn append(self:Table_nodes&,values:const Node[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_nodes);self.len=self.items.len;}
fn resize(self:Table_nodes&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_nodes&,length:i64,value:Node) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_nodes&)->Node {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_nodes&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_nodes&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_nodes&) {blot_support_pooled_buffer::deinit(self,pool_Table_nodes);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_nodes&,value:const Node&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_nodes&,values:const Node[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_extra {storage:Id[:]=[],items:Id[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_extra:Id[>..];
fn ensure(self:Table_extra&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_extra);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_extra&,value:Id) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_extra);self.len=self.items.len;}
fn append(self:Table_extra&,values:const Id[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_extra);self.len=self.items.len;}
fn resize(self:Table_extra&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_extra&,length:i64,value:Id) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_extra&)->Id {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_extra&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_extra&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_extra&) {blot_support_pooled_buffer::deinit(self,pool_Table_extra);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_extra&,value:const Id&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_extra&,values:const Id[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_variables {storage:Variable[:]=[],items:Variable[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_variables:Variable[>..];
fn ensure(self:Table_variables&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_variables);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_variables&,value:Variable) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_variables);self.len=self.items.len;}
fn append(self:Table_variables&,values:const Variable[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_variables);self.len=self.items.len;}
fn resize(self:Table_variables&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_variables&,length:i64,value:Variable) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_variables&)->Variable {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_variables&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_variables&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_variables&) {blot_support_pooled_buffer::deinit(self,pool_Table_variables);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_variables&,value:const Variable&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_variables&,values:const Variable[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_versions {storage:Version[:]=[],items:Version[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_versions:Version[>..];
fn ensure(self:Table_versions&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_versions);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_versions&,value:Version) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_versions);self.len=self.items.len;}
fn append(self:Table_versions&,values:const Version[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_versions);self.len=self.items.len;}
fn resize(self:Table_versions&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_versions&,length:i64,value:Version) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_versions&)->Version {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_versions&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_versions&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_versions&) {blot_support_pooled_buffer::deinit(self,pool_Table_versions);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_versions&,value:const Version&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_versions&,values:const Version[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_operations {storage:Operation[:]=[],items:Operation[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_operations:Operation[>..];
fn ensure(self:Table_operations&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_operations);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_operations&,value:Operation) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_operations);self.len=self.items.len;}
fn append(self:Table_operations&,values:const Operation[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_operations);self.len=self.items.len;}
fn resize(self:Table_operations&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_operations&,length:i64,value:Operation) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_operations&)->Operation {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_operations&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_operations&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_operations&) {blot_support_pooled_buffer::deinit(self,pool_Table_operations);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_operations&,value:const Operation&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_operations&,values:const Operation[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_operation_links {storage:OperationLink[:]=[],items:OperationLink[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_operation_links:OperationLink[>..];
fn ensure(self:Table_operation_links&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_operation_links);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_operation_links&,value:OperationLink) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_operation_links);self.len=self.items.len;}
fn append(self:Table_operation_links&,values:const OperationLink[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_operation_links);self.len=self.items.len;}
fn resize(self:Table_operation_links&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_operation_links&,length:i64,value:OperationLink) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_operation_links&)->OperationLink {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_operation_links&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_operation_links&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_operation_links&) {blot_support_pooled_buffer::deinit(self,pool_Table_operation_links);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_operation_links&,value:const OperationLink&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_operation_links&,values:const OperationLink[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_quantifier_goals {storage:QuantifierGoals[:]=[],items:QuantifierGoals[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_quantifier_goals:QuantifierGoals[>..];
fn ensure(self:Table_quantifier_goals&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_quantifier_goals);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_quantifier_goals&,value:QuantifierGoals) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_quantifier_goals);self.len=self.items.len;}
fn append(self:Table_quantifier_goals&,values:const QuantifierGoals[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_quantifier_goals);self.len=self.items.len;}
fn resize(self:Table_quantifier_goals&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_quantifier_goals&,length:i64,value:QuantifierGoals) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_quantifier_goals&)->QuantifierGoals {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_quantifier_goals&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_quantifier_goals&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_quantifier_goals&) {blot_support_pooled_buffer::deinit(self,pool_Table_quantifier_goals);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_quantifier_goals&,value:const QuantifierGoals&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_quantifier_goals&,values:const QuantifierGoals[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_quantifier_obligations {storage:Obligation[:]=[],items:Obligation[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_quantifier_obligations:Obligation[>..];
fn ensure(self:Table_quantifier_obligations&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_quantifier_obligations);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_quantifier_obligations&,value:Obligation) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_quantifier_obligations);self.len=self.items.len;}
fn append(self:Table_quantifier_obligations&,values:const Obligation[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_quantifier_obligations);self.len=self.items.len;}
fn resize(self:Table_quantifier_obligations&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_quantifier_obligations&,length:i64,value:Obligation) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_quantifier_obligations&)->Obligation {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_quantifier_obligations&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_quantifier_obligations&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_quantifier_obligations&) {blot_support_pooled_buffer::deinit(self,pool_Table_quantifier_obligations);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_quantifier_obligations&,value:const Obligation&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_quantifier_obligations&,values:const Obligation[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_occurs_seen {storage:u32[:]=[],items:u32[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_occurs_seen:u32[>..];
fn ensure(self:Table_occurs_seen&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_occurs_seen);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_occurs_seen&,value:u32) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_occurs_seen);self.len=self.items.len;}
fn append(self:Table_occurs_seen&,values:const u32[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_occurs_seen);self.len=self.items.len;}
fn resize(self:Table_occurs_seen&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_occurs_seen&,length:i64,value:u32) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_occurs_seen&)->u32 {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_occurs_seen&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_occurs_seen&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_occurs_seen&) {blot_support_pooled_buffer::deinit(self,pool_Table_occurs_seen);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_occurs_seen&,value:const u32&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_occurs_seen&,values:const u32[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_closed_row_index {storage:RowCertificate[:]=[],items:RowCertificate[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_closed_row_index:RowCertificate[>..];
fn ensure(self:Table_closed_row_index&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_closed_row_index);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_closed_row_index&,value:RowCertificate) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_closed_row_index);self.len=self.items.len;}
fn append(self:Table_closed_row_index&,values:const RowCertificate[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_closed_row_index);self.len=self.items.len;}
fn resize(self:Table_closed_row_index&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_closed_row_index&,length:i64,value:RowCertificate) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_closed_row_index&)->RowCertificate {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_closed_row_index&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_closed_row_index&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_closed_row_index&) {blot_support_pooled_buffer::deinit(self,pool_Table_closed_row_index);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_closed_row_index&,value:const RowCertificate&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_closed_row_index&,values:const RowCertificate[:])->Error {self.clear();self.append(values);return self.failure;}

struct Table_closed_operation_index {storage:RowCertificate[:]=[],items:RowCertificate[:]=[],len:i64=0,failure:Error=Error.none}
reusable[] var pool_Table_closed_operation_index:RowCertificate[>..];
fn ensure(self:Table_closed_operation_index&,minimum:i64)->Error {if self.failure!=Error.none {return self.failure;}let error=blot_support_pooled_buffer::ensure(self,minimum,pool_Table_closed_operation_index);if error!=Error.none {self.failure=error;}return error;}
fn push(self:Table_closed_operation_index&,value:RowCertificate) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::push(self,value,pool_Table_closed_operation_index);self.len=self.items.len;}
fn append(self:Table_closed_operation_index&,values:const RowCertificate[:]) {if self.failure!=Error.none {return;}self.failure=blot_support_pooled_buffer::append(self,values,pool_Table_closed_operation_index);self.len=self.items.len;}
fn resize(self:Table_closed_operation_index&,length:i64) {blot_support_pooled_buffer::resize(self,length);self.len=length;}
fn resize(self:Table_closed_operation_index&,length:i64,value:RowCertificate) {if length<=self.len {self.resize(length);return;}let error=self.ensure(length);if error!=Error.none {return;}for index in self.len..length {self.storage[index]=value;}self.items=self.storage[..length];self.len=length;}
fn pop(self:Table_closed_operation_index&)->RowCertificate {assert(self.len!=0);let value=self.items[self.len-1];self.resize(self.len-1);return value;}
fn pop_n(self:Table_closed_operation_index&,count:i64) {assert(count>=0 && count<=self.len);self.resize(self.len-count);}
fn clear(self:Table_closed_operation_index&) {self.items=self.storage[..0];self.len=0;self.failure=Error.none;}
fn deinit(self:Table_closed_operation_index&) {blot_support_pooled_buffer::deinit(self,pool_Table_closed_operation_index);self.len=0;self.failure=Error.none;}
fn index_of(self:const Table_closed_operation_index&,value:const RowCertificate&)->i64 {return self.items.index_of(value);}
fn restore(self:Table_closed_operation_index&,values:const RowCertificate[:])->Error {self.clear();self.append(values);return self.failure;}
struct Map_variable_views { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<u64,Id>[:] = [] }
fn probe(map: const Map_variable_views&,key: u64) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_variable_views&,key: u64) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_variable_views&,key: u64) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<u64,Id>[:]) { if slots.len != 0 { pool_Map_variable_views.free_slice(slots); } }
fn grow(map: Map_variable_views&,capacity: i64) {
    if map.failure != Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return; }
    let replacement = pool_Map_variable_views.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<u64,Id> { default<u64>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_variable_views&,key: u64,value: Id) -> bool {
    if map.failure != Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<u64,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<u64,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_variable_views&,key: u64) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<u64,Id> { default<u64>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_variable_views&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_variable_views&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const Map_variable_views&) -> Map_variable_views { var copy = Map_variable_views {}; if map.slots.len != 0 { let slots = pool_Map_variable_views.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_variable_views&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_variable_views:dictionary_slot<u64,Id>[>..];
fn restore(map:Map_variable_views&,slots:const dictionary_slot<u64,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_Map_variable_views.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
struct Map_associated_equations { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<Id,Id>[:] = [] }
fn probe(map: const Map_associated_equations&,key: Id) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_associated_equations&,key: Id) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_associated_equations&,key: Id) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<Id,Id>[:]) { if slots.len != 0 { pool_Map_associated_equations.free_slice(slots); } }
fn grow(map: Map_associated_equations&,capacity: i64) {
    if map.failure != Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return; }
    let replacement = pool_Map_associated_equations.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_associated_equations&,key: Id,value: Id) -> bool {
    if map.failure != Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<Id,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<Id,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_associated_equations&,key: Id) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_associated_equations&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_associated_equations&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const Map_associated_equations&) -> Map_associated_equations { var copy = Map_associated_equations {}; if map.slots.len != 0 { let slots = pool_Map_associated_equations.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_associated_equations&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_associated_equations:dictionary_slot<Id,Id>[>..];
fn restore(map:Map_associated_equations&,slots:const dictionary_slot<Id,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_Map_associated_equations.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
struct Map_projection_resolutions { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<ProjectionResolution,Id>[:] = [] }
fn probe(map: const Map_projection_resolutions&,key: ProjectionResolution) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_projection_resolutions&,key: ProjectionResolution) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_projection_resolutions&,key: ProjectionResolution) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<ProjectionResolution,Id>[:]) { if slots.len != 0 { pool_Map_projection_resolutions.free_slice(slots); } }
fn grow(map: Map_projection_resolutions&,capacity: i64) {
    if map.failure != Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return; }
    let replacement = pool_Map_projection_resolutions.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<ProjectionResolution,Id> { default<ProjectionResolution>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_projection_resolutions&,key: ProjectionResolution,value: Id) -> bool {
    if map.failure != Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<ProjectionResolution,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<ProjectionResolution,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_projection_resolutions&,key: ProjectionResolution) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<ProjectionResolution,Id> { default<ProjectionResolution>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_projection_resolutions&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_projection_resolutions&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const Map_projection_resolutions&) -> Map_projection_resolutions { var copy = Map_projection_resolutions {}; if map.slots.len != 0 { let slots = pool_Map_projection_resolutions.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_projection_resolutions&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_projection_resolutions:dictionary_slot<ProjectionResolution,Id>[>..];
fn restore(map:Map_projection_resolutions&,slots:const dictionary_slot<ProjectionResolution,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_Map_projection_resolutions.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
struct Map_operation_chains { count: i64 = 0, failure:Error=Error.none, slots: dictionary_slot<OperationKey,OperationChain>[:] = [] }
fn probe(map: const Map_operation_chains&,key: OperationKey) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_operation_chains&,key: OperationKey) -> OperationChain? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_operation_chains&,key: OperationKey) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<OperationKey,OperationChain>[:]) { if slots.len != 0 { pool_Map_operation_chains.free_slice(slots); } }
fn grow(map: Map_operation_chains&,capacity: i64) {
    if map.failure != Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return; }
    let replacement = pool_Map_operation_chains.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<OperationKey,OperationChain> { default<OperationKey>(),default<OperationChain>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_operation_chains&,key: OperationKey,value: OperationChain) -> bool {
    if map.failure != Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<OperationKey,OperationChain> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<OperationKey,OperationChain> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_operation_chains&,key: OperationKey) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<OperationKey,OperationChain> { default<OperationKey>(),default<OperationChain>(),0 }; map.count--; return true;
}
fn clear(map: Map_operation_chains&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_operation_chains&) { release(map.slots); map.slots = []; map.count = 0;map.failure=Error.none; }
fn clone(map: const Map_operation_chains&) -> Map_operation_chains { var copy = Map_operation_chains {}; if map.slots.len != 0 { let slots = pool_Map_operation_chains.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_operation_chains&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_operation_chains:dictionary_slot<OperationKey,OperationChain>[>..];
fn restore(map:Map_operation_chains&,slots:const dictionary_slot<OperationKey,OperationChain>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return Error.invalid_artifact;}return Error.none;}let run=pool_Map_operation_chains.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return Error.none;}
fn valid(self:const Store&)->bool {return self.lease!=0 && self.lease-1<owner_states.len && owner_states[self.lease-1].live && owner_states[self.lease-1].generation==self.owner_generation;}
fn initPooled(options:Options=Options{})->Store,Error {if next_owner_generation==0xffffffffffffffff || owner_states.len>=0xffffffff {return Store{},Error.out_of_memory;}let generation=next_owner_generation;next_owner_generation+=1;let index=owner_states.alloc_index(OwnerState{generation:generation,live:true});let state:OwnerState&=owner_states[index];var self=Store{lease:(index+1) as u32,owner_generation:generation,nodes:state.nodes,extra:state.extra,variables:state.variables,versions:state.versions,operations:state.operations,operation_links:state.operation_links,quantifier_goals:state.quantifier_goals,quantifier_obligations:state.quantifier_obligations,occurs_seen:state.occurs_seen,closed_row_index:state.closed_row_index,closed_operation_index:state.closed_operation_index,variable_views:state.variable_views,associated_equations:state.associated_equations,projection_resolutions:state.projection_resolutions,operation_chains:state.operation_chains,effects:state.effects,resolved:state.resolved,composites:state.composites,owner_id:state.owner_id,use_closed_rows:state.use_closed_rows,closed_rows:state.closed_rows,use_operation_rows:state.use_operation_rows,operation_rows:state.operation_rows,has_usage_types:state.has_usage_types,has_rank_types:state.has_rank_types,next_rigid_scope:state.next_rigid_scope,use_closed_graphs:state.use_closed_graphs,has_proof_kinds:state.has_proof_kinds,has_projections:state.has_projections,projection_limit:state.projection_limit,projection_steps:state.projection_steps,resolution_depth_limit:state.resolution_depth_limit,projection_exhausted:state.projection_exhausted,projection_resolution_types:state.projection_resolution_types,projection_resolution_rows:state.projection_resolution_rows,projection_resolution_limit:state.projection_resolution_limit,closed_generation:state.closed_generation,closed_effect_physical_epoch:state.closed_effect_physical_epoch,mutation_epoch:state.mutation_epoch,occurs_steps:state.occurs_steps,normalization:state.normalization,resolution_steps:state.resolution_steps,occurs_generation:state.occurs_generation,use_resolution_cache:state.use_resolution_cache,use_composite_cache:state.use_composite_cache,composite_min_growth:state.composite_min_growth,use_operation_shapes:state.use_operation_shapes,operation_shape_generation:state.operation_shape_generation,operation_shape_enabled:state.operation_shape_enabled,};self.owner_id=blot_native::fresh_owner_id();self.use_closed_graphs=options.closed_graphs;self.use_resolution_cache=options.resolution_cache;self.use_composite_cache=options.composite_cache && options.closed_graphs;self.composite_min_growth=options.composite_min_growth;let effects,error=blot_check_effects::initPooled(blot_check_effects::Options{resolution_cache:options.resolution_cache});if error!=Error.none {self.deinit();return Store{},effectError(error);}self.effects=effects;let resolved,error=blot_reuse_epoch_resolution_cache::initPooled();if error!=Error.none {self.deinit();return Store{},error;}self.resolved=resolved;let composites,error=blot_reuse_composite_resolution_cache::initPooled();if error!=Error.none {self.deinit();return Store{},error;}self.composites=composites;self.nodes.append([Node{Tag.absent},Node{Tag.unit},Node{Tag.boolean},Node{Tag.unsigned32},Node{Tag.floating32},Node{Tag.never}]);self.operations.append([Operation{NominalIdentity{0,0}},Operation{NominalIdentity{0,1}}]);if self.nodes.failure!=Error.none || self.operations.failure!=Error.none {var error=self.nodes.failure;if error==Error.none {error=self.operations.failure;}self.deinit();return Store{},error;}return self,Error.none;}
fn init()->Store,Error {return initPooled();}
fn initWithOptions(options:Options)->Store,Error {return initPooled(options);}
fn deinit(self:Store&) {if self.lease==0 {return;}assert(valid(self));self.nodes.deinit();self.extra.deinit();self.variables.deinit();self.versions.deinit();self.operations.deinit();self.operation_links.deinit();self.quantifier_goals.deinit();self.quantifier_obligations.deinit();self.occurs_seen.deinit();self.closed_row_index.deinit();self.closed_operation_index.deinit();self.variable_views.deinit();self.associated_equations.deinit();self.projection_resolutions.deinit();self.operation_chains.deinit();self.effects.deinit();self.resolved.deinit();self.composites.deinit();let index=self.lease-1;owner_states[index].live=false;owner_states.free(index);self=Store{};}
fn withStore<C,F>(context:C&)->Error {let initialized,error=initPooled();if error!=Error.none {return error;}var store=initialized;let result=F(context,store);store.deinit();return result;}
fn withStoreValue<C,F,R>(context:C&)->R,Error {let initialized,error=initPooled();if error!=Error.none {return default<R>(),error;}var store=initialized;let result,failure=F(context,store);store.deinit();return result,failure;}
