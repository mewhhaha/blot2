//! Closed evidence transfer between independent owners of the same immutable
//! source catalogs. Numeric semantic/effect IDs are always explicitly remapped.
const std = @import("std");
const evidence = @import("type_evidence.zig");
const A = std.mem.Allocator;
pub const Importer = struct {
    allocator: A,
    source: evidence.View,
    destination: *evidence.Store,
    max_depth: usize,
    nodes: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    rows: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    labels: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    pub fn deinit(self: *Importer) void {
        self.nodes.deinit(self.allocator);
        self.rows.deinit(self.allocator);
        self.labels.deinit(self.allocator);
    }
    pub fn ty(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (id == 0) return 0;
        if (depth >= self.max_depth or id >= self.source.nodes.len) return error.EvidenceLimit;
        if (id <= 5) return id;
        if (self.nodes.get(id)) |known| return known;
        const node = self.source.node(id);
        const children = self.source.children(id);
        const copied = try self.allocator.dupe(u32, children);
        defer self.allocator.free(copied);
        for (copied, 0..) |*child, index| {
            if (node.tag != .record or index % 2 != 0) child.* = try self.ty(child.*, depth + 1);
        }
        const a = switch (node.tag) {
            .function, .array, .list, .cursor, .demand, .resolver, .provider, .state_provider => try self.ty(node.a, depth + 1),
            .nominal, .type_constructor => node.a,
            else => 0,
        };
        const b = switch (node.tag) {
            .function, .state_provider => try self.ty(node.b, depth + 1),
            .nominal, .type_constructor => node.b,
            else => 0,
        };
        const c = switch (node.tag) {
            .function, .demand, .provider => try self.row(node.c, depth + 1),
            .state_provider => try self.ty(node.c, depth + 1),
            else => 0,
        };
        const result = if (node.tag == .state_provider) try self.destination.internStateProvider(a, b, c) else try self.destination.internWithEffects(node.tag, a, b, c, copied);
        try self.nodes.put(self.allocator, id, result);
        return result;
    }
    pub fn row(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (id == 0) return 0;
        if (depth >= self.max_depth or id >= self.source.effects.rows.len) return error.EvidenceLimit;
        if (self.rows.get(id)) |known| return known;
        const original = self.source.effects.rowLabels(id);
        const copied = try self.allocator.alloc(u32, original.len);
        defer self.allocator.free(copied);
        for (original, copied) |old, *new| new.* = try self.label(old, depth + 1);
        const result = try self.destination.effects.internRow(copied);
        try self.rows.put(self.allocator, id, result);
        return result;
    }
    fn label(self: *Importer, id: u32, depth: usize) evidence.Error!u32 {
        if (depth >= self.max_depth or id == 0 or id >= self.source.effects.operations.len) return error.EvidenceLimit;
        if (self.labels.get(id)) |known| return known;
        const operation = self.source.effects.operation(id);
        const original = self.source.effects.operationArguments(id);
        const copied = try self.allocator.alloc(u32, original.len);
        defer self.allocator.free(copied);
        for (original, copied) |old, *new| new.* = try self.ty(old, depth + 1);
        const result = try self.destination.effects.internOperation(operation.identity, copied);
        try self.labels.put(self.allocator, id, result);
        return result;
    }
};

fn transferScenario(a: A) !void {
    var source = try evidence.Store.init(a);
    defer source.deinit();
    const nominal = try source.intern(.nominal, 17, 23, &.{3});
    const write = try source.intern(.nominal, 17, 24, &.{4});
    const label_ = try source.effects.internOperation(.{ .unit = 17, .decl = 31 }, &.{nominal});
    const row_ = try source.effects.internRow(&.{ label_, label_ });
    const function = try source.internWithEffects(.function, nominal, write, row_, &.{});
    const provider = try source.internWithEffects(.provider, nominal, 0, row_, &.{});
    const state = try source.internStateProvider(nominal, write, 3);
    const record = try source.intern(.record, 0, 0, &.{ 41, function, 42, function });
    const root = try source.intern(.product, 0, 0, &.{ record, provider, state });
    var destination = try evidence.Store.init(a);
    defer destination.deinit();
    _ = try destination.intern(.array, 4, 0, &.{});
    var before = try destination.copyOwned(a);
    defer before.deinit(a);
    var staged = try destination.clone(a);
    defer staged.deinit();
    var copy: Importer = .{ .allocator = a, .source = source.view(), .destination = &staged, .max_depth = 256 };
    defer copy.deinit();
    const copied = try copy.ty(root, 0);
    try std.testing.expectEqualDeep(before.nodes, destination.nodes.items);
    try std.testing.expectEqualDeep(before.extra, destination.extra.items);
    std.mem.swap(evidence.Store, &staged, &destination);
    const children = destination.children(copied);
    const fields = destination.children(children[0]);
    try std.testing.expectEqual(@as(u32, 41), fields[0]);
    try std.testing.expectEqual(fields[1], fields[3]);
    const arrow = destination.node(fields[1]);
    const nominal_copy = destination.node(arrow.a);
    try std.testing.expectEqual(@as(u32, 17), nominal_copy.a);
    try std.testing.expectEqual(@as(u32, 23), nominal_copy.b);
    const labels = destination.effects.view().rowLabels(arrow.c);
    try std.testing.expectEqual(@as(usize, 2), labels.len);
    try std.testing.expectEqual(labels[0], labels[1]);
    try std.testing.expectEqual(arrow.a, destination.effects.view().operationArguments(labels[0])[0]);
    try std.testing.expectEqual(arrow.c, destination.node(children[1]).c);
    const state_copy = destination.node(children[2]);
    try std.testing.expectEqual(arrow.a, state_copy.a);
    try std.testing.expectEqual(arrow.b, state_copy.b);
    try std.testing.expectEqual(@as(u32, 3), state_copy.c);
}
test "private semantic evidence remaps nominal records aliases and repeated effect labels with atomic owner staging" {
    try transferScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, transferScenario, .{});
}
