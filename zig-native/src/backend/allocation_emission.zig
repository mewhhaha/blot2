//! Source coordinates for allocator calls emitted before Wasm optimization.
//! They identify a materialization site, not surviving guest allocator traffic.
const std = @import("std");
const core = @import("../check/core.zig");
const wasm = @import("wasm.zig");
const identity = @import("runtime_identity.zig");

pub const max_sites = 256;
pub const Kind = enum { closure_storage, constructor_storage, aggregate_storage, boxed_constant, call_materialization, array_storage, other_materialization };
pub const Site = struct {
    filename: [160]u8 = @splat(0),
    filename_len: u8 = 0,
    filename_truncated: bool = false,
    unit: u32,
    span: core.Span,
    kind: Kind,
    requested_bytes: ?u32,
    emissions: u32 = 1,
    pub fn jsonStringify(self: *const Site, stream: *std.json.Stringify) std.Io.Writer.Error!void {
        try stream.write(.{
            .filename = self.filename[0..self.filename_len],
            .filename_truncated = self.filename_truncated,
            .unit = self.unit,
            .start = self.span.start,
            .end = self.span.end,
            .offset_encoding = "utf8_bytes",
            .kind = self.kind,
            .requested_bytes = self.requested_bytes,
            .emissions = self.emissions,
        });
    }
};
pub const Snapshot = struct {
    sites: []Site = &.{},
    omitted: usize = 0,
    pub fn deinit(self: *Snapshot, allocator: std.mem.Allocator) void {
        allocator.free(self.sites);
        self.* = .{};
    }
};

fn category(tag: core.Tag) Kind {
    return switch (tag) {
        .closure, .suspend_ => .closure_storage,
        .construct => .constructor_storage,
        .product, .record, .record_merge => .aggregate_storage,
        .constant => .boxed_constant,
        .call, .apply => .call_materialization,
        .array, .array_op, .update => .array_storage,
        else => .other_materialization,
    };
}

pub fn capture(allocator: std.mem.Allocator, units: []const core.Module, names: ?identity.View, module: *const wasm.Module, entry: u32, prelude: u32) std.mem.Allocator.Error!Snapshot {
    var sites: std.ArrayList(Site) = .empty;
    errdefer sites.deinit(allocator);
    var omitted: usize = 0;
    // Entry first, then imports, so a generated library cannot fill the cap
    // before the requested source's remarks are published.
    for (0..2) |pass| for (module.semantic_sites.items) |record| {
        if (record.kind != .allocation or record.unit == 0 or record.unit > units.len or record.unit == prelude or (record.unit == entry) != (pass == 0)) continue;
        const source = &units[record.unit - 1];
        if (record.node == 0 or record.node >= source.nodes.len or record.function >= module.functions.items.len) continue;
        const span = source.span(record.node);
        if (span.end <= span.start) continue;
        const function = &module.functions.items[record.function];
        if (record.place >= function.instructions.items.len) continue;
        const previous = if (record.place == 0) null else function.instructions.items[record.place - 1];
        const bytes: ?u32 = if (previous != null and previous.?.op == .i32_const and previous.?.operand != 0) previous.?.operand else null;
        const kind = category(source.node(record.node).tag);
        var found = false;
        for (sites.items) |*site| {
            if (site.unit == record.unit and std.meta.eql(site.span, span) and site.kind == kind and site.requested_bytes == bytes) {
                site.emissions +|= 1;
                found = true;
                break;
            }
        }
        if (found) continue;
        if (sites.items.len == max_sites) {
            omitted += 1;
            continue;
        }
        var site: Site = .{ .unit = record.unit, .span = span, .kind = kind, .requested_bytes = bytes };
        const path = if (names) |view| view.owner(record.unit) orelse "" else "";
        var length = @min(path.len, site.filename.len);
        while (length != 0 and length < path.len and path[length] & 0xc0 == 0x80) length -= 1;
        @memcpy(site.filename[0..length], path[0..length]);
        site.filename_len = @intCast(length);
        site.filename_truncated = length != path.len;
        try sites.append(allocator, site);
    };
    return .{ .sites = try sites.toOwnedSlice(allocator), .omitted = omitted };
}
