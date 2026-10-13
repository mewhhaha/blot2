//! Focused solver laws. The production suite remains the complete gate.
comptime {
    _ = @import("types.zig");
    _ = @import("effects.zig");
    _ = @import("effect_unification_tests.zig");
    _ = @import("resolution_cache_tests.zig");
    _ = @import("frozen_types.zig");
    _ = @import("type_evidence.zig");
    _ = @import("parameter_patterns.zig");
}
