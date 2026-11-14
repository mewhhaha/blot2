//! Owned frontend diagnostics and the result of one project build, published
//! after every frontend owner is released.
const std = @import("std");
const ast = @import("../parse/ast.zig");
const backend = @import("../compile.zig");
const Allocator = std.mem.Allocator;
const syntax = @import("../parse/syntax_diagnostics.zig");
const token = @import("../parse/token.zig");

pub const Stats = struct { syntax_nodes: usize, body_elaborations: usize, body_lowerings: usize, imported_schemes: usize, normalization: @import("../work_counters.zig").Normalization = .{} };
/// Failure metadata is snapped while frontend owners are live. JSON details
/// contain the actual evidence, independently owned after frontend teardown.
pub const Publication = struct {
    utf16: ?ast.Span,
    cause: syntax.Cause,
    expected_token: ?token.Tag,
    actual_token: ?token.Tag,
    details_json: []u8,
    /// The project server forwards these details: a hole snapshot or a
    /// dispatch explanation, whose client schemas decode them defensively.
    forwarded: bool = false,
};
pub const Details = struct {
    bytes: []const u8,
    pub fn jsonStringify(self: Details, writer: anytype) !void {
        // These bytes are produced only by std.json.Stringify.valueAlloc.
        // They are not untrusted source text or artifact wire contents.
        try writer.print("{s}", .{self.bytes});
    }
};
pub const Diagnostic = struct {
    stage: []const u8,
    unit: u32,
    code: []u8,
    start: u32,
    end: u32,
    message: []u8,
    publication: ?Publication = null,
    pub fn init(allocator: Allocator, unit: u32, stage: []const u8, code: []const u8, span: ast.Span, message: []const u8) !Diagnostic {
        const owned_code = try allocator.dupe(u8, code);
        errdefer allocator.free(owned_code);
        return .{ .stage = stage, .unit = unit, .code = owned_code, .start = span.start, .end = span.end, .message = try allocator.dupe(u8, message) };
    }
    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        if (self.publication) |published| allocator.free(published.details_json);
        allocator.free(self.code);
        allocator.free(self.message);
        self.* = undefined;
    }
    pub fn write(self: *const Diagnostic, writer: *std.Io.Writer, filename: []const u8) !void {
        if (self.publication) |published| {
            try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = self.stage, .code = self.code, .start = self.start, .end = self.end, .message = self.message, .offset_encoding = "utf8_bytes", .utf16 = published.utf16, .cause = published.cause, .expected_token = published.expected_token, .actual_token = published.actual_token, .details = Details{ .bytes = published.details_json } }, .{}, writer);
        } else {
            try std.json.Stringify.value(.{ .kind = "diagnostic", .filename = filename, .stage = self.stage, .unit = self.unit, .code = self.code, .start = self.start, .end = self.end, .message = self.message }, .{}, writer);
        }
        try writer.writeByte('\n');
    }
};
/// Test helper: every field a project build publishes for a frontend
/// rejection agrees. The unit ordinal is not published (the file name is): it
/// numbers the modules of the lane that found the diagnostic.
pub fn expectSamePublished(expected: ?Diagnostic, actual: ?Diagnostic) !void {
    try std.testing.expectEqual(expected == null, actual == null);
    const left = expected orelse return;
    const right = actual.?;
    try std.testing.expectEqualStrings(left.stage, right.stage);
    try std.testing.expectEqualStrings(left.code, right.code);
    try std.testing.expectEqual(left.start, right.start);
    try std.testing.expectEqual(left.end, right.end);
    try std.testing.expectEqualStrings(left.message, right.message);
    try std.testing.expectEqualDeep(left.publication, right.publication);
}
pub fn publishedDiagnostic(allocator: Allocator, unit: u32, stage: []const u8, source: []const u8, publication: syntax.Publication, details: anytype) !Diagnostic {
    var result = try Diagnostic.init(allocator, unit, stage, publication.code, publication.span, publication.message);
    errdefer result.deinit(allocator);
    // Publish the optional payload only after all fallible ownership exists.
    const details_json = try std.json.Stringify.valueAlloc(allocator, details, .{});
    const Details_ = @TypeOf(details);
    const forwarded = comptime @typeInfo(Details_) == .@"struct" and (@hasField(Details_, "hole") or @hasField(Details_, "explanation") or @hasField(Details_, "contexts"));
    result.publication = .{ .utf16 = publication.utf16(source), .cause = publication.cause, .expected_token = publication.expected_token, .actual_token = publication.actual_token, .details_json = details_json, .forwarded = forwarded };
    return result;
}
pub const Result = struct {
    compiled: backend.Result,
    stats: Stats,
    diagnostic: ?Diagnostic = null,
    pub fn deinit(self: *Result, allocator: Allocator) void {
        self.compiled.deinit(allocator);
        if (self.diagnostic) |*item| item.deinit(allocator);
        self.* = undefined;
    }
};
