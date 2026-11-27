// Checked type store images for copied workers. Logical IDs survive the
// handoff. The receiving process creates a fresh owner for the store.
namespace squid_check_type_store_snapshot;
import check.types;
import support.error;
import support.native;

import .type_store_snapshot;
// The checked packet borrows these lanes only while encoding. Inference's
// resolution caches and occurs-check scratch can be rebuilt in the receiver.
fn viewPacketStore(store: const squid_check_types::Store&) -> Snapshot, Error {
    if !squid_check_types::valid(store) || store.owner_id == 0 {
        return Snapshot {..}, squid_error::Error.invalid_artifact;
    }
    return Snapshot {
        state: State {
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
            store_use_resolution_cache: store.use_resolution_cache,
            store_use_composite_cache: store.use_composite_cache,
            store_composite_min_growth: store.composite_min_growth,
            store_use_operation_shapes: store.use_operation_shapes,
            store_operation_shape_generation: store.operation_shape_generation,
            store_operation_shape_enabled: store.operation_shape_enabled,
            effects_physical_epoch: store.effects.physical_epoch,
            effects_mutation_epoch: store.effects.mutation_epoch,
            effects_use_resolution_cache: store.effects.use_resolution_cache,
            effects_next_position: store.effects.next_position,
            store_variable_views_count: store.variable_views.count,
            store_associated_equations_count: store.associated_equations.count,
            store_projection_resolutions_count: store.projection_resolutions.count,
            store_operation_chains_count: store.operation_chains.count,
            effects_resolved_count: 0,
            ..
        },
        store_nodes: store.nodes.items,
        store_extra: store.extra.items,
        store_variables: store.variables.items,
        store_versions: store.versions.items,
        store_operations: store.operations.items,
        store_operation_links: store.operation_links.items,
        store_closed_row_index: store.closed_row_index.items,
        store_closed_operation_index: store.closed_operation_index.items,
        store_variable_views: store.variable_views.slots,
        store_associated_equations: store.associated_equations.slots,
        store_projection_resolutions: store.projection_resolutions.slots,
        store_operation_chains: store.operation_chains.slots,
        effects_rows: store.effects.rows.items,
        effects_labels: store.effects.labels.items,
        effects_variables: store.effects.variables.items,
        effects_versions: store.effects.versions.items,
        ..
    }, squid_error::Error.none;
}

fn restorePacketStore(snapshot: const Snapshot&, store: squid_check_types::Store&) -> Error {
    if !squid_check_types::valid(store) { return squid_error::Error.invalid_artifact; }
    let error = store.nodes.restore(snapshot.store_nodes); if error != squid_error::Error.none { return error; }
    let error = store.extra.restore(snapshot.store_extra); if error != squid_error::Error.none { return error; }
    let error = store.variables.restore(snapshot.store_variables); if error != squid_error::Error.none { return error; }
    let error = store.versions.restore(snapshot.store_versions); if error != squid_error::Error.none { return error; }
    let error = store.operations.restore(snapshot.store_operations); if error != squid_error::Error.none { return error; }
    let error = store.operation_links.restore(snapshot.store_operation_links); if error != squid_error::Error.none { return error; }
    let error = store.closed_row_index.restore(snapshot.store_closed_row_index); if error != squid_error::Error.none { return error; }
    let error = store.closed_operation_index.restore(snapshot.store_closed_operation_index); if error != squid_error::Error.none { return error; }
    let error = store.variable_views.restore(snapshot.store_variable_views, snapshot.state.store_variable_views_count); if error != squid_error::Error.none { return error; }
    let error = store.associated_equations.restore(snapshot.store_associated_equations, snapshot.state.store_associated_equations_count); if error != squid_error::Error.none { return error; }
    let error = store.projection_resolutions.restore(snapshot.store_projection_resolutions, snapshot.state.store_projection_resolutions_count); if error != squid_error::Error.none { return error; }
    let error = store.operation_chains.restore(snapshot.store_operation_chains, snapshot.state.store_operation_chains_count); if error != squid_error::Error.none { return error; }
    let error = store.effects.rows.restore(snapshot.effects_rows); if error != squid_error::Error.none { return error; }
    let error = store.effects.labels.restore(snapshot.effects_labels); if error != squid_error::Error.none { return error; }
    let error = store.effects.variables.restore(snapshot.effects_variables); if error != squid_error::Error.none { return error; }
    let error = store.effects.versions.restore(snapshot.effects_versions); if error != squid_error::Error.none { return error; }
    store.owner_id = squid_native::fresh_owner_id();
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
    store.use_resolution_cache = snapshot.state.store_use_resolution_cache;
    store.use_composite_cache = snapshot.state.store_use_composite_cache;
    store.composite_min_growth = snapshot.state.store_composite_min_growth;
    store.use_operation_shapes = snapshot.state.store_use_operation_shapes;
    store.operation_shape_generation = snapshot.state.store_operation_shape_generation;
    store.operation_shape_enabled = snapshot.state.store_operation_shape_enabled;
    store.effects.physical_epoch = snapshot.state.effects_physical_epoch;
    store.effects.mutation_epoch = snapshot.state.effects_mutation_epoch;
    store.effects.use_resolution_cache = snapshot.state.effects_use_resolution_cache;
    store.effects.next_position = snapshot.state.effects_next_position;
    return squid_error::Error.none;
}
