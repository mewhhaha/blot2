//! Execution choices are owned by a compilation/session. They never grant
//! cache validity; source, evidence, executable and value checks remain distinct.
//! Compiler behavior is not policy: fresh and retained builds run the same
//! implementation, and artifact retention follows the retained session.
pub const Policy = struct {
    codegen_tier: @import("compilation_tier.zig").Tier = .optimized,
    share_machine_code: bool = false,
    codegen_workers: u8 = 1,
    semantic_workers: u8 = 1,
};
