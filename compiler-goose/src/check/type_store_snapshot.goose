// A suspension moves the exact logical store into typed reusable backing.
namespace blot_check_type_store_snapshot;
import std;
import dictionary;
import support.error;
import .types;
type Error = blot_error::Error;
struct Range { start: i64 = 0, len: i64 = 0 }
struct State {
    store_owner_id: u64,
    store_use_closed_rows: bool = true,
    store_closed_rows: blot_check_types::ClosedRow[4] = [blot_check_types::ClosedRow {..}; 4],
    store_use_operation_rows: bool = true,
    store_operation_rows: blot_check_types::OperationRow[64] = [blot_check_types::OperationRow {..}; 64],
    store_has_usage_types: bool = false,
    store_has_rank_types: bool = false,
    store_next_rigid_scope: u32 = 1,
    store_use_closed_graphs: bool = false,
    store_has_proof_kinds: bool = false,
    store_has_projections: bool = false,
    store_projection_limit: i64 = 1000000,
    store_projection_steps: i64 = 0,
    store_resolution_depth_limit: i64 = 1024,
    store_projection_exhausted: bool = false,
    store_projection_resolution_types: u64 = 0,
    store_projection_resolution_rows: u64 = 0,
    store_projection_resolution_limit: i64 = 0,
    store_closed_generation: u16 = 1,
    store_closed_effect_physical_epoch: u64 = 0,
    store_mutation_epoch: u64 = 0,
    store_occurs_steps: u64 = 0,
    store_normalization: blot_work_counters::Normalization = blot_work_counters::Normalization {..},
    store_resolution_steps: u64 = 0,
    store_occurs_generation: u32 = 0,
    store_use_resolution_cache: bool = true,
    store_use_composite_cache: bool = true,
    store_composite_min_growth: i64 = 4,
    store_use_operation_shapes: bool = true,
    store_operation_shape_generation: u16 = 0,
    store_operation_shape_enabled: bool = false,
    effects_physical_epoch: u64 = 0,
    effects_mutation_epoch: u64 = 0,
    effects_resolved_physical: u64 = 0xffffffffffffffff,
    effects_resolved_high_water: u32 = 0,
    effects_use_resolution_cache: bool = true,
    effects_next_position: u32 = 0,
    resolved_generation: u32 = 0,
    resolved_mutation: u32 = 0,
    resolved_other: u32 = 0,
    resolved_count: i64 = 0,
    resolved_high_water: i64 = 0,
    composites_physical: u16 = 0,
    composites_effects_physical: u64 = 0,
    store_variable_views_count: i64,
    store_associated_equations_count: i64,
    store_projection_resolutions_count: i64,
    store_operation_chains_count: i64,
    effects_resolved_count: i64,
}
struct Snapshot { state: State, lease_index: u32 = 0, generation: u64 = 0,
    store_nodes: const blot_check_types::Node[:] = [],
    store_extra: const u32[:] = [],
    store_variables: const blot_check_types::Variable[:] = [],
    store_versions: const blot_check_types::Version[:] = [],
    store_operations: const blot_check_types::Operation[:] = [],
    store_operation_links: const blot_check_types::OperationLink[:] = [],
    store_quantifier_goals: const blot_check_types::QuantifierGoals[:] = [],
    store_quantifier_obligations: const blot_check_types::Obligation[:] = [],
    store_occurs_seen: const u32[:] = [],
    store_closed_row_index: const blot_check_types::RowCertificate[:] = [],
    store_closed_operation_index: const blot_check_types::RowCertificate[:] = [],
    store_variable_views: const dictionary_slot<u64, u32>[:] = [],
    store_associated_equations: const dictionary_slot<u32, u32>[:] = [],
    store_projection_resolutions: const dictionary_slot<blot_check_types::ProjectionResolution, u32>[:] = [],
    store_operation_chains: const dictionary_slot<blot_check_types::OperationKey, blot_check_types::OperationChain>[:] = [],
    effects_rows: const blot_check_effects::Row[:] = [],
    effects_labels: const u32[:] = [],
    effects_variables: const blot_check_effects::Variable[:] = [],
    effects_versions: const blot_check_effects::Version[:] = [],
    effects_resolved: const dictionary_slot<u32, u32>[:] = [],
    resolved_entries: const blot_reuse_epoch_resolution_cache::Entry[:] = [],
    composites_entries: const blot_reuse_composite_resolution_cache::Entry[:] = [],
}
struct Lease { live: bool = false, generation: u64 = 0,
    store_nodes: Range = Range {..},
    store_extra: Range = Range {..},
    store_variables: Range = Range {..},
    store_versions: Range = Range {..},
    store_operations: Range = Range {..},
    store_operation_links: Range = Range {..},
    store_quantifier_goals: Range = Range {..},
    store_quantifier_obligations: Range = Range {..},
    store_occurs_seen: Range = Range {..},
    store_closed_row_index: Range = Range {..},
    store_closed_operation_index: Range = Range {..},
    store_variable_views: Range = Range {..},
    store_associated_equations: Range = Range {..},
    store_projection_resolutions: Range = Range {..},
    store_operation_chains: Range = Range {..},
    effects_rows: Range = Range {..},
    effects_labels: Range = Range {..},
    effects_variables: Range = Range {..},
    effects_versions: Range = Range {..},
    effects_resolved: Range = Range {..},
    resolved_entries: Range = Range {..},
    composites_entries: Range = Range {..},
}
reusable var leases: Lease[>..] = [];
var next_generation: u64 = 1;
reusable[] var pool_store_nodes: blot_check_types::Node[>..] = [];
reusable[] var pool_store_extra: u32[>..] = [];
reusable[] var pool_store_variables: blot_check_types::Variable[>..] = [];
reusable[] var pool_store_versions: blot_check_types::Version[>..] = [];
reusable[] var pool_store_operations: blot_check_types::Operation[>..] = [];
reusable[] var pool_store_operation_links: blot_check_types::OperationLink[>..] = [];
reusable[] var pool_store_quantifier_goals: blot_check_types::QuantifierGoals[>..] = [];
reusable[] var pool_store_quantifier_obligations: blot_check_types::Obligation[>..] = [];
reusable[] var pool_store_occurs_seen: u32[>..] = [];
reusable[] var pool_store_closed_row_index: blot_check_types::RowCertificate[>..] = [];
reusable[] var pool_store_closed_operation_index: blot_check_types::RowCertificate[>..] = [];
reusable[] var pool_store_variable_views: dictionary_slot<u64, u32>[>..] = [];
reusable[] var pool_store_associated_equations: dictionary_slot<u32, u32>[>..] = [];
reusable[] var pool_store_projection_resolutions: dictionary_slot<blot_check_types::ProjectionResolution, u32>[>..] = [];
reusable[] var pool_store_operation_chains: dictionary_slot<blot_check_types::OperationKey, blot_check_types::OperationChain>[>..] = [];
reusable[] var pool_effects_rows: blot_check_effects::Row[>..] = [];
reusable[] var pool_effects_labels: u32[>..] = [];
reusable[] var pool_effects_variables: blot_check_effects::Variable[>..] = [];
reusable[] var pool_effects_versions: blot_check_effects::Version[>..] = [];
reusable[] var pool_effects_resolved: dictionary_slot<u32, u32>[>..] = [];
reusable[] var pool_resolved_entries: blot_reuse_epoch_resolution_cache::Entry[>..] = [];
reusable[] var pool_composites_entries: blot_reuse_composite_resolution_cache::Entry[>..] = [];
fn suspendStore(store: blot_check_types::Store&) -> Snapshot, Error {
    if !blot_check_types::valid(store) || store.owner_id == 0 { return Snapshot {..}, Error.invalid_artifact; }
    if store.owner_id == 0 || next_generation == 0xffffffffffffffff || leases.len == 0xffffffff { return default<Snapshot>(), Error.type_limit; }
    var result = Snapshot { state: State {
        store_owner_id: store.owner_id,
        store_use_closed_rows: store.use_closed_rows,
        store_closed_rows: store.closed_rows,
        store_use_operation_rows: store.use_operation_rows,
        store_operation_rows: store.operation_rows,
        store_has_usage_types: store.has_usage_types,
        store_has_rank_types: store.has_rank_types,
        store_next_rigid_scope: store.next_rigid_scope,
        store_use_closed_graphs: store.use_closed_graphs,
        store_has_proof_kinds: store.has_proof_kinds,
        store_has_projections: store.has_projections,
        store_projection_limit: store.projection_limit,
        store_projection_steps: store.projection_steps,
        store_resolution_depth_limit: store.resolution_depth_limit,
        store_projection_exhausted: store.projection_exhausted,
        store_projection_resolution_types: store.projection_resolution_types,
        store_projection_resolution_rows: store.projection_resolution_rows,
        store_projection_resolution_limit: store.projection_resolution_limit,
        store_closed_generation: store.closed_generation,
        store_closed_effect_physical_epoch: store.closed_effect_physical_epoch,
        store_mutation_epoch: store.mutation_epoch,
        store_occurs_steps: store.occurs_steps,
        store_normalization: store.normalization,
        store_resolution_steps: store.resolution_steps,
        store_occurs_generation: store.occurs_generation,
        store_use_resolution_cache: store.use_resolution_cache,
        store_use_composite_cache: store.use_composite_cache,
        store_composite_min_growth: store.composite_min_growth,
        store_use_operation_shapes: store.use_operation_shapes,
        store_operation_shape_generation: store.operation_shape_generation,
        store_operation_shape_enabled: store.operation_shape_enabled,
        effects_physical_epoch: store.effects.physical_epoch,
        effects_mutation_epoch: store.effects.mutation_epoch,
        effects_resolved_physical: store.effects.resolved_physical,
        effects_resolved_high_water: store.effects.resolved_high_water,
        effects_use_resolution_cache: store.effects.use_resolution_cache,
        effects_next_position: store.effects.next_position,
        resolved_generation: store.resolved.generation,
        resolved_mutation: store.resolved.mutation,
        resolved_other: store.resolved.other,
        resolved_count: store.resolved.count,
        resolved_high_water: store.resolved.high_water,
        composites_physical: store.composites.physical,
        composites_effects_physical: store.composites.effects_physical,
        store_variable_views_count: store.variable_views.count,
        store_associated_equations_count: store.associated_equations.count,
        store_projection_resolutions_count: store.projection_resolutions.count,
        store_operation_chains_count: store.operation_chains.count,
        effects_resolved_count: store.effects.resolved.count, ..} , ..};
    let generation = next_generation; next_generation += 1; var lease = Lease { true, generation , ..};
    if store.nodes.len != 0 {
        let run = pool_store_nodes.alloc_slice(store.nodes.len);
        for value, index in store.nodes.items { run[index] = value; }
        let first: const blot_check_types::Node& = run[0];
        lease.store_nodes = Range { pool_store_nodes.index_of(first), run.len , ..}; result.store_nodes = run;
    }
    if store.extra.len != 0 {
        let run = pool_store_extra.alloc_slice(store.extra.len);
        for value, index in store.extra.items { run[index] = value; }
        let first: const u32& = run[0];
        lease.store_extra = Range { pool_store_extra.index_of(first), run.len , ..}; result.store_extra = run;
    }
    if store.variables.len != 0 {
        let run = pool_store_variables.alloc_slice(store.variables.len);
        for value, index in store.variables.items { run[index] = value; }
        let first: const blot_check_types::Variable& = run[0];
        lease.store_variables = Range { pool_store_variables.index_of(first), run.len , ..}; result.store_variables = run;
    }
    if store.versions.len != 0 {
        let run = pool_store_versions.alloc_slice(store.versions.len);
        for value, index in store.versions.items { run[index] = value; }
        let first: const blot_check_types::Version& = run[0];
        lease.store_versions = Range { pool_store_versions.index_of(first), run.len , ..}; result.store_versions = run;
    }
    if store.operations.len != 0 {
        let run = pool_store_operations.alloc_slice(store.operations.len);
        for value, index in store.operations.items { run[index] = value; }
        let first: const blot_check_types::Operation& = run[0];
        lease.store_operations = Range { pool_store_operations.index_of(first), run.len , ..}; result.store_operations = run;
    }
    if store.operation_links.len != 0 {
        let run = pool_store_operation_links.alloc_slice(store.operation_links.len);
        for value, index in store.operation_links.items { run[index] = value; }
        let first: const blot_check_types::OperationLink& = run[0];
        lease.store_operation_links = Range { pool_store_operation_links.index_of(first), run.len , ..}; result.store_operation_links = run;
    }
    if store.quantifier_goals.len != 0 {
        let run = pool_store_quantifier_goals.alloc_slice(store.quantifier_goals.len);
        for value, index in store.quantifier_goals.items { run[index] = value; }
        let first: const blot_check_types::QuantifierGoals& = run[0];
        lease.store_quantifier_goals = Range { pool_store_quantifier_goals.index_of(first), run.len , ..}; result.store_quantifier_goals = run;
    }
    if store.quantifier_obligations.len != 0 {
        let run = pool_store_quantifier_obligations.alloc_slice(store.quantifier_obligations.len);
        for value, index in store.quantifier_obligations.items { run[index] = value; }
        let first: const blot_check_types::Obligation& = run[0];
        lease.store_quantifier_obligations = Range { pool_store_quantifier_obligations.index_of(first), run.len , ..}; result.store_quantifier_obligations = run;
    }
    if store.occurs_seen.len != 0 {
        let run = pool_store_occurs_seen.alloc_slice(store.occurs_seen.len);
        for value, index in store.occurs_seen.items { run[index] = value; }
        let first: const u32& = run[0];
        lease.store_occurs_seen = Range { pool_store_occurs_seen.index_of(first), run.len , ..}; result.store_occurs_seen = run;
    }
    if store.closed_row_index.len != 0 {
        let run = pool_store_closed_row_index.alloc_slice(store.closed_row_index.len);
        for value, index in store.closed_row_index.items { run[index] = value; }
        let first: const blot_check_types::RowCertificate& = run[0];
        lease.store_closed_row_index = Range { pool_store_closed_row_index.index_of(first), run.len , ..}; result.store_closed_row_index = run;
    }
    if store.closed_operation_index.len != 0 {
        let run = pool_store_closed_operation_index.alloc_slice(store.closed_operation_index.len);
        for value, index in store.closed_operation_index.items { run[index] = value; }
        let first: const blot_check_types::RowCertificate& = run[0];
        lease.store_closed_operation_index = Range { pool_store_closed_operation_index.index_of(first), run.len , ..}; result.store_closed_operation_index = run;
    }
    if store.variable_views.slots.len != 0 {
        let run = pool_store_variable_views.alloc_slice(store.variable_views.slots.len);
        for value, index in store.variable_views.slots { run[index] = value; }
        let first: const dictionary_slot<u64, u32>& = run[0];
        lease.store_variable_views = Range { pool_store_variable_views.index_of(first), run.len , ..}; result.store_variable_views = run;
    }
    if store.associated_equations.slots.len != 0 {
        let run = pool_store_associated_equations.alloc_slice(store.associated_equations.slots.len);
        for value, index in store.associated_equations.slots { run[index] = value; }
        let first: const dictionary_slot<u32, u32>& = run[0];
        lease.store_associated_equations = Range { pool_store_associated_equations.index_of(first), run.len , ..}; result.store_associated_equations = run;
    }
    if store.projection_resolutions.slots.len != 0 {
        let run = pool_store_projection_resolutions.alloc_slice(store.projection_resolutions.slots.len);
        for value, index in store.projection_resolutions.slots { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::ProjectionResolution, u32>& = run[0];
        lease.store_projection_resolutions = Range { pool_store_projection_resolutions.index_of(first), run.len , ..}; result.store_projection_resolutions = run;
    }
    if store.operation_chains.slots.len != 0 {
        let run = pool_store_operation_chains.alloc_slice(store.operation_chains.slots.len);
        for value, index in store.operation_chains.slots { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::OperationKey, blot_check_types::OperationChain>& = run[0];
        lease.store_operation_chains = Range { pool_store_operation_chains.index_of(first), run.len , ..}; result.store_operation_chains = run;
    }
    if store.effects.rows.len != 0 {
        let run = pool_effects_rows.alloc_slice(store.effects.rows.len);
        for value, index in store.effects.rows.items { run[index] = value; }
        let first: const blot_check_effects::Row& = run[0];
        lease.effects_rows = Range { pool_effects_rows.index_of(first), run.len , ..}; result.effects_rows = run;
    }
    if store.effects.labels.len != 0 {
        let run = pool_effects_labels.alloc_slice(store.effects.labels.len);
        for value, index in store.effects.labels.items { run[index] = value; }
        let first: const u32& = run[0];
        lease.effects_labels = Range { pool_effects_labels.index_of(first), run.len , ..}; result.effects_labels = run;
    }
    if store.effects.variables.len != 0 {
        let run = pool_effects_variables.alloc_slice(store.effects.variables.len);
        for value, index in store.effects.variables.items { run[index] = value; }
        let first: const blot_check_effects::Variable& = run[0];
        lease.effects_variables = Range { pool_effects_variables.index_of(first), run.len , ..}; result.effects_variables = run;
    }
    if store.effects.versions.len != 0 {
        let run = pool_effects_versions.alloc_slice(store.effects.versions.len);
        for value, index in store.effects.versions.items { run[index] = value; }
        let first: const blot_check_effects::Version& = run[0];
        lease.effects_versions = Range { pool_effects_versions.index_of(first), run.len , ..}; result.effects_versions = run;
    }
    if store.effects.resolved.slots.len != 0 {
        let run = pool_effects_resolved.alloc_slice(store.effects.resolved.slots.len);
        for value, index in store.effects.resolved.slots { run[index] = value; }
        let first: const dictionary_slot<u32, u32>& = run[0];
        lease.effects_resolved = Range { pool_effects_resolved.index_of(first), run.len , ..}; result.effects_resolved = run;
    }
    if store.resolved.entries.len != 0 {
        let run = pool_resolved_entries.alloc_slice(store.resolved.entries.len);
        for value, index in store.resolved.entries.items { run[index] = value; }
        let first: const blot_reuse_epoch_resolution_cache::Entry& = run[0];
        lease.resolved_entries = Range { pool_resolved_entries.index_of(first), run.len , ..}; result.resolved_entries = run;
    }
    if store.composites.entries.len != 0 {
        let run = pool_composites_entries.alloc_slice(store.composites.entries.len);
        for value, index in store.composites.entries.items { run[index] = value; }
        let first: const blot_reuse_composite_resolution_cache::Entry& = run[0];
        lease.composites_entries = Range { pool_composites_entries.index_of(first), run.len , ..}; result.composites_entries = run;
    }
    let index = leases.alloc_index(lease); result.lease_index = (index + 1) as u32; result.generation = generation;
    store.nodes.clear();
    store.extra.clear();
    store.variables.clear();
    store.versions.clear();
    store.operations.clear();
    store.operation_links.clear();
    store.quantifier_goals.clear();
    store.quantifier_obligations.clear();
    store.occurs_seen.clear();
    store.closed_row_index.clear();
    store.closed_operation_index.clear();
    store.variable_views.clear();
    store.variable_views.count = 0;
    store.associated_equations.clear();
    store.associated_equations.count = 0;
    store.projection_resolutions.clear();
    store.projection_resolutions.count = 0;
    store.operation_chains.clear();
    store.operation_chains.count = 0;
    store.effects.rows.clear();
    store.effects.labels.clear();
    store.effects.variables.clear();
    store.effects.versions.clear();
    store.effects.resolved.clear();
    store.effects.resolved.count = 0;
    store.resolved.entries.clear();
    store.composites.entries.clear();
    store.owner_id = 0; return result, Error.none;
}
fn restoreStore(snapshot: Snapshot&, store: blot_check_types::Store&) -> Error {
    if !blot_check_types::valid(store) { return Error.invalid_artifact; }
    if snapshot.lease_index == 0 || snapshot.lease_index > leases.len { return Error.invalid_artifact; }
    let lease = leases[snapshot.lease_index - 1]; if !lease.live || lease.generation != snapshot.generation { return Error.invalid_artifact; }
    let error = store.nodes.restore(snapshot.store_nodes); if error != Error.none { return error; }
    let error = store.extra.restore(snapshot.store_extra); if error != Error.none { return error; }
    let error = store.variables.restore(snapshot.store_variables); if error != Error.none { return error; }
    let error = store.versions.restore(snapshot.store_versions); if error != Error.none { return error; }
    let error = store.operations.restore(snapshot.store_operations); if error != Error.none { return error; }
    let error = store.operation_links.restore(snapshot.store_operation_links); if error != Error.none { return error; }
    let error = store.quantifier_goals.restore(snapshot.store_quantifier_goals); if error != Error.none { return error; }
    let error = store.quantifier_obligations.restore(snapshot.store_quantifier_obligations); if error != Error.none { return error; }
    let error = store.occurs_seen.restore(snapshot.store_occurs_seen); if error != Error.none { return error; }
    let error = store.closed_row_index.restore(snapshot.store_closed_row_index); if error != Error.none { return error; }
    let error = store.closed_operation_index.restore(snapshot.store_closed_operation_index); if error != Error.none { return error; }
    let error = store.variable_views.restore(snapshot.store_variable_views, snapshot.state.store_variable_views_count); if error != Error.none { return error; }
    let error = store.associated_equations.restore(snapshot.store_associated_equations, snapshot.state.store_associated_equations_count); if error != Error.none { return error; }
    let error = store.projection_resolutions.restore(snapshot.store_projection_resolutions, snapshot.state.store_projection_resolutions_count); if error != Error.none { return error; }
    let error = store.operation_chains.restore(snapshot.store_operation_chains, snapshot.state.store_operation_chains_count); if error != Error.none { return error; }
    let error = store.effects.rows.restore(snapshot.effects_rows); if error != Error.none { return error; }
    let error = store.effects.labels.restore(snapshot.effects_labels); if error != Error.none { return error; }
    let error = store.effects.variables.restore(snapshot.effects_variables); if error != Error.none { return error; }
    let error = store.effects.versions.restore(snapshot.effects_versions); if error != Error.none { return error; }
    let error = store.effects.resolved.restore(snapshot.effects_resolved, snapshot.state.effects_resolved_count); if error != Error.none { return error; }
    store.resolved.entries.restore(snapshot.resolved_entries);
    store.composites.entries.restore(snapshot.composites_entries);
    store.owner_id = snapshot.state.store_owner_id;
    store.use_closed_rows = snapshot.state.store_use_closed_rows;
    store.closed_rows = snapshot.state.store_closed_rows;
    store.use_operation_rows = snapshot.state.store_use_operation_rows;
    store.operation_rows = snapshot.state.store_operation_rows;
    store.has_usage_types = snapshot.state.store_has_usage_types;
    store.has_rank_types = snapshot.state.store_has_rank_types;
    store.next_rigid_scope = snapshot.state.store_next_rigid_scope;
    store.use_closed_graphs = snapshot.state.store_use_closed_graphs;
    store.has_proof_kinds = snapshot.state.store_has_proof_kinds;
    store.has_projections = snapshot.state.store_has_projections;
    store.projection_limit = snapshot.state.store_projection_limit;
    store.projection_steps = snapshot.state.store_projection_steps;
    store.resolution_depth_limit = snapshot.state.store_resolution_depth_limit;
    store.projection_exhausted = snapshot.state.store_projection_exhausted;
    store.projection_resolution_types = snapshot.state.store_projection_resolution_types;
    store.projection_resolution_rows = snapshot.state.store_projection_resolution_rows;
    store.projection_resolution_limit = snapshot.state.store_projection_resolution_limit;
    store.closed_generation = snapshot.state.store_closed_generation;
    store.closed_effect_physical_epoch = snapshot.state.store_closed_effect_physical_epoch;
    store.mutation_epoch = snapshot.state.store_mutation_epoch;
    store.occurs_steps = snapshot.state.store_occurs_steps;
    store.normalization = snapshot.state.store_normalization;
    store.resolution_steps = snapshot.state.store_resolution_steps;
    store.occurs_generation = snapshot.state.store_occurs_generation;
    store.use_resolution_cache = snapshot.state.store_use_resolution_cache;
    store.use_composite_cache = snapshot.state.store_use_composite_cache;
    store.composite_min_growth = snapshot.state.store_composite_min_growth;
    store.use_operation_shapes = snapshot.state.store_use_operation_shapes;
    store.operation_shape_generation = snapshot.state.store_operation_shape_generation;
    store.operation_shape_enabled = snapshot.state.store_operation_shape_enabled;
    store.effects.physical_epoch = snapshot.state.effects_physical_epoch;
    store.effects.mutation_epoch = snapshot.state.effects_mutation_epoch;
    store.effects.resolved_physical = snapshot.state.effects_resolved_physical;
    store.effects.resolved_high_water = snapshot.state.effects_resolved_high_water;
    store.effects.use_resolution_cache = snapshot.state.effects_use_resolution_cache;
    store.effects.next_position = snapshot.state.effects_next_position;
    store.resolved.generation = snapshot.state.resolved_generation;
    store.resolved.mutation = snapshot.state.resolved_mutation;
    store.resolved.other = snapshot.state.resolved_other;
    store.resolved.count = snapshot.state.resolved_count;
    store.resolved.high_water = snapshot.state.resolved_high_water;
    store.composites.physical = snapshot.state.composites_physical;
    store.composites.effects_physical = snapshot.state.composites_effects_physical;
    return deinit(snapshot);
}
fn deinit(snapshot: Snapshot&) -> Error {
    if snapshot.lease_index == 0 { return Error.none; }
    if snapshot.lease_index > leases.len { return Error.invalid_artifact; } let index = snapshot.lease_index - 1; let lease = leases[index];
    if !lease.live || lease.generation != snapshot.generation { return Error.invalid_artifact; } leases[index].live = false;
    if lease.store_nodes.len != 0 { pool_store_nodes.free_slice(pool_store_nodes[lease.store_nodes.start..lease.store_nodes.start + lease.store_nodes.len]); }
    if lease.store_extra.len != 0 { pool_store_extra.free_slice(pool_store_extra[lease.store_extra.start..lease.store_extra.start + lease.store_extra.len]); }
    if lease.store_variables.len != 0 { pool_store_variables.free_slice(pool_store_variables[lease.store_variables.start..lease.store_variables.start + lease.store_variables.len]); }
    if lease.store_versions.len != 0 { pool_store_versions.free_slice(pool_store_versions[lease.store_versions.start..lease.store_versions.start + lease.store_versions.len]); }
    if lease.store_operations.len != 0 { pool_store_operations.free_slice(pool_store_operations[lease.store_operations.start..lease.store_operations.start + lease.store_operations.len]); }
    if lease.store_operation_links.len != 0 { pool_store_operation_links.free_slice(pool_store_operation_links[lease.store_operation_links.start..lease.store_operation_links.start + lease.store_operation_links.len]); }
    if lease.store_quantifier_goals.len != 0 { pool_store_quantifier_goals.free_slice(pool_store_quantifier_goals[lease.store_quantifier_goals.start..lease.store_quantifier_goals.start + lease.store_quantifier_goals.len]); }
    if lease.store_quantifier_obligations.len != 0 { pool_store_quantifier_obligations.free_slice(pool_store_quantifier_obligations[lease.store_quantifier_obligations.start..lease.store_quantifier_obligations.start + lease.store_quantifier_obligations.len]); }
    if lease.store_occurs_seen.len != 0 { pool_store_occurs_seen.free_slice(pool_store_occurs_seen[lease.store_occurs_seen.start..lease.store_occurs_seen.start + lease.store_occurs_seen.len]); }
    if lease.store_closed_row_index.len != 0 { pool_store_closed_row_index.free_slice(pool_store_closed_row_index[lease.store_closed_row_index.start..lease.store_closed_row_index.start + lease.store_closed_row_index.len]); }
    if lease.store_closed_operation_index.len != 0 { pool_store_closed_operation_index.free_slice(pool_store_closed_operation_index[lease.store_closed_operation_index.start..lease.store_closed_operation_index.start + lease.store_closed_operation_index.len]); }
    if lease.store_variable_views.len != 0 { pool_store_variable_views.free_slice(pool_store_variable_views[lease.store_variable_views.start..lease.store_variable_views.start + lease.store_variable_views.len]); }
    if lease.store_associated_equations.len != 0 { pool_store_associated_equations.free_slice(pool_store_associated_equations[lease.store_associated_equations.start..lease.store_associated_equations.start + lease.store_associated_equations.len]); }
    if lease.store_projection_resolutions.len != 0 { pool_store_projection_resolutions.free_slice(pool_store_projection_resolutions[lease.store_projection_resolutions.start..lease.store_projection_resolutions.start + lease.store_projection_resolutions.len]); }
    if lease.store_operation_chains.len != 0 { pool_store_operation_chains.free_slice(pool_store_operation_chains[lease.store_operation_chains.start..lease.store_operation_chains.start + lease.store_operation_chains.len]); }
    if lease.effects_rows.len != 0 { pool_effects_rows.free_slice(pool_effects_rows[lease.effects_rows.start..lease.effects_rows.start + lease.effects_rows.len]); }
    if lease.effects_labels.len != 0 { pool_effects_labels.free_slice(pool_effects_labels[lease.effects_labels.start..lease.effects_labels.start + lease.effects_labels.len]); }
    if lease.effects_variables.len != 0 { pool_effects_variables.free_slice(pool_effects_variables[lease.effects_variables.start..lease.effects_variables.start + lease.effects_variables.len]); }
    if lease.effects_versions.len != 0 { pool_effects_versions.free_slice(pool_effects_versions[lease.effects_versions.start..lease.effects_versions.start + lease.effects_versions.len]); }
    if lease.effects_resolved.len != 0 { pool_effects_resolved.free_slice(pool_effects_resolved[lease.effects_resolved.start..lease.effects_resolved.start + lease.effects_resolved.len]); }
    if lease.resolved_entries.len != 0 { pool_resolved_entries.free_slice(pool_resolved_entries[lease.resolved_entries.start..lease.resolved_entries.start + lease.resolved_entries.len]); }
    if lease.composites_entries.len != 0 { pool_composites_entries.free_slice(pool_composites_entries[lease.composites_entries.start..lease.composites_entries.start + lease.composites_entries.len]); }
    leases.free(index); snapshot.lease_index = 0; snapshot.generation = 0;
    snapshot.store_nodes = [];
    snapshot.store_extra = [];
    snapshot.store_variables = [];
    snapshot.store_versions = [];
    snapshot.store_operations = [];
    snapshot.store_operation_links = [];
    snapshot.store_quantifier_goals = [];
    snapshot.store_quantifier_obligations = [];
    snapshot.store_occurs_seen = [];
    snapshot.store_closed_row_index = [];
    snapshot.store_closed_operation_index = [];
    snapshot.store_variable_views = [];
    snapshot.store_associated_equations = [];
    snapshot.store_projection_resolutions = [];
    snapshot.store_operation_chains = [];
    snapshot.effects_rows = [];
    snapshot.effects_labels = [];
    snapshot.effects_variables = [];
    snapshot.effects_versions = [];
    snapshot.effects_resolved = [];
    snapshot.resolved_entries = [];
    snapshot.composites_entries = [];
    return Error.none;
}
fn cloneSnapshot(source: const Snapshot&) -> Snapshot, Error {
    if source.lease_index == 0 || source.lease_index > leases.len { return default<Snapshot>(), Error.invalid_artifact; }
    let owned = leases[source.lease_index - 1]; if !owned.live || owned.generation != source.generation { return default<Snapshot>(), Error.invalid_artifact; }
    if next_generation == 0xffffffffffffffff || leases.len == 0xffffffff { return default<Snapshot>(), Error.type_limit; }
    let generation = next_generation; next_generation += 1; var lease = Lease { true, generation , ..}; var result = Snapshot { state: source.state , ..};
    if source.store_nodes.len != 0 {
        let run = pool_store_nodes.alloc_slice(source.store_nodes.len);
        for value, index in source.store_nodes { run[index] = value; }
        let first: const blot_check_types::Node& = run[0];
        lease.store_nodes = Range { pool_store_nodes.index_of(first), run.len , ..}; result.store_nodes = run;
    }
    if source.store_extra.len != 0 {
        let run = pool_store_extra.alloc_slice(source.store_extra.len);
        for value, index in source.store_extra { run[index] = value; }
        let first: const u32& = run[0];
        lease.store_extra = Range { pool_store_extra.index_of(first), run.len , ..}; result.store_extra = run;
    }
    if source.store_variables.len != 0 {
        let run = pool_store_variables.alloc_slice(source.store_variables.len);
        for value, index in source.store_variables { run[index] = value; }
        let first: const blot_check_types::Variable& = run[0];
        lease.store_variables = Range { pool_store_variables.index_of(first), run.len , ..}; result.store_variables = run;
    }
    if source.store_versions.len != 0 {
        let run = pool_store_versions.alloc_slice(source.store_versions.len);
        for value, index in source.store_versions { run[index] = value; }
        let first: const blot_check_types::Version& = run[0];
        lease.store_versions = Range { pool_store_versions.index_of(first), run.len , ..}; result.store_versions = run;
    }
    if source.store_operations.len != 0 {
        let run = pool_store_operations.alloc_slice(source.store_operations.len);
        for value, index in source.store_operations { run[index] = value; }
        let first: const blot_check_types::Operation& = run[0];
        lease.store_operations = Range { pool_store_operations.index_of(first), run.len , ..}; result.store_operations = run;
    }
    if source.store_operation_links.len != 0 {
        let run = pool_store_operation_links.alloc_slice(source.store_operation_links.len);
        for value, index in source.store_operation_links { run[index] = value; }
        let first: const blot_check_types::OperationLink& = run[0];
        lease.store_operation_links = Range { pool_store_operation_links.index_of(first), run.len , ..}; result.store_operation_links = run;
    }
    if source.store_quantifier_goals.len != 0 {
        let run = pool_store_quantifier_goals.alloc_slice(source.store_quantifier_goals.len);
        for value, index in source.store_quantifier_goals { run[index] = value; }
        let first: const blot_check_types::QuantifierGoals& = run[0];
        lease.store_quantifier_goals = Range { pool_store_quantifier_goals.index_of(first), run.len , ..}; result.store_quantifier_goals = run;
    }
    if source.store_quantifier_obligations.len != 0 {
        let run = pool_store_quantifier_obligations.alloc_slice(source.store_quantifier_obligations.len);
        for value, index in source.store_quantifier_obligations { run[index] = value; }
        let first: const blot_check_types::Obligation& = run[0];
        lease.store_quantifier_obligations = Range { pool_store_quantifier_obligations.index_of(first), run.len , ..}; result.store_quantifier_obligations = run;
    }
    if source.store_occurs_seen.len != 0 {
        let run = pool_store_occurs_seen.alloc_slice(source.store_occurs_seen.len);
        for value, index in source.store_occurs_seen { run[index] = value; }
        let first: const u32& = run[0];
        lease.store_occurs_seen = Range { pool_store_occurs_seen.index_of(first), run.len , ..}; result.store_occurs_seen = run;
    }
    if source.store_closed_row_index.len != 0 {
        let run = pool_store_closed_row_index.alloc_slice(source.store_closed_row_index.len);
        for value, index in source.store_closed_row_index { run[index] = value; }
        let first: const blot_check_types::RowCertificate& = run[0];
        lease.store_closed_row_index = Range { pool_store_closed_row_index.index_of(first), run.len , ..}; result.store_closed_row_index = run;
    }
    if source.store_closed_operation_index.len != 0 {
        let run = pool_store_closed_operation_index.alloc_slice(source.store_closed_operation_index.len);
        for value, index in source.store_closed_operation_index { run[index] = value; }
        let first: const blot_check_types::RowCertificate& = run[0];
        lease.store_closed_operation_index = Range { pool_store_closed_operation_index.index_of(first), run.len , ..}; result.store_closed_operation_index = run;
    }
    if source.store_variable_views.len != 0 {
        let run = pool_store_variable_views.alloc_slice(source.store_variable_views.len);
        for value, index in source.store_variable_views { run[index] = value; }
        let first: const dictionary_slot<u64, u32>& = run[0];
        lease.store_variable_views = Range { pool_store_variable_views.index_of(first), run.len , ..}; result.store_variable_views = run;
    }
    if source.store_associated_equations.len != 0 {
        let run = pool_store_associated_equations.alloc_slice(source.store_associated_equations.len);
        for value, index in source.store_associated_equations { run[index] = value; }
        let first: const dictionary_slot<u32, u32>& = run[0];
        lease.store_associated_equations = Range { pool_store_associated_equations.index_of(first), run.len , ..}; result.store_associated_equations = run;
    }
    if source.store_projection_resolutions.len != 0 {
        let run = pool_store_projection_resolutions.alloc_slice(source.store_projection_resolutions.len);
        for value, index in source.store_projection_resolutions { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::ProjectionResolution, u32>& = run[0];
        lease.store_projection_resolutions = Range { pool_store_projection_resolutions.index_of(first), run.len , ..}; result.store_projection_resolutions = run;
    }
    if source.store_operation_chains.len != 0 {
        let run = pool_store_operation_chains.alloc_slice(source.store_operation_chains.len);
        for value, index in source.store_operation_chains { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::OperationKey, blot_check_types::OperationChain>& = run[0];
        lease.store_operation_chains = Range { pool_store_operation_chains.index_of(first), run.len , ..}; result.store_operation_chains = run;
    }
    if source.effects_rows.len != 0 {
        let run = pool_effects_rows.alloc_slice(source.effects_rows.len);
        for value, index in source.effects_rows { run[index] = value; }
        let first: const blot_check_effects::Row& = run[0];
        lease.effects_rows = Range { pool_effects_rows.index_of(first), run.len , ..}; result.effects_rows = run;
    }
    if source.effects_labels.len != 0 {
        let run = pool_effects_labels.alloc_slice(source.effects_labels.len);
        for value, index in source.effects_labels { run[index] = value; }
        let first: const u32& = run[0];
        lease.effects_labels = Range { pool_effects_labels.index_of(first), run.len , ..}; result.effects_labels = run;
    }
    if source.effects_variables.len != 0 {
        let run = pool_effects_variables.alloc_slice(source.effects_variables.len);
        for value, index in source.effects_variables { run[index] = value; }
        let first: const blot_check_effects::Variable& = run[0];
        lease.effects_variables = Range { pool_effects_variables.index_of(first), run.len , ..}; result.effects_variables = run;
    }
    if source.effects_versions.len != 0 {
        let run = pool_effects_versions.alloc_slice(source.effects_versions.len);
        for value, index in source.effects_versions { run[index] = value; }
        let first: const blot_check_effects::Version& = run[0];
        lease.effects_versions = Range { pool_effects_versions.index_of(first), run.len , ..}; result.effects_versions = run;
    }
    if source.effects_resolved.len != 0 {
        let run = pool_effects_resolved.alloc_slice(source.effects_resolved.len);
        for value, index in source.effects_resolved { run[index] = value; }
        let first: const dictionary_slot<u32, u32>& = run[0];
        lease.effects_resolved = Range { pool_effects_resolved.index_of(first), run.len , ..}; result.effects_resolved = run;
    }
    if source.resolved_entries.len != 0 {
        let run = pool_resolved_entries.alloc_slice(source.resolved_entries.len);
        for value, index in source.resolved_entries { run[index] = value; }
        let first: const blot_reuse_epoch_resolution_cache::Entry& = run[0];
        lease.resolved_entries = Range { pool_resolved_entries.index_of(first), run.len , ..}; result.resolved_entries = run;
    }
    if source.composites_entries.len != 0 {
        let run = pool_composites_entries.alloc_slice(source.composites_entries.len);
        for value, index in source.composites_entries { run[index] = value; }
        let first: const blot_reuse_composite_resolution_cache::Entry& = run[0];
        lease.composites_entries = Range { pool_composites_entries.index_of(first), run.len , ..}; result.composites_entries = run;
    }
    let index = leases.alloc_index(lease); result.lease_index = (index + 1) as u32; result.generation = generation; return result, Error.none;
}
// Packed C.2 typed-run footprints; state and lease metadata are separate.
fn snapshotOwnedBytes(snapshot: const Snapshot&) -> i64 {
    var total: i64 = 0;
    if snapshot.store_nodes.len > (9223372036854775807 - total) / 16 { return 9223372036854775807; }
    total += snapshot.store_nodes.len * 16;
    if snapshot.store_extra.len > (9223372036854775807 - total) / 4 { return 9223372036854775807; }
    total += snapshot.store_extra.len * 4;
    if snapshot.store_variables.len > (9223372036854775807 - total) / 13 { return 9223372036854775807; }
    total += snapshot.store_variables.len * 13;
    if snapshot.store_versions.len > (9223372036854775807 - total) / 20 { return 9223372036854775807; }
    total += snapshot.store_versions.len * 20;
    if snapshot.store_operations.len > (9223372036854775807 - total) / 24 { return 9223372036854775807; }
    total += snapshot.store_operations.len * 24;
    if snapshot.store_operation_links.len > (9223372036854775807 - total) / 16 { return 9223372036854775807; }
    total += snapshot.store_operation_links.len * 16;
    if snapshot.store_quantifier_goals.len > (9223372036854775807 - total) / 12 { return 9223372036854775807; }
    total += snapshot.store_quantifier_goals.len * 12;
    if snapshot.store_quantifier_obligations.len > (9223372036854775807 - total) / 48 { return 9223372036854775807; }
    total += snapshot.store_quantifier_obligations.len * 48;
    if snapshot.store_occurs_seen.len > (9223372036854775807 - total) / 4 { return 9223372036854775807; }
    total += snapshot.store_occurs_seen.len * 4;
    if snapshot.store_closed_row_index.len > (9223372036854775807 - total) / 4 { return 9223372036854775807; }
    total += snapshot.store_closed_row_index.len * 4;
    if snapshot.store_closed_operation_index.len > (9223372036854775807 - total) / 4 { return 9223372036854775807; }
    total += snapshot.store_closed_operation_index.len * 4;
    if snapshot.store_variable_views.len > (9223372036854775807 - total) / 16 { return 9223372036854775807; }
    total += snapshot.store_variable_views.len * 16;
    if snapshot.store_associated_equations.len > (9223372036854775807 - total) / 12 { return 9223372036854775807; }
    total += snapshot.store_associated_equations.len * 12;
    if snapshot.store_projection_resolutions.len > (9223372036854775807 - total) / 20 { return 9223372036854775807; }
    total += snapshot.store_projection_resolutions.len * 20;
    if snapshot.store_operation_chains.len > (9223372036854775807 - total) / 40 { return 9223372036854775807; }
    total += snapshot.store_operation_chains.len * 40;
    if snapshot.effects_rows.len > (9223372036854775807 - total) / 17 { return 9223372036854775807; }
    total += snapshot.effects_rows.len * 17;
    if snapshot.effects_labels.len > (9223372036854775807 - total) / 4 { return 9223372036854775807; }
    total += snapshot.effects_labels.len * 4;
    if snapshot.effects_variables.len > (9223372036854775807 - total) / 8 { return 9223372036854775807; }
    total += snapshot.effects_variables.len * 8;
    if snapshot.effects_versions.len > (9223372036854775807 - total) / 32 { return 9223372036854775807; }
    total += snapshot.effects_versions.len * 32;
    if snapshot.effects_resolved.len > (9223372036854775807 - total) / 12 { return 9223372036854775807; }
    total += snapshot.effects_resolved.len * 12;
    if snapshot.resolved_entries.len > (9223372036854775807 - total) / 12 { return 9223372036854775807; }
    total += snapshot.resolved_entries.len * 12;
    if snapshot.composites_entries.len > (9223372036854775807 - total) / 90 { return 9223372036854775807; }
    total += snapshot.composites_entries.len * 90;
    return total;
}
// State fixed fields + index/generation + 22 immutable slice headers.
fn snapshotMetadataBytes() -> i64 { return 3479 + 4 + 8 + 22 * 16; }
