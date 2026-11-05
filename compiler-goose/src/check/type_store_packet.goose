// Complete copied-process store images. All maps/cache entries are ID-only;
// allocator/header lease generations remain local while logical epochs survive.
namespace blot_check_type_store_snapshot;
import check.effects;
import check.types;
import reuse.composite_resolution_cache;
import reuse.epoch_resolution_cache;
import support.error;
import support.native;

import .type_store_snapshot;
fn captureStore(store: const blot_check_types::Store&) -> Snapshot, Error {
    if !blot_check_types::valid(store) || store.owner_id == 0 { return Snapshot {..}, blot_error::Error.invalid_artifact; }
    if store.owner_id == 0 || next_generation == 0xffffffffffffffff || leases.len == 0xffffffff { return default<Snapshot>(), blot_error::Error.type_limit; }
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
        let first: const blot_check_types::Node&  = run[0];
        lease.store_nodes = Range { pool_store_nodes.index_of(first), run.len , ..}; result.store_nodes = run;
    }
    if store.extra.len != 0 {
        let run = pool_store_extra.alloc_slice(store.extra.len);
        for value, index in store.extra.items { run[index] = value; }
        let first: const u32&  = run[0];
        lease.store_extra = Range { pool_store_extra.index_of(first), run.len , ..}; result.store_extra = run;
    }
    if store.variables.len != 0 {
        let run = pool_store_variables.alloc_slice(store.variables.len);
        for value, index in store.variables.items { run[index] = value; }
        let first: const blot_check_types::Variable&  = run[0];
        lease.store_variables = Range { pool_store_variables.index_of(first), run.len , ..}; result.store_variables = run;
    }
    if store.versions.len != 0 {
        let run = pool_store_versions.alloc_slice(store.versions.len);
        for value, index in store.versions.items { run[index] = value; }
        let first: const blot_check_types::Version&  = run[0];
        lease.store_versions = Range { pool_store_versions.index_of(first), run.len , ..}; result.store_versions = run;
    }
    if store.operations.len != 0 {
        let run = pool_store_operations.alloc_slice(store.operations.len);
        for value, index in store.operations.items { run[index] = value; }
        let first: const blot_check_types::Operation&  = run[0];
        lease.store_operations = Range { pool_store_operations.index_of(first), run.len , ..}; result.store_operations = run;
    }
    if store.operation_links.len != 0 {
        let run = pool_store_operation_links.alloc_slice(store.operation_links.len);
        for value, index in store.operation_links.items { run[index] = value; }
        let first: const blot_check_types::OperationLink&  = run[0];
        lease.store_operation_links = Range { pool_store_operation_links.index_of(first), run.len , ..}; result.store_operation_links = run;
    }
    if store.quantifier_goals.len != 0 {
        let run = pool_store_quantifier_goals.alloc_slice(store.quantifier_goals.len);
        for value, index in store.quantifier_goals.items { run[index] = value; }
        let first: const blot_check_types::QuantifierGoals&  = run[0];
        lease.store_quantifier_goals = Range { pool_store_quantifier_goals.index_of(first), run.len , ..}; result.store_quantifier_goals = run;
    }
    if store.quantifier_obligations.len != 0 {
        let run = pool_store_quantifier_obligations.alloc_slice(store.quantifier_obligations.len);
        for value, index in store.quantifier_obligations.items { run[index] = value; }
        let first: const blot_check_types::Obligation&  = run[0];
        lease.store_quantifier_obligations = Range { pool_store_quantifier_obligations.index_of(first), run.len , ..}; result.store_quantifier_obligations = run;
    }
    if store.occurs_seen.len != 0 {
        let run = pool_store_occurs_seen.alloc_slice(store.occurs_seen.len);
        for value, index in store.occurs_seen.items { run[index] = value; }
        let first: const u32&  = run[0];
        lease.store_occurs_seen = Range { pool_store_occurs_seen.index_of(first), run.len , ..}; result.store_occurs_seen = run;
    }
    if store.closed_row_index.len != 0 {
        let run = pool_store_closed_row_index.alloc_slice(store.closed_row_index.len);
        for value, index in store.closed_row_index.items { run[index] = value; }
        let first: const blot_check_types::RowCertificate&  = run[0];
        lease.store_closed_row_index = Range { pool_store_closed_row_index.index_of(first), run.len , ..}; result.store_closed_row_index = run;
    }
    if store.closed_operation_index.len != 0 {
        let run = pool_store_closed_operation_index.alloc_slice(store.closed_operation_index.len);
        for value, index in store.closed_operation_index.items { run[index] = value; }
        let first: const blot_check_types::RowCertificate&  = run[0];
        lease.store_closed_operation_index = Range { pool_store_closed_operation_index.index_of(first), run.len , ..}; result.store_closed_operation_index = run;
    }
    if store.variable_views.slots.len != 0 {
        let run = pool_store_variable_views.alloc_slice(store.variable_views.slots.len);
        for value, index in store.variable_views.slots { run[index] = value; }
        let first: const dictionary_slot<u64, u32>&  = run[0];
        lease.store_variable_views = Range { pool_store_variable_views.index_of(first), run.len , ..}; result.store_variable_views = run;
    }
    if store.associated_equations.slots.len != 0 {
        let run = pool_store_associated_equations.alloc_slice(store.associated_equations.slots.len);
        for value, index in store.associated_equations.slots { run[index] = value; }
        let first: const dictionary_slot<u32, u32>&  = run[0];
        lease.store_associated_equations = Range { pool_store_associated_equations.index_of(first), run.len , ..}; result.store_associated_equations = run;
    }
    if store.projection_resolutions.slots.len != 0 {
        let run = pool_store_projection_resolutions.alloc_slice(store.projection_resolutions.slots.len);
        for value, index in store.projection_resolutions.slots { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::ProjectionResolution, u32>&  = run[0];
        lease.store_projection_resolutions = Range { pool_store_projection_resolutions.index_of(first), run.len , ..}; result.store_projection_resolutions = run;
    }
    if store.operation_chains.slots.len != 0 {
        let run = pool_store_operation_chains.alloc_slice(store.operation_chains.slots.len);
        for value, index in store.operation_chains.slots { run[index] = value; }
        let first: const dictionary_slot<blot_check_types::OperationKey, blot_check_types::OperationChain>&  = run[0];
        lease.store_operation_chains = Range { pool_store_operation_chains.index_of(first), run.len , ..}; result.store_operation_chains = run;
    }
    if store.effects.rows.len != 0 {
        let run = pool_effects_rows.alloc_slice(store.effects.rows.len);
        for value, index in store.effects.rows.items { run[index] = value; }
        let first: const blot_check_effects::Row&  = run[0];
        lease.effects_rows = Range { pool_effects_rows.index_of(first), run.len , ..}; result.effects_rows = run;
    }
    if store.effects.labels.len != 0 {
        let run = pool_effects_labels.alloc_slice(store.effects.labels.len);
        for value, index in store.effects.labels.items { run[index] = value; }
        let first: const u32&  = run[0];
        lease.effects_labels = Range { pool_effects_labels.index_of(first), run.len , ..}; result.effects_labels = run;
    }
    if store.effects.variables.len != 0 {
        let run = pool_effects_variables.alloc_slice(store.effects.variables.len);
        for value, index in store.effects.variables.items { run[index] = value; }
        let first: const blot_check_effects::Variable&  = run[0];
        lease.effects_variables = Range { pool_effects_variables.index_of(first), run.len , ..}; result.effects_variables = run;
    }
    if store.effects.versions.len != 0 {
        let run = pool_effects_versions.alloc_slice(store.effects.versions.len);
        for value, index in store.effects.versions.items { run[index] = value; }
        let first: const blot_check_effects::Version&  = run[0];
        lease.effects_versions = Range { pool_effects_versions.index_of(first), run.len , ..}; result.effects_versions = run;
    }
    if store.effects.resolved.slots.len != 0 {
        let run = pool_effects_resolved.alloc_slice(store.effects.resolved.slots.len);
        for value, index in store.effects.resolved.slots { run[index] = value; }
        let first: const dictionary_slot<u32, u32>&  = run[0];
        lease.effects_resolved = Range { pool_effects_resolved.index_of(first), run.len , ..}; result.effects_resolved = run;
    }
    if store.resolved.entries.len != 0 {
        let run = pool_resolved_entries.alloc_slice(store.resolved.entries.len);
        for value, index in store.resolved.entries.items { run[index] = value; }
        let first: const blot_reuse_epoch_resolution_cache::Entry&  = run[0];
        lease.resolved_entries = Range { pool_resolved_entries.index_of(first), run.len , ..}; result.resolved_entries = run;
    }
    if store.composites.entries.len != 0 {
        let run = pool_composites_entries.alloc_slice(store.composites.entries.len);
        for value, index in store.composites.entries.items { run[index] = value; }
        let first: const blot_reuse_composite_resolution_cache::Entry&  = run[0];
        lease.composites_entries = Range { pool_composites_entries.index_of(first), run.len , ..}; result.composites_entries = run;
    }
    let index = leases.alloc_index(lease); result.lease_index = (index + 1) as u32; result.generation = generation;
    return result,blot_error::Error.none;
}

fn restorePacketStore(snapshot: const Snapshot&, store: blot_check_types::Store&) -> Error {
    if !blot_check_types::valid(store) { return blot_error::Error.invalid_artifact; }
    let error = store.nodes.restore(snapshot.store_nodes); if error != blot_error::Error.none { return error; }
    let error = store.extra.restore(snapshot.store_extra); if error != blot_error::Error.none { return error; }
    let error = store.variables.restore(snapshot.store_variables); if error != blot_error::Error.none { return error; }
    let error = store.versions.restore(snapshot.store_versions); if error != blot_error::Error.none { return error; }
    let error = store.operations.restore(snapshot.store_operations); if error != blot_error::Error.none { return error; }
    let error = store.operation_links.restore(snapshot.store_operation_links); if error != blot_error::Error.none { return error; }
    let error = store.quantifier_goals.restore(snapshot.store_quantifier_goals); if error != blot_error::Error.none { return error; }
    let error = store.quantifier_obligations.restore(snapshot.store_quantifier_obligations); if error != blot_error::Error.none { return error; }
    let error = store.occurs_seen.restore(snapshot.store_occurs_seen); if error != blot_error::Error.none { return error; }
    let error = store.closed_row_index.restore(snapshot.store_closed_row_index); if error != blot_error::Error.none { return error; }
    let error = store.closed_operation_index.restore(snapshot.store_closed_operation_index); if error != blot_error::Error.none { return error; }
    let error = store.variable_views.restore(snapshot.store_variable_views, snapshot.state.store_variable_views_count); if error != blot_error::Error.none { return error; }
    let error = store.associated_equations.restore(snapshot.store_associated_equations, snapshot.state.store_associated_equations_count); if error != blot_error::Error.none { return error; }
    let error = store.projection_resolutions.restore(snapshot.store_projection_resolutions, snapshot.state.store_projection_resolutions_count); if error != blot_error::Error.none { return error; }
    let error = store.operation_chains.restore(snapshot.store_operation_chains, snapshot.state.store_operation_chains_count); if error != blot_error::Error.none { return error; }
    let error = store.effects.rows.restore(snapshot.effects_rows); if error != blot_error::Error.none { return error; }
    let error = store.effects.labels.restore(snapshot.effects_labels); if error != blot_error::Error.none { return error; }
    let error = store.effects.variables.restore(snapshot.effects_variables); if error != blot_error::Error.none { return error; }
    let error = store.effects.versions.restore(snapshot.effects_versions); if error != blot_error::Error.none { return error; }
    let error = store.effects.resolved.restore(snapshot.effects_resolved, snapshot.state.effects_resolved_count); if error != blot_error::Error.none { return error; }
    store.resolved.entries.restore(snapshot.resolved_entries);
    store.composites.entries.restore(snapshot.composites_entries);
    store.owner_id = blot_native::fresh_owner_id();
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
    return blot_error::Error.none;
}
