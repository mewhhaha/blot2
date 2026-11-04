//! Runtime test policy. Full qualification is exhaustive unless explicitly sampled.
pub const FaultMode = enum { full, sampled };
pub var fault_mode: FaultMode = .full;
pub const Counts = struct {
    full_sweeps: usize = 0,
    sampled_sweeps: usize = 0,
    discovered_allocations: usize = 0,
    fault_runs: usize = 0,
};
pub var counts: Counts = .{};
