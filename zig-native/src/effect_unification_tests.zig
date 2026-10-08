const std = @import("std");
const Before = @import("effects.zig");
const After = @import("effects.zig");
// Reference rules publish each intermediate row. The candidate keeps local
// views; compare semantic histories, never incidental row IDs or capacities.
fn materializedUnify(store: *Before.Store, left: u32, right: u32) Before.Error!void {
    const point = store.mark();
    errdefer store.rollback(point);
    var a = try store.resolve(left, 0);
    var b = try store.resolve(right, 0);
    for (0..65536) |_| {
        const an = store.node(a);
        const bn = store.node(b);
        if (an.labels.len == 0 and bn.labels.len == 0 and std.meta.eql(an.tail, bn.tail)) return;
        if (an.labels.len == 0 and an.tail == .variable) return store.bind(an.tail.variable, b);
        if (bn.labels.len == 0 and bn.tail == .variable) return store.bind(bn.tail.variable, a);
        if (an.labels.len == 0) return error.EffectMismatch;
        const selected = try store.extract(b, store.list(an.labels)[0]);
        if (selected.expanded) |variable| if (an.tail == .variable and an.tail.variable == variable) return error.InfiniteEffect;
        const remainder: u32 = @intCast(store.rows.items.len);
        try store.rows.append(store.allocator, .{ .labels = .{ .start = an.labels.start + 1, .len = an.labels.len - 1 }, .tail = an.tail, .cursor = an.cursor });
        a = try store.resolve(remainder, 0);
        b = try store.resolve(selected.remaining, 0);
    }
    return error.EffectLimit;
}
fn sameRow(before: anytype, a: anytype, after: anytype, b: anytype) !void {
    try std.testing.expectEqualSlices(u32, before.list(a.labels), after.list(b.labels));
    try std.testing.expectEqualStrings(@tagName(a.tail), @tagName(b.tail));
    switch (a.tail) {
        .closed => {},
        .variable => |v| try std.testing.expectEqual(v, b.tail.variable),
        .parameter => |v| try std.testing.expectEqual(v, b.tail.parameter),
    }
    try std.testing.expectEqual(a.cursor, b.cursor);
}
test "row views preserve ordered unification substitutions at every retained root" {
    const allocator = std.testing.allocator;
    for (0..32) |seed| {
        var random = std.Random.DefaultPrng.init(10717 * seed + 19);
        const rng = random.random();
        var before = try Before.Store.init(allocator);
        defer before.deinit();
        var after = try After.Store.init(allocator);
        defer after.deinit();
        var roots: [6]u32 = undefined;
        for (&roots) |*root| {
            root.* = try before.fresh();
            try std.testing.expectEqual(root.*, try after.fresh());
        }
        for (0..32) |iteration| {
            const old_mark = before.mark();
            const new_mark = after.mark();
            var old_rows: [2]u32 = undefined;
            var new_rows: [2]u32 = undefined;
            for (&old_rows, &new_rows) |*old_row, *new_row| {
                var labels: [7]u32 = undefined;
                for (&labels) |*label| label.* = rng.uintLessThan(u32, 5) + 1;
                const count = rng.uintLessThan(usize, labels.len + 1);
                const kind = rng.uintLessThan(u32, 4);
                const variable = rng.uintLessThan(u32, roots.len);
                const cursor = if (iteration % 3 == 0) before.cursor() + rng.uintLessThan(u32, 3) else 0;
                const old_tail: Before.Tail = switch (kind) {
                    0 => .closed,
                    1 => .{ .parameter = variable % 3 },
                    else => .{ .variable = variable },
                };
                const new_tail: After.Tail = switch (kind) {
                    0 => .closed,
                    1 => .{ .parameter = variable % 3 },
                    else => .{ .variable = variable },
                };
                old_row.* = try before.rowAt(labels[0..count], old_tail, cursor);
                new_row.* = try after.rowAt(labels[0..count], new_tail, cursor);
            }
            const old_error: ?anyerror = result: {
                materializedUnify(&before, old_rows[0], old_rows[1]) catch |err| break :result err;
                break :result null;
            };
            const new_error: ?anyerror = result: {
                after.unify(new_rows[0], new_rows[1]) catch |err| break :result err;
                break :result null;
            };
            try std.testing.expectEqualStrings(if (old_error) |err| @errorName(err) else "ok", if (new_error) |err| @errorName(err) else "ok");
            try std.testing.expectEqual(before.cursor(), after.cursor());
            try std.testing.expectEqual(before.variables.items.len, after.variables.items.len);
            try std.testing.expectEqual(before.versions.items.len, after.versions.items.len);
            for (before.versions.items, after.versions.items) |old, new| {
                try std.testing.expectEqual(old.variable, new.variable);
                try std.testing.expectEqual(old.position, new.position);
                try sameRow(&before, before.node(old.replacement), &after, after.node(new.replacement));
            }
            for (roots) |root| for ([_]u32{ 0, before.cursor(), before.cursor() + 1 }) |cursor| {
                const old = try before.resolve(root, cursor);
                const new = try after.resolve(root, cursor);
                try sameRow(&before, before.node(old), &after, after.node(new));
            };
            if (iteration % 4 == 0) {
                before.rollback(old_mark);
                after.rollback(new_mark);
            }
        }
    }
}

fn wideRows(allocator: std.mem.Allocator) !void {
    var store = try After.Store.init(allocator);
    defer store.deinit();
    var labels: [320]u32 = undefined;
    var reversed: [320]u32 = undefined;
    for (&labels, 0..) |*label, index| label.* = @intCast(index % 19 + 1);
    for (&reversed, 0..) |*label, index| label.* = labels[labels.len - index - 1];
    const left = try store.rowAt(&labels, .closed, 17);
    const right = try store.rowAt(&reversed, .closed, 29);
    try store.unify(left, right);
    try std.testing.expectEqualSlices(u32, &labels, store.list(store.node(left).labels));
    try std.testing.expectEqualSlices(u32, &reversed, store.list(store.node(right).labels));
    reversed[0] = 77;
    const mismatch = try store.row(&reversed, .closed);
    const point = store.mark();
    if (store.unify(left, mismatch)) |_| return error.TestExpectedError else |err| {
        try std.testing.expectEqual(point, store.mark());
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.EffectMismatch, err);
    }
    try store.unify(right, left);
}
test "row views retain source order and multiplicity through wide permutations failures and recovery" {
    try wideRows(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, wideRows, .{});
}
test "row views preserve the historical unification work limit" {
    var store = try After.Store.init(std.testing.allocator);
    defer store.deinit();
    const labels = try std.testing.allocator.alloc(u32, 65536);
    defer std.testing.allocator.free(labels);
    @memset(labels, 7);
    const accepted = try store.row(labels[0..65535], .closed);
    try store.unify(accepted, accepted);
    const limited = try store.row(labels, .closed);
    const point = store.mark();
    try std.testing.expectError(error.EffectLimit, store.unify(limited, limited));
    try std.testing.expectEqual(point, store.mark());
}
