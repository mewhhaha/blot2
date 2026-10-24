//! Deterministic, always-on compiler work counters. They are plain integer
//! increments on existing evaluator and solver structs: no clocks, allocation,
//! identity or semantic decision reads them, so a budget can assert on them
//! without wall-time noise. A retained revision counts only the work it ran.
pub const Normalization = struct {
    row_requests: u64 = 0,
    closed_row_hits: u64 = 0,
    epoch_row_hits: u64 = 0,
    epoch_row_probes: u64 = 0,
    epoch_row_collisions: u64 = 0,
    epoch_row_stale: u64 = 0,
    epoch_row_context_misses: u64 = 0,
    epoch_row_publications: u64 = 0,
    composite_probes: u64 = 0,
    composite_hits: u64 = 0,
    composite_collisions: u64 = 0,
    composite_stale_dependencies: u64 = 0,
    composite_future_clock_misses: u64 = 0,
    composite_frontier_declines: u64 = 0,
    composite_publications: u64 = 0,
    free_type_queries: u64 = 0,
    free_type_visits: u64 = 0,
    free_row_queries: u64 = 0,
    free_row_visits: u64 = 0,
    argument_rows: u64 = 0,
    labels: u64 = 0,
    arguments: u64 = 0,
    changed_rows: u64 = 0,
    closed_row_evictions: u64 = 0,
    interner_requests: u64 = 0,
    interner_candidates: u64 = 0,
    interner_arguments: u64 = 0,
    interner_linked: u64 = 0,
    interner_rebuilds: u64 = 0,
    closed_operation_hits: u64 = 0,
    argument_height_checks: u64 = 0,
    pub fn merge(self: *Normalization, other: Normalization) void {
        inline for (@typeInfo(Normalization).@"struct".field_names) |field| @field(self, field) +|= @field(other, field);
    }
};
pub const SchemeMembership = struct {
    prepares: u64 = 0,
    small: u64 = 0,
    hits: u64 = 0,
    publications: u64 = 0,
    saturated: u64 = 0,
    indexed_items: u64 = 0,
};
pub const Counters = struct {
    /// Region solver work only; frontend type stores are counted separately.
    normalization: Normalization = .{},
    scheme_membership: SchemeMembership = .{},
    ragged_runtime_regions: u64 = 0,
    ragged_staged_regions: u64 = 0,
    ragged_probe_visits: u64 = 0,
    ragged_probe_declines: u64 = 0,
    ragged_selected: u64 = 0,
    ragged_published_children: u64 = 0,
    demand_summary_builds: u64 = 0,
    demand_summary_hits: u64 = 0,
    demand_summary_imports: u64 = 0,
    demand_summary_dependency_checks: u64 = 0,
    demand_summary_nodes: u64 = 0,
    demand_summary_edges: u64 = 0,
    demand_summary_iterations: u64 = 0,
    demand_summary_declines: u64 = 0,
    demand_summary_never: u64 = 0,
    demand_summary_once: u64 = 0,
    demand_summary_repeated: u64 = 0,
    demand_summary_unknown: u64 = 0,
    demand_summary_escaping: u64 = 0,
    /// Structural sites/slots emitted this build, not dynamic runtime traffic.
    demand_allocations: u64 = 0,
    demand_local_memo_slots: u64 = 0,
    demand_eliminated: u64 = 0,
    demand_direct: u64 = 0,
    demand_indirect_calls: u64 = 0,
    demand_inline_nodes: u64 = 0,

    semantic_component_batches: u64 = 0,
    semantic_component_jobs: u64 = 0,
    semantic_component_attempts: u64 = 0,
    semantic_component_no_io: u64 = 0,
    semantic_component_disabled: u64 = 0,
    semantic_component_recording: u64 = 0,
    semantic_component_observing: u64 = 0,
    semantic_component_exhausted: u64 = 0,
    /// Admitted worker capacity, including the coordinator; not overlap or CPUs.
    max_semantic_component_workers: u64 = 0,
    /// Inference regions opened (ClosureRegion lifetimes, including split children).
    inference_regions: u64 = 0,
    /// Session-local canonical requests and complete proofs reconstructed around
    /// the current captures without opening a new inference region.
    canonical_specialization_queries: u64 = 0,
    canonical_specialization_prefiltered: u64 = 0,
    canonical_specialization_lookups: u64 = 0,
    canonical_specialization_candidates: u64 = 0,
    canonical_specialization_hits: u64 = 0,
    /// Logical successful client growth inside region arenas; these overlap
    /// backing `memory` totals and must never be added to them.
    solver_requested_bytes: u64 = 0,
    solver_allocations: u64 = 0,
    scratch_requested_bytes: u64 = 0,
    scratch_allocations: u64 = 0,
    max_solver_live_bytes: u64 = 0,
    max_scratch_live_bytes: u64 = 0,
    /// Subsets of the logical totals, counted only by the outer import.
    evidence_import_solver_bytes: u64 = 0,
    evidence_import_scratch_bytes: u64 = 0,
    /// Bytes and fields copied for the evaluator snapshot, including its
    /// evidence; fields leased from the previous revision incur none.
    snapshot_copy_bytes: u64 = 0,
    snapshot_copy_allocations: u64 = 0,
    /// Artifact pool fields leased unchanged from the previous revision versus
    /// copied into new leases, with their payload bytes.
    metadata_shared_fields: u64 = 0,
    metadata_shared_bytes: u64 = 0,
    metadata_copied_fields: u64 = 0,
    metadata_copied_bytes: u64 = 0,
    /// Durable principal copier buffers (the destination type Store is separate).
    principal_copy_buffer_bytes: u64 = 0,
    principal_copy_buffer_allocations: u64 = 0,
    /// Capture preparation and durable child publication, distinct owners.
    frozen_capture_temporary_bytes: u64 = 0,
    frozen_capture_published_bytes: u64 = 0,
    frozen_edge_scratch_bytes: u64 = 0,
    /// Sum and maximum of type scopes held by one region at release.
    region_scopes: u64 = 0,
    max_region_scopes: u64 = 0,
    /// Callee body collections in ClosureRegion.collectCall whose instantiated
    /// signature was closed and therefore keyed in `call_instances`.
    call_collections_closed: u64 = 0,
    /// Callee body collections whose signature stayed unresolved; each use
    /// collects the body again.
    call_collections_unresolved: u64 = 0,
    /// Calls answered by an existing `call_instances` entry instead of collecting.
    call_memo_hits: u64 = 0,
    /// Fixed-point passes of ClosureRegion.solveMode and unsolved constraints
    /// examined across them.
    solver_passes: u64 = 0,
    solver_constraint_visits: u64 = 0,
    worklist_subscriber_visits: u64 = 0,
    worklist_retained_watches: u64 = 0,
    worklist_refreshed_watches: u64 = 0,
    worklist_ready_word_scans: u64 = 0,
    /// Type nodes visited by occurs checks in region solvers.
    occurs_steps: u64 = 0,
    /// Owned principal graphs described, imported into a region instead of
    /// collecting the body, and open callee edges retained unsolved.
    principal_graph_builds: u64 = 0,
    principal_graph_imports: u64 = 0,
    principal_graph_deferred: u64 = 0,
    principal_containing_sources: u64 = 0,
    principal_module_sources: u64 = 0,
    /// Capture scopes projected while selecting interfaces for lexical keys.
    lexical_interface_projections: u64 = 0,
    /// Former region-wide lexical scan candidates and entries actually visited
    /// through the scope index. Both preserve the same insertion-order bound.
    lexical_region_candidates: u64 = 0,
    lexical_scope_candidates: u64 = 0,
    lexical_row_region_candidates: u64 = 0,
    lexical_row_scope_candidates: u64 = 0,
    /// Calls selected before emission, by shape, and the closures applied to
    /// arguments past a selected callee's parameters.
    resolved_bodies: u64 = 0,
    resolved_plan_entries: u64 = 0,
    safe_local_sinks: u64 = 0,
    resolved_plan_reads: u64 = 0,
    prepared_named_calls: u64 = 0,
    prepared_dispatch_calls: u64 = 0,
    prepared_resolver_calls: u64 = 0,
    prepared_indirect_calls: u64 = 0,
    prepared_static_closures: u64 = 0,
    prepared_extra_applications: u64 = 0,
    prepared_exits: u64 = 0,
    prepared_exit_cleanups: u64 = 0,
    prepared_joins: u64 = 0,
    prepared_loops: u64 = 0,
    prepared_matches: u64 = 0,
    prepared_request_loops: u64 = 0,
    /// Allocations annotated with word roles from checked layouts.
    allocation_role_runs: u64 = 0,
    /// Functions given parameter roles from checked layouts.
    parameter_role_functions: u64 = 0,
    pub fn merge(self: *Counters, other: Counters) void {
        inline for (@typeInfo(Counters).@"struct".field_names) |name| {
            if (comptime @typeInfo(@TypeOf(@field(self.*, name))) == .@"struct") {
                inline for (@typeInfo(@TypeOf(@field(self.*, name))).@"struct".field_names) |field| @field(@field(self.*, name), field) +|= @field(@field(other, name), field);
            } else if (comptime @import("std").mem.startsWith(u8, name, "max_")) {
                @field(self, name) = @max(@field(self, name), @field(other, name));
            } else @field(self, name) +|= @field(other, name);
        }
    }
};
