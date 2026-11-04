//! Bounded source-site outcomes from the same ownership proof used by array edits.
//! A copied edit may still be eliminated later; these are proof decisions, not
//! observed allocator traffic.
const std = @import("std");
const core = @import("../check/core.zig");
const owned = @import("owned_arrays.zig");

// Keep reports bounded while covering a complete asset-heavy application.
pub const max_sites = 16384;
pub const Site = struct {
    filename: [160]u8 = @splat(0),
    filename_len: u8 = 0,
    filename_truncated: bool = false,
    unit: u32,
    span: core.Span,
    decision: owned.Proof.Decision,
    pub fn jsonStringify(self: *const Site, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{
            .filename = self.filename[0..self.filename_len],
            .filename_truncated = self.filename_truncated,
            .unit = self.unit,
            .start = self.span.start,
            .end = self.span.end,
            .offset_encoding = "utf8_bytes",
            .result = if (self.decision == .reused) "reuse_eligible" else "copy_required",
            .reason = self.decision,
        });
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

pub fn analyze(allocator: std.mem.Allocator, units: []const core.Module, filenames: []const []const u8, entry: u32, prelude: u32) !Snapshot {
    std.debug.assert(filenames.len == units.len);
    var sites: std.ArrayList(Site) = .empty;
    errdefer sites.deinit(allocator);
    var omitted: usize = 0;
    // Put the requested source first so a large standard library cannot use
    // the entire bounded report before the entry's sites are seen.
    for (0..units.len) |order| {
        const unit_id: u32 = if (order == 0) entry else if (order < entry) @intCast(order) else @intCast(order + 1);
        if (unit_id == prelude) continue;
        const module = &units[unit_id - 1];
        var proof = try owned.Proof.initWithDecisions(allocator, units, unit_id, true);
        defer proof.deinit(allocator);
        for (proof.decisions, 0..) |maybe, index| {
            const decision = maybe orelse continue;
            const span = module.span(@intCast(index));
            if (span.end <= span.start) continue;
            if (sites.items.len == max_sites) {
                omitted += 1;
                continue;
            }
            var site: Site = .{ .unit = unit_id, .span = span, .decision = decision };
            const path = filenames[unit_id - 1];
            var length = @min(path.len, site.filename.len);
            while (length != 0 and length < path.len and path[length] & 0xc0 == 0x80) length -= 1;
            @memcpy(site.filename[0..length], path[0..length]);
            site.filename_len = @intCast(length);
            site.filename_truncated = length != path.len;
            try sites.append(allocator, site);
        }
    }
    return .{ .sites = try sites.toOwnedSlice(allocator), .omitted = omitted };
}
