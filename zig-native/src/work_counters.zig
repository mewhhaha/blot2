//! Deterministic, always-on compiler work counters. They are plain integer
//! increments on existing evaluator and solver structs: no clocks, allocation,
//! identity or semantic decision reads them, so a budget can assert on them
//! without wall-time noise. A retained revision counts only the work it ran.
pub const Counters = struct {
    semantic_component_batches: u64 = 0,
    semantic_component_jobs: u64 = 0,
    /// Inference regions opened (ClosureRegion lifetimes, including split children).
    inference_regions: u64 = 0,
    /// Session-local canonical requests and complete proofs reconstructed around
    /// the current captures without opening a new inference region.
    canonical_specialization_queries: u64 = 0,
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
    /// Exact allocations for owned evaluator snapshot cloning, including its
    /// evidence snapshot; borrowed snapshots incur none of this traffic.
    snapshot_copy_bytes: u64 = 0,
    snapshot_copy_allocations: u64 = 0,
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
    /// Type nodes visited by occurs checks in region solvers.
    occurs_steps: u64 = 0,
    pub fn merge(self: *Counters, other: Counters) void {
        inline for (@typeInfo(Counters).@"struct".field_names) |name| {
            if (comptime @import("std").mem.startsWith(u8, name, "max_")) {
                @field(self, name) = @max(@field(self, name), @field(other, name));
            } else @field(self, name) +|= @field(other, name);
        }
    }
};
