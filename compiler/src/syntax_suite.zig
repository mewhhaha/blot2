//! Independently compiled syntax laws.
comptime {
    _ = @import("parse/syntax_diagnostics_tests.zig");
    _ = @import("parse/symbols_tests.zig");
    _ = @import("parse/lexer_tests.zig");
    _ = @import("parse/parser.zig");
    _ = @import("parse/parser_tests.zig");
    _ = @import("parse/parser_binder_tests.zig");
    _ = @import("parse/parser_identifier_tests.zig");
    _ = @import("parse/parser_adjacent_call_tests.zig");
    _ = @import("parse/source_operators_tests.zig");
    _ = @import("parse/parser_use_tests.zig");
}
