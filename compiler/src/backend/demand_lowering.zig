//! Optional, bounded source-site explanations. Structural work counters live
//! separately; neither the records nor counters select a lowering.
const std = @import("std");
const core = @import("../check/core.zig");
pub const max_sites = 256;
pub const Kind = enum { eliminated, direct, local_memo, stored };
pub const Reason = enum { unused, proved_local, repeated_local, unknown_callee, escaping_use, unresolved_control, inlining_limit, unavailable_body, unresolved_shape };
pub const Site = struct {
    filename: [160]u8 = @splat(0),
    filename_len: u8 = 0,
    filename_truncated: bool = false,
    unit: u32,
    span: core.Span,
    lowering: Kind,
    reason: Reason,
    pub fn jsonStringify(self: *const Site, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{ .filename = self.filename[0..self.filename_len], .filename_truncated = self.filename_truncated, .unit = self.unit, .start = self.span.start, .end = self.span.end, .offset_encoding = "utf8_bytes", .lowering = self.lowering, .reason = self.reason });
    }
};
pub const Snapshot = struct {
    sites: []Site = &.{},
    omitted: usize = 0,
    pub fn clone(self: Snapshot, allocator: std.mem.Allocator) std.mem.Allocator.Error!Snapshot {
        return .{ .sites = try allocator.dupe(Site, self.sites), .omitted = self.omitted };
    }
    pub fn deinit(self: *Snapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.sites);
        self.* = .{};
    }
};
pub const Store = struct {
    enabled: bool = false,
    sites: std.ArrayList(Site) = .empty,
    omitted: usize = 0,
    pub fn deinit(self: *Store, allocator: std.mem.Allocator) void {
        self.sites.deinit(allocator);
        self.* = .{};
    }
    pub fn add(self: *Store, allocator: std.mem.Allocator, filename: []const u8, unit: u32, span: core.Span, lowering: Kind, reason: Reason) std.mem.Allocator.Error!void {
        if (!self.enabled) return;
        for (self.sites.items) |*site| if (site.unit == unit and std.meta.eql(site.span, span) and site.lowering == lowering) {
            if (site.reason == reason) return;
            // Keep different specialization decisions at the same source span.
            // Generic stored emission only refines an unclassified fallback.
            if (lowering == .stored) {
                if (reason == .unresolved_control) return;
                if (site.reason == .unresolved_control) {
                    site.reason = reason;
                    return;
                }
            }
        };
        if (self.sites.items.len == max_sites) {
            self.omitted += 1;
            return;
        }
        var site: Site = .{ .unit = unit, .span = span, .lowering = lowering, .reason = reason };
        var length = @min(filename.len, site.filename.len);
        while (length != 0 and length < filename.len and filename[length] & 0xc0 == 0x80) length -= 1;
        @memcpy(site.filename[0..length], filename[0..length]);
        site.filename_len = @intCast(length);
        site.filename_truncated = length != filename.len;
        try self.sites.append(allocator, site);
    }
    pub fn take(self: *Store, allocator: std.mem.Allocator) std.mem.Allocator.Error!?Snapshot {
        if (!self.enabled) return null;
        return .{ .sites = try self.sites.toOwnedSlice(allocator), .omitted = self.omitted };
    }
};

test "demand explanations bound storage, own UTF8 paths and release failed publication" {
    const allocator = std.testing.allocator;
    const Law = struct {
        fn run(a: std.mem.Allocator) !void {
            var store: Store = .{ .enabled = true };
            defer store.deinit(a);
            var path: [201]u8 = @splat('a');
            for (0..100) |index| @memcpy(path[1 + index * 2 ..][0..2], "é");
            for (0..max_sites + 8) |index| try store.add(a, &path, 1, .{ .start = @intCast(index), .end = @intCast(index + 1) }, .stored, .unresolved_control);
            try store.add(a, &path, 1, .{ .start = 0, .end = 1 }, .stored, .escaping_use);
            var snapshot = (try store.take(a)).?;
            defer snapshot.deinit(a);
            try std.testing.expectEqual(max_sites, snapshot.sites.len);
            try std.testing.expectEqual(@as(usize, 8), snapshot.omitted);
            try std.testing.expectEqual(Reason.escaping_use, snapshot.sites[0].reason);
            try std.testing.expect(snapshot.sites[0].filename_truncated);
            try std.testing.expect(std.unicode.utf8ValidateSlice(snapshot.sites[0].filename[0..snapshot.sites[0].filename_len]));
            var copied = try snapshot.clone(a);
            defer copied.deinit(a);
            try std.testing.expectEqual(snapshot.omitted, copied.omitted);
            try std.testing.expectEqualSlices(Site, snapshot.sites, copied.sites);
        }
    };
    try Law.run(allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(allocator, Law.run, .{});
    var disabled: Store = .{};
    defer disabled.deinit(allocator);
    try disabled.add(allocator, "ignored", 1, .{ .start = 0, .end = 1 }, .stored, .unknown_callee);
    try std.testing.expectEqual(@as(usize, 0), disabled.sites.capacity);
    try std.testing.expect((try disabled.take(allocator)) == null);
}
