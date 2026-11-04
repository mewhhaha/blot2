//! Independently compiled types laws.
comptime {
    _ = @import("check/types.zig");
    _ = @import("check/types_tests.zig");
    _ = @import("reuse/resolution_cache_tests.zig");
    _ = @import("check/effect_unification_tests.zig");
    _ = @import("eval/type_evidence.zig");
    _ = @import("check/effects.zig");
    _ = @import("check/frozen_types.zig");
    _ = @import("check/parameter_patterns.zig");
}
