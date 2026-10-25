//! The full gate is the union of every independently compiled subsystem.
comptime {
    _ = @import("reuse/parallel_check_tests.zig");
    _ = @import("syntax_suite.zig");
    _ = @import("types_suite.zig");
    _ = @import("runtime_suite.zig");
    _ = @import("checker_suite.zig");
    _ = @import("evaluator_suite.zig");
    _ = @import("backend_suite.zig");
    _ = @import("retained_suite.zig");
}
