//! Public source coordinates borrow filenames only for serialization.
const core = @import("core.zig");
pub const Location = struct {
    filename: []const u8,
    start: u32,
    end: u32,
    offset_encoding: []const u8 = "utf8_bytes",
    pub fn init(filename: []const u8, span: core.Span) Location {
        return .{ .filename = filename, .start = span.start, .end = span.end };
    }
};
