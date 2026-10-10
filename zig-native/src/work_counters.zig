//! Deterministic, always-on compiler work counters. They are plain integer
//! increments on existing evaluator and solver structs: no clocks, allocation,
//! identity or semantic decision reads them, so a budget can assert on them
//! without wall-time noise. A retained revision counts only the work it ran.
pub const Counters = struct {
    /// Inference regions opened (ClosureRegion lifetimes, including split children).
    inference_regions: u64 = 0,
    /// Session-local canonical requests and complete proofs reconstructed around
    /// the current captures without opening a new inference region.
    canonical_specialization_queries: u64 = 0,
    canonical_specialization_hits: u64 = 0,
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
};
