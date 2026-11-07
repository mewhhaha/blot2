// Dense owned types with chronological, non-collapsing substitution history.
namespace blot_check_types;
import check.effects;
import check.quantifier_goals;
import check.rank_equal;
import check.rank_walk;
import check.type_store_packet;
import check.usage_check;
import parse.ast;
import reuse.composite_resolution_cache;
import reuse.epoch_resolution_cache;
import support.error;
import support.native;
import support.option;
import support.pooled_buffer;
import support.pooled_map;
import support.structural_adapters;
import work_counters;

import support.structural;
import std;
import dictionary;
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
struct Operation { identity: NominalIdentity, arguments: List = List {..}, instance: NominalIdentity = NominalIdentity { 0, 0 , ..} }
let foreign_operation: blot_check_effects::Label = 1;
let builtin_state_read = NominalIdentity { 0xffffffff, 1 , ..};
let builtin_state_write = NominalIdentity { 0xffffffff, 2 , ..};
let effect_set_identity = NominalIdentity { 0xffffffff, 3 , ..};
let effect_descriptor_identity = NominalIdentity { 0xffffffff, 4 , ..};
struct Scheme { root: Id = absent, variables: List = List {..}, row_variables: List = List {..}, closed_rows: List = List {..}, obligations: List = List {..}, generative: List = List {..} }
struct ClosedCovariant { root: Id, closed_rows: List }
enum Operator { none, add, sub, mul, div, rem, equal, not_equal, less, less_equal, greater, greater_equal, bit_and, bit_or, bit_xor, shift_left, shift_right }
enum ObligationKind { arithmetic, ordered, equality, integer, field, writable_field, dispatch, result_dispatch, monad_factory, resolver_dispatch, resolver_shape, effect_operation, effect_handler, receiver, update, type_rep, effect_rep, type_head, collection, record_merge, callee_use, type_eq, contract, task_receive }
struct QuantifierGoals { owner: Id, goals: List }
struct Obligation {
    ty: Id, kind: ObligationKind, source: u32, name: u32 = 0, result: Id = 0,
    other: Id = 0, signature: Id = 0, operator: Operator = Operator.none,
    identity: NominalIdentity = NominalIdentity { 0, 0 , ..}, explicit: bool = false,
    qualification_span: blot_support::Option<blot_parse_ast::Span>   = blot_support::Option<blot_parse_ast::Span> { false, default<blot_parse_ast::Span>() , ..},
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
nodes:Table_nodes& =inactive_nodes,
extra:Table_extra& =inactive_extra,
variables:Table_variables& =inactive_variables,
versions:Table_versions& =inactive_versions,
operations:Table_operations& =inactive_operations,
operation_links:Table_operation_links& =inactive_operation_links,
quantifier_goals:Table_quantifier_goals& =inactive_quantifier_goals,
quantifier_obligations:Table_quantifier_obligations& =inactive_quantifier_obligations,
occurs_seen:Table_occurs_seen& =inactive_occurs_seen,
closed_row_index:Table_closed_row_index& =inactive_closed_row_index,
closed_operation_index:Table_closed_operation_index& =inactive_closed_operation_index,
variable_views:Map_variable_views& =inactive_variable_views,
associated_equations:Map_associated_equations& =inactive_associated_equations,
projection_resolutions:Map_projection_resolutions& =inactive_projection_resolutions,
operation_chains:Map_operation_chains& =inactive_operation_chains,
effects:blot_check_effects::Store& =inactive_effects,
resolved:blot_reuse_epoch_resolution_cache::Cache& =inactive_resolved,
composites:blot_reuse_composite_resolution_cache::Cache& =inactive_composites,
owner_id:(u64)& =inactive_scalars.owner_id,
use_closed_rows:(bool)& =inactive_scalars.use_closed_rows,
closed_rows:(ClosedRow[4])& =inactive_scalars.closed_rows,
use_operation_rows:(bool)& =inactive_scalars.use_operation_rows,
operation_rows:(OperationRow[64])& =inactive_scalars.operation_rows,
has_usage_types:(bool)& =inactive_scalars.has_usage_types,
has_rank_types:(bool)& =inactive_scalars.has_rank_types,
next_rigid_scope:(u32)& =inactive_scalars.next_rigid_scope,
use_closed_graphs:(bool)& =inactive_scalars.use_closed_graphs,
has_proof_kinds:(bool)& =inactive_scalars.has_proof_kinds,
has_projections:(bool)& =inactive_scalars.has_projections,
projection_limit:(i64)& =inactive_scalars.projection_limit,
projection_steps:(i64)& =inactive_scalars.projection_steps,
resolution_depth_limit:(i64)& =inactive_scalars.resolution_depth_limit,
projection_exhausted:(bool)& =inactive_scalars.projection_exhausted,
projection_resolution_types:(u64)& =inactive_scalars.projection_resolution_types,
projection_resolution_rows:(u64)& =inactive_scalars.projection_resolution_rows,
projection_resolution_limit:(i64)& =inactive_scalars.projection_resolution_limit,
closed_generation:(u16)& =inactive_scalars.closed_generation,
closed_effect_physical_epoch:(u64)& =inactive_scalars.closed_effect_physical_epoch,
mutation_epoch:(u64)& =inactive_scalars.mutation_epoch,
occurs_steps:(u64)& =inactive_scalars.occurs_steps,
normalization:(blot_work_counters::Normalization)& =inactive_scalars.normalization,
resolution_steps:(u64)& =inactive_scalars.resolution_steps,
occurs_generation:(u32)& =inactive_scalars.occurs_generation,
use_resolution_cache:(bool)& =inactive_scalars.use_resolution_cache,
use_composite_cache:(bool)& =inactive_scalars.use_composite_cache,
composite_min_growth:(i64)& =inactive_scalars.composite_min_growth,
use_operation_shapes:(bool)& =inactive_scalars.use_operation_shapes,
operation_shape_generation:(u16)& =inactive_scalars.operation_shape_generation,
operation_shape_enabled:(bool)& =inactive_scalars.operation_shape_enabled,
}
struct Options { resolution_cache: bool = true, closed_graphs: bool = false, composite_cache: bool = true, composite_min_growth: i64 = 4 }



fn node(self_: const Store&, id: Id) -> Node { return self_.nodes.items[id]; }
fn list(self_: const Store&, span: List) -> const Id[:] { return self_.extra.items[span.start..span.start + span.len]; }
fn saveList(self_: Store&, values: const Id[:]) -> List, Error {
    if values.len > none - self_.extra.len { return List {..}, blot_error::Error.type_limit; }
    let start = self_.extra.len as u32; self_.extra.append(values);if self_.extra.failure!=blot_error::Error.none {return default<List>(),self_.extra.failure;}
    return List { start, values.len as u32 , ..}, blot_error::Error.none;
}
fn tick(self_: Store&) { if self_.mutation_epoch != 0xffffffffffffffff { self_.mutation_epoch += 1; } }
fn invalidateClosedGraphs(self_: Store&) { if self_.closed_generation != 0xffff { self_.closed_generation += 1; } }
fn synchronizeClosedGraphs(self_: Store&) {
    if self_.closed_effect_physical_epoch == self_.effects.physical_epoch { return; }
    invalidateClosedGraphs(self_); self_.closed_effect_physical_epoch = self_.effects.physical_epoch;
}
fn replaceListItem(self_: Store&, span: List, index: i64, value: Id) {
    assert(index < span.len && value < self_.nodes.len); let slot = span.start + index;
    if self_.extra.items[slot] == value { return; } self_.extra.items[slot] = value;
    invalidateClosedGraphs(self_); tick(self_);
}
fn add(self_: Store&, value: Node) -> Id, Error {
    if self_.nodes.len == none { return 0, blot_error::Error.type_limit; }
    let id = self_.nodes.len as u32; var owned = value;
    if self_.use_closed_graphs { synchronizeClosedGraphs(self_); owned.closed_height = closedNodeHeight(self_, value); owned.closed_generation = self_.closed_generation; }
    self_.nodes.push(owned);if self_.nodes.failure!=blot_error::Error.none {return 0,self_.nodes.failure;} return id, blot_error::Error.none;
}
fn formalRowKey(binder: Id) -> u32, Error {
    if binder == 0 || binder >= blot_check_effects::formal_key_bit { return 0, blot_error::Error.type_limit; }
    return blot_check_effects::formal_key_bit | binder, blot_error::Error.none;
}
fn rowKeyFormal(key: u32) -> blot_support::Option<Id> {
    if key & blot_check_effects::formal_key_bit == 0 { return blot_support::Option<Id> { false, 0 , ..}; }
    return blot_support::Option<Id> { true, key & ~blot_check_effects::formal_key_bit , ..};
}
fn effectError(error: Error) -> Error { if error == blot_error::Error.effect_limit { return blot_error::Error.type_limit; } return error; }
fn receiverIdentity(value: Node) -> blot_support::Option<NominalIdentity> {
    match value.tag {
        nominal => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { value.a, value.b , ..} , ..}; },
        unsigned32 => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, u32_type , ..} , ..}; },
        floating32 => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, f32_type , ..} , ..}; },
        boolean => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, boolean , ..} , ..}; },
        unit => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, unit , ..} , ..}; },
        array => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none , ..} , ..}; },
        list => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none - 1 , ..} , ..}; },
        cursor => { return blot_support::Option<NominalIdentity> { true, NominalIdentity { 0, none - 2 , ..} , ..}; },
        _ => { return blot_support::Option<NominalIdentity> { false, default<NominalIdentity>() , ..}; },
    }
}
fn isReflectionIdentity(unit_: u32, decl: u32) -> bool { return unit_ == none && (decl == 3 || decl == 4); }
fn compilerNominalArity(identity: NominalIdentity) -> blot_support::Option<u32> {
    if identity.unit != none { return blot_support::Option<u32> { false, 0 , ..}; }
    match identity.decl {
        3, 4, 16 => { return blot_support::Option<u32> { true, 0 , ..}; },
        5, 9, 20, 21, 22, 23, 24 => { return blot_support::Option<u32> { true, 1 , ..}; },
        6 => { return blot_support::Option<u32> { true, 3 , ..}; },
        8, 17, 18 => { return blot_support::Option<u32> { true, 2 , ..}; },
        _ => { return blot_support::Option<u32> { false, 0 , ..}; },
    }
}
fn compilerNominalVersionArgument(identity: NominalIdentity) -> blot_support::Option<u32> {
    if identity.unit == none && identity.decl == 18 { return blot_support::Option<u32> { true, 1 , ..}; }
    return blot_support::Option<u32> { false, 0 , ..};
}
fn closedHeight(self_: const Store&, id: Id) -> u8 {
    if !self_.use_closed_graphs || self_.closed_generation == 0xffff || self_.effects.physical_epoch == 0xffffffffffffffff || self_.closed_effect_physical_epoch != self_.effects.physical_epoch { return 0; }
    if id <= never { if id == absent { return 0; } return 1; }
    let value = node(self_, id);
    if value.closed_generation == self_.closed_generation { return value.closed_height; }
    return 0;
}
fn knownClosed(self_: const Store&, id: Id) -> bool { return closedHeight(self_, id) != 0; }
fn spanSlot(labels: blot_check_effects::List) -> i64 { return ((labels.start ^ (labels.start >> 8) ^ labels.len) % 4) as i64; }
fn closedRow(self_: const Store&, id: blot_check_effects::Id) -> blot_support::Option<ClosedRow> {
    if !self_.use_closed_rows || !self_.use_closed_graphs || self_.closed_generation == 0xffff || self_.effects.physical_epoch == 0xffffffffffffffff || self_.closed_effect_physical_epoch != self_.effects.physical_epoch { return blot_support::Option<ClosedRow> { false, ClosedRow {..} , ..}; }
    var value = self_.closed_rows[id % self_.closed_rows.len];
    if id < self_.closed_row_index.len {
        let proof = self_.closed_row_index.items[id];
        value = ClosedRow { id, proof.generation, proof.argument_height, proof.has_arguments , ..};
    }
    if value.row == id && value.generation == self_.closed_generation { return blot_support::Option<ClosedRow> { true, value , ..}; }
    let labels = row(self_, id).labels; let shared = self_.closed_rows[spanSlot(labels)];
    if shared.generation != self_.closed_generation || shared.row >= self_.effects.rows.len { return blot_support::Option<ClosedRow> { false, ClosedRow {..} , ..}; }
    let old = row(self_, shared.row).labels;
    if old.start == labels.start && old.len == labels.len { return blot_support::Option<ClosedRow> { true, ClosedRow { id, shared.generation, shared.argument_height, shared.has_arguments , ..} , ..}; }
    return blot_support::Option<ClosedRow> { false, ClosedRow {..} , ..};
}
fn saveClosedRow(self_: Store&, id: blot_check_effects::Id, height: u8, has_arguments: bool) {
    if !self_.use_closed_rows || !self_.use_closed_graphs || self_.closed_generation == 0xffff || self_.effects.physical_epoch == 0xffffffffffffffff || self_.closed_effect_physical_epoch != self_.effects.physical_epoch { return; }
    if id < self_.closed_row_index.len { self_.closed_row_index.items[id] = RowCertificate { self_.closed_generation, height, has_arguments , ..}; }
    let slot = spanSlot(row(self_, id).labels);
    if self_.closed_rows[slot].generation == self_.closed_generation && self_.closed_rows[slot].row != id { self_.normalization.closed_row_evictions += 1; }
    self_.closed_rows[slot] = ClosedRow { id, self_.closed_generation, height, has_arguments , ..};
}
fn closedOperation(self_: const Store&, label: blot_check_effects::Label) -> blot_support::Option<RowCertificate> {
    if !self_.use_closed_rows || !self_.use_closed_graphs || self_.closed_generation == 0xffff || self_.effects.physical_epoch == 0xffffffffffffffff || self_.closed_effect_physical_epoch != self_.effects.physical_epoch || label >= self_.closed_operation_index.len { return blot_support::Option<RowCertificate> { false, RowCertificate {..} , ..}; }
    let proof = self_.closed_operation_index.items[label];
    return blot_support::Option<RowCertificate> { proof.generation == self_.closed_generation, proof , ..};
}
fn saveClosedOperation(self_: Store&, label: blot_check_effects::Label, height: u8, has_arguments: bool) {
    if !self_.use_closed_rows || !self_.use_closed_graphs || self_.closed_generation == 0xffff || self_.effects.physical_epoch == 0xffffffffffffffff || self_.closed_effect_physical_epoch != self_.effects.physical_epoch || label >= self_.closed_operation_index.len { return; }
    self_.closed_operation_index.items[label] = RowCertificate { self_.closed_generation, height, has_arguments , ..};
}
fn closedRowHeight(self_: Store&, id: blot_check_effects::Id) -> u8 {
    let value = self_.effects.node(id);
    if value.tail != blot_check_effects::Tail.closed { return 0; }
    if value.labels.len == 0 { return 1; }
    let cached = closedRow(self_, id);
    if cached.present { if cached.value.argument_height == 255 { return 0; } return cached.value.argument_height + 1; }
    var height: u8 = 0; var has_arguments = false;
    for label in self_.effects.list(value.labels) {
        if label >= self_.operations.len { return 0; }
        let proof = closedOperation(self_, label);
        if proof.present { height = max(height, proof.value.argument_height); has_arguments = has_arguments || proof.value.has_arguments; continue; }
        let instance = self_.operations.items[label].instance;
        if instance.unit == 0 && instance.decl != 0 { return 0; }
        var operation_height: u8 = 0;
        for arg in list(self_, self_.operations.items[label].arguments) {
            has_arguments = true; let argument_height = closedHeight(self_, arg);
            if argument_height == 0 { return 0; }
            height = max(height, argument_height); operation_height = max(operation_height, argument_height);
        }
        saveClosedOperation(self_, label, operation_height, self_.operations.items[label].arguments.len != 0);
    }
    saveClosedRow(self_, id, height, has_arguments);
    if height == 255 { return 0; } return height + 1;
}
fn closedNodeHeight(self_: Store&, value: Node) -> u8 {
    var height: u8 = 0;
    match value.tag {
        absent, variable, forall, existential, bound, rigid => { return 0; },
        function, provider => {
            let row_height = closedRowHeight(self_, value.c); if row_height == 0 { return 0; }
            height = closedHeight(self_, value.a); if height == 0 { return 0; } height = max(height, row_height);
            if value.tag == Tag.function { let result = closedHeight(self_, value.b); if result == 0 { return 0; } height = max(height, result); }
        },
        usage, scoped, array, list, cursor, resolver => {
            if (value.tag == Tag.scoped && value.b == 0) || (value.tag == Tag.usage && value.c != 0) { return 0; }
            height = closedHeight(self_, value.a); if height == 0 { return 0; }
        },
        state_provider => {
            for child in [value.a, value.b, value.c] { let child_height = closedHeight(self_, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        product => {
            for child in list(self_, List { value.a, value.b , ..}) { let child_height = closedHeight(self_, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        record => {
            for index in value.b { let child_height = closedHeight(self_, recordField(self_, value, index).ty); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        projection => { return 0; },
        nominal, instance_selection => {
            for child in nominalArguments(self_, value) { let child_height = closedHeight(self_, child); if child_height == 0 { return 0; } height = max(height, child_height); }
        },
        _ => {},
    }
    if height == 255 { return 0; } return height + 1;
}
fn boundType(self_: Store&, ordinal: u32, sort: u32) -> Id, Error { self_.has_rank_types = true; return add(self_, Node { tag: Tag.bound, a: ordinal, b: sort , ..}); }
fn rigidScope(self_: Store&) -> u32, Error {
    if self_.next_rigid_scope == none { return 0, blot_error::Error.type_limit; }
    let scope = self_.next_rigid_scope; self_.next_rigid_scope += 1; return scope, blot_error::Error.none;
}
fn rigid(self_: Store&, scope: u32, ordinal: u32, sort: u32) -> Id, Error { self_.has_rank_types = true; return add(self_, Node { tag: Tag.rigid, a: scope, b: ordinal, c: sort , ..}); }
fn quantifierGoals(self_: const Store&, owner: Id) -> const Obligation[:] { return blot_check_quantifier_goals::get(self_.quantifier_goals.items, self_.quantifier_obligations.items, owner); }
fn quantified(self_: Store&, tag: Tag, body: Id, binders: const Id[:]) -> Id, Error { return quantifiedWithGoals(self_, tag, body, binders, []); }
fn quantifiedWithGoals(self_: Store&, tag: Tag, body: Id, binders: const Id[:], goals: const Obligation[:]) -> Id, Error {
    assert(tag == Tag.forall || tag == Tag.existential);
    if binders.len == 0 || binders.len > 4096 { return 0, blot_error::Error.type_limit; }
    for binder, ordinal in binders {
        if binder >= self_.nodes.len { return 0, blot_error::Error.type_mismatch; }
        let leaf = node(self_, binder);
        if leaf.tag != Tag.bound || leaf.a != ordinal || leaf.b > 2 || leaf.c != 0 { return 0, blot_error::Error.type_mismatch; }
    }
    self_.has_rank_types = true;
    var owned_goals: Obligation[>..] = []; owned_goals.append(goals);
    for goal in owned_goals { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child >= self_.nodes.len { return 0, blot_error::Error.type_mismatch; } } }
    let point = mark(self_);
    let span, se = saveList(self_, binders); if se != blot_error::Error.none { rollback(self_, point); return 0, se; }
    let owner, oe = add(self_, Node { tag: tag, a: body, b: span.start, c: span.len , ..}); if oe != blot_error::Error.none { rollback(self_, point); return 0, oe; }
    if owned_goals.len != 0 {
        let stored, error = saveQuantifierGoals(self_, owned_goals); if error != blot_error::Error.none { rollback(self_, point); return 0, error; }
        self_.quantifier_goals.push(QuantifierGoals { owner, stored , ..});if self_.quantifier_goals.failure!=blot_error::Error.none {return 0,self_.quantifier_goals.failure;}
    }
    return owner, blot_error::Error.none;
}
fn bindRankAnnotation(self_: Store&, slot: Id, required: Id) -> Error {
    let root, error = resolve(self_, slot, 0); if error != blot_error::Error.none { return error; }
    if node(self_, root).tag != Tag.variable { return unify(self_, root, required); }
    var quantified_root = required;
    if node(self_, quantified_root).tag == Tag.usage { quantified_root = node(self_, quantified_root).a; }
    if node(self_, quantified_root).tag != Tag.forall { return blot_error::Error.type_mismatch; }
    let recursive_, recursion_error = occurs(self_, node(self_, root).a, required); if recursion_error != blot_error::Error.none { return recursion_error; }
    if recursive_ { return blot_error::Error.infinite_type; }
    return appendVersion(self_, root, required);
}
recursive fn reownQuantified(self_:Store&,tag:Tag,body:Id,binders:const Id[:],goals:Obligation[:])->Id,Error {let replacements=substitution_ids.alloc_slice(binders.len);let result,error=reownQuantifiedValues(self_,tag,body,binders,goals,replacements);substitution_ids.free_slice(replacements);return result,error;}
recursive fn reownQuantifiedValues(self_: Store&, tag: Tag, body: Id, binders: const Id[:], goals: Obligation[:], replacements:Id[:]) -> Id, Error {
    for binder,index in binders { let leaf = node(self_, binder); let replacement, error = boundType(self_, leaf.a, leaf.b); if error != blot_error::Error.none { return 0, error; } replacements[index]=replacement; }
    let owned_body, be = substitute(self_, body, binders, replacements); if be != blot_error::Error.none { return 0, be; }
    for &goal in goals { let replaced, error = substituteGoal(self_, goal, binders, replacements); if error != blot_error::Error.none { return 0, error; } goal = replaced; }
    return quantifiedWithGoals(self_, tag, owned_body, replacements, goals);
}
fn saveQuantifierGoals(self_: Store&, goals: const Obligation[:]) -> List, Error {
    if goals.len > 4096 || goals.len > none - self_.quantifier_obligations.len { return List {..}, blot_error::Error.type_limit; }
    let start = self_.quantifier_obligations.len as u32; self_.quantifier_obligations.append(goals);if self_.quantifier_obligations.failure!=blot_error::Error.none {return default<List>(),self_.quantifier_obligations.failure;} return List { start, goals.len as u32 , ..}, blot_error::Error.none;
}
recursive fn substituteGoal(self_: Store&, goal: Obligation, old: const Id[:], fresh_ids: const Id[:]) -> Obligation, Error {
    var result = goal;
    if goal.ty != 0 { let value, error = substitute(self_, goal.ty, old, fresh_ids); if error != blot_error::Error.none { return default<Obligation>(), error; } result.ty = value; }
    if goal.other != 0 { let value, error = substitute(self_, goal.other, old, fresh_ids); if error != blot_error::Error.none { return default<Obligation>(), error; } result.other = value; }
    if goal.result != 0 { let value, error = substitute(self_, goal.result, old, fresh_ids); if error != blot_error::Error.none { return default<Obligation>(), error; } result.result = value; }
    if goal.signature != 0 { let value, error = substitute(self_, goal.signature, old, fresh_ids); if error != blot_error::Error.none { return default<Obligation>(), error; } result.signature = value; }
    if goal.identity.unit == 0 && goal.identity.decl != 0 { let value, error = substitute(self_, goal.identity.decl, old, fresh_ids); if error != blot_error::Error.none { return default<Obligation>(), error; } result.identity.decl = value; }
    return result, blot_error::Error.none;
}
struct RankInstance { body: Id, scope: u32 = 0, goals: List = List {..} }
fn instantiateRank(self_: Store&, root: Id, skolemize: bool) -> RankInstance, Error {
    let resolved, error = resolve(self_, root, 0); if error != blot_error::Error.none { return default<RankInstance>(), error; }
    let value = node(self_, resolved);
    if value.tag != Tag.forall && value.tag != Tag.existential { return default<RankInstance>(), blot_error::Error.type_mismatch; }
    var binders: Id[>..] = []; binders.append(list(self_, List { value.b, value.c , ..}));
    var replacements: Id[>..] = []; var scope: u32 = 0;
    if skolemize { let id, error = rigidScope(self_); if error != blot_error::Error.none { return default<RankInstance>(), error; } scope = id; }
    for binder in binders {
        let leaf = node(self_, binder); if leaf.tag != Tag.bound || leaf.b > 2 { return default<RankInstance>(), blot_error::Error.type_mismatch; }
        var id: Id = 0; var error = blot_error::Error.none;
        if skolemize { let result, failure = rigid(self_, scope, leaf.a, leaf.b); id = result; error = failure; }
        else if leaf.b == 1 { let result, failure = freshRowType(self_); id = result; error = failure; }
        else if leaf.b == 2 { let result, failure = freshRegion(self_); id = result; error = failure; }
        else { let result, failure = fresh(self_); id = result; error = failure; }
        if error != blot_error::Error.none { return default<RankInstance>(), error; } replacements.push(id);
    }
    var source_goals: Obligation[>..] = []; source_goals.append(quantifierGoals(self_, resolved));
    for &goal in source_goals { let replaced, error = substituteGoal(self_, goal, binders, replacements); if error != blot_error::Error.none { return default<RankInstance>(), error; } goal = replaced; }
    let goals, ge = saveQuantifierGoals(self_, source_goals); if ge != blot_error::Error.none { return default<RankInstance>(), ge; }
    let body, be = substitute(self_, value.a, binders, replacements); if be != blot_error::Error.none { return default<RankInstance>(), be; }
    return RankInstance { body, scope, goals , ..}, blot_error::Error.none;
}
fn containsQuantifier(self_: Store&, root: Id) -> bool, Error { if !self_.has_rank_types { return false, blot_error::Error.none; } return blot_check_rank_walk::quantified(self_, root); }
fn containsRigidRow(self_: Store&, root: blot_check_effects::Id, scope: u32) -> bool, Error { if !self_.has_rank_types { return false, blot_error::Error.none; } return blot_check_rank_walk::containsRow(self_, root, scope); }
fn containsRigid(self_: Store&, root: Id, scope: u32) -> bool, Error { if !self_.has_rank_types { return false, blot_error::Error.none; } return blot_check_rank_walk::contains(self_, root, scope, false); }
fn freeBound(self_: Store&, root: Id) -> bool, Error { if !self_.has_rank_types { return false, blot_error::Error.none; } return blot_check_rank_walk::contains(self_, root, 0, true); }
fn increment(value: u64&) { if value != 0xffffffffffffffff { value += 1; } }
fn fresh(self_: Store&) -> Id, Error {
    if self_.variables.len >= none { return 0, blot_error::Error.type_limit; } let index = self_.variables.len as u32;
    self_.variables.push(Variable {..});if self_.variables.failure!=blot_error::Error.none {return 0,self_.variables.failure;} increment(self_.normalization.type_binders_created);
    let id, error = variableView(self_, index, 0); if error != blot_error::Error.none { self_.variables.pop(); } return id, error;
}
fn freshRegion(self_: Store&) -> Id, Error {
    if self_.variables.len >= none { return 0, blot_error::Error.type_limit; } let index = self_.variables.len as u32;
    self_.variables.push(Variable { region: true , ..});if self_.variables.failure!=blot_error::Error.none {return 0,self_.variables.failure;} increment(self_.normalization.type_binders_created); self_.has_rank_types = true;
    let id, error = variableView(self_, index, 0); if error != blot_error::Error.none { self_.variables.pop(); } return id, error;
}
fn freshRowType(self_: Store&) -> Id, Error {
    let point = mark(self_); let row_, re = freshEffects(self_); if re != blot_error::Error.none { rollback(self_, point); return 0, re; }
    if self_.variables.len >= none { rollback(self_, point); return 0, blot_error::Error.type_limit; }
    let index = self_.variables.len as u32; self_.variables.push(Variable { row_effect: row_ , ..});if self_.variables.failure!=blot_error::Error.none {return 0,self_.variables.failure;} increment(self_.normalization.type_binders_created); self_.has_rank_types = true;
    let id, error = variableView(self_, index, 0); if error != blot_error::Error.none { rollback(self_, point); } return id, error;
}
fn rowType(self_: Store&, root: Id) -> blot_check_effects::Id, Error {
    let resolved, error = resolve(self_, root, 0); if error != blot_error::Error.none { return 0, error; } let leaf = node(self_, resolved);
    if leaf.tag == Tag.variable && self_.variables.items[leaf.a].row_effect != none { return self_.variables.items[leaf.a].row_effect, blot_error::Error.none; }
    if (leaf.tag == Tag.bound && leaf.b == 1 && leaf.c == 0) || (leaf.tag == Tag.rigid && leaf.c == 1) {
        let id, error = self_.effects.row([], blot_check_effects::Tail.formal { resolved , ..}); return id, effectError(error);
    }
    return 0, blot_error::Error.type_mismatch;
}
fn rowIdentity(self_: const Store&, root: Id) -> bool {
    if root >= self_.nodes.len { return false; } let leaf = node(self_, head(self_, root, 0));
    match leaf.tag { variable => { return self_.variables.items[leaf.a].row_effect != none; }, bound => { return leaf.b == 1 && leaf.c == 0; }, rigid => { return leaf.c == 1; }, _ => { return false; }, }
}
fn regionIdentity(self_: const Store&, root: Id) -> bool {
    if root >= self_.nodes.len { return false; } let leaf = node(self_, head(self_, root, 0));
    match leaf.tag { variable => { return self_.variables.items[leaf.a].region; }, bound => { return leaf.b == 2; }, rigid => { return leaf.c == 2; }, _ => { return false; }, }
}
fn usage(self_: Store&, payload: Id, kind: UsageKind, region: Id) -> Id, Error {
    if payload == absent || payload >= self_.nodes.len || node(self_, head(self_, payload, 0)).tag == Tag.erased_proof { return 0, blot_error::Error.type_mismatch; }
    if kind == blot_parse_ast::usagekind_shared { let affine, error = blot_check_usage_check::affine(self_, payload); if error != blot_error::Error.none { return 0, error; } if affine { return 0, blot_error::Error.type_mismatch; } }
    let loan = kind == blot_parse_ast::usagekind_borrow || kind == blot_parse_ast::usagekind_borrow_mut;
    if loan != (region != 0) || (loan && !regionIdentity(self_, region)) { return 0, blot_error::Error.type_mismatch; }
    self_.has_usage_types = true; return add(self_, Node { tag: Tag.usage, a: payload, b: kind as u32, c: region , ..});
}
fn proofKind(self_: Store&) -> Id, Error { let marker, error = add(self_, Node { Tag.erased_proof , ..}); if error != blot_error::Error.none { return 0, error; } self_.has_proof_kinds = true; return marker, blot_error::Error.none; }
fn dataKind(self_: const Store&, root: Id) -> Error {
    if self_.has_rank_types && (regionIdentity(self_, root) || rowIdentity(self_, root)) { return blot_error::Error.type_mismatch; }
    if self_.has_proof_kinds && node(self_, head(self_, root, 0)).tag == Tag.erased_proof { return blot_error::Error.type_mismatch; }
    return blot_error::Error.none;
}
fn variableView(self_: Store&, index: u32, at: Cursor) -> Id, Error {
    var position = at; if self_.variables.items[index].first == none && at <= cursor(self_) { position = 0; }
    let key = ((index as u64) << 32) | position;
    block { let saved = self_.variable_views.get(key); if saved { return saved, blot_error::Error.none; } }
    let id, error = add(self_, Node { tag: Tag.variable, a: index, b: position , ..}); if error != blot_error::Error.none { return 0, error; }
    self_.variable_views.insert(key, id);if self_.variable_views.failure!=blot_error::Error.none {return 0,self_.variable_views.failure;} increment(self_.normalization.variable_views_created); return id, blot_error::Error.none;
}
fn function(self_: Store&, parameter: Id, result: Id) -> Id, Error { return functionWithEffects(self_, parameter, result, 0); }
fn functionWithEffects(self_: Store&, parameter: Id, result: Id, effect_row: blot_check_effects::Id) -> Id, Error {
    if self_.has_rank_types && (regionIdentity(self_, parameter) || regionIdentity(self_, result) || rowIdentity(self_, parameter) || rowIdentity(self_, result)) { return 0, blot_error::Error.type_mismatch; }
    return add(self_, Node { tag: Tag.function, a: parameter, b: result, c: effect_row , ..});
}
fn product(self_: Store&, fields: const Id[:]) -> Id, Error {
    for field in fields { let error = dataKind(self_, field); if error != blot_error::Error.none { return 0, error; } }
    let span, error = saveList(self_, fields); if error != blot_error::Error.none { return 0, error; }
    return add(self_, Node { tag: Tag.product, a: span.start, b: span.len , ..});
}
fn array(self_: Store&, element: Id) -> Id, Error { let error = dataKind(self_, element); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: Tag.array, a: element , ..}); }
fn sequence(self_: Store&, tag: Tag, element: Id) -> Id, Error { assert(tag == Tag.array || tag == Tag.list || tag == Tag.cursor); let error = dataKind(self_, element); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: tag, a: element , ..}); }
fn typeConstructor(self_: Store&, identity: NominalIdentity) -> Id, Error { return add(self_, Node { tag: Tag.type_constructor, a: identity.unit, b: identity.decl , ..}); }
fn resolver(self_: Store&, token: Id) -> Id, Error { let error = dataKind(self_, token); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: Tag.resolver, a: token , ..}); }
fn provider(self_: Store&, operation_type: Id, implementation_effects: blot_check_effects::Id) -> Id, Error { let error = dataKind(self_, operation_type); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: Tag.provider, a: operation_type, c: implementation_effects , ..}); }
fn stateProvider(self_: Store&, read: Id, write: Id, state_type: Id) -> Id, Error { let error = dataKind(self_, state_type); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: Tag.state_provider, a: read, b: write, c: state_type , ..}); }
fn record(self_: Store&, fields: const Field[:]) -> Id, Error {
    var words: Id[>..] = [];
    for field in fields { let error = dataKind(self_, field.ty); if error != blot_error::Error.none { return 0, error; } words.push(field.name); words.push(field.ty); }
    let span, error = saveList(self_, words); if error != blot_error::Error.none { return 0, error; }
    return add(self_, Node { tag: Tag.record, a: span.start, b: fields.len as u32 , ..});
}
fn scoped(self_: Store&, descriptor: Id, instance: NominalIdentity) -> Id, Error { let error = dataKind(self_, descriptor); if error != blot_error::Error.none { return 0, error; } return add(self_, Node { tag: Tag.scoped, a: descriptor, b: instance.unit, c: instance.decl , ..}); }
fn capabilityParameter(self_: Store&, descriptor: Id) -> Id, Error { let variable, error = fresh(self_); if error != blot_error::Error.none { return 0, error; } return scoped(self_, descriptor, NominalIdentity { 0, variable , ..}); }
fn resolveInstance(self_: Store&, instance: NominalIdentity, at: Cursor, depth: i64) -> NominalIdentity, Error {
    if instance.unit != 0 || instance.decl == 0 { return instance, blot_error::Error.none; }
    let bound, error = resolveDepth(self_, instance.decl, at, depth + 1); if error != blot_error::Error.none { return default<NominalIdentity>(), error; }
    let value = node(self_, bound);
    if value.tag == Tag.variable || value.tag == Tag.instance_selection || regionIdentity(self_, bound) { return NominalIdentity { 0, bound , ..}, blot_error::Error.none; }
    if value.tag != Tag.scoped { return default<NominalIdentity>(), blot_error::Error.type_mismatch; }
    return NominalIdentity { value.b, value.c , ..}, blot_error::Error.none;
}
fn instanceVersion(self_: Store&, identity: NominalIdentity, ordinal: u32) -> Id, Error {
    if identity.unit == 0 || identity.decl == 0 || identity.decl >= 0x04000000 || ordinal >= 16 { return 0, blot_error::Error.type_mismatch; }
    return add(self_, Node { tag: Tag.instance_version, a: identity.unit, b: identity.decl, c: ordinal , ..});
}
fn instanceSelection(self_: Store&, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error {
    if identity.unit == 0 || identity.decl == 0 || (arguments.len != 2 && arguments.len != 3) { return 0, blot_error::Error.type_mismatch; }
    for argument in arguments[..2] { if argument >= self_.nodes.len || node(self_, argument).tag != Tag.scoped { return 0, blot_error::Error.type_mismatch; } }
    if arguments.len == 3 && (arguments[2] >= self_.nodes.len || node(self_, arguments[2]).tag != Tag.instance_version) { return 0, blot_error::Error.type_mismatch; }
    if self_.nodes.len > 65536 { return 0, blot_error::Error.type_limit; }
    for value, index in self_.nodes.items {
        if value.tag != Tag.instance_selection || value.a != identity.unit || value.b != identity.decl { continue; }
        let choices = nominalArguments(self_, value); if choices.len != arguments.len { continue; }
        if choices.len == 3 && node(self_, choices[2]) != node(self_, arguments[2]) { continue; }
        var same = true;
        for choice, i in choices[..2] { let old = node(self_, choice); let next = node(self_, arguments[i]); same = same && old.b == next.b && old.c == next.c; }
        if same { return index as u32, blot_error::Error.none; }
    }
    return nominalLike(self_, Tag.instance_selection, identity, arguments);
}
fn nominal(self_: Store&, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error { return nominalLike(self_, Tag.nominal, identity, arguments); }
fn nominalLike(self_: Store&, tag: Tag, identity: NominalIdentity, arguments: const Id[:]) -> Id, Error {
    for argument in arguments { let error = dataKind(self_, argument); if error != blot_error::Error.none { return 0, error; } }
    if arguments.len >= none || self_.extra.len > none - arguments.len - 1 { return 0, blot_error::Error.type_limit; }
    var owned: Id[>..] = []; owned.append(arguments); let start = self_.extra.len as u32;
    self_.extra.push(owned.len as u32);if self_.extra.failure!=blot_error::Error.none {return 0,self_.extra.failure;} self_.extra.append(owned);if self_.extra.failure!=blot_error::Error.none {return 0,self_.extra.failure;}
    return add(self_, Node { tag: tag, a: identity.unit, b: identity.decl, c: start , ..});
}
fn chargeProjection(self_: Store&) -> Error { if self_.projection_steps >= self_.projection_limit { self_.projection_exhausted = true; return blot_error::Error.type_limit; } self_.projection_steps += 1; return blot_error::Error.none; }
fn projection(self_: Store&, identity: NominalIdentity, member: u32, arguments: const Id[:]) -> Id, Error {
    for argument in arguments { let error = dataKind(self_, argument); if error != blot_error::Error.none { return 0, error; } }
    self_.has_projections = true; let id, error = nominal(self_, identity, arguments); if error != blot_error::Error.none { return 0, error; }
    self_.extra.push(member);if self_.extra.failure!=blot_error::Error.none {return 0,self_.extra.failure;} self_.nodes.items[id].tag = Tag.projection; self_.nodes.items[id].closed_height = 0; return id, blot_error::Error.none;
}
fn projectionMember(self_: const Store&, value: Node) -> u32 { assert(value.tag == Tag.projection); return self_.extra.items[value.c + 1 + self_.extra.items[value.c]]; }
fn nominalArguments(self_: const Store&, value: Node) -> const Id[:] { assert(value.tag == Tag.nominal || value.tag == Tag.projection || value.tag == Tag.instance_selection); return self_.extra.items[value.c + 1..value.c + 1 + self_.extra.items[value.c]]; }
fn recordField(self_: const Store&, value: Node, index: i64) -> Field { assert(value.tag == Tag.record && index < value.b); return Field { self_.extra.items[value.a + index * 2], self_.extra.items[value.a + index * 2 + 1] , ..}; }
fn mergeRecords(self_: Store&, left: Id, right: Id) -> blot_support::Option<Id>, Error {
    let a = node(self_, head(self_, left, 0)); let b = node(self_, head(self_, right, 0));
    if a.tag == Tag.never || b.tag == Tag.never { return blot_support::Option<Id> { true, never , ..}, blot_error::Error.none; }
    if (a.tag != Tag.record && a.tag != Tag.variable) || (b.tag != Tag.record && b.tag != Tag.variable) { return blot_support::Option<Id> { false, 0 , ..}, blot_error::Error.type_mismatch; }
    if a.tag == Tag.variable || b.tag == Tag.variable { return blot_support::Option<Id> { false, 0 , ..}, blot_error::Error.none; }
    if a.b == 0 { return blot_support::Option<Id> { true, right , ..}, blot_error::Error.none; } if b.b == 0 { return blot_support::Option<Id> { true, left , ..}, blot_error::Error.none; }
    var fields: Field[>..] = []; var slots = dictionary<u32, i64> {};
    for shape in [a, b] { for index in shape.b {
        let field = recordField(self_, shape, index); var found = false; var slot: i64 = 0;
        block { let previous = ::get(slots,field.name); if previous { found = true; slot = previous; } }
        if found { fields[slot] = field; } else { ::insert(slots,field.name, fields.len); fields.push(field); }
    } }
    let result, error = record(self_, fields); return blot_support::Option<Id> { error == blot_error::Error.none, result , ..}, error;
}
fn cursor(self_: const Store&) -> Cursor { return self_.effects.next_position; }
fn mark(self_: const Store&) -> Mark { return Mark { self_.nodes.len, self_.extra.len, self_.variables.len, self_.versions.len, self_.operations.len, self_.quantifier_goals.len, self_.quantifier_obligations.len, self_.effects.mark() , ..}; }
fn rollback(self_: Store&, point: Mark) {
    var discarded: Id[>..] = [];
    for slot in self_.associated_equations.slots { if slot.tag != 0 && (slot.key >= point.nodes || slot.val >= point.nodes) { discarded.push(slot.key); } }
    for key in discarded { self_.associated_equations.remove(key); }
    invalidateClosedGraphs(self_); tick(self_);
    while self_.versions.len > point.versions {
        let write = self_.versions.pop(); self_.variables.items[write.variable].last = write.previous;
        if write.previous == none { self_.variables.items[write.variable].first = none; } else { self_.versions.items[write.previous].next = none; }
    }
    for value in self_.nodes.items[point.nodes..] { if value.tag == Tag.variable { self_.variable_views.remove(((value.a as u64) << 32) | value.b); } }
    self_.nodes.pop_n(self_.nodes.len - point.nodes); self_.extra.pop_n(self_.extra.len - point.extra); self_.variables.pop_n(self_.variables.len - point.variables);
    unlinkOperations(self_, point.operations); self_.operations.pop_n(self_.operations.len - point.operations);
    self_.quantifier_goals.pop_n(self_.quantifier_goals.len - point.quantifier_goals); self_.quantifier_obligations.pop_n(self_.quantifier_obligations.len - point.quantifier_obligations);
    self_.effects.rollback(point.effects); self_.closed_effect_physical_epoch = self_.effects.physical_epoch;
}
fn appendVersion(self_: Store&, variable: Id, replacement_id: Id) -> Error {
    let value = node(self_, variable); assert(value.tag == Tag.variable); let old = self_.variables.items[value.a];
    if old.row_effect != none { if !rowIdentity(self_, replacement_id) { return blot_error::Error.type_mismatch; } }
    else if old.region { if !regionIdentity(self_, replacement_id) { return blot_error::Error.type_mismatch; } }
    else { let error = dataKind(self_, replacement_id); if error != blot_error::Error.none { return error; } }
    if self_.versions.len == none || cursor(self_) == none { return blot_error::Error.type_limit; }
    let index = self_.versions.len as u32; self_.versions.push(Version { value.a, replacement_id, cursor(self_), old.last , ..});if self_.versions.failure!=blot_error::Error.none {return self_.versions.failure;}
    if old.last == none { self_.variables.items[value.a].first = index; } else { self_.versions.items[old.last].next = index; }
    self_.variables.items[value.a].last = index; self_.effects.next_position += 1; tick(self_); return blot_error::Error.none;
}
fn replacement(self_: const Store&, index: u32, at: Cursor) -> blot_support::Option<Version> {
    var version = self_.variables.items[index].first;
    if version == none { return blot_support::Option<Version> { false, default<Version>() , ..}; }
    let first = self_.versions.items[version]; if first.position >= at { return blot_support::Option<Version> { true, first , ..}; }
    if self_.versions.items[self_.variables.items[index].last].position < at { return blot_support::Option<Version> { false, default<Version>() , ..}; }
    version = first.next;
    while version != none { let value = self_.versions.items[version]; if value.position >= at { return blot_support::Option<Version> { true, value , ..}; } version = value.next; }
    return blot_support::Option<Version> { false, default<Version>() , ..};
}
fn bindAssociated(self_: Store&, projection_: Id, result: Id) -> Error {
    let kind = dataKind(self_, result); if kind != blot_error::Error.none { return kind; } let charged = chargeProjection(self_); if charged != blot_error::Error.none { return charged; }
    if node(self_, projection_).tag != Tag.projection { return blot_error::Error.type_mismatch; }
    self_.associated_equations.insert(projection_, result);if self_.associated_equations.failure!=blot_error::Error.none {return self_.associated_equations.failure;} tick(self_); return blot_error::Error.none;
}
fn head(self_: const Store&, root: Id, at: Cursor) -> Id {
    var id = root; var position = at;
    while node(self_, id).tag == Tag.variable {
        let variable = node(self_, id); position = max(position, variable.b); let write = replacement(self_, variable.a, position);
        if !write.present { break; } id = write.value.replacement; position = write.value.position + 1;
    }
    block { let equation = self_.associated_equations.get(id); if equation { id = equation; } }
    let value = node(self_, id);
    if value.tag == Tag.variable { let saved = self_.variable_views.get(((value.a as u64) << 32) | position); if saved { return saved; } }
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
        0 => { return Tag.absent, blot_error::Error.none; },
        1 => { return Tag.unit, blot_error::Error.none; },
        2 => { return Tag.boolean, blot_error::Error.none; },
        3 => { return Tag.unsigned32, blot_error::Error.none; },
        4 => { return Tag.floating32, blot_error::Error.none; },
        5 => { return Tag.never, blot_error::Error.none; },
        6 => { return Tag.variable, blot_error::Error.none; },
        7 => { return Tag.function, blot_error::Error.none; },
        8 => { return Tag.product, blot_error::Error.none; },
        9 => { return Tag.record, blot_error::Error.none; },
        10 => { return Tag.nominal, blot_error::Error.none; },
        11 => { return Tag.array, blot_error::Error.none; },
        12 => { return Tag.list, blot_error::Error.none; },
        13 => { return Tag.cursor, blot_error::Error.none; },
        14 => { return Tag.type_constructor, blot_error::Error.none; },
        15 => { return Tag.resolver, blot_error::Error.none; },
        16 => { return Tag.provider, blot_error::Error.none; },
        17 => { return Tag.state_provider, blot_error::Error.none; },
        18 => { return Tag.projection, blot_error::Error.none; },
        19 => { return Tag.scoped, blot_error::Error.none; },
        20 => { return Tag.instance_selection, blot_error::Error.none; },
        21 => { return Tag.erased_proof, blot_error::Error.none; },
        22 => { return Tag.forall, blot_error::Error.none; },
        23 => { return Tag.existential, blot_error::Error.none; },
        24 => { return Tag.bound, blot_error::Error.none; },
        25 => { return Tag.rigid, blot_error::Error.none; },
        26 => { return Tag.usage, blot_error::Error.none; },
        27 => { return Tag.instance_version, blot_error::Error.none; },
        _ => { return Tag.absent, blot_error::Error.type_mismatch; },
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
        0 => { return Operator.none, blot_error::Error.none; },
        1 => { return Operator.add, blot_error::Error.none; },
        2 => { return Operator.sub, blot_error::Error.none; },
        3 => { return Operator.mul, blot_error::Error.none; },
        4 => { return Operator.div, blot_error::Error.none; },
        5 => { return Operator.rem, blot_error::Error.none; },
        6 => { return Operator.equal, blot_error::Error.none; },
        7 => { return Operator.not_equal, blot_error::Error.none; },
        8 => { return Operator.less, blot_error::Error.none; },
        9 => { return Operator.less_equal, blot_error::Error.none; },
        10 => { return Operator.greater, blot_error::Error.none; },
        11 => { return Operator.greater_equal, blot_error::Error.none; },
        12 => { return Operator.bit_and, blot_error::Error.none; },
        13 => { return Operator.bit_or, blot_error::Error.none; },
        14 => { return Operator.bit_xor, blot_error::Error.none; },
        15 => { return Operator.shift_left, blot_error::Error.none; },
        16 => { return Operator.shift_right, blot_error::Error.none; },
        _ => { return Operator.none, blot_error::Error.type_mismatch; },
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
        0 => { return ObligationKind.arithmetic, blot_error::Error.none; },
        1 => { return ObligationKind.ordered, blot_error::Error.none; },
        2 => { return ObligationKind.equality, blot_error::Error.none; },
        3 => { return ObligationKind.integer, blot_error::Error.none; },
        4 => { return ObligationKind.field, blot_error::Error.none; },
        5 => { return ObligationKind.writable_field, blot_error::Error.none; },
        6 => { return ObligationKind.dispatch, blot_error::Error.none; },
        7 => { return ObligationKind.result_dispatch, blot_error::Error.none; },
        8 => { return ObligationKind.monad_factory, blot_error::Error.none; },
        9 => { return ObligationKind.resolver_dispatch, blot_error::Error.none; },
        10 => { return ObligationKind.resolver_shape, blot_error::Error.none; },
        11 => { return ObligationKind.effect_operation, blot_error::Error.none; },
        12 => { return ObligationKind.effect_handler, blot_error::Error.none; },
        13 => { return ObligationKind.receiver, blot_error::Error.none; },
        14 => { return ObligationKind.update, blot_error::Error.none; },
        15 => { return ObligationKind.type_rep, blot_error::Error.none; },
        16 => { return ObligationKind.effect_rep, blot_error::Error.none; },
        17 => { return ObligationKind.type_head, blot_error::Error.none; },
        18 => { return ObligationKind.collection, blot_error::Error.none; },
        19 => { return ObligationKind.record_merge, blot_error::Error.none; },
        20 => { return ObligationKind.callee_use, blot_error::Error.none; },
        21 => { return ObligationKind.type_eq, blot_error::Error.none; },
        22 => { return ObligationKind.contract, blot_error::Error.none; },
        23 => { return ObligationKind.task_receive, blot_error::Error.none; },
        _ => { return ObligationKind.arithmetic, blot_error::Error.type_mismatch; },
    }
}

fn selectionAtom(source, original: NominalIdentity) -> NominalIdentity {
    if original.unit != 0 || original.decl == 0 { return original; }
    let value = source.node(original.decl);
    if value.tag != Tag.instance_selection { return original; }
    let choices = source.nominalArguments(value);
    if choices.len == 3 { let version = source.node(choices[2]); return NominalIdentity { version.a, 0x40000000 | (version.b << 4) | version.c , ..}; }
    return NominalIdentity { value.a, value.b , ..};
}
fn saturatedAdd(value: u64&, added: u64) { if added > 0xffffffffffffffff - value { value = 0xffffffffffffffff; } else { value += added; } }
fn compositeWindow(self_: Store&, root: Id, at: Cursor) -> Id, Error {
    let enabled = self_.use_composite_cache && self_.mutation_epoch < none && self_.effects.mutation_epoch < none;
    if enabled { let result = compositeResult(self_, root, at); if result.present { return result.value, blot_error::Error.none; } }
    let before_nodes = self_.nodes.len;
    let result, error = resolveDepth(self_, root, at, 0); if error != blot_error::Error.none { return 0, error; }
    if enabled && (result != root || self_.composites.entries.len != 0) && self_.nodes.len - before_nodes >= self_.composite_min_growth && self_.composites.activate(self_.closed_generation, self_.effects.physical_epoch) {
        let error = saveComposite(self_, root, at, result); if error != blot_error::Error.none { return 0, error; }
    }
    return result, blot_error::Error.none;
}
fn compositeResult(self_: Store&, root: Id, at: Cursor) -> blot_support::Option<Id> {
    self_.normalization.composite_probes += 1;
    if self_.composites.entries.len == 0 || !self_.composites.activate(self_.closed_generation, self_.effects.physical_epoch) { return blot_support::Option<Id> { false, 0 , ..}; }
    let certificate = self_.composites.get(root, at);
    if !certificate.present { if self_.composites.occupied(root, at) { self_.normalization.composite_collisions += 1; } return blot_support::Option<Id> { false, 0 , ..}; }
    if !validResolution(self_, certificate.value) { return blot_support::Option<Id> { false, 0 , ..}; }
    self_.normalization.composite_hits += 1; return blot_support::Option<Id> { true, certificate.value.result , ..};
}
fn saveComposite(self_: Store&, root: Id, at: Cursor, result: Id) -> Error {
    let certificate = resolutionDependencies(self_, result);
    if !certificate.present { self_.normalization.composite_frontier_declines += 1; return blot_error::Error.none; }
    let error = self_.composites.put(root, at, certificate.value); if error != blot_error::Error.none { return error; }
    self_.normalization.composite_publications += 1; return blot_error::Error.none;
}
fn validResolution(self_: Store&, certificate: blot_reuse_composite_resolution_cache::Record) -> bool {
    if certificate.future_clock.present && certificate.future_clock.value != cursor(self_) { self_.normalization.composite_future_clock_misses += 1; return false; }
    for dependency in certificate.dependencies[..certificate.count] {
        var last: u32 = 0; if dependency.effect { last = self_.effects.variables.items[dependency.variable].last; } else { last = self_.variables.items[dependency.variable].last; }
        if last != dependency.last { self_.normalization.composite_stale_dependencies += 1; return false; }
    }
    return true;
}
fn resolutionDependencies(self_: const Store&, result: Id) -> blot_support::Option<blot_reuse_composite_resolution_cache::Record> {
    var certificate = blot_reuse_composite_resolution_cache::Record { result: result , ..};
    var pending: Id[128] = [0; 128]; pending[0] = result; var count: i64 = 1; var budget: i64 = 256;
    while count != 0 {
        count -= 1; let id = pending[count]; if closedHeight(self_, id) != 0 || id <= never { continue; }
        if budget == 0 { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; } budget -= 1;
        let value = node(self_, id);
        if value.tag == Tag.variable {
            let variable = self_.variables.items[value.a];
            if !certificate.add(blot_reuse_composite_resolution_cache::Dependency { value.a, variable.last , ..}) { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; }
            if variable.first == none && value.b > cursor(self_) { certificate.future_clock = blot_support::Option<u32> { true, cursor(self_) , ..}; }
            continue;
        }
        if value.tag == Tag.function || value.tag == Tag.provider {
            let row_ = row(self_, value.c);
            for label in rowLabels(self_, value.c) {
                let arguments = operationArguments(self_, label);
                if arguments.len > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; }
                for argument in arguments { pending[count] = argument; count += 1; }
                let instance = operation(self_, label).instance;
                if instance.unit == 0 && instance.decl != 0 { if count == pending.len { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; } pending[count] = instance.decl; count += 1; }
            }
            match row_.tail { variable v => {
                if !certificate.add(blot_reuse_composite_resolution_cache::Dependency { v.value, self_.effects.variables.items[v.value].last, true , ..}) { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; }
            }, _ => {}, }
        }
        var children: Id[3] = [0; 3]; var length: i64 = 0; let tail:const Id[:] = if value.tag==Tag.product {list(self_,List{value.a,value.b,..})}else if value.tag==Tag.nominal || value.tag==Tag.projection || value.tag==Tag.instance_selection {nominalArguments(self_,value)}else {default<const Id[:]>()};
        match value.tag {
            function => { children = [value.a, value.b, 0]; length = 2; },
            usage => { children = [value.a, value.c, 0]; length = 1; if value.c != 0 { length = 2; } },
            scoped => { children = [value.a, value.c, 0]; length = 1; if value.b == 0 { length = 2; } },
            array, list, cursor, resolver, provider => { children[0] = value.a; length = 1; },
            state_provider => { children = [value.a, value.b, value.c]; length = 3; },
            record => {
                if value.b > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; }
                for i in value.b { pending[count + i] = recordField(self_, value, i).ty; } count += value.b;
            },
            _ => {},
        }
        if length + tail.len > pending.len - count { return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { false, certificate , ..}; }
        for child in children[..length] { pending[count] = child; count += 1; }
        for child in tail { pending[count] = child; count += 1; }
    }
    return blot_support::Option<blot_reuse_composite_resolution_cache::Record> { true, certificate , ..};
}
fn resolve(self_: Store&, root: Id, at: Cursor) -> Id, Error {
    let attribution_start = self_.nodes.len; let result, error = resolveRoot(self_, root, at);
    saturatedAdd(self_.normalization.resolve_nodes_added, (self_.nodes.len - attribution_start) as u64);
    return result, error;
}
fn resolveRoot(self_: Store&, root: Id, at: Cursor) -> Id, Error {
    if self_.use_closed_graphs {
        synchronizeClosedGraphs(self_); if closedHeight(self_, root) != 0 { return root, blot_error::Error.none; }
        let raw = node(self_, root);
        if self_.use_resolution_cache && at == 0 && raw.tag == Tag.variable && raw.b == 0 && raw.c != 0 && raw.closed_generation == self_.closed_generation && self_.closed_generation != 0xffff && self_.effects.physical_epoch != 0xffffffffffffffff {
            let remaining = node(self_, raw.c); if closedHeight(self_, raw.c) != 0 { return raw.c, blot_error::Error.none; }
            if remaining.tag == Tag.variable {
                let last = self_.variables.items[remaining.a].last;
                if last == none { if remaining.b == 0 || remaining.b > cursor(self_) { return raw.c, blot_error::Error.none; } }
                else if self_.versions.items[last].position < remaining.b { return raw.c, blot_error::Error.none; }
            }
        }
    }
    if !self_.use_resolution_cache || root <= never { return resolveDepth(self_, root, at, 0); }
    if at != 0 { return compositeWindow(self_, root, at); }
    if self_.mutation_epoch >= none || self_.effects.mutation_epoch >= none { return resolveDepth(self_, root, at, 0); }
    if !self_.resolved.activate(self_.mutation_epoch as u32, self_.effects.mutation_epoch as u32) { return resolveDepth(self_, root, at, 0); }
    let cached = self_.resolved.get(root); if cached.present { return cached.value, blot_error::Error.none; }
    let composite = self_.use_composite_cache;
    if composite { let cached = compositeResult(self_, root, at); if cached.present {
        if cached.value != root || root < self_.resolved.high_water { let error = self_.resolved.put(root, cached.value); if error != blot_error::Error.none { return 0, error; } }
        return cached.value, blot_error::Error.none;
    } }
    let before_nodes = self_.nodes.len; let result, error = resolveDepth(self_, root, at, 0); if error != blot_error::Error.none { return 0, error; }
    if self_.use_closed_graphs && self_.closed_generation != 0xffff && self_.effects.physical_epoch != 0xffffffffffffffff && (closedHeight(self_, result) != 0 || node(self_, result).tag == Tag.variable) && node(self_, root).tag == Tag.variable && node(self_, root).b == 0 {
        self_.nodes.items[root].c = result; self_.nodes.items[root].closed_generation = self_.closed_generation; return result, blot_error::Error.none;
    }
    if result == root && root >= self_.resolved.high_water { return result, blot_error::Error.none; }
    let publication = self_.resolved.put(root, result); if publication != blot_error::Error.none { return 0, publication; }
    if composite && self_.nodes.len - before_nodes >= self_.composite_min_growth && self_.composites.activate(self_.closed_generation, self_.effects.physical_epoch) {
        let error = saveComposite(self_, root, at, result); if error != blot_error::Error.none { return 0, error; }
    }
    return result, blot_error::Error.none;
}
recursive fn resolveDepth(self_: Store&, root: Id, at: Cursor, depth: i64) -> Id, Error {
    increment(self_.normalization.resolve_depth_entries);
    if (self_.has_projections || self_.use_closed_graphs) && self_.use_resolution_cache && depth != 0 && root > never {
        if closedHeight(self_, root) != 0 || self_.mutation_epoch == 0xffffffffffffffff || self_.effects.mutation_epoch == 0xffffffffffffffff { return resolveNode(self_, root, at, depth); }
        if self_.projection_resolution_types != self_.mutation_epoch || self_.projection_resolution_rows != self_.effects.mutation_epoch || self_.projection_resolution_limit != self_.resolution_depth_limit {
            self_.projection_resolutions.clear(); self_.projection_resolution_types = self_.mutation_epoch; self_.projection_resolution_rows = self_.effects.mutation_epoch; self_.projection_resolution_limit = self_.resolution_depth_limit;
        }
        if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } }
        let key = ProjectionResolution { root, at, depth as u32 , ..};
        block { let cached = self_.projection_resolutions.get(key); if cached { return cached, blot_error::Error.none; } }
        let result, error = resolveNode(self_, root, at, depth); if error != blot_error::Error.none { return 0, error; }
        if self_.projection_resolutions.count < 65536 { self_.projection_resolutions.insert(key, result);if self_.projection_resolutions.failure!=blot_error::Error.none {return 0,self_.projection_resolutions.failure;} }
        return result, blot_error::Error.none;
    }
    return resolveNode(self_, root, at, depth);
}
recursive fn resolveNode(self_: Store&, root: Id, at: Cursor, depth: i64) -> Id, Error {
    block { let equation = self_.associated_equations.get(root); if equation { return resolveDepth(self_, equation, at, depth + 1); } }
    if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } }
    if depth >= self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; }
    let height = closedHeight(self_, root);
    if height != 0 { if depth + height > self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; } return root, blot_error::Error.none; }
    var id = root; var position = at;
    while node(self_, id).tag == Tag.variable {
        let variable = node(self_, id); position = max(position, variable.b); let write = replacement(self_, variable.a, position);
        if !write.present { break; } id = write.value.replacement; position = write.value.position + 1;
    }
    if id != root { let height = closedHeight(self_, id); if height != 0 { if depth + height > self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; } return id, blot_error::Error.none; } }
    let value = node(self_, id); let result, error = resolveSelected(self_, id, value, position, depth);
    if self_.use_closed_graphs && value.tag != Tag.variable && self_.closed_generation != 0xffff {
        let refreshed = closedNodeHeight(self_, value); if refreshed != 0 { self_.nodes.items[id].closed_height = refreshed; self_.nodes.items[id].closed_generation = self_.closed_generation; }
    }
    return result, error;
}
recursive fn resolveSelected(self_: Store&, id: Id, value: Node, position: Cursor, depth: i64) -> Id, Error {
    match value.tag {
        forall, existential => {
            let binders=resolution_binders.alloc_slice(value.c);
            {let original_binders=list(self_,List {value.b,value.c});for binder,index in original_binders {binders[index]=binder;}}
            let result,error=resolveQuantified(self_,id,value,position,depth,binders);
            resolution_binders.free_slice(binders);
            return result,error;
        },
        usage => {
            let payload, pe = resolveDepth(self_, value.a, position, depth + 1); if pe != blot_error::Error.none { return 0, pe; }
            var region = value.c; if region != 0 { let next, error = resolveDepth(self_, region, position, depth + 1); if error != blot_error::Error.none { return 0, error; } region = next; }
            if payload == value.a && region == value.c { return id, blot_error::Error.none; } return usage(self_, payload, value.b as UsageKind, region);
        },
        scoped => {
            let child, ce = resolveDepth(self_, value.a, position, depth + 1); if ce != blot_error::Error.none { return 0, ce; }
            let instance, ie = resolveInstance(self_, NominalIdentity { value.b, value.c , ..}, position, depth + 1); if ie != blot_error::Error.none { return 0, ie; }
            if child == value.a && instance.unit == value.b && instance.decl == value.c { return id, blot_error::Error.none; } return scoped(self_, child, instance);
        },
        variable => { return variableView(self_, value.a, position); },
        function => {
            let parameter, pe = resolveDepth(self_, value.a, position, depth + 1); if pe != blot_error::Error.none { return 0, pe; }
            let result, re = resolveDepth(self_, value.b, position, depth + 1); if re != blot_error::Error.none { return 0, re; }
            let effect_row, ee = resolveOperationRow(self_, value.c, position, depth + 1); if ee != blot_error::Error.none { return 0, ee; }
            if parameter == value.a && result == value.b && effect_row == value.c { return id, blot_error::Error.none; }
            return functionWithEffects(self_, parameter, result, effect_row);
        },
        product => {
            let fields=resolution_arguments.alloc_slice(value.b);let result,error=resolveProductFields(self_,id,value,position,depth,fields);resolution_arguments.free_slice(fields);return result,error;
        },
        array, list, cursor, resolver => {
            let child, error = resolveDepth(self_, value.a, position, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if child == value.a { return id, blot_error::Error.none; } if value.tag == Tag.resolver { return resolver(self_, child); } return sequence(self_, value.tag, child);
        },
        provider => {
            let child, ce = resolveDepth(self_, value.a, position, depth + 1); if ce != blot_error::Error.none { return 0, ce; }
            let effect_row, ee = resolveOperationRow(self_, value.c, position, depth + 1); if ee != blot_error::Error.none { return 0, ee; }
            if child == value.a && effect_row == value.c { return id, blot_error::Error.none; } return provider(self_, child, effect_row);
        },
        state_provider => {
            let read, re = resolveDepth(self_, value.a, position, depth + 1); if re != blot_error::Error.none { return 0, re; }
            let write, we = resolveDepth(self_, value.b, position, depth + 1); if we != blot_error::Error.none { return 0, we; }
            let state_type, se = resolveDepth(self_, value.c, position, depth + 1); if se != blot_error::Error.none { return 0, se; }
            if read == value.a && write == value.b && state_type == value.c { return id, blot_error::Error.none; } return stateProvider(self_, read, write, state_type);
        },
        record => {
            let fields=resolution_fields.alloc_slice(value.b);let result,error=resolveRecordFields(self_,id,value,position,depth,fields);resolution_fields.free_slice(fields);return result,error;
        },
        nominal, projection, instance_selection => {
            let count=self_.extra.items[value.c];let args=resolution_arguments.alloc_slice(count);let result,error=resolveNominalArguments(self_,id,value,position,depth,count,args);resolution_arguments.free_slice(args);return result,error;
        },
        _ => { return id, blot_error::Error.none; },
    }
}
reusable[] var resolution_fields:Field[>..];
// Copy prefixes only after the first changed child, as in the original traversal.
recursive fn resolveProductFields(self_:Store&,id:Id,value:Node,position:Cursor,depth:i64,fields:Id[:])->Id,Error {
            var changed=false;
            for i in value.b {
                let old = self_.extra.items[value.a + i]; let child, error = resolveDepth(self_, old, position, depth + 1); if error != blot_error::Error.none { return 0, error; }
                if !changed && child != old { for previous,offset in self_.extra.items[value.a..value.a+i] {fields[offset]=previous;} changed=true; }
                if changed { fields[i]=child; }
            }
            if changed { return product(self_, fields); } return id, blot_error::Error.none;
}
recursive fn resolveRecordFields(self_:Store&,id:Id,value:Node,position:Cursor,depth:i64,fields:Field[:])->Id,Error {
            var changed=false;
            for i in value.b {
                let field = recordField(self_, value, i); let child, error = resolveDepth(self_, field.ty, position, depth + 1); if error != blot_error::Error.none { return 0, error; }
                if !changed && child != field.ty { for prefix in i {fields[prefix]=recordField(self_,value,prefix);} changed=true; }
                if changed { fields[i]=Field{field.name,child,..}; }
            }
            if changed { return record(self_, fields); } return id, blot_error::Error.none;
}
recursive fn resolveNominalArguments(self_:Store&,id:Id,value:Node,position:Cursor,depth:i64,count:u32,args:Id[:])->Id,Error {
            var changed=false;
            for i in count {
                let child = self_.extra.items[value.c + 1 + i]; let next, error = resolveDepth(self_, child, position, depth + 1); if error != blot_error::Error.none { return 0, error; }
                if !changed && child != next { for previous,offset in self_.extra.items[value.c+1..value.c+1+i] {args[offset]=previous;} changed=true; } if changed { args[i]=next; }
            }
            if !changed { return id, blot_error::Error.none; }
            if value.tag == Tag.projection { return projection(self_, NominalIdentity { value.a, value.b , ..}, projectionMember(self_, value), args); }
            if value.tag == Tag.instance_selection { return instanceSelection(self_, NominalIdentity { value.a, value.b , ..}, args); }
            return nominal(self_, NominalIdentity { value.a, value.b , ..}, args);
}
fn occurs(self_: Store&, variable: u32, root: Id) -> bool, Error {
    let resolved_root, error = resolve(self_, root, 0); if error != blot_error::Error.none { return false, error; }
    if closedHeight(self_, resolved_root) != 0 || resolved_root <= never { self_.occurs_steps += 1; return false, blot_error::Error.none; }
    if self_.occurs_seen.len < self_.nodes.len { self_.occurs_seen.resize(self_.nodes.len, 0);if self_.occurs_seen.failure!=blot_error::Error.none {return false,self_.occurs_seen.failure;} }
    self_.occurs_generation += 1;
    if self_.occurs_generation == 0 { for &value in self_.occurs_seen.items { value = 0; } self_.occurs_generation = 1; }
    var pending: Id[>..<] = []; pending.push(resolved_root); var budget: i64 = 1000000;
    while pending.len > 0 {
        let id = pending.pop(); if self_.occurs_seen.items[id] == self_.occurs_generation { continue; } self_.occurs_seen.items[id] = self_.occurs_generation;
        if budget == 0 { return false, blot_error::Error.type_limit; } budget -= 1; self_.occurs_steps += 1; if closedHeight(self_, id) != 0 { continue; }
        let value = node(self_, id);
        if value.tag == Tag.function || value.tag == Tag.provider { for label in rowLabels(self_, value.c) {
            pending.append(operationArguments(self_, label)); let instance = operation(self_, label).instance;
            if instance.unit == 0 && instance.decl != 0 { pending.push(instance.decl); }
        } }
        match value.tag {
            variable => { if value.a == variable { return true, blot_error::Error.none; } },
            function => { pending.append([value.a, value.b]); },
            product => { pending.append(list(self_, List { value.a, value.b , ..})); },
            usage => { pending.push(value.a); if value.c != 0 { pending.push(value.c); } },
            scoped => { pending.push(value.a); if value.b == 0 { pending.push(value.c); } },
            forall, existential => { pending.push(value.a); for goal in quantifierGoals(self_, id) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { pending.push(child); } } } },
            array, list, cursor, resolver, provider => { pending.push(value.a); },
            state_provider => { pending.append([value.a, value.b, value.c]); },
            record => { for i in value.b { pending.push(recordField(self_, value, i).ty); } },
            nominal, projection, instance_selection => { pending.append(nominalArguments(self_, value)); },
            _ => {},
        }
    }
    return false, blot_error::Error.none;
}
fn snapshotResolutionIds(values:const Id[:])->Id[:] {let result=resolution_arguments.alloc_slice(values.len);for value,index in values {result[index]=value;}return result;}
fn snapshotResolutionGoals(values:const Obligation[:])->Obligation[:] {let result=resolution_goals.alloc_slice(values.len);for value,index in values {result[index]=value;}return result;}
recursive fn unifyEffects(self_: Store&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    let point = mark(self_); let error = unifyEffectsInner(self_, left, right); if error != blot_error::Error.none { rollback(self_, point); } return error;
}
recursive fn unifyEffectsInner(self_: Store&, left: blot_check_effects::Id, right: blot_check_effects::Id) -> Error {
    let a, ae = resolveEffects(self_, left, 0); if ae != blot_error::Error.none { return ae; }
    let b, be = resolveEffects(self_, right, 0); if be != blot_error::Error.none { return be; }
    var symbolic = false;
    for label in rowLabels(self_, a) { if symbolic { break; } let result, error = symbolicOperation(self_, label); if error != blot_error::Error.none { return error; } symbolic = result; }
    for label in rowLabels(self_, b) { if symbolic { break; } let result, error = symbolicOperation(self_, label); if error != blot_error::Error.none { return error; } symbolic = result; }
    if !symbolic { return effectError(self_.effects.unify(a, b)); }
    let labels=snapshotResolutionIds(rowLabels(self_,a));let candidates=snapshotResolutionIds(rowLabels(self_,b));
    let error=unifySymbolicEffects(self_,a,b,labels,candidates);resolution_arguments.free_slice(candidates);resolution_arguments.free_slice(labels);return error;
}
recursive fn unifySymbolicEffects(self_:Store&,a:blot_check_effects::Id,b:blot_check_effects::Id,labels:const blot_check_effects::Label[:],candidates:const blot_check_effects::Label[:])->Error {
    for label in labels {
        var exact = false; for candidate in candidates { exact = exact || candidate == label; } if exact { continue; }
        let operation_ = operation(self_, label); var selected: blot_support::Option<blot_check_effects::Label>   = blot_support::Option<blot_check_effects::Label> { false, 0 , ..};
        for candidate in candidates {
            let other = operation(self_, candidate);
            if operation_.identity != other.identity || operation_.instance != other.instance || operation_.arguments.len != other.arguments.len { continue; }
            let trial = mark(self_); let matched, error = unifyOperationArguments(self_, label, candidate); rollback(self_, trial);
            if error != blot_error::Error.none { if error == blot_error::Error.out_of_memory || error == blot_error::Error.type_limit { return error; } continue; }
            if !matched { continue; }
            if selected.present { if selected.value != candidate { return blot_error::Error.effect_mismatch; } }
            else { selected = blot_support::Option<blot_check_effects::Label> { true, candidate , ..}; }
        }
        if selected.present { let matched, error = unifyOperationArguments(self_, label, selected.value); if error != blot_error::Error.none { return error; } }
    }
    let ar, are = resolveEffects(self_, a, 0); if are != blot_error::Error.none { return are; }
    let br, bre = resolveEffects(self_, b, 0); if bre != blot_error::Error.none { return bre; }
    return effectError(self_.effects.unify(ar, br));
}
fn symbolicOperation(self_: Store&, label: blot_check_effects::Label) -> bool, Error {
    for argument in operationArguments(self_, label) { if closedHeight(self_, argument) != 0 { continue; } let same, error = equalClosed(self_, argument, argument); if error != blot_error::Error.none { return false, error; } if !same { return true, blot_error::Error.none; } }
    return false, blot_error::Error.none;
}
recursive fn unifyOperationArguments(self_: Store&, left: blot_check_effects::Label, right: blot_check_effects::Label) -> bool, Error {
    let ls, le = symbolicOperation(self_, left); if le != blot_error::Error.none { return false, le; }
    if !ls { let rs, re = symbolicOperation(self_, right); if re != blot_error::Error.none { return false, re; } if !rs { return false, blot_error::Error.none; } }
    let a=snapshotResolutionIds(operationArguments(self_,left));let b=snapshotResolutionIds(operationArguments(self_,right));
    let result,error=unifyOperationArgumentSnapshots(self_,a,b);resolution_arguments.free_slice(b);resolution_arguments.free_slice(a);return result,error;
}
recursive fn unifyOperationArgumentSnapshots(self_:Store&,a:const Id[:],b:const Id[:])->bool,Error {
    for first, i in a { let error = unify(self_, first, b[i]); if error != blot_error::Error.none { return false, error; } }
    return true, blot_error::Error.none;
}
fn freshEffects(self_: Store&) -> blot_check_effects::Id, Error { let id, error = self_.effects.fresh(); return id, effectError(error); }
fn resolveEffects(self_: Store&, effect_row: blot_check_effects::Id, at: Cursor) -> blot_check_effects::Id, Error { if self_.use_closed_graphs { synchronizeClosedGraphs(self_); } return resolveOperationRow(self_, effect_row, at, 0); }
recursive fn resolveOperationRow(self_: Store&, root: blot_check_effects::Id, at: Cursor, depth: i64) -> blot_check_effects::Id, Error {
    self_.normalization.row_requests += 1; if depth >= 1024 { return 0, blot_error::Error.type_limit; }
    let id, error = self_.effects.resolve(root, at); if error != blot_error::Error.none { return 0, effectError(error); }
    let row_ = row(self_, id); if row_.labels.len == 0 { return id, blot_error::Error.none; }
    if self_.use_closed_rows && self_.use_closed_graphs && id >= self_.closed_row_index.len {
        let previous = self_.closed_row_index.len; self_.closed_row_index.resize(self_.effects.rows.len, RowCertificate {..});if self_.closed_row_index.failure!=blot_error::Error.none {return default<blot_check_effects::Id>(),self_.closed_row_index.failure;}
        for value in self_.closed_rows { if value.row >= previous && value.row < self_.closed_row_index.len { self_.closed_row_index.items[value.row] = RowCertificate { value.generation, value.argument_height, value.has_arguments , ..}; } }
    }
    let cached = closedRow(self_, id);
    if cached.present { self_.normalization.closed_row_hits += 1; if cached.value.has_arguments && depth + 1 + cached.value.argument_height > self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; } return id, blot_error::Error.none; }
    let mutation = self_.mutation_epoch; let effects = self_.effects.mutation_epoch;
    let cacheable = self_.use_operation_rows && self_.use_resolution_cache && mutation != 0xffffffffffffffff && effects != 0xffffffffffffffff;
    let slot = id % self_.operation_rows.len;
    if cacheable {
        self_.normalization.epoch_row_probes += 1; let saved = self_.operation_rows[slot];
        if saved.row == id && saved.at == at && saved.depth == depth && saved.limit == self_.resolution_depth_limit && saved.mutation == mutation && saved.effects == effects { self_.normalization.epoch_row_hits += 1; return saved.result, blot_error::Error.none; }
        if saved.row != id { if saved.row != 0 { self_.normalization.epoch_row_collisions += 1; } }
        else if saved.mutation != mutation || saved.effects != effects { self_.normalization.epoch_row_stale += 1; }
        else { self_.normalization.epoch_row_context_misses += 1; }
    }
    let result, error = resolveOperationArguments(self_, id, at, depth); if error != blot_error::Error.none { return 0, error; }
    if cacheable && self_.mutation_epoch == mutation && self_.effects.mutation_epoch == effects {
        self_.operation_rows[slot] = OperationRow { id, result, at, depth, self_.resolution_depth_limit, mutation, effects , ..}; self_.normalization.epoch_row_publications += 1;
    }
    return result, blot_error::Error.none;
}
recursive fn resolveOperationArguments(self_: Store&, id: blot_check_effects::Id, at: Cursor, depth: i64) -> blot_check_effects::Id, Error {
    self_.normalization.argument_rows += 1;
    if self_.use_closed_rows && self_.use_closed_graphs && self_.closed_operation_index.len < self_.operations.len { self_.closed_operation_index.resize(self_.operations.len, RowCertificate {..});if self_.closed_operation_index.failure!=blot_error::Error.none {return default<blot_check_effects::Id>(),self_.closed_operation_index.failure;} }
    let row_=row(self_,id);let labels=resolution_arguments.alloc_slice(row_.labels.len);
    let result,error=resolveOperationLabels(self_,id,at,depth,row_,labels);resolution_arguments.free_slice(labels);return result,error;
}
reusable[] var resolution_arguments:Id[>..];
recursive fn resolveOperationLabels(self_:Store&,id:blot_check_effects::Id,at:Cursor,depth:i64,row_:blot_check_effects::Row,labels:blot_check_effects::Label[:])->blot_check_effects::Id,Error {
    var all_closed=true;var argument_height:u8=0;var has_arguments=false;var changed=false;
    for index in row_.labels.len {
        let label = self_.effects.list(row_.labels)[index]; let operation_ = operation(self_, label);
        self_.normalization.labels += 1; self_.normalization.arguments += operation_.arguments.len;
        let proof = closedOperation(self_, label);
        if proof.present {
            self_.normalization.closed_operation_hits += 1; has_arguments = has_arguments || proof.value.has_arguments; argument_height = max(argument_height, proof.value.argument_height);
            if proof.value.has_arguments && depth + 1 + proof.value.argument_height > self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; }
            if changed { labels[index]=label; } continue;
        }
        var closed = operation_.instance.unit != 0 || operation_.instance.decl == 0; var operation_height: u8 = 0;
        for argument in list(self_, operation_.arguments) {
            has_arguments = true; let height = closedHeight(self_, argument); self_.normalization.argument_height_checks += 1;
            argument_height = max(argument_height, height); operation_height = max(operation_height, height);
            if height == 0 { closed = false; } if height != 0 && depth + 1 + height > self_.resolution_depth_limit { return 0, blot_error::Error.type_limit; }
        }
        all_closed = all_closed && closed;
        if closed { saveClosedOperation(self_, label, operation_height, operation_.arguments.len != 0); if changed { labels[index]=label; } continue; }
        let arguments=resolution_arguments.alloc_slice(operation_.arguments.len);
        let next,error=resolveOperationLabel(self_,label,operation_,at,depth,arguments);resolution_arguments.free_slice(arguments);if error!=blot_error::Error.none {return 0,error;}
        if !changed && next != label { for previous,offset in self_.effects.list(row_.labels)[..index] {labels[offset]=previous;} changed=true; }
        if changed { labels[index]=next; }
    }
    if !changed { if all_closed { saveClosedRow(self_, id, argument_height, has_arguments); } return id, blot_error::Error.none; }
    self_.normalization.changed_rows += 1; let result, error = self_.effects.rowAt(labels, row_.tail, row_.cursor); return result, effectError(error);
}
recursive fn resolveOperationLabel(self_:Store&,label:blot_check_effects::Label,operation_:Operation,at:Cursor,depth:i64,arguments:Id[:])->blot_check_effects::Label,Error {
 var argument_changed=false;
        for offset in operation_.arguments.len {
            let argument = list(self_, operation_.arguments)[offset]; let resolved, error = resolveDepth(self_, argument, at, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if !argument_changed && resolved != argument { for previous,index in list(self_,operation_.arguments)[..offset] {arguments[index]=previous;} argument_changed=true; }
            if argument_changed { arguments[offset]=resolved; }
        }
        let instance, ie = resolveInstance(self_, operation_.instance, at, depth + 1); if ie != blot_error::Error.none { return 0, ie; }
        var next = label;
        if argument_changed || instance != operation_.instance {
            let selected_arguments:const Id[:] = if argument_changed {arguments}else {list(self_,operation_.arguments)};
            let result, error = internResolvedOperation(self_, operation_.identity, instance, selected_arguments, true); if error != blot_error::Error.none { return 0, error; } next = result;
        }
 return next,blot_error::Error.none;
}
fn row(self_: const Store&, id: blot_check_effects::Id) -> blot_check_effects::Row { return self_.effects.node(id); }
fn rowLabels(self_: const Store&, id: blot_check_effects::Id) -> const blot_check_effects::Label[:] { return self_.effects.list(row(self_, id).labels); }
fn operation(self_: const Store&, label: blot_check_effects::Label) -> Operation { return self_.operations.items[label]; }
fn operationArguments(self_: const Store&, label: blot_check_effects::Label) -> const Id[:] { return list(self_, operation(self_, label).arguments); }
fn internOperation(self_: Store&, identity: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error { return internOperationMode(self_, identity, NominalIdentity { 0, 0 , ..}, arguments, false); }
fn internSymbolicOperation(self_: Store&, identity: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error { return internOperationMode(self_, identity, NominalIdentity { 0, 0 , ..}, arguments, true); }
fn internScopedOperation(self_: Store&, identity: NominalIdentity, instance: NominalIdentity, arguments: const Id[:]) -> blot_check_effects::Label, Error {
    if identity.unit == 0 && identity.decl == 1 && (instance.unit != 0 || instance.decl != 0) { return 0, blot_error::Error.type_mismatch; }
    let resolved, error = resolveInstance(self_, instance, 0, 0); if error != blot_error::Error.none { return 0, error; }
    return internOperationMode(self_, identity, resolved, arguments, true);
}
fn internOperationMode(self_: Store&, identity: NominalIdentity, instance: NominalIdentity, arguments: const Id[:], symbolic: bool) -> blot_check_effects::Label, Error {
    let point = mark(self_); var borrowed: Id[>..] = []; borrowed.append(arguments); var resolved: Id[>..] = [];
    for argument in borrowed {
        let ty, error = resolve(self_, argument, 0); if error != blot_error::Error.none { rollback(self_, point); return 0, error; }
        let kind = dataKind(self_, ty); if kind != blot_error::Error.none { rollback(self_, point); return 0, kind; }
        if !symbolic { let same, error = equalClosed(self_, ty, ty); if error != blot_error::Error.none { rollback(self_, point); return 0, error; } if !same { rollback(self_, point); return 0, blot_error::Error.type_mismatch; } }
        resolved.push(ty);
    }
    let label, error = internResolvedOperation(self_, identity, instance, resolved, symbolic); if error != blot_error::Error.none { rollback(self_, point); } return label, error;
}
fn internResolvedOperation(self_: Store&, identity: NominalIdentity, instance: NominalIdentity, resolved: const Id[:], symbolic: bool) -> blot_check_effects::Label, Error {
    self_.normalization.interner_requests += 1; let point = mark(self_); let linked = linkOperations(self_); if linked != blot_error::Error.none { rollback(self_, point); return 0, linked; }
    if resolved.len <= none {
        let key = OperationKey { identity, instance, resolved.len as u32, operationShape(self_, resolved) , ..};
        var first = none; block { let chain = self_.operation_chains.get(key); if chain { first = chain.first; } }
        var index = first;
        while index != none {
            self_.normalization.interner_candidates += 1; let old = list(self_, self_.operations.items[index].arguments); var same = true;
            for a, i in old { if !same { break; } self_.normalization.interner_arguments += 1; let result, error = equalGraph(self_, a, resolved[i], symbolic); if error != blot_error::Error.none { rollback(self_, point); return 0, error; } same = result; }
            if same { return index, blot_error::Error.none; } index = self_.operation_links.items[index].next;
        }
    }
    if self_.operations.len == none { rollback(self_, point); return 0, blot_error::Error.type_limit; }
    let span, error = saveList(self_, resolved); if error != blot_error::Error.none { rollback(self_, point); return 0, error; }
    let id = self_.operations.len as u32; self_.operations.push(Operation { identity, span, instance , ..});if self_.operations.failure!=blot_error::Error.none {return default<blot_check_effects::Label>(),self_.operations.failure;} return id, blot_error::Error.none;
}
fn operationShape(self_: const Store&, arguments: const Id[:]) -> u64 {
    if !self_.operation_shape_enabled { return 0; } var value = arguments.len as u64;
    for argument in arguments[..min(arguments.len, 4)] { value = mixShape(value, operationTypeShape(self_, argument, 2)); } return value;
}
fn mixShape(left: u64, right: u64) -> u64 { return (left ^ right) * 0x9e3779b97f4a7c15 + 0x85ebca6b; }
recursive fn operationTypeShape(self_: const Store&, id: Id, depth: i64) -> u64 {
    let value = node(self_, id); var fingerprint = tagCode(value.tag) as u64;
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
        array, list, cursor, resolver, provider, usage, scoped => { fingerprint = mixShape(fingerprint, operationTypeShape(self_, value.a, depth - 1)); },
        function => { fingerprint = mixShape(fingerprint, operationTypeShape(self_, value.a, depth - 1)); fingerprint = mixShape(fingerprint, operationTypeShape(self_, value.b, depth - 1)); },
        product => { for child in list(self_, List { value.a, min(value.b, 2) , ..}) { fingerprint = mixShape(fingerprint, operationTypeShape(self_, child, depth - 1)); } },
        _ => {},
    }
    return fingerprint;
}
fn linkOperations(self_: Store&) -> Error {
    let enabled = self_.use_operation_shapes && !self_.has_projections && self_.closed_generation != 0xffff;
    if self_.operation_links.len > self_.operations.len || self_.operation_shape_generation != self_.closed_generation || self_.operation_shape_enabled != enabled {
        self_.normalization.interner_rebuilds += 1; self_.operation_chains.clear(); self_.operation_links.clear();
    }
    self_.operation_shape_generation = self_.closed_generation; self_.operation_shape_enabled = enabled;
    if self_.operation_links.len == 0 { self_.operation_links.push(OperationLink {..});if self_.operation_links.failure!=blot_error::Error.none {return self_.operation_links.failure;} }
    while self_.operation_links.len < self_.operations.len {
        self_.normalization.interner_linked += 1; let index = self_.operation_links.len as u32; let operation_ = self_.operations.items[index];
        let shape = operationShape(self_, list(self_, operation_.arguments)); let key = OperationKey { operation_.identity, operation_.instance, operation_.arguments.len, shape , ..};
        var found = false; var last = none;
        block { let entry .= self_.operation_chains.get(key); if entry { found = true; last = entry.last; entry.last = index; } }
        if found { self_.operation_links.items[last].next = index; self_.operation_links.push(OperationLink { previous: last, shape: shape , ..});if self_.operation_links.failure!=blot_error::Error.none {return self_.operation_links.failure;} }
        else { self_.operation_links.push(OperationLink { shape: shape , ..});if self_.operation_links.failure!=blot_error::Error.none {return self_.operation_links.failure;} self_.operation_chains.insert(key, OperationChain { index, index , ..});if self_.operation_chains.failure!=blot_error::Error.none {return self_.operation_chains.failure;} }
    }
    return blot_error::Error.none;
}
fn unlinkOperations(self_: Store&, length: i64) {
    if self_.operation_links.len > self_.operations.len { self_.operation_chains.clear(); self_.operation_links.clear(); }
    while self_.operation_links.len > max(length, 1) {
        let index = self_.operation_links.len - 1; let operation_ = self_.operations.items[index];
        let key = OperationKey { operation_.identity, operation_.instance, operation_.arguments.len, self_.operation_links.items[index].shape , ..};
        let previous = self_.operation_links.pop().previous;
        if previous == none { self_.operation_chains.remove(key); }
        else { self_.operation_links.items[previous].next = none; let chain .= self_.operation_chains.get(key); assert(chain); chain.last = previous; }
    }
}
struct Pair { a: Id, b: Id, effect_row: bool = false }
fn hash(value: Pair) -> u64 { var row: u64 = 0; if value.effect_row { row = 1; } return ::hash_combine(::hash_combine(::hash(value.a), ::hash(value.b)), ::hash(row)); }
fn hash(value: ProjectionResolution) -> u64 { return ::hash_combine(::hash_combine(::hash(value.root), ::hash(value.at)), ::hash(value.depth)); }
fn hash(value: OperationKey) -> u64 {
    return ::hash_combine(::hash_combine(::hash_combine(::hash_combine(::hash_combine(::hash(value.identity.unit), ::hash(value.identity.decl)), ::hash(value.instance.unit)), ::hash(value.instance.decl)), ::hash(value.arity)), ::hash(value.shape));
}
fn equalClosed(self_: Store&, left: Id, right: Id) -> bool, Error { return equalGraph(self_, left, right, false); }
fn equalSymbolic(self_: Store&, left: Id, right: Id) -> bool, Error { return equalGraph(self_, left, right, true); }
fn equalGraph(self_: Store&, left: Id, right: Id, symbolic: bool) -> bool, Error {
    if !self_.has_projections {
        if symbolic && left == right { return true, blot_error::Error.none; } if !symbolic && left == right && closedHeight(self_, left) != 0 { return true, blot_error::Error.none; }
        let l = node(self_, left); let r = node(self_, right); if l.tag != r.tag { return false, blot_error::Error.none; }
        match l.tag {
            absent, bound => { return false, blot_error::Error.none; }, unit, boolean, unsigned32, floating32, never => { return true, blot_error::Error.none; },
            nominal, instance_selection, type_constructor => { if l.a != r.a || l.b != r.b { return false, blot_error::Error.none; } }, _ => {},
        }
    }
    return equalGraphWalk(self_, left, right, symbolic);
}
fn equalLabelMultisets(left: const blot_check_effects::Label[:], right: const blot_check_effects::Label[:]) -> bool, Error {
    if left.len != right.len { return false, blot_error::Error.none; } if left == right { return true, blot_error::Error.none; }
    if left.len <= 16 {
        for label in left { var before: i64 = 0; var after: i64 = 0; for value in left { if value == label { before += 1; } } for value in right { if value == label { after += 1; } } if before != after { return false, blot_error::Error.none; } }
        return true, blot_error::Error.none;
    }
    var counts = dictionary<blot_check_effects::Label, i64> {};
    for label in left { let count .= ::get_or_insert(counts,label,0); count += 1; }
    for label in right { let count .= ::get(counts,label); if !count { return false, blot_error::Error.none; } if count == 0 { return false, blot_error::Error.none; } count -= 1; }
    return true, blot_error::Error.none;
}
fn equalGraphWalk(self_: Store&, left: Id, right: Id, symbolic: bool) -> bool, Error {
    let shared_closed = !symbolic && !self_.has_projections && closedHeight(self_, left) != 0 && closedHeight(self_, right) != 0;
    var pending: Pair[>..<] = []; pending.push(Pair { left, right , ..}); var seen = dictionary<Pair, bool> {};
    var few: Pair[16] = [default<Pair>(); 16]; var few_count: i64 = 0; var budget: i64 = 1000000;
    while pending.len > 0 {
        let pair = pending.pop();
        if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return false, error; } }
        if symbolic && pair.a == pair.b { continue; }
        if symbolic || self_.has_projections || shared_closed {
            if few_count < few.len {
                var repeated = false; for prior in few[..few_count] { if prior.a == pair.a && prior.b == pair.b { repeated = true; break; } }
                if repeated { continue; } few[few_count] = pair; few_count += 1;
            } else {
                if seen.count == 0 { for prior in few { ::insert(seen,prior, true); } }
                if ::contains(seen,pair) { continue; } ::insert(seen,pair, true);
            }
        }
        if budget == 0 { return false, blot_error::Error.type_limit; } budget -= 1;
        let a = node(self_, pair.a); let b = node(self_, pair.b); if a.tag != b.tag { return false, blot_error::Error.none; }
        match a.tag {
            bound, absent => { return false, blot_error::Error.none; },
            rigid => { if !symbolic || a.a != b.a || a.b != b.b || a.c != b.c { return false, blot_error::Error.none; } },
            usage => { if a.b != b.b || (a.c == 0) != (b.c == 0) { return false, blot_error::Error.none; } pending.push(Pair { a.a, b.a , ..}); if a.c != 0 { pending.push(Pair { a.c, b.c , ..}); } },
            forall, existential => { let same, error = blot_check_rank_equal::equal(self_, pair.a, pair.b, symbolic); if error != blot_error::Error.none || !same { return same, error; } },
            variable => { if !symbolic || a.a != b.a || a.b != b.b { return false, blot_error::Error.none; } },
            function, provider => {
                let ar = self_.effects.node(a.c); let br = self_.effects.node(b.c);
                if symbolic { if ar.tail != br.tail || ar.cursor != br.cursor { return false, blot_error::Error.none; } }
                else if ar.tail != blot_check_effects::Tail.closed || br.tail != blot_check_effects::Tail.closed { return false, blot_error::Error.none; }
                let same, error = equalLabelMultisets(self_.effects.list(ar.labels), self_.effects.list(br.labels)); if error != blot_error::Error.none || !same { return same, error; }
                for label in self_.effects.list(ar.labels) {
                    for argument in operationArguments(self_, label) { pending.push(Pair { argument, argument , ..}); }
                    let instance = operation(self_, label).instance; if instance.unit == 0 && instance.decl != 0 { pending.push(Pair { instance.decl, instance.decl , ..}); }
                }
                if a.tag == Tag.function { pending.push(Pair { a.b, b.b , ..}); } pending.push(Pair { a.a, b.a , ..});
            },
            array, list, cursor, resolver => { pending.push(Pair { a.a, b.a , ..}); },
            state_provider => { pending.append([Pair { a.a, b.a , ..}, Pair { a.b, b.b , ..}, Pair { a.c, b.c , ..}]); },
            scoped => { if a.b != b.b { return false, blot_error::Error.none; } if a.b == 0 { pending.push(Pair { a.c, b.c , ..}); } else if a.c != b.c { return false, blot_error::Error.none; } pending.push(Pair { a.a, b.a , ..}); },
            instance_version => { if a.a != b.a || a.b != b.b || a.c != b.c { return false, blot_error::Error.none; } },
            type_constructor => { if a.a != b.a || a.b != b.b { return false, blot_error::Error.none; } },
            product => { if a.b != b.b { return false, blot_error::Error.none; } for av, i in list(self_, List { a.a, a.b , ..}) { pending.push(Pair { av, list(self_, List { b.a, b.b , ..})[i] , ..}); } },
            nominal, projection, instance_selection => {
                if a.a != b.a || a.b != b.b { return false, blot_error::Error.none; } if a.tag == Tag.projection && projectionMember(self_, a) != projectionMember(self_, b) { return false, blot_error::Error.none; }
                let aa = nominalArguments(self_, a); let ba = nominalArguments(self_, b); if aa.len != ba.len { return false, blot_error::Error.none; }
                for av, i in aa { pending.push(Pair { av, ba[i] , ..}); }
            },
            record => {
                if a.b != b.b { return false, blot_error::Error.none; } var fields = dictionary<u32, Id> {};
                if b.b > 16 { for j in b.b { let other = recordField(self_, b, j); if !::contains(fields,other.name) { ::insert(fields,other.name, other.ty); } } }
                for i in a.b {
                    let field = recordField(self_, a, i); var found = false; var ty: Id = 0;
                    if b.b > 16 { let saved = ::get(fields,field.name); if saved { found = true; ty = saved; } }
                    else { for j in b.b { let other = recordField(self_, b, j); if field.name == other.name { ty = other.ty; found = true; break; } } }
                    if !found { return false, blot_error::Error.none; } pending.push(Pair { field.ty, ty , ..});
                }
            },
            _ => {},
        }
    }
    return true, blot_error::Error.none;
}
struct SilentReporter {}
fn report(self_: SilentReporter, store: const Store&, left: Id, right: Id) -> Error { return blot_error::Error.none; }
fn mismatch(self_: const Store&, reporter, left: Id, right: Id) -> Error { let error = reporter.report(self_, left, right); if error != blot_error::Error.none { return blot_error::Error.out_of_memory; } return blot_error::Error.type_mismatch; }
recursive fn unify(self_: Store&, left: Id, right: Id) -> Error { return unifyMode(self_, left, right, SilentReporter {..}, false); }
fn unifyWithReporter<R>(self_: Store&, left: Id, right: Id, reporter:R) -> Error { return unifyMode(self_, left, right, reporter, false); }
fn unifyPattern(self_: Store&, left: Id, right: Id) -> Error { return unifyMode(self_, left, right, SilentReporter {..}, true); }
fn resolveUnification(self_: Store&, root: Id) -> Id, Error {
    let entries = self_.normalization.resolve_depth_entries; let nodes = self_.nodes.len; increment(self_.normalization.unify_resolve_calls);
    let result, error = resolve(self_, root, 0); saturatedAdd(self_.normalization.unify_resolve_entries, self_.normalization.resolve_depth_entries - entries); saturatedAdd(self_.normalization.unify_resolve_nodes, (self_.nodes.len - nodes) as u64); return result, error;
}
recursive fn unifyMode<R>(self_: Store&, left: Id, right: Id, reporter:R, associated: bool) -> Error {
    let point = mark(self_); let error = unifyInner(self_, left, right, reporter, associated); if error != blot_error::Error.none { rollback(self_, point); } return error;
}
type UnificationSeen=blot_support_pooled_map::Map<Pair,bool>;
type UnificationPending=blot_support_pooled_buffer::Buffer<Pair>;
reusable[] var unification_seen:dictionary_slot<Pair,bool>[>..];
reusable[] var unification_pairs:Pair[>..];
fn pushUnification(pending:UnificationPending&,value:Pair)->Error {return blot_support_pooled_buffer::push(pending,value,unification_pairs);}
fn appendUnification(pending:UnificationPending&,values:const Pair[:])->Error {return blot_support_pooled_buffer::append(pending,values,unification_pairs);}
fn popUnification(pending:UnificationPending&)->Pair {let length=pending.items.len;assert(length!=0);let result=pending.items[length-1];blot_support_pooled_buffer::resize(pending,length-1);return result;}
recursive fn unifyInner<R>(self_:Store&,left:Id,right:Id,reporter:R,associated:bool)->Error {
 var seen=UnificationSeen{..};var pending=UnificationPending{..};let error=unifyWalk(self_,left,right,reporter,associated,seen,pending);
 blot_support_pooled_buffer::deinit(pending,unification_pairs);blot_support_pooled_map::deinit(seen,unification_seen);return error;
}
recursive fn unifyWalk<R>(self_: Store&, left: Id, right: Id, reporter:R, associated: bool,seen:UnificationSeen&,pending:UnificationPending&) -> Error {
    let initial=pushUnification(pending,Pair{left,right,..});if initial!=blot_error::Error.none {return initial;}
    let bounded = associated || self_.has_projections; var rank_active = false; var rank_remaining: i64 = 4096;
    while pending.items.len > 0 {
        let pair = popUnification(pending);
        if rank_active { if rank_remaining == 0 { return blot_error::Error.type_limit; } rank_remaining -= 1; }
        if bounded { let error = chargeProjection(self_); if error != blot_error::Error.none { return error; } }
        if pair.effect_row {
            if bounded { for label in rowLabels(self_, pair.a) { let error = chargeProjection(self_); if error != blot_error::Error.none { return error; } } for label in rowLabels(self_, pair.b) { let error = chargeProjection(self_); if error != blot_error::Error.none { return error; } } }
            let error = unifyEffects(self_, pair.a, pair.b); if error != blot_error::Error.none { return error; } continue;
        }
        increment(self_.normalization.unify_pairs); if self_.has_projections { increment(self_.normalization.unify_projected_pairs); }
        let a, ae = resolveUnification(self_, pair.a); if ae != blot_error::Error.none { return ae; }
        let b, be = resolveUnification(self_, pair.b); if be != blot_error::Error.none { return be; }
        let an = node(self_, a); let bn = node(self_, b);
        if rowIdentity(self_, a) || rowIdentity(self_, b) {
            if !rowIdentity(self_, a) || !rowIdentity(self_, b) { return mismatch(self_, reporter, a, b); }
            let ar, are = rowType(self_, a); if are != blot_error::Error.none { return are; } let br, bre = rowType(self_, b); if bre != blot_error::Error.none { return bre; }
            let error = unifyEffects(self_, ar, br); if error != blot_error::Error.none { return error; } continue;
        }
        if an.tag == Tag.variable && self_.variables.items[an.a].region && !regionIdentity(self_, b) { return mismatch(self_, reporter, a, b); }
        if bn.tag == Tag.variable && self_.variables.items[bn.a].region && !regionIdentity(self_, a) { return mismatch(self_, reporter, a, b); }
        if a == b || a == never || b == never { continue; }
        if self_.has_rank_types && (isRank(an.tag) || isRank(bn.tag)) { rank_active = true; }
        if bounded || rank_active { let key = Pair { a, b , ..}; if blot_support_pooled_map::contains(seen,key) { continue; } blot_support_pooled_map::insert(seen,key,true,unification_seen); }
        if an.tag == Tag.variable && bn.tag == Tag.variable && an.a == bn.a { continue; }
        if an.tag == Tag.variable {
            if bn.tag == Tag.forall { return mismatch(self_, reporter, a, b); }
            if !self_.variables.items[an.a].region { let free, error = freeBound(self_, b); if error != blot_error::Error.none { return error; } if free { return mismatch(self_, reporter, a, b); } }
            let infinite, error = occurs(self_, an.a, b); if error != blot_error::Error.none { return error; } if infinite { return blot_error::Error.infinite_type; }
            let error = appendVersion(self_, a, b); if error != blot_error::Error.none { return error; } continue;
        }
        if bn.tag == Tag.variable {
            if an.tag == Tag.forall { return mismatch(self_, reporter, a, b); }
            if !self_.variables.items[bn.a].region { let free, error = freeBound(self_, a); if error != blot_error::Error.none { return error; } if free { return mismatch(self_, reporter, a, b); } }
            let infinite, error = occurs(self_, bn.a, a); if error != blot_error::Error.none { return error; } if infinite { return blot_error::Error.infinite_type; }
            let error = appendVersion(self_, b, a); if error != blot_error::Error.none { return error; } continue;
        }
        if an.tag != bn.tag { return mismatch(self_, reporter, a, b); }
        match an.tag {
            usage => { if an.b != bn.b || (an.c == 0) != (bn.c == 0) { return mismatch(self_, reporter, a, b); } let pending_failure_0=pushUnification(pending,Pair { an.a, bn.a , ..});if pending_failure_0!=blot_error::Error.none {return pending_failure_0;} if an.c != 0 { let pending_failure_1=pushUnification(pending,Pair { an.c, bn.c , ..});if pending_failure_1!=blot_error::Error.none {return pending_failure_1;} } },
            bound => { return mismatch(self_, reporter, a, b); },
            rigid, instance_version => { if an.a != bn.a || an.b != bn.b || an.c != bn.c { return mismatch(self_, reporter, a, b); } },
            forall, existential => {
                if an.c != bn.c { return mismatch(self_, reporter, a, b); }
                let old=snapshotResolutionIds(list(self_,List{bn.b,bn.c,..}));let fresh_ids=snapshotResolutionIds(list(self_,List{an.b,an.c,..}));
                let error=unifyQuantifiedBinders(self_,a,b,an,bn,reporter,pending,old,fresh_ids);resolution_arguments.free_slice(fresh_ids);resolution_arguments.free_slice(old);if error!=blot_error::Error.none {return error;}
            },
            function => { let pending_failure_2=appendUnification(pending,[Pair { an.c, bn.c, true , ..}, Pair { an.b, bn.b , ..}, Pair { an.a, bn.a , ..}]);if pending_failure_2!=blot_error::Error.none {return pending_failure_2;} },
            product => { if an.b != bn.b { return mismatch(self_, reporter, a, b); } var i = an.b; while i != 0 { i -= 1; let pending_failure_3=pushUnification(pending,Pair { self_.extra.items[an.a + i], self_.extra.items[bn.a + i] , ..});if pending_failure_3!=blot_error::Error.none {return pending_failure_3;} } },
            array, list, cursor, resolver => { let pending_failure_4=pushUnification(pending,Pair { an.a, bn.a , ..});if pending_failure_4!=blot_error::Error.none {return pending_failure_4;} },
            provider => { let pending_failure_5=appendUnification(pending,[Pair { an.c, bn.c, true , ..}, Pair { an.a, bn.a , ..}]);if pending_failure_5!=blot_error::Error.none {return pending_failure_5;} },
            state_provider => { let pending_failure_6=appendUnification(pending,[Pair { an.c, bn.c , ..}, Pair { an.b, bn.b , ..}, Pair { an.a, bn.a , ..}]);if pending_failure_6!=blot_error::Error.none {return pending_failure_6;} },
            scoped => {
                if an.b == 0 && node(self_, an.c).tag == Tag.variable && !regionIdentity(self_, an.c) { if bn.b != 0 || an.c != bn.c { let pending_failure_7=pushUnification(pending,Pair { an.c, b , ..});if pending_failure_7!=blot_error::Error.none {return pending_failure_7;} } }
                else if bn.b == 0 && node(self_, bn.c).tag == Tag.variable && !regionIdentity(self_, bn.c) { let pending_failure_8=pushUnification(pending,Pair { bn.c, a , ..});if pending_failure_8!=blot_error::Error.none {return pending_failure_8;} }
                else if an.b == 0 && bn.b == 0 { let pending_failure_9=pushUnification(pending,Pair { an.c, bn.c , ..});if pending_failure_9!=blot_error::Error.none {return pending_failure_9;} }
                else if an.b != bn.b || an.c != bn.c { return mismatch(self_, reporter, a, b); }
                let pending_failure_10=pushUnification(pending,Pair { an.a, bn.a , ..});if pending_failure_10!=blot_error::Error.none {return pending_failure_10;}
            },
            type_constructor => { if an.a != bn.a || an.b != bn.b { return mismatch(self_, reporter, a, b); } },
            projection => {
                if an.a != bn.a || an.b != bn.b || projectionMember(self_, an) != projectionMember(self_, bn) { return mismatch(self_, reporter, a, b); }
                let aa=snapshotResolutionIds(nominalArguments(self_,an));let bb=snapshotResolutionIds(nominalArguments(self_,bn));
                let error=unifyProjectionArguments(self_,a,b,reporter,aa,bb);resolution_arguments.free_slice(bb);resolution_arguments.free_slice(aa);if error!=blot_error::Error.none {return error;}
            },
            nominal, instance_selection => {
                if an.a != bn.a || an.b != bn.b { return mismatch(self_, reporter, a, b); } let aa = nominalArguments(self_, an); let bb = nominalArguments(self_, bn);
                if aa.len != bb.len { return mismatch(self_, reporter, a, b); } var i = aa.len; while i != 0 { i -= 1; let pending_failure_11=pushUnification(pending,Pair { aa[i], bb[i] , ..});if pending_failure_11!=blot_error::Error.none {return pending_failure_11;} }
            },
            record => {
                if an.b != bn.b { return mismatch(self_, reporter, a, b); }
                for i in an.b { let af = recordField(self_, an, i); var found = false; var ty: Id = 0; for j in bn.b { let bf = recordField(self_, bn, j); if af.name == bf.name { ty = bf.ty; found = true; break; } } if !found { return mismatch(self_, reporter, a, b); } let pending_failure_12=pushUnification(pending,Pair { af.ty, ty , ..});if pending_failure_12!=blot_error::Error.none {return pending_failure_12;} }
            },
            _ => {},
        }
    }
    return blot_error::Error.none;
}
recursive fn unifyQuantifiedBinders<R>(self_:Store&,a:Id,b:Id,an:Node,bn:Node,reporter:R,pending:UnificationPending&,old:const Id[:],fresh_ids:const Id[:])->Error {
                for left_, i in old { if node(self_, left_).b != node(self_, fresh_ids[i]).b { return mismatch(self_, reporter, a, b); } }
 let left_goals=snapshotResolutionGoals(quantifierGoals(self_,a));let right_goals=snapshotResolutionGoals(quantifierGoals(self_,b));
 let error=unifyQuantifiedGoals(self_,a,b,an,bn,reporter,pending,old,fresh_ids,left_goals,right_goals);resolution_goals.free_slice(right_goals);resolution_goals.free_slice(left_goals);return error;
}
recursive fn unifyQuantifiedGoals<R>(self_:Store&,a:Id,b:Id,an:Node,bn:Node,reporter:R,pending:UnificationPending&,old:const Id[:],fresh_ids:const Id[:],left_goals:const Obligation[:],right_goals:const Obligation[:])->Error {
                if left_goals.len != right_goals.len { return mismatch(self_, reporter, a, b); }
                for left_goal, i in left_goals {
                    let right_goal = right_goals[i]; if !blot_check_quantifier_goals::sameHead(left_goal, right_goal) { return mismatch(self_, reporter, a, b); }
                    let replaced, error = substituteGoal(self_, right_goal, old, fresh_ids); if error != blot_error::Error.none { return error; }
                    let first = [left_goal.ty, left_goal.other, left_goal.result, left_goal.signature]; let second = [replaced.ty, replaced.other, replaced.result, replaced.signature];
                    for left_child, j in first { let right_child = second[j]; if (left_child == 0) != (right_child == 0) { return mismatch(self_, reporter, a, b); } if left_child != 0 { let pending_failure_0=pushUnification(pending,Pair { left_child, right_child , ..});if pending_failure_0!=blot_error::Error.none {return pending_failure_0;} } }
                }
                let body, error = substitute(self_, bn.a, old, fresh_ids); if error != blot_error::Error.none { return error; } let pending_failure_1=pushUnification(pending,Pair { an.a, body , ..});if pending_failure_1!=blot_error::Error.none {return pending_failure_1;}
 return blot_error::Error.none;
}
recursive fn unifyProjectionArguments<R>(self_:Store&,a:Id,b:Id,reporter:R,aa:const Id[:],bb:const Id[:])->Error {
                if aa.len != bb.len { return mismatch(self_, reporter, a, b); }
                for left_arg, i in aa {
                    let al, ae = resolve(self_, left_arg, 0); if ae != blot_error::Error.none { return ae; } let bl, be = resolve(self_, bb[i], 0); if be != blot_error::Error.none { return be; }
                    if al == bl { continue; } let same, error = equalSymbolic(self_, al, bl); if error != blot_error::Error.none { return error; } if !same { return mismatch(self_, reporter, a, b); }
                }
 return blot_error::Error.none;
}
fn isRank(tag: Tag) -> bool { match tag { forall, existential, bound, rigid => { return true; }, _ => { return false; }, } }
fn usageCode(kind: UsageKind) -> u32 { return kind; }
fn usageFromCode(code: u32) -> UsageKind, Error { if code > 7 { return 0, blot_error::Error.type_mismatch; } return code, blot_error::Error.none; }
fn appendChildren(self_: const Store&, pending: Id[>..<]&, id: Id, scoped_identity: bool) {
    let value = node(self_, id);
    match value.tag {
        function => { pending.append([value.a, value.b]); }, product => { pending.append(list(self_, List { value.a, value.b , ..})); },
        usage => { pending.push(value.a); if value.c != 0 { pending.push(value.c); } },
        scoped => { pending.push(value.a); if scoped_identity && value.b == 0 { pending.push(value.c); } },
        forall, existential => { pending.push(value.a); for goal in quantifierGoals(self_, id) { for child in [goal.ty, goal.other, goal.result, goal.signature] { if child != 0 { pending.push(child); } } } },
        array, list, cursor, resolver, provider => { pending.push(value.a); }, state_provider => { pending.append([value.a, value.b, value.c]); },
        record => { for i in value.b { pending.push(recordField(self_, value, i).ty); } },
        nominal, projection, instance_selection => { pending.append(nominalArguments(self_, value)); }, _ => {},
    }
}
fn freeVariables(self_: Store&, root: Id) -> Id[>..], Error { return freeVariablesMode(self_, root, true); }
fn freeVariablesMode(self_: Store&, root: Id, bounded: bool) -> Id[>..], Error {
    var values: Id[>..] = []; var pending: Id[>..<] = [];
    let resolved, error = resolve(self_, root, 0); if error != blot_error::Error.none { return [], error; }
    if bounded && (resolved <= never || closedHeight(self_, resolved) != 0) { return [], blot_error::Error.none; }
    if bounded && node(self_, resolved).tag == Tag.variable { values.push(resolved); return values, blot_error::Error.none; }
    self_.normalization.free_type_queries += 1; pending.push(resolved); var seen = dictionary<Id, bool> {};
    while pending.len > 0 {
        let id = pending.pop(); self_.normalization.free_type_visits += 1;
        if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return [], error; } }
        if bounded && closedHeight(self_, id) != 0 { continue; } if ::contains(seen,id) { continue; } ::insert(seen,id, true);
        let value = node(self_, id);
        if value.tag == Tag.function || value.tag == Tag.provider { for label in rowLabels(self_, value.c) { pending.append(operationArguments(self_, label)); let instance = operation(self_, label).instance; if instance.unit == 0 && instance.decl != 0 { pending.push(instance.decl); } } }
        if value.tag == Tag.variable { values.push(id); } else { appendChildren(self_, pending, id, true); }
    }
    return values, blot_error::Error.none;
}
struct ProjectionWork { root: Id, row: bool = false }
fn hash(value: ProjectionWork) -> u64 { var row: u64 = 0; if value.row { row = 1; } return ::hash_combine(::hash(value.root), ::hash(row)); }
fn containsProjection(self_: Store&, root: Id) -> bool, Error {
    if !self_.has_projections || root == 0 { return false, blot_error::Error.none; }
    var pending: ProjectionWork[>..<] = []; var seen = dictionary<ProjectionWork, bool> {}; pending.push(ProjectionWork { root , ..}); var remaining: i64 = 1000000;
    while pending.len > 0 {
        let item = pending.pop(); if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return false, error; } }
        if remaining == 0 { return false, blot_error::Error.type_limit; } remaining -= 1;
        if ::contains(seen,item) { continue; } ::insert(seen,item, true);
        if item.row { for label in rowLabels(self_, item.root) { for argument in operationArguments(self_, label) { pending.push(ProjectionWork { argument , ..}); } } continue; }
        let id = head(self_, item.root, 0); if closedHeight(self_, id) != 0 { continue; } let value = node(self_, id);
        if value.tag == Tag.projection { return true, blot_error::Error.none; }
        if value.tag == Tag.function { pending.append([ProjectionWork { value.a , ..}, ProjectionWork { value.b , ..}, ProjectionWork { value.c, true , ..}]); continue; }
        if value.tag == Tag.provider { pending.append([ProjectionWork { value.a , ..}, ProjectionWork { value.c, true , ..}]); continue; }
        var children: Id[>..<] = []; appendChildren(self_, children, id, false); for child in children { pending.push(ProjectionWork { child , ..}); }
    }
    return false, blot_error::Error.none;
}
fn has(values: const u32[:], value: u32) -> bool { for item in values { if item == value { return true; } } return false; }
fn unionInto(self_: Store&, values: u32[>..]&, added: const u32[:]) -> Error { for item in added { if !has(values, item) { values.push(item); } } return blot_error::Error.none; }
struct RowWork { id: Id, at: Cursor, depth: u32 = 0 }
fn freeRowVariables(self_: Store&, root: Id) -> u32[>..], Error { return freeRowVariablesMode(self_, root, true); }
fn freeRowVariablesMode(self_: Store&, root: Id, bounded: bool) -> u32[>..], Error {
    if bounded && (root <= never || closedHeight(self_, root) != 0) { return [], blot_error::Error.none; }
    if bounded { let selected = head(self_, root, 0); if selected <= never || node(self_, selected).tag == Tag.variable || node(self_, selected).tag == Tag.type_constructor { return [], blot_error::Error.none; } }
    self_.normalization.free_row_queries += 1; var result: u32[>..] = []; var pending: RowWork[>..<] = []; var seen = dictionary<u64, bool> {}; pending.push(RowWork { root, 0 , ..});
    while pending.len > 0 {
        let work = pending.pop(); self_.normalization.free_row_visits += 1;
        if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return [], error; } }
        if work.depth >= 1024 { return [], blot_error::Error.type_limit; } var id = work.id; var at = work.at;
        while node(self_, id).tag == Tag.variable { let variable = node(self_, id); at = max(at, variable.b); let write = replacement(self_, variable.a, at); if !write.present { break; } id = write.value.replacement; at = write.value.position + 1; }
        if bounded {
            if id <= never || node(self_, id).tag == Tag.variable || node(self_, id).tag == Tag.type_constructor { continue; }
            let height = closedHeight(self_, id); if height != 0 { if work.depth + height > 1024 { return [], blot_error::Error.type_limit; } continue; }
        }
        let key = ((id as u64) << 32) | at; if ::contains(seen,key) { continue; } ::insert(seen,key, true); let value = node(self_, id);
        if value.tag == Tag.function || value.tag == Tag.provider {
            var row_ = self_.effects.node(value.c); var row_at = max(at, row_.cursor);
            loop {
                for label in self_.effects.list(row_.labels) { for argument in operationArguments(self_, label) { pending.push(RowWork { argument, at, work.depth + 1 , ..}); } }
                var variable = none; match row_.tail { variable v => { variable = v.value; }, _ => { break; }, }
                row_at = max(row_at, row_.cursor); let write, found = self_.effects.replacementAt(variable, row_at); if !found { break; }
                row_ = self_.effects.node(write.replacement); row_at = write.position + 1;
            }
            match row_.tail { variable v => { if !has(result, v.value) { result.push(v.value); } }, _ => {}, }
        }
        var children: Id[>..<] = []; appendChildren(self_, children, id, false);
        for child in children { pending.push(RowWork { child, at, work.depth + 1 , ..}); }
    }
    return result, blot_error::Error.none;
}
struct KindStamp { mutation_epoch: u64, rank_types: bool, proof_kinds: bool }
struct Substitution {
    old: const Id[:], fresh_ids: const Id[:], old_rows: const u32[:], fresh_rows: const blot_check_effects::Id[:],
    leaves: dictionary<Id, u32>&, row_leaves: dictionary<u32, u32>&,
    checked: blot_support::Option<KindStamp>   = blot_support::Option<KindStamp> { false, default<KindStamp>() , ..},
}
fn deinit(self_:Substitution&) {::clear(self_.leaves);::clear(self_.row_leaves);self_.checked.present=false;}
fn substitutionLeaf(leaves:const dictionary<u32,u32>&,key:u32)->u32? {return ::get(leaves,key);}
fn substitutionLeaf(leaves:const Map_associated_equations&,key:u32)->u32? {return get(leaves,key);}
fn typeIndex<L>(old:const Id[:],leaves:const L&,root:Id) -> i64, bool {
    if leaves.count != 0 { let index = substitutionLeaf(leaves,root); if index { return index as i64, true; } return 0, false; }
    for before, index in old { if before == root { return index, true; } } return 0, false;
}
fn rowIndex<R>(old_rows:const u32[:],row_leaves:const R&,variable:u32,from:i64) -> i64, bool {
    if from == 0 && row_leaves.count != 0 { let index = substitutionLeaf(row_leaves,variable); if index { return index as i64, true; } return 0, false; }
    for before, offset in old_rows[from..] { if before == variable { return from + offset, true; } } return 0, false;
}
fn prepareSubstitution(self_: Store&, old: const Id[:], fresh_ids: const Id[:], old_rows: const u32[:], fresh_rows: const blot_check_effects::Id[:],
                       leaves: dictionary<Id, u32>&, row_leaves: dictionary<u32, u32>&) -> Substitution, Error {
    assert(old.len == fresh_ids.len && old_rows.len == fresh_rows.len);
    var result = Substitution { old, fresh_ids, old_rows, fresh_rows, leaves, row_leaves , ..};
    if old.len > 16 { for before, index in old { if !::contains(leaves,before) { ::insert(leaves,before, index as u32); } } }
    if old_rows.len > 16 { for before, index in old_rows { if !::contains(row_leaves,before) { ::insert(row_leaves,before, index as u32); } } }
    return result, blot_error::Error.none;
}
recursive fn substitute(self_:Store&,root:Id,old:const Id[:],fresh_ids:const Id[:])->Id,Error {return substituteWithRows(self_,root,old,fresh_ids,[],[]);}
recursive fn substituteWithRows(self_:Store&,root:Id,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:])->Id,Error {
 assert(old.len==fresh_ids.len && old_rows.len==fresh_rows.len);
 var leaves=Map_associated_equations{..};var row_leaves=Map_associated_equations{..};var checked=blot_support::none<KindStamp>();
 return substituteInputs(self_,root,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,checked);
}
recursive fn substitutePrepared(self_:Store&,substitution:Substitution&,root:Id)->Id,Error {
 return substituteInputs(self_,root,substitution.old,substitution.fresh_ids,substitution.old_rows,substitution.fresh_rows,substitution.leaves,substitution.row_leaves,substitution.checked);
}
recursive fn substituteInputs<L,R>(self_:Store&,root:Id,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,checked:blot_support::Option<KindStamp>&)->Id,Error {
 let attribution_start=self_.nodes.len;let result,error=substituteInputsInner(self_,root,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,checked);
 saturatedAdd(self_.normalization.substitute_nodes_added,(self_.nodes.len-attribution_start) as u64);return result,error;
}
recursive fn substituteInputsInner<L,R>(self_:Store&,root:Id,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,checked:blot_support::Option<KindStamp>&)->Id,Error {
 let error=checkReplacementKinds(self_,old,fresh_ids,checked);if error!=blot_error::Error.none {return 0,error;}
 if old.len==0 && old_rows.len==0 {return root,blot_error::Error.none;}
 var copied=Map_associated_equations{..};let result,error=substituteDepth(self_,root,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,0);copied.deinit();return result,error;
}
fn checkReplacementKinds(self_: Store&, old:const Id[:],fresh_ids:const Id[:],checked:blot_support::Option<KindStamp>&) -> Error {
    let stamp = KindStamp { self_.mutation_epoch, self_.has_rank_types, self_.has_proof_kinds , ..};
    if checked.present && stamp.mutation_epoch != 0xffffffffffffffff && checked.value == stamp { return blot_error::Error.none; }
    for original, i in old {
        let replacement_id = fresh_ids[i]; let leaf = node(self_, original);
        if (leaf.tag == Tag.bound && leaf.b == 1) || (leaf.tag == Tag.rigid && leaf.c == 1) { if !rowIdentity(self_, replacement_id) { return blot_error::Error.type_mismatch; } }
        else if (leaf.tag == Tag.bound && leaf.b == 2) || (leaf.tag == Tag.rigid && leaf.c == 2) { if !regionIdentity(self_, replacement_id) { return blot_error::Error.type_mismatch; } }
        else { let error = dataKind(self_, replacement_id); if error != blot_error::Error.none { return error; } }
    }
    checked = blot_support::Option<KindStamp> { true, stamp , ..}; return blot_error::Error.none;
}
recursive fn substitutedRow<L,R>(self_:Store&,root:blot_check_effects::Id,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64)->blot_check_effects::Id,Error {
 if self_.has_projections {let error=chargeProjection(self_);if error!=blot_error::Error.none {return 0,error;}}
 let row_=row(self_,root);let labels=substitution_ids.alloc_slice(row_.labels.len);
 let result,error=substitutedRowLabels(self_,root,row_,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,labels);substitution_ids.free_slice(labels);return result,error;
}
recursive fn substitutedRowLabels<L,R>(self_:Store&,root:blot_check_effects::Id,row_:blot_check_effects::Row,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,labels:blot_check_effects::Label[:])->blot_check_effects::Id,Error {
 var changed=false;
    for index in row_.labels.len {
        let label = self_.effects.list(row_.labels)[index]; if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } }
        let operation_=operation(self_,label);let arguments=substitution_ids.alloc_slice(operation_.arguments.len);
        let next,error=substituteOperationArguments(self_,label,operation_,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,arguments);substitution_ids.free_slice(arguments);if error!=blot_error::Error.none {return 0,error;}
        changed=changed || next!=label;labels[index]=next;
    }
    var result = root;
    match row_.tail { formal v => {
        let index, found = typeIndex(old,leaves, v.value);
        if found { let replacement_row, re = rowType(self_, fresh_ids[index]); if re != blot_error::Error.none { return 0, re; }
            let next, error = self_.effects.substituteFormal(root, old[index], replacement_row); if error != blot_error::Error.none { return 0, effectError(error); } result = next; }
    }, _ => {}, }
    if changed {
        let next,error=rebuildSubstitutedRow(self_,root,row_,result,labels);if error!=blot_error::Error.none {return 0,error;}result=next;
    }
    var from: i64 = 0;
    while from < old_rows.len {
        var variable = none; match self_.effects.node(result).tail { variable v => { variable = v.value; }, _ => { break; }, }
        let index, found = rowIndex(old_rows,row_leaves, variable, from); if !found { break; }
        let next, error = self_.effects.substitute(result, old_rows[index], fresh_rows[index]); if error != blot_error::Error.none { return 0, effectError(error); } result = next; from = index + 1;
    }
    return result, blot_error::Error.none;
}
recursive fn substituteOperationArguments<L,R>(self_:Store&,label:blot_check_effects::Label,operation_:Operation,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,arguments:Id[:])->blot_check_effects::Label,Error {
 var argument_changed=false;
        for offset in operation_.arguments.len {
            let argument = list(self_, operation_.arguments)[offset]; let next, error = substituteDepth(self_, argument, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; }
            argument_changed = argument_changed || next != argument; arguments[offset]=next;
        }
        var instance = operation_.instance;
        if instance.unit == 0 && instance.decl != 0 { let next, error = substituteDepth(self_, instance.decl, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } instance.decl = next; }
        var next = label;
        if argument_changed || instance != operation_.instance { let result, error = internResolvedOperation(self_, operation_.identity, instance, arguments, true); if error != blot_error::Error.none { return 0, error; } next = result; }
 return next,blot_error::Error.none;
}
fn rebuildSubstitutedRow(self_:Store&,root:blot_check_effects::Id,original:blot_check_effects::Row,result:blot_check_effects::Id,labels:const blot_check_effects::Label[:])->blot_check_effects::Id,Error {
 let replaced=row(self_,result);let cursor=max(original.cursor,replaced.cursor);
 if result==root {let next,error=self_.effects.rowAt(labels,replaced.tail,cursor);return next,effectError(error);}
 let extra=self_.effects.list(replaced.labels)[original.labels.len..];
 if extra.len==0 {let next,error=self_.effects.rowAt(labels,replaced.tail,cursor);return next,effectError(error);}
 let combined=substitution_ids.alloc_slice(labels.len+extra.len);for label,index in labels {combined[index]=label;}for label,index in extra {combined[labels.len+index]=label;}
 let next,error=self_.effects.rowAt(combined,replaced.tail,cursor);substitution_ids.free_slice(combined);return next,effectError(error);
}
recursive fn substituteDepth<L,R>(self_: Store&, root: Id, old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&, copied:Map_associated_equations&, depth: i64) -> Id, Error {
    increment(self_.normalization.substitute_depth_entries); if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } }
    if depth >= 1024 { return 0, blot_error::Error.type_limit; }
    let index, found = typeIndex(old,leaves, root); if found { return fresh_ids[index], blot_error::Error.none; }
    if root <= never || node(self_, root).tag == Tag.variable { return root, blot_error::Error.none; }
    if depth != 0 { let known = get(copied,root); if known { increment(self_.normalization.substitute_memo_hits); return known, blot_error::Error.none; } }
    let result, error = substituteNode(self_, root, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth); if error != blot_error::Error.none { return 0, error; }
    if result == root { increment(self_.normalization.substitute_unchanged); } if depth != 0 { insert(copied,root,result);if copied.failure!=blot_error::Error.none {return 0,copied.failure;} }
    return result, blot_error::Error.none;
}
recursive fn substituteNode<L,R>(self_: Store&, root: Id, old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&, copied:Map_associated_equations&, depth: i64) -> Id, Error {
    if depth >= 1024 { return 0, blot_error::Error.type_limit; } let value = node(self_, root);
    match value.tag {
        forall, existential => {
            let source_binders=list(self_,List{value.b,value.c,..});let binders=resolution_binders.alloc_slice(source_binders.len);for binder,index in source_binders {binders[index]=binder;}
            let result,error=substituteQuantified(self_,root,value,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,binders);resolution_binders.free_slice(binders);return result,error;
        },
        usage => {
            let payload, pe = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if pe != blot_error::Error.none { return 0, pe; }
            var region: Id = 0; if value.c != 0 { let next, error = substituteDepth(self_, value.c, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } region = next; }
            return usage(self_, payload, value.b, region);
        },
        scoped => {
            let descriptor, de = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if de != blot_error::Error.none { return 0, de; }
            var instance = NominalIdentity { value.b, value.c , ..}; if instance.unit == 0 { let next, error = substituteDepth(self_, instance.decl, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } instance.decl = next; }
            return scoped(self_, descriptor, instance);
        },
        function => {
            let parameter, pe = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if pe != blot_error::Error.none { return 0, pe; }
            let result, re = substituteDepth(self_, value.b, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if re != blot_error::Error.none { return 0, re; }
            let row_, ee = substitutedRow(self_, value.c, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if ee != blot_error::Error.none { return 0, ee; }
            return functionWithEffects(self_, parameter, result, row_);
        },
        product => {
            let fields=substitution_ids.alloc_slice(value.b);let result,error=substituteProduct(self_,value,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,fields);substitution_ids.free_slice(fields);return result,error;
        },
        array, list, cursor, resolver => {
            let next, error = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if value.tag == Tag.resolver { return resolver(self_, next); } return sequence(self_, value.tag, next);
        },
        provider => {
            let child, ce = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if ce != blot_error::Error.none { return 0, ce; }
            let row_, re = substitutedRow(self_, value.c, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if re != blot_error::Error.none { return 0, re; }
            return provider(self_, child, row_);
        },
        state_provider => {
            let read, re = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if re != blot_error::Error.none { return 0, re; }
            let write, we = substituteDepth(self_, value.b, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if we != blot_error::Error.none { return 0, we; }
            let state, se = substituteDepth(self_, value.c, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if se != blot_error::Error.none { return 0, se; }
            return stateProvider(self_, read, write, state);
        },
        record => {
            let fields=substitution_fields.alloc_slice(value.b);let result,error=substituteRecord(self_,value,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,fields);substitution_fields.free_slice(fields);return result,error;
        },
        nominal, projection, instance_selection => {
            let original=nominalArguments(self_,value);let prior=substitution_ids.alloc_slice(original.len);for item,index in original {prior[index]=item;}let args=substitution_ids.alloc_slice(prior.len);
            let result,error=substituteArguments(self_,value,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,prior,args);substitution_ids.free_slice(args);substitution_ids.free_slice(prior);return result,error;
        },
        _ => { return root, blot_error::Error.none; },
    }
}
recursive fn substituteQuantified<L,R>(self_:Store&,root:Id,value:Node,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,binders:const Id[:])->Id,Error {
            let body, be = substituteDepth(self_, value.a, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if be != blot_error::Error.none { return 0, be; }
            let source_goals=quantifierGoals(self_,root);let goals=resolution_goals.alloc_slice(source_goals.len);for goal,index in source_goals {goals[index]=goal;}
 let result,error=substituteQuantifiedGoals(self_,root,value,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth,binders,body,goals);resolution_goals.free_slice(goals);return result,error;
}
recursive fn substituteQuantifiedGoals<L,R>(self_:Store&,root:Id,value:Node,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,binders:const Id[:],body:Id,goals:Obligation[:])->Id,Error {
 var changed = body != value.a;
            for &goal in goals {
                if goal.ty != 0 { let next, error = substituteDepth(self_, goal.ty, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || next != goal.ty; goal.ty = next; }
                if goal.other != 0 { let next, error = substituteDepth(self_, goal.other, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || next != goal.other; goal.other = next; }
                if goal.result != 0 { let next, error = substituteDepth(self_, goal.result, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || next != goal.result; goal.result = next; }
                if goal.signature != 0 { let next, error = substituteDepth(self_, goal.signature, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || next != goal.signature; goal.signature = next; }
            }
            if !changed { return root, blot_error::Error.none; } return reownQuantified(self_, value.tag, body, binders, goals);

}
reusable[] var substitution_ids:Id[>..];
reusable[] var substitution_fields:Field[>..];
recursive fn substituteProduct<L,R>(self_:Store&,value:Node,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,fields:Id[:])->Id,Error {for i in value.b {let next,error=substituteDepth(self_,self_.extra.items[value.a+i],old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth+1);if error!=blot_error::Error.none {return 0,error;}fields[i]=next;}return product(self_,fields);}
recursive fn substituteRecord<L,R>(self_:Store&,value:Node,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,fields:Field[:])->Id,Error {for i in value.b {let field=recordField(self_,value,i);let next,error=substituteDepth(self_,field.ty,old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied,depth+1);if error!=blot_error::Error.none {return 0,error;}fields[i]=Field{field.name,next,..};}return record(self_,fields);}
recursive fn substituteArguments<L,R>(self_:Store&,value:Node,old:const Id[:],fresh_ids:const Id[:],old_rows:const u32[:],fresh_rows:const blot_check_effects::Id[:],leaves:const L&,row_leaves:const R&,copied:Map_associated_equations&,depth:i64,prior:const Id[:],args:Id[:])->Id,Error {
            for child,index in prior { let next, error = substituteDepth(self_, child, old,fresh_ids,old_rows,fresh_rows,leaves,row_leaves,copied, depth + 1); if error != blot_error::Error.none { return 0, error; } args[index]=next; }
            if value.tag == Tag.projection { return projection(self_, NominalIdentity { value.a, value.b , ..}, projectionMember(self_, value), args); }
            if value.tag == Tag.instance_selection { return instanceSelection(self_, NominalIdentity { value.a, value.b , ..}, args); }
            return nominal(self_, NominalIdentity { value.a, value.b , ..}, args);
}

struct CovariantInput { root: Id, depth: i64 }
fn hash(value: CovariantInput) -> u64 { return ::hash_combine(::hash(value.root), ::hash(value.depth)); }
struct CovariantEntry { root: Id, depth: i64, protected: List, result: Id }
struct CovariantMemo { entries: CovariantEntry[>..]&, protected_values: u32[>..]& }
fn closeCovariant(self_: Store&, root: Id, generalized: const u32[:], protected: const u32[:]) -> Id, Error {
    let attribution_start = self_.nodes.len;
    var entries: CovariantEntry[>..] = []; var protected_values: u32[>..] = []; var memo = CovariantMemo { entries, protected_values , ..}; var decisions: u32[>..] = [];
    let result, error = closeCovariantDepth(self_, root, generalized, protected, decisions, false, memo, 0);
    saturatedAdd(self_.normalization.close_nodes_added, (self_.nodes.len - attribution_start) as u64); return result, error;
}
fn closeCovariantCertified(self_: Store&, root: Id, generalized: const u32[:], protected: const u32[:]) -> ClosedCovariant, Error {
    let attribution_start = self_.nodes.len;
    var entries: CovariantEntry[>..] = []; var protected_values: u32[>..] = []; var memo = CovariantMemo { entries, protected_values , ..}; var decisions: u32[>..] = [];
    let closed, error = closeCovariantDepth(self_, root, generalized, protected, decisions, true, memo, 0);
    saturatedAdd(self_.normalization.close_nodes_added, (self_.nodes.len - attribution_start) as u64);
    if error != blot_error::Error.none { return default<ClosedCovariant>(), error; }
    let rows, error = saveList(self_, decisions); if error != blot_error::Error.none { return default<ClosedCovariant>(), error; }
    return ClosedCovariant { closed, rows , ..}, blot_error::Error.none;
}
recursive fn closeCovariantDepth(self_: Store&, root: Id, generalized: const u32[:], protected: const u32[:],
                                 decisions: u32[>..]&, record_decisions: bool, memo: CovariantMemo&, depth: i64) -> Id, Error {
    increment(self_.normalization.close_depth_entries); if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } }
    if depth >= 1024 { return 0, blot_error::Error.type_limit; } if generalized.len == 0 { return root, blot_error::Error.none; }
    if self_.has_projections || self_.use_closed_graphs {
        for entry in memo.entries { if entry.root == root && entry.depth == depth && memo.protected_values[entry.protected.start..entry.protected.start + entry.protected.len] == protected { return entry.result, blot_error::Error.none; } }
        let rows, error = freeRowVariables(self_, root); if error != blot_error::Error.none { return 0, error; }
        var changes = false; for row_id in rows { if has(generalized, row_id) && !has(protected, row_id) { changes = true; break; } }
        if !changes { return root, blot_error::Error.none; }
    }
    let result, error = closeCovariantNode(self_, root, generalized, protected, decisions, record_decisions, memo, depth); if error != blot_error::Error.none { return 0, error; }
    if (self_.has_projections || self_.use_closed_graphs) && memo.entries.len < 65536 {
        let span = List { memo.protected_values.len as u32, protected.len as u32 , ..}; memo.protected_values.append(protected); memo.entries.push(CovariantEntry { root, depth, span, result , ..});
    }
    return result, blot_error::Error.none;
}
recursive fn closeCovariantNode(self_: Store&, root: Id, generalized: const u32[:], protected: const u32[:],
                                decisions: u32[>..]&, record_decisions: bool, memo: CovariantMemo&, depth: i64) -> Id, Error {
    if depth >= 1024 { return 0, blot_error::Error.type_limit; } let value = node(self_, root);
    match value.tag {
        provider => {
            var effect_row = value.c; let tail = self_.effects.node(effect_row).tail;
            let token_rows, error = freeRowVariables(self_, value.a); if error != blot_error::Error.none { return 0, error; }
            match tail { variable v => { if has(generalized, v.value) && !has(protected, v.value) && !has(token_rows, v.value) {
                if record_decisions && !has(decisions, v.value) { decisions.push(v.value); }
                let next, error = self_.effects.row(rowLabels(self_, effect_row), blot_check_effects::Tail.closed); if error != blot_error::Error.none { return 0, effectError(error); } effect_row = next;
            } }, _ => {}, }
            if effect_row == value.c { return root, blot_error::Error.none; } return provider(self_, value.a, effect_row);
        },
        function => {
            let parameter_free, pe = freeRowVariables(self_, value.a); if pe != blot_error::Error.none { return 0, pe; }
            let result_free, re = freeRowVariables(self_, value.b); if re != blot_error::Error.none { return 0, re; }
            var effect_row = value.c; let tail = self_.effects.node(effect_row).tail;
            match tail { variable v => { if has(generalized, v.value) && !has(protected, v.value) && !has(parameter_free, v.value) && !has(result_free, v.value) {
                if record_decisions && !has(decisions, v.value) { decisions.push(v.value); }
                let next, error = self_.effects.row(rowLabels(self_, effect_row), blot_check_effects::Tail.closed); if error != blot_error::Error.none { return 0, effectError(error); } effect_row = next;
            } }, _ => {}, }
            var nested: u32[>..] = []; nested.append(protected); let union = unionInto(self_, nested, parameter_free); if union != blot_error::Error.none { return 0, union; }
            match self_.effects.node(effect_row).tail { variable v => { let error = unionInto(self_, nested, [v.value]); if error != blot_error::Error.none { return 0, error; } }, _ => {}, }
            let result, error = closeCovariantDepth(self_, value.b, generalized, nested, decisions, record_decisions, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if result == value.b && effect_row == value.c { return root, blot_error::Error.none; } return functionWithEffects(self_, value.a, result, effect_row);
        },
        product, record => {
            var protected_siblings: u32[>..] = []; protected_siblings.append(protected);
            for i in value.b { var child = self_.extra.items[value.a + i]; if value.tag == Tag.record { child = recordField(self_, value, i).ty; } let error = covariantInputs(self_, child, protected_siblings, depth + 1); if error != blot_error::Error.none { return 0, error; } }
            var children: Id[>..] = []; var fields: Field[>..] = []; var changed = false;
            for i in value.b {
                var field = Field { 0, self_.extra.items[value.a + i] , ..}; if value.tag == Tag.record { field = recordField(self_, value, i); }
                let child, error = closeCovariantDepth(self_, field.ty, generalized, protected_siblings, decisions, record_decisions, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
                changed = changed || child != field.ty; if value.tag == Tag.record { fields.push(Field { field.name, child , ..}); } else { children.push(child); }
            }
            if !changed { return root, blot_error::Error.none; } if value.tag == Tag.record { return record(self_, fields); } return product(self_, children);
        },
        usage => {
            let child, error = closeCovariantDepth(self_, value.a, generalized, protected, decisions, record_decisions, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if child == value.a { return root, blot_error::Error.none; } return usage(self_, child, value.b, value.c);
        },
        array, list, cursor => {
            let child, error = closeCovariantDepth(self_, value.a, generalized, protected, decisions, record_decisions, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if child == value.a { return root, blot_error::Error.none; } return sequence(self_, value.tag, child);
        },
        _ => { return root, blot_error::Error.none; },
    }
}
fn covariantInputs(self_: Store&, root: Id, out: u32[>..]&, depth: i64) -> Error { var seen = dictionary<CovariantInput, bool> {}; return covariantInputsSeen(self_, root, out, depth, seen); }
recursive fn covariantInputsSeen(self_: Store&, root: Id, out: u32[>..]&, depth: i64, seen: dictionary<CovariantInput, bool>&) -> Error {
    if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return error; } }
    if depth >= 1024 { return blot_error::Error.type_limit; }
    if self_.has_projections || self_.use_closed_graphs { let key = CovariantInput { root, depth , ..}; if ::contains(seen,key) { return blot_error::Error.none; } ::insert(seen,key, true); }
    let value = node(self_, root);
    match value.tag {
        function => { let free, error = freeRowVariables(self_, value.a); if error != blot_error::Error.none { return error; } let added = unionInto(self_, out, free); if added != blot_error::Error.none { return added; } return covariantInputsSeen(self_, value.b, out, depth + 1, seen); },
        nominal, state_provider => { let free, error = freeRowVariables(self_, root); if error != blot_error::Error.none { return error; } return unionInto(self_, out, free); },
        provider => { let free, error = freeRowVariables(self_, value.a); if error != blot_error::Error.none { return error; } return unionInto(self_, out, free); },
        product, record => { for i in value.b { var child = self_.extra.items[value.a + i]; if value.tag == Tag.record { child = recordField(self_, value, i).ty; } let error = covariantInputsSeen(self_, child, out, depth + 1, seen); if error != blot_error::Error.none { return error; } } },
        usage, array, list, cursor => { return covariantInputsSeen(self_, value.a, out, depth + 1, seen); }, _ => {},
    }
    return blot_error::Error.none;
}
fn openCovariant(self_: Store&, root: Id) -> Id, Error {
    let attribution_start = self_.nodes.len; var memo = dictionary<CovariantInput, Id> {}; let result, error = openCovariantDepth(self_, root, memo, 0);
    saturatedAdd(self_.normalization.open_nodes_added, (self_.nodes.len - attribution_start) as u64); return result, error;
}
recursive fn openCovariantDepth(self_: Store&, root: Id, memo: dictionary<CovariantInput, Id>&, depth: i64) -> Id, Error {
    increment(self_.normalization.open_depth_entries);
    if !self_.has_projections { if depth >= 1024 { return 0, blot_error::Error.type_limit; } match node(self_, root).tag { function, provider, product, record, usage, array, list, cursor => {}, _ => { return root, blot_error::Error.none; }, } }
    var query = CovariantInput { root, depth , ..}; if self_.has_projections { query.depth = 0; }
    block { let known = ::get(memo,query); if known { return known, blot_error::Error.none; } }
    let result, error = openCovariantNode(self_, root, memo, depth); if error != blot_error::Error.none { return 0, error; }
    if (self_.has_projections || result == root) && memo.count < 65536 { ::insert(memo,query, result); } return result, blot_error::Error.none;
}
recursive fn openCovariantNode(self_: Store&, root: Id, memo: dictionary<CovariantInput, Id>&, depth: i64) -> Id, Error {
    if self_.has_projections { let error = chargeProjection(self_); if error != blot_error::Error.none { return 0, error; } } if depth >= 1024 { return 0, blot_error::Error.type_limit; }
    let value = node(self_, root);
    match value.tag {
        provider => {
            var effect_row = value.c; if self_.effects.node(effect_row).tail == blot_check_effects::Tail.closed {
                let opened, oe = freshEffects(self_); if oe != blot_error::Error.none { return 0, oe; }
                let next, error = self_.effects.row(rowLabels(self_, effect_row), self_.effects.node(opened).tail); if error != blot_error::Error.none { return 0, effectError(error); } effect_row = next;
            }
            if effect_row == value.c { return root, blot_error::Error.none; } return provider(self_, value.a, effect_row);
        },
        function => {
            let result, re = openCovariantDepth(self_, value.b, memo, depth + 1); if re != blot_error::Error.none { return 0, re; }
            var effect_row = value.c; if self_.effects.node(effect_row).tail == blot_check_effects::Tail.closed {
                let opened, oe = freshEffects(self_); if oe != blot_error::Error.none { return 0, oe; }
                let next, error = self_.effects.row(rowLabels(self_, effect_row), self_.effects.node(opened).tail); if error != blot_error::Error.none { return 0, effectError(error); } effect_row = next;
            }
            if result == value.b && effect_row == value.c { return root, blot_error::Error.none; } return functionWithEffects(self_, value.a, result, effect_row);
        },
        product, record => {
            var children: Id[>..] = []; var fields: Field[>..] = []; var changed = false;
            for i in value.b { var field = Field { 0, self_.extra.items[value.a + i] , ..}; if value.tag == Tag.record { field = recordField(self_, value, i); }
                let child, error = openCovariantDepth(self_, field.ty, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
                changed = changed || child != field.ty; if value.tag == Tag.record { fields.push(Field { field.name, child , ..}); } else { children.push(child); }
            }
            if !changed { return root, blot_error::Error.none; } if value.tag == Tag.record { return record(self_, fields); } return product(self_, children);
        },
        usage => {
            if value.b == blot_parse_ast::usagekind_cleanup || value.b == blot_parse_ast::usagekind_concurrent { return root, blot_error::Error.none; }
            let child, error = openCovariantDepth(self_, value.a, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if child == value.a { return root, blot_error::Error.none; } return usage(self_, child, value.b, value.c);
        },
        array, list, cursor => {
            let child, error = openCovariantDepth(self_, value.a, memo, depth + 1); if error != blot_error::Error.none { return 0, error; }
            if child == value.a { return root, blot_error::Error.none; } return sequence(self_, value.tag, child);
        },
        _ => { return root, blot_error::Error.none; },
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

struct ScalarDefaults {
owner_id:u64=default<u64>(),
use_closed_rows:bool=true,
closed_rows:ClosedRow[4]=[ClosedRow {..}; 4],
use_operation_rows:bool=true,
operation_rows:OperationRow[64]=[OperationRow {..}; 64],
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
normalization:blot_work_counters::Normalization=blot_work_counters::Normalization {..},
resolution_steps:u64=0,
occurs_generation:u32=0,
use_resolution_cache:bool=true,
use_composite_cache:bool=true,
composite_min_growth:i64=4,
use_operation_shapes:bool=true,
operation_shape_generation:u16=0,
operation_shape_enabled:bool=false,
}
var inactive_scalars=ScalarDefaults{..};
struct OwnerState {generation:u64=0,live:bool=false,
nodes:Table_nodes=Table_nodes{..},
extra:Table_extra=Table_extra{..},
variables:Table_variables=Table_variables{..},
versions:Table_versions=Table_versions{..},
operations:Table_operations=Table_operations{..},
operation_links:Table_operation_links=Table_operation_links{..},
quantifier_goals:Table_quantifier_goals=Table_quantifier_goals{..},
quantifier_obligations:Table_quantifier_obligations=Table_quantifier_obligations{..},
occurs_seen:Table_occurs_seen=Table_occurs_seen{..},
closed_row_index:Table_closed_row_index=Table_closed_row_index{..},
closed_operation_index:Table_closed_operation_index=Table_closed_operation_index{..},
variable_views:Map_variable_views=Map_variable_views{..},
associated_equations:Map_associated_equations=Map_associated_equations{..},
projection_resolutions:Map_projection_resolutions=Map_projection_resolutions{..},
operation_chains:Map_operation_chains=Map_operation_chains{..},
effects:blot_check_effects::Store=blot_check_effects::Store{..},
resolved:blot_reuse_epoch_resolution_cache::Cache=blot_reuse_epoch_resolution_cache::Cache{..},
composites:blot_reuse_composite_resolution_cache::Cache=blot_reuse_composite_resolution_cache::Cache{..},
owner_id:u64=default<u64>(),
use_closed_rows:bool=true,
closed_rows:ClosedRow[4]=[ClosedRow {..}; 4],
use_operation_rows:bool=true,
operation_rows:OperationRow[64]=[OperationRow {..}; 64],
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
normalization:blot_work_counters::Normalization=blot_work_counters::Normalization {..},
resolution_steps:u64=0,
occurs_generation:u32=0,
use_resolution_cache:bool=true,
use_composite_cache:bool=true,
composite_min_growth:i64=4,
use_operation_shapes:bool=true,
operation_shape_generation:u16=0,
operation_shape_enabled:bool=false,
}
var inactive_nodes=Table_nodes{..};
var inactive_extra=Table_extra{..};
var inactive_variables=Table_variables{..};
var inactive_versions=Table_versions{..};
var inactive_operations=Table_operations{..};
var inactive_operation_links=Table_operation_links{..};
var inactive_quantifier_goals=Table_quantifier_goals{..};
var inactive_quantifier_obligations=Table_quantifier_obligations{..};
var inactive_occurs_seen=Table_occurs_seen{..};
var inactive_closed_row_index=Table_closed_row_index{..};
var inactive_closed_operation_index=Table_closed_operation_index{..};
var inactive_variable_views=Map_variable_views{..};
var inactive_associated_equations=Map_associated_equations{..};
var inactive_projection_resolutions=Map_projection_resolutions{..};
var inactive_operation_chains=Map_operation_chains{..};
var inactive_effects=blot_check_effects::Store{..};
var inactive_resolved=blot_reuse_epoch_resolution_cache::Cache{..};
var inactive_composites=blot_reuse_composite_resolution_cache::Cache{..};































reusable var owner_states:OwnerState[>..]=[];
var next_owner_generation:u64=1;

struct Table_nodes {storage:Node[:]=default<Node[:]>(),items:Node[:]=default<Node[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_nodes:Node[>..];
fn ensure(self_:Table_nodes&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_nodes);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_nodes&,value:Node) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_nodes);self_.len=self_.items.len;}
fn append(self_:Table_nodes&,values:const Node[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_nodes);self_.len=self_.items.len;}
fn resize(self_:Table_nodes&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_nodes&,length:i64,value:Node) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_nodes&)->Node {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_nodes&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_nodes&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_nodes&) {blot_support_pooled_buffer::deinit(self_,pool_Table_nodes);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_nodes&,value:const Node&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_nodes&,values:const Node[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_extra {storage:Id[:]=default<Id[:]>(),items:Id[:]=default<Id[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_extra:Id[>..];
fn ensure(self_:Table_extra&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_extra);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_extra&,value:Id) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_extra);self_.len=self_.items.len;}
fn append(self_:Table_extra&,values:const Id[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_extra);self_.len=self_.items.len;}
fn resize(self_:Table_extra&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_extra&,length:i64,value:Id) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_extra&)->Id {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_extra&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_extra&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_extra&) {blot_support_pooled_buffer::deinit(self_,pool_Table_extra);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_extra&,value:const Id&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_extra&,values:const Id[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_variables {storage:Variable[:]=default<Variable[:]>(),items:Variable[:]=default<Variable[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_variables:Variable[>..];
fn ensure(self_:Table_variables&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_variables);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_variables&,value:Variable) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_variables);self_.len=self_.items.len;}
fn append(self_:Table_variables&,values:const Variable[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_variables);self_.len=self_.items.len;}
fn resize(self_:Table_variables&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_variables&,length:i64,value:Variable) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_variables&)->Variable {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_variables&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_variables&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_variables&) {blot_support_pooled_buffer::deinit(self_,pool_Table_variables);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_variables&,value:const Variable&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_variables&,values:const Variable[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_versions {storage:Version[:]=default<Version[:]>(),items:Version[:]=default<Version[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_versions:Version[>..];
fn ensure(self_:Table_versions&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_versions);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_versions&,value:Version) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_versions);self_.len=self_.items.len;}
fn append(self_:Table_versions&,values:const Version[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_versions);self_.len=self_.items.len;}
fn resize(self_:Table_versions&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_versions&,length:i64,value:Version) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_versions&)->Version {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_versions&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_versions&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_versions&) {blot_support_pooled_buffer::deinit(self_,pool_Table_versions);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_versions&,value:const Version&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_versions&,values:const Version[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_operations {storage:Operation[:]=default<Operation[:]>(),items:Operation[:]=default<Operation[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_operations:Operation[>..];
fn ensure(self_:Table_operations&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_operations);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_operations&,value:Operation) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_operations);self_.len=self_.items.len;}
fn append(self_:Table_operations&,values:const Operation[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_operations);self_.len=self_.items.len;}
fn resize(self_:Table_operations&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_operations&,length:i64,value:Operation) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_operations&)->Operation {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_operations&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_operations&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_operations&) {blot_support_pooled_buffer::deinit(self_,pool_Table_operations);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_operations&,value:const Operation&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_operations&,values:const Operation[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_operation_links {storage:OperationLink[:]=default<OperationLink[:]>(),items:OperationLink[:]=default<OperationLink[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_operation_links:OperationLink[>..];
fn ensure(self_:Table_operation_links&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_operation_links);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_operation_links&,value:OperationLink) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_operation_links);self_.len=self_.items.len;}
fn append(self_:Table_operation_links&,values:const OperationLink[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_operation_links);self_.len=self_.items.len;}
fn resize(self_:Table_operation_links&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_operation_links&,length:i64,value:OperationLink) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_operation_links&)->OperationLink {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_operation_links&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_operation_links&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_operation_links&) {blot_support_pooled_buffer::deinit(self_,pool_Table_operation_links);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_operation_links&,value:const OperationLink&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_operation_links&,values:const OperationLink[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_quantifier_goals {storage:QuantifierGoals[:]=default<QuantifierGoals[:]>(),items:QuantifierGoals[:]=default<QuantifierGoals[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_quantifier_goals:QuantifierGoals[>..];
fn ensure(self_:Table_quantifier_goals&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_quantifier_goals);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_quantifier_goals&,value:QuantifierGoals) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_quantifier_goals);self_.len=self_.items.len;}
fn append(self_:Table_quantifier_goals&,values:const QuantifierGoals[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_quantifier_goals);self_.len=self_.items.len;}
fn resize(self_:Table_quantifier_goals&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_quantifier_goals&,length:i64,value:QuantifierGoals) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_quantifier_goals&)->QuantifierGoals {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_quantifier_goals&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_quantifier_goals&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_quantifier_goals&) {blot_support_pooled_buffer::deinit(self_,pool_Table_quantifier_goals);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_quantifier_goals&,value:const QuantifierGoals&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_quantifier_goals&,values:const QuantifierGoals[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_quantifier_obligations {storage:Obligation[:]=default<Obligation[:]>(),items:Obligation[:]=default<Obligation[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_quantifier_obligations:Obligation[>..];
fn ensure(self_:Table_quantifier_obligations&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_quantifier_obligations);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_quantifier_obligations&,value:Obligation) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_quantifier_obligations);self_.len=self_.items.len;}
fn append(self_:Table_quantifier_obligations&,values:const Obligation[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_quantifier_obligations);self_.len=self_.items.len;}
fn resize(self_:Table_quantifier_obligations&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_quantifier_obligations&,length:i64,value:Obligation) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_quantifier_obligations&)->Obligation {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_quantifier_obligations&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_quantifier_obligations&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_quantifier_obligations&) {blot_support_pooled_buffer::deinit(self_,pool_Table_quantifier_obligations);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_quantifier_obligations&,value:const Obligation&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_quantifier_obligations&,values:const Obligation[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_occurs_seen {storage:u32[:]=default<u32[:]>(),items:u32[:]=default<u32[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_occurs_seen:u32[>..];
fn ensure(self_:Table_occurs_seen&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_occurs_seen);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_occurs_seen&,value:u32) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_occurs_seen);self_.len=self_.items.len;}
fn append(self_:Table_occurs_seen&,values:const u32[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_occurs_seen);self_.len=self_.items.len;}
fn resize(self_:Table_occurs_seen&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_occurs_seen&,length:i64,value:u32) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_occurs_seen&)->u32 {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_occurs_seen&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_occurs_seen&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_occurs_seen&) {blot_support_pooled_buffer::deinit(self_,pool_Table_occurs_seen);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_occurs_seen&,value:const u32&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_occurs_seen&,values:const u32[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_closed_row_index {storage:RowCertificate[:]=default<RowCertificate[:]>(),items:RowCertificate[:]=default<RowCertificate[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_closed_row_index:RowCertificate[>..];
fn ensure(self_:Table_closed_row_index&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_closed_row_index);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_closed_row_index&,value:RowCertificate) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_closed_row_index);self_.len=self_.items.len;}
fn append(self_:Table_closed_row_index&,values:const RowCertificate[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_closed_row_index);self_.len=self_.items.len;}
fn resize(self_:Table_closed_row_index&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_closed_row_index&,length:i64,value:RowCertificate) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_closed_row_index&)->RowCertificate {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_closed_row_index&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_closed_row_index&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_closed_row_index&) {blot_support_pooled_buffer::deinit(self_,pool_Table_closed_row_index);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_closed_row_index&,value:const RowCertificate&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_closed_row_index&,values:const RowCertificate[:])->Error {self_.clear();self_.append(values);return self_.failure;}

struct Table_closed_operation_index {storage:RowCertificate[:]=default<RowCertificate[:]>(),items:RowCertificate[:]=default<RowCertificate[:]>(),len:i64=0,failure:Error=blot_error::Error.none}
reusable[] var pool_Table_closed_operation_index:RowCertificate[>..];
fn ensure(self_:Table_closed_operation_index&,minimum:i64)->Error {if self_.failure!=blot_error::Error.none {return self_.failure;}let error=blot_support_pooled_buffer::ensure(self_,minimum,pool_Table_closed_operation_index);if error!=blot_error::Error.none {self_.failure=error;}return error;}
fn push(self_:Table_closed_operation_index&,value:RowCertificate) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::push(self_,value,pool_Table_closed_operation_index);self_.len=self_.items.len;}
fn append(self_:Table_closed_operation_index&,values:const RowCertificate[:]) {if self_.failure!=blot_error::Error.none {return;}self_.failure=blot_support_pooled_buffer::append(self_,values,pool_Table_closed_operation_index);self_.len=self_.items.len;}
fn resize(self_:Table_closed_operation_index&,length:i64) {blot_support_pooled_buffer::resize(self_,length);self_.len=length;}
fn resize(self_:Table_closed_operation_index&,length:i64,value:RowCertificate) {if length<=self_.len {self_.resize(length);return;}let error=self_.ensure(length);if error!=blot_error::Error.none {return;}for index in self_.len..length {self_.storage[index]=value;}self_.items=self_.storage[..length];self_.len=length;}
fn pop(self_:Table_closed_operation_index&)->RowCertificate {assert(self_.len!=0);let value=self_.items[self_.len-1];self_.resize(self_.len-1);return value;}
fn pop_n(self_:Table_closed_operation_index&,count:i64) {assert(count>=0 && count<=self_.len);self_.resize(self_.len-count);}
fn clear(self_:Table_closed_operation_index&) {self_.items=self_.storage[..0];self_.len=0;self_.failure=blot_error::Error.none;}
fn deinit(self_:Table_closed_operation_index&) {blot_support_pooled_buffer::deinit(self_,pool_Table_closed_operation_index);self_.len=0;self_.failure=blot_error::Error.none;}
fn index_of(self_:const Table_closed_operation_index&,value:const RowCertificate&)->i64 {return self_.items.index_of(value);}
fn restore(self_:Table_closed_operation_index&,values:const RowCertificate[:])->Error {self_.clear();self_.append(values);return self_.failure;}
struct Map_variable_views { count: i64 = 0, failure:Error=blot_error::Error.none, slots: dictionary_slot<u64,Id>[:] = default<dictionary_slot<u64,Id>[:]>() }
fn probe(map: const Map_variable_views&,key: u64) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_variable_views&,key: u64) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_variable_views&,key: u64) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<u64,Id>[:]) { if slots.len != 0 { pool_Map_variable_views.free_slice(slots); } }
fn grow(map: Map_variable_views&,capacity: i64) {
    if map.failure != blot_error::Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return; }
    let replacement = pool_Map_variable_views.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<u64,Id> { default<u64>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_variable_views&,key: u64,value: Id) -> bool {
    if map.failure != blot_error::Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != blot_error::Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<u64,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<u64,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_variable_views&,key: u64) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<u64,Id> { default<u64>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_variable_views&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_variable_views&) { release(map.slots); map.slots = default<dictionary_slot<u64,Id>[:]>(); map.count = 0;map.failure=blot_error::Error.none; }
fn clone(map: const Map_variable_views&) -> Map_variable_views { var copy = Map_variable_views {..}; if map.slots.len != 0 { let slots = pool_Map_variable_views.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_variable_views&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_variable_views:dictionary_slot<u64,Id>[>..];
fn restore(map:Map_variable_views&,slots:const dictionary_slot<u64,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}let run=pool_Map_variable_views.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return blot_error::Error.none;}
struct Map_associated_equations { count: i64 = 0, failure:Error=blot_error::Error.none, slots: dictionary_slot<Id,Id>[:] = default<dictionary_slot<Id,Id>[:]>() }
fn probe(map: const Map_associated_equations&,key: Id) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_associated_equations&,key: Id) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_associated_equations&,key: Id) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<Id,Id>[:]) { if slots.len != 0 { pool_Map_associated_equations.free_slice(slots); } }
fn grow(map: Map_associated_equations&,capacity: i64) {
    if map.failure != blot_error::Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return; }
    let replacement = pool_Map_associated_equations.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_associated_equations&,key: Id,value: Id) -> bool {
    if map.failure != blot_error::Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != blot_error::Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<Id,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<Id,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_associated_equations&,key: Id) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<Id,Id> { default<Id>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_associated_equations&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_associated_equations&) { release(map.slots); map.slots=default<dictionary_slot<Id,Id>[:]>(); map.count = 0;map.failure=blot_error::Error.none; }
fn clone(map: const Map_associated_equations&) -> Map_associated_equations { var copy = Map_associated_equations {..}; if map.slots.len != 0 { let slots = pool_Map_associated_equations.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_associated_equations&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_associated_equations:dictionary_slot<Id,Id>[>..];
fn restore(map:Map_associated_equations&,slots:const dictionary_slot<Id,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}let run=pool_Map_associated_equations.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return blot_error::Error.none;}
struct Map_projection_resolutions { count: i64 = 0, failure:Error=blot_error::Error.none, slots: dictionary_slot<ProjectionResolution,Id>[:] = default<dictionary_slot<ProjectionResolution,Id>[:]>() }
fn probe(map: const Map_projection_resolutions&,key: ProjectionResolution) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_projection_resolutions&,key: ProjectionResolution) -> Id? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_projection_resolutions&,key: ProjectionResolution) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<ProjectionResolution,Id>[:]) { if slots.len != 0 { pool_Map_projection_resolutions.free_slice(slots); } }
fn grow(map: Map_projection_resolutions&,capacity: i64) {
    if map.failure != blot_error::Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return; }
    let replacement = pool_Map_projection_resolutions.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<ProjectionResolution,Id> { default<ProjectionResolution>(),default<Id>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_projection_resolutions&,key: ProjectionResolution,value: Id) -> bool {
    if map.failure != blot_error::Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != blot_error::Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<ProjectionResolution,Id> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<ProjectionResolution,Id> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_projection_resolutions&,key: ProjectionResolution) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<ProjectionResolution,Id> { default<ProjectionResolution>(),default<Id>(),0 }; map.count--; return true;
}
fn clear(map: Map_projection_resolutions&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_projection_resolutions&) { release(map.slots); map.slots=default<dictionary_slot<ProjectionResolution,Id>[:]>(); map.count = 0;map.failure=blot_error::Error.none; }
fn clone(map: const Map_projection_resolutions&) -> Map_projection_resolutions { var copy = Map_projection_resolutions {..}; if map.slots.len != 0 { let slots = pool_Map_projection_resolutions.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_projection_resolutions&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_projection_resolutions:dictionary_slot<ProjectionResolution,Id>[>..];
fn restore(map:Map_projection_resolutions&,slots:const dictionary_slot<ProjectionResolution,Id>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}let run=pool_Map_projection_resolutions.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return blot_error::Error.none;}
struct Map_operation_chains { count: i64 = 0, failure:Error=blot_error::Error.none, slots: dictionary_slot<OperationKey,OperationChain>[:] = default<dictionary_slot<OperationKey,OperationChain>[:]>() }
fn probe(map: const Map_operation_chains&,key: OperationKey) -> i64 {
    if map.count == 0 { return -1; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == tag && map.slots[index].key == key { return index; } if present == 0 { return -1; } index = (index + 1) & mask; }
}
fn get(map: const Map_operation_chains&,key: OperationKey) -> OperationChain? { let index = probe(map,key); if index < 0 { return null; } return map.slots[index].val; }
fn contains(map: const Map_operation_chains&,key: OperationKey) -> bool { return probe(map,key) >= 0; }
fn release(slots: dictionary_slot<OperationKey,OperationChain>[:]) { if slots.len != 0 { pool_Map_operation_chains.free_slice(slots); } }
fn grow(map: Map_operation_chains&,capacity: i64) {
    if map.failure != blot_error::Error.none { return; } if capacity < 8 || capacity > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return; }
    let replacement = pool_Map_operation_chains.alloc_slice(capacity); for &slot in replacement { slot = dictionary_slot<OperationKey,OperationChain> { default<OperationKey>(),default<OperationChain>(),0 }; }
    for slot in map.slots { if slot.tag != 0 { var index = (slot.key.hash() & ((capacity - 1) as u64)) as i64; while replacement[index].tag != 0 { index = (index + 1) & (capacity - 1); } replacement[index] = slot; } }
    release(map.slots); map.slots = replacement;
}
fn insert(map: Map_operation_chains&,key: OperationKey,value: OperationChain) -> bool {
    if map.failure != blot_error::Error.none { return false; } if map.count > 0x1ffffffffffffffe || map.slots.len > 0x1fffffffffffffff { map.failure = blot_error::Error.out_of_memory; return false; }
    if map.slots.len == 0 { grow(map,8); } else if (map.count + 1) * 3 > map.slots.len * 2 { grow(map,map.slots.len * 2); }
    if map.failure != blot_error::Error.none { return false; }
    let hash = key.hash(); let tag = (hash as! u32) | 2147483648; let mask = map.slots.len - 1; var index = (hash & (mask as u64)) as i64;
    loop { let present = map.slots[index].tag; if present == 0 { map.slots[index] = dictionary_slot<OperationKey,OperationChain> { key,value,tag }; map.count++; return true; } if present == tag && map.slots[index].key == key { map.slots[index] = dictionary_slot<OperationKey,OperationChain> { map.slots[index].key,value,tag }; return false; } index = (index + 1) & mask; }
}
fn remove(map: Map_operation_chains&,key: OperationKey) -> bool {
    var hole = probe(map,key); if hole < 0 { return false; } let mask = map.slots.len - 1; var index = hole;
    loop { index = (index + 1) & mask; let tag = map.slots[index].tag; if tag == 0 { break; } let home = (map.slots[index].key.hash() & (mask as u64)) as i64; if ((index - home) & mask) >= ((index - hole) & mask) { map.slots[hole] = map.slots[index]; hole = index; } }
    map.slots[hole] = dictionary_slot<OperationKey,OperationChain> { default<OperationKey>(),default<OperationChain>(),0 }; map.count--; return true;
}
fn clear(map: Map_operation_chains&) { for &slot in map.slots { slot.tag = 0; } map.count = 0; }
fn deinit(map: Map_operation_chains&) { release(map.slots); map.slots=default<dictionary_slot<OperationKey,OperationChain>[:]>(); map.count = 0;map.failure=blot_error::Error.none; }
fn clone(map: const Map_operation_chains&) -> Map_operation_chains { var copy = Map_operation_chains {..}; if map.slots.len != 0 { let slots = pool_Map_operation_chains.alloc_slice(map.slots.len); for slot,index in map.slots { slots[index] = slot; } copy.slots = slots; copy.count = map.count; } return copy; }
fn each<F>(map: Map_operation_chains&) { for &slot in map.slots { if slot.tag != 0 { F(slot.key,&slot.val); } } }

reusable[] var pool_Map_operation_chains:dictionary_slot<OperationKey,OperationChain>[>..];
fn restore(map:Map_operation_chains&,slots:const dictionary_slot<OperationKey,OperationChain>[:],count:i64)->Error {map.deinit();if slots.len==0 {if count!=0 {return blot_error::Error.invalid_artifact;}return blot_error::Error.none;}let run=pool_Map_operation_chains.alloc_slice(slots.len);for slot,index in slots {run[index]=slot;}map.slots=run;map.count=count;return blot_error::Error.none;}
fn valid(self_:const Store&)->bool {return self_.lease!=0 && self_.lease-1<owner_states.len && owner_states[self_.lease-1].live && owner_states[self_.lease-1].generation==self_.owner_generation;}
fn initPooled(options:Options=Options{..})->Store,Error {if next_owner_generation==0xffffffffffffffff || owner_states.len>=0xffffffff {return Store{..},blot_error::Error.out_of_memory;}let generation=next_owner_generation;next_owner_generation+=1;let index=owner_states.alloc_index(OwnerState{generation:generation,live:true, ..});let state:OwnerState& =owner_states[index];var self_=Store{lease:(index+1) as u32,owner_generation:generation,nodes:state.nodes,extra:state.extra,variables:state.variables,versions:state.versions,operations:state.operations,operation_links:state.operation_links,quantifier_goals:state.quantifier_goals,quantifier_obligations:state.quantifier_obligations,occurs_seen:state.occurs_seen,closed_row_index:state.closed_row_index,closed_operation_index:state.closed_operation_index,variable_views:state.variable_views,associated_equations:state.associated_equations,projection_resolutions:state.projection_resolutions,operation_chains:state.operation_chains,effects:state.effects,resolved:state.resolved,composites:state.composites,owner_id:state.owner_id,use_closed_rows:state.use_closed_rows,closed_rows:state.closed_rows,use_operation_rows:state.use_operation_rows,operation_rows:state.operation_rows,has_usage_types:state.has_usage_types,has_rank_types:state.has_rank_types,next_rigid_scope:state.next_rigid_scope,use_closed_graphs:state.use_closed_graphs,has_proof_kinds:state.has_proof_kinds,has_projections:state.has_projections,projection_limit:state.projection_limit,projection_steps:state.projection_steps,resolution_depth_limit:state.resolution_depth_limit,projection_exhausted:state.projection_exhausted,projection_resolution_types:state.projection_resolution_types,projection_resolution_rows:state.projection_resolution_rows,projection_resolution_limit:state.projection_resolution_limit,closed_generation:state.closed_generation,closed_effect_physical_epoch:state.closed_effect_physical_epoch,mutation_epoch:state.mutation_epoch,occurs_steps:state.occurs_steps,normalization:state.normalization,resolution_steps:state.resolution_steps,occurs_generation:state.occurs_generation,use_resolution_cache:state.use_resolution_cache,use_composite_cache:state.use_composite_cache,composite_min_growth:state.composite_min_growth,use_operation_shapes:state.use_operation_shapes,operation_shape_generation:state.operation_shape_generation,operation_shape_enabled:state.operation_shape_enabled, ..};self_.owner_id=blot_native::fresh_owner_id();self_.use_closed_graphs=options.closed_graphs;self_.use_resolution_cache=options.resolution_cache;self_.use_composite_cache=options.composite_cache && options.closed_graphs;self_.composite_min_growth=options.composite_min_growth;let effects,error=blot_check_effects::initPooled(blot_check_effects::Options{resolution_cache:options.resolution_cache, ..});if error!=blot_error::Error.none {self_.deinit();return Store{..},effectError(error);}self_.effects=effects;let resolved,error=blot_reuse_epoch_resolution_cache::initPooled();if error!=blot_error::Error.none {self_.deinit();return Store{..},error;}self_.resolved=resolved;let composites,error=blot_reuse_composite_resolution_cache::initPooled();if error!=blot_error::Error.none {self_.deinit();return Store{..},error;}self_.composites=composites;self_.nodes.append([Node{Tag.absent, ..},Node{Tag.unit, ..},Node{Tag.boolean, ..},Node{Tag.unsigned32, ..},Node{Tag.floating32, ..},Node{Tag.never, ..}]);self_.operations.append([Operation{NominalIdentity{0,0}, ..},Operation{NominalIdentity{0,1}, ..}]);if self_.nodes.failure!=blot_error::Error.none || self_.operations.failure!=blot_error::Error.none {var error=self_.nodes.failure;if error==blot_error::Error.none {error=self_.operations.failure;}self_.deinit();return Store{..},error;}return self_,blot_error::Error.none;}
fn init()->Store,Error {return initPooled();}
fn initWithOptions(options:Options)->Store,Error {return initPooled(options);}
fn deinit(self_:Store&) {if self_.lease==0 {return;}assert(valid(self_));self_.nodes.deinit();self_.extra.deinit();self_.variables.deinit();self_.versions.deinit();self_.operations.deinit();self_.operation_links.deinit();self_.quantifier_goals.deinit();self_.quantifier_obligations.deinit();self_.occurs_seen.deinit();self_.closed_row_index.deinit();self_.closed_operation_index.deinit();self_.variable_views.deinit();self_.associated_equations.deinit();self_.projection_resolutions.deinit();self_.operation_chains.deinit();self_.effects.deinit();self_.resolved.deinit();self_.composites.deinit();let index=self_.lease-1;owner_states[index].live=false;owner_states.free(index);self_=Store{..};}
fn withStore<C,F>(context:C&)->Error {let initialized,error=initPooled();if error!=blot_error::Error.none {return error;}var store=initialized;let result=F(context,store);store.deinit();return result;}
fn withStoreValue<C,R,F>(context:C&)->R,Error {let initialized,error=initPooled();if error!=blot_error::Error.none {return default<R>(),error;}var store=initialized;let result,failure=F(context,store);store.deinit();return result,failure;}

fn obligationKindName(kind:ObligationKind)->const u8[:] {match kind {
arithmetic=>{return "arithmetic";},
ordered=>{return "ordered";},
equality=>{return "equality";},
integer=>{return "integer";},
field=>{return "field";},
writable_field=>{return "writable_field";},
dispatch=>{return "dispatch";},
result_dispatch=>{return "result_dispatch";},
monad_factory=>{return "monad_factory";},
resolver_dispatch=>{return "resolver_dispatch";},
resolver_shape=>{return "resolver_shape";},
effect_operation=>{return "effect_operation";},
effect_handler=>{return "effect_handler";},
receiver=>{return "receiver";},
update=>{return "update";},
type_rep=>{return "type_rep";},
effect_rep=>{return "effect_rep";},
type_head=>{return "type_head";},
collection=>{return "collection";},
record_merge=>{return "record_merge";},
callee_use=>{return "callee_use";},
type_eq=>{return "type_eq";},
contract=>{return "contract";},
task_receive=>{return "task_receive";},
}}

fn hash(value:u32)->u64 { return ::hash(value); }
fn hash(value:u64)->u64 { return ::hash(value); }

reusable[] var resolution_binders:Id[>..];
reusable[] var resolution_goals:Obligation[>..];
recursive fn resolveQuantified(self_:Store&,id:Id,value:Node,position:Cursor,depth:i64,binders:const Id[:])->Id,Error {
 let body,error=resolveDepth(self_,value.a,position,depth+1);if error!=blot_error::Error.none {return 0,error;}
 let count=quantifierGoals(self_,id).len;let goals=resolution_goals.alloc_slice(count);
 {let original=quantifierGoals(self_,id);for goal,index in original {goals[index]=goal;}}
 let result,failure=resolveQuantifiedGoals(self_,id,value,position,depth,binders,body,goals);
 resolution_goals.free_slice(goals);return result,failure;
}
recursive fn resolveQuantifiedGoals(self_:Store&,id:Id,value:Node,position:Cursor,depth:i64,binders:const Id[:],body:Id,goals:Obligation[:])->Id,Error {
            var changed = body != value.a;
            for &goal in goals {
                if goal.ty != 0 { let child, error = resolveDepth(self_, goal.ty, position, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || child != goal.ty; goal.ty = child; }
                if goal.other != 0 { let child, error = resolveDepth(self_, goal.other, position, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || child != goal.other; goal.other = child; }
                if goal.result != 0 { let child, error = resolveDepth(self_, goal.result, position, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || child != goal.result; goal.result = child; }
                if goal.signature != 0 { let child, error = resolveDepth(self_, goal.signature, position, depth + 1); if error != blot_error::Error.none { return 0, error; } changed = changed || child != goal.signature; goal.signature = child; }
            }
            if !changed { return id, blot_error::Error.none; } return reownQuantified(self_, value.tag, body, binders, goals);
}

fn hash(key:NominalIdentity)->u64 {return ::hash_combine(::hash(key.unit),::hash(key.decl));}
