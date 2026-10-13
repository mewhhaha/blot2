//! Focused syntax laws. The production suite remains the complete gate.
comptime {
    _ = @import("symbols.zig");
    _ = @import("lexer.zig");
    _ = @import("parser_tests.zig");
    _ = @import("parser_binder_tests.zig");
    _ = @import("parser_identifier_tests.zig");
    _ = @import("syntax_diagnostics.zig");
}
