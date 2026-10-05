const std = @import("std");
const E = @import("effects.zig");
const a = std.testing.allocator;

const Observation = struct {
    labels: []E.Label,
    tail: E.Tail,
    cursor: E.Cursor,
    fn deinit(self: *Observation, allocator: std.mem.Allocator) void {
        allocator.free(self.labels);
        self.* = undefined;
    }
};
fn chronological(store: *const E.Store, root: E.Id, at: E.Cursor) !Observation {
    var current = store.node(root);
    var cursor = @max(at, current.cursor);
    var labels: std.ArrayList(E.Label) = .empty;
    errdefer labels.deinit(a);
    var changed = false;
    while (current.tail == .variable) {
        cursor = @max(cursor, current.cursor);
        const write = for (store.versions.items) |version| {
            if (version.variable == current.tail.variable and version.position >= cursor) break version;
        } else break;
        try labels.appendSlice(a, store.list(current.labels));
        current = store.node(write.replacement);
        cursor = write.position + 1;
        changed = true;
    }
    try labels.appendSlice(a, store.list(current.labels));
    if (labels.items.len == 0 and current.tail == .closed) cursor = 0;
    if (!changed and store.node(root).tail != .variable) cursor = store.node(root).cursor;
    return .{ .labels = try labels.toOwnedSlice(a), .tail = current.tail, .cursor = cursor };
}
fn observe(store: *E.Store, root: E.Id, cursor: E.Cursor) !void {
    var expected = try chronological(store, root, cursor);
    defer expected.deinit(a);
    const actual = try store.resolve(root, cursor);
    try std.testing.expectEqualSlices(E.Label, expected.labels, store.list(store.node(actual).labels));
    try std.testing.expectEqualDeep(expected.tail, store.node(actual).tail);
    try std.testing.expectEqual(expected.cursor, store.node(actual).cursor);
}

test "effect span projections equal sequential history through repeated labels cursor views rollback and recycled storage" {
    for (0..8) |seed| {
        var random = std.Random.DefaultPrng.init(7919 * seed + 17);
        var store = try E.Store.init(a);
        defer store.deinit();
        var variables: [4]E.Id = undefined;
        for (&variables) |*variable| variable.* = try store.fresh();
        const roots = [_]E.Id{ variables[0], try store.row(&.{ 7, 7, 3 }, store.node(variables[1]).tail), variables[2] };
        for (0..20) |iteration| {
            const point = store.mark();
            const selected = random.random().uintLessThan(usize, variables.len);
            const next = random.random().uintLessThan(usize, variables.len);
            const labels = [_]E.Label{ @intCast(1 + iteration % 5), 7, 7 };
            const count = random.random().uintLessThan(usize, labels.len + 1);
            const tail: E.Tail = if (iteration % 4 == 0) .closed else store.node(variables[next]).tail;
            const row = try store.row(labels[0..count], tail);
            try store.appendVersion(store.node(variables[selected]).tail.variable, row);
            for (roots) |root| for (0..store.cursor() + 3) |cursor| try observe(&store, root, @intCast(cursor));
            if (iteration % 3 == 0) {
                store.rollback(point);
                const recycled = try store.row(&.{ 11, 9, 11 }, .closed);
                try store.appendVersion(store.node(variables[selected]).tail.variable, recycled);
                for (roots) |root| for (0..store.cursor() + 2) |cursor| try observe(&store, root, @intCast(cursor));
            }
        }
    }
}

fn wide(allocator: std.mem.Allocator) !void {
    var store = try E.Store.initWithOptions(allocator, .{ .resolution_cache = false });
    defer store.deinit();
    var labels: [160]E.Label = undefined;
    for (&labels, 0..) |*label, index| label.* = @intCast(index % 7 + 1);
    const root = try store.fresh();
    const middle = try store.fresh();
    const replacement = try store.row(&labels, .closed);
    try store.appendVersion(store.node(root).tail.variable, middle);
    try store.appendVersion(store.node(middle).tail.variable, replacement);
    const before = store.labels.items.len;
    const resolved = try store.resolve(root, 0);
    try std.testing.expectEqual(before, store.labels.items.len);
    try std.testing.expectEqualDeep(store.node(replacement).labels, store.node(resolved).labels);
    try std.testing.expectEqualSlices(E.Label, &labels, store.list(store.node(resolved).labels));
    try std.testing.expectEqual(@as(E.Cursor, 2), store.node(resolved).cursor);
    // A subsequent write must not retroactively change the retained projection.
    try store.appendVersion(store.node(middle).tail.variable, try store.row(&.{99}, .closed));
    try std.testing.expectEqualSlices(E.Label, &labels, store.list(store.node(try store.resolve(resolved, 0)).labels));
    try std.testing.expectEqual(@as(E.Cursor, 2), store.node(resolved).cursor);
    const original = try allocator.dupe(E.Label, store.labels.items);
    defer allocator.free(original);
    _ = try store.resolve(root, 1);
    try std.testing.expectEqualSlices(E.Label, original, store.labels.items[0..original.len]);
}
test "single wide effect label fragment retains owned storage without copying and releases every failed allocation" {
    try wide(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, wide, .{});
}
