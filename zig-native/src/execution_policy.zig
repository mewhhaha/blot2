//! Execution choices are owned by a compilation/session. They never grant
//! cache validity; source, evidence, executable and value checks remain distinct.
//! Compiler behavior is not policy: fresh and retained builds run the same
//! implementation, and artifact retention follows the retained session.
pub const Policy = struct {
    storage: @import("backend/storage_plan.zig").Budgets = .{},
    codegen_tier: @import("compilation_tier.zig").Tier = .optimized,
    share_machine_code: bool = false,
    /// Diagnostic final-Wasm counters; absent from ordinary release output.
    memory_profile: bool = false,
    /// Reject unless the complete module has a checked collector-free certificate.
    require_collector_free: bool = false,
    codegen_workers: u8 = 1,
    semantic_workers: u8 = 1,
    frontend_workers: u8 = 4,
    /// Run the same private component path with one worker for qualification.
    semantic_components: bool = false,
};
