//! The full gate is the union of every independently compiled subsystem.
comptime {
    _ = @import("syntax_suite.zig");
    _ = @import("types_suite.zig");
    _ = @import("checker_suite.zig");
    _ = @import("project_suite.zig");
}
