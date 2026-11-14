//! Deterministic frontend work counters plus trace-only timing diagnostics.
//! Work counts use plain integer increments without clocks or allocation.
//! Identity and semantic decisions never read these fields.

/// Completed checker invocations in the project-check phase, aggregated across
/// modules.
pub const Frontend = struct {
    parallel_batches: u64 = 0,
    parallel_jobs: u64 = 0,
    parallel_retries: u64 = 0,
    /// Trace-only inclusive clocks. Worker wall/CPU includes waiting inside
    /// checking and allocator calls; it is not exclusive useful work.
    parallel_prepare_us: u64 = 0,
    parallel_batch_us: u64 = 0,
    parallel_capacity_us: u64 = 0,
    parallel_worker_us: u64 = 0,
    parallel_worker_cpu_us: u64 = 0,
    parallel_worker_cpu_samples: u64 = 0,
    /// Successfully started workers, including the coordinator, summed over
    /// batches. Jobs may finish before another admitted worker begins.
    parallel_worker_slots: u64 = 0,
    parallel_worker_jobs: u64 = 0,
    modules: u64 = 0,
    scheme_calls: u64 = 0,
    closed_array_locals: u64 = 0,
    candidate_scans: u64 = 0,
    candidates: u64 = 0,
    candidate_parts: u64 = 0,
    candidate_variables: u64 = 0,
    candidate_rows: u64 = 0,
    dependency_hits: u64 = 0,
    dependency_recomputations: u64 = 0,
    import_requests: u64 = 0,
    imported_schemes: u64 = 0,
    imported_summary_reuses: u64 = 0,
    imported_read: u64 = 0,
    type_nodes: u64 = 0,
    normalization: Normalization = .{},

    pub fn merge(self: *Frontend, other: Frontend) void {
        inline for (@typeInfo(Frontend).@"struct".field_names) |field| {
            if (comptime @import("std").mem.eql(u8, field, "normalization")) self.normalization.merge(other.normalization) else @field(self, field) +|= @field(other, field);
        }
    }
};

pub const Normalization = struct {
    // Diagnostic operation attribution. Node deltas include nested operations
    // and count net appended nodes even on failure; they are not additive
    // exclusive phases. Depth entries include memo hits and leaf visits.
    substitute_nodes_added: u64 = 0,
    substitute_depth_entries: u64 = 0,
    substitute_memo_hits: u64 = 0,
    // Completed non-leaf walks returning their original node (not leaf exits).
    substitute_unchanged: u64 = 0,
    resolve_nodes_added: u64 = 0,
    resolve_depth_entries: u64 = 0,
    unify_pairs: u64 = 0,
    unify_projected_pairs: u64 = 0,
    unify_resolve_calls: u64 = 0,
    unify_resolve_entries: u64 = 0,
    unify_resolve_nodes: u64 = 0,
    open_nodes_added: u64 = 0,
    open_depth_entries: u64 = 0,
    close_nodes_added: u64 = 0,
    close_depth_entries: u64 = 0,
    import_nodes_added: u64 = 0,
    import_depth_entries: u64 = 0,
    // Cumulative creations, including work later discarded by rollback.
    variable_views_created: u64 = 0,
    type_binders_created: u64 = 0,
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
