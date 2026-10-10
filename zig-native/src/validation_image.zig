//! Exact local validation input stream. This is an owned image, not a digest:
//! matching walks every structural field, including ordered catalogs and IDs.
//! Native framing is deliberately local; portable schemas belong to archives.
const std = @import("std");
const structural = @import("structural.zig");
const A = std.mem.Allocator;

pub const Image = struct {
    bytes: []u8,
    pub fn deinit(self: *Image, a: A) void {
        a.free(self.bytes);
        self.* = undefined;
    }
    pub fn capture(a: A, input: anytype, remaining: *usize) A.Error!?Image {
        var sink: Writer = .{ .allocator = a, .limit = remaining.* };
        defer sink.bytes.deinit(a);
        structural.hash(&sink, input);
        if (sink.failure) |failure| return failure;
        if (sink.declined) return null;
        const bytes = try sink.bytes.toOwnedSlice(a);
        remaining.* -= bytes.len;
        return .{ .bytes = bytes };
    }
    pub fn matches(self: Image, input: anytype) bool {
        var sink: Reader = .{ .expected = self.bytes };
        structural.hash(&sink, input);
        return sink.equal and sink.position == self.bytes.len;
    }
};

const Writer = struct {
    allocator: A,
    limit: usize,
    bytes: std.ArrayList(u8) = .empty,
    failure: ?A.Error = null,
    declined: bool = false,
    pub fn update(self: *Writer, bytes: []const u8) void {
        if (self.failure != null or self.declined) return;
        if (bytes.len > self.limit -| self.bytes.items.len) {
            self.declined = true;
            return;
        }
        const needed = self.bytes.items.len + bytes.len;
        if (needed > self.bytes.capacity) self.bytes.ensureTotalCapacityPrecise(self.allocator, @min(self.limit, @max(needed, @max(64, self.bytes.capacity *| 2)))) catch |failure| {
            self.failure = failure;
            return;
        };
        self.bytes.appendSlice(self.allocator, bytes) catch |failure| {
            self.failure = failure;
        };
    }
};
const Reader = struct {
    expected: []const u8,
    position: usize = 0,
    equal: bool = true,
    pub fn update(self: *Reader, bytes: []const u8) void {
        if (!self.equal) return;
        if (bytes.len > self.expected.len -| self.position or !std.mem.eql(u8, bytes, self.expected[self.position..][0..bytes.len])) {
            self.equal = false;
            return;
        }
        self.position += bytes.len;
    }
};

fn imageScenario(a: A) !void {
    const input = .{ @as(u32, 7), @as([]const u8, "exact graph"), @as(?u32, null) };
    var remaining: usize = 1024;
    var image = (try Image.capture(a, input, &remaining)).?;
    defer image.deinit(a);
    try std.testing.expect(image.matches(input));
    try std.testing.expect(!image.matches(.{ @as(u32, 8), @as([]const u8, "exact graph"), @as(?u32, null) }));
    try std.testing.expect(!image.matches(.{ @as(u32, 7), @as([]const u8, "exact grapH"), @as(?u32, null) }));
    try std.testing.expect(!image.matches(.{ @as(u32, 7), @as([]const u8, "exact graph"), @as(?u32, 0) }));
    var too_small: usize = image.bytes.len - 1;
    try std.testing.expect((try Image.capture(a, input, &too_small)) == null);
    try std.testing.expectEqual(image.bytes.len - 1, too_small);
}
test "source validation images own exact framing with bounded retention and allocation failure cleanup" {
    try imageScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, imageScenario, .{});
}
