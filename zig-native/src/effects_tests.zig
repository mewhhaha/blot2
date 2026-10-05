const std = @import("std");
const E = @import("effects.zig");

test "effect resolution observes one ordered clock including gaps for type writes" {
    var store = try E.Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const b = try store.fresh();
    const prefix = try store.row(&.{1}, store.node(b).tail);
    const first = try store.row(&.{9}, .closed);
    const later = try store.row(&.{3}, .closed);
    try store.appendVersionAt(store.node(a).tail.variable, prefix, 2);
    try store.appendVersionAt(store.node(b).tail.variable, first, 5);
    try store.appendVersionAt(store.node(a).tail.variable, later, 8);
    const old = store.node(try store.resolve(a, 0));
    try std.testing.expectEqualSlices(E.Label, &.{ 1, 9 }, store.list(old.labels));
    const newer = store.node(try store.resolve(a, 3));
    try std.testing.expectEqualSlices(E.Label, &.{3}, store.list(newer.labels));
    const future = store.node(try store.resolve(a, 9));
    try std.testing.expectEqual(store.node(a).tail.variable, future.tail.variable);
    try std.testing.expectEqual(@as(E.Cursor, 9), future.cursor);
}

fn rowOwnership(allocator: std.mem.Allocator) !void {
    var store = try E.Store.init(allocator);
    defer store.deinit();
    const a = try store.fresh();
    const b = try store.fresh();
    const left = try store.row(&.{1}, store.node(a).tail);
    const right = try store.row(&.{2}, store.node(b).tail);
    try store.unify(left, right);
    try store.unify(b, try store.row(&.{ 1, 3 }, .closed));
    const resolved = try store.resolve(left, 0);
    const labels = try store.operationSet(resolved);
    defer allocator.free(labels);
    try std.testing.expectEqualSlices(E.Label, &.{ 1, 2, 3 }, labels);
    const point = store.mark();
    try std.testing.expectError(error.EffectMismatch, store.unify(try store.row(&.{ 1, 1 }, .closed), try store.row(&.{1}, .closed)));
    store.rollback(point);
    try std.testing.expectEqual(point, store.mark());
}
test "open effect rows expand exactly and every allocation is released" {
    try rowOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, rowOwnership, .{});
}

test "failed recursive expansion and rigid parameters leave the revision usable" {
    var store = try E.Store.init(std.testing.allocator);
    defer store.deinit();
    const a = try store.fresh();
    const recursive = try store.row(&.{42}, store.node(a).tail);
    const point = store.mark();
    try std.testing.expectError(error.InfiniteEffect, store.unify(a, recursive));
    try std.testing.expectEqual(point, store.mark());
    const parameter = try store.row(&.{}, .{ .parameter = 7 });
    const other = try store.row(&.{}, .{ .parameter = 8 });
    try std.testing.expectError(error.EffectMismatch, store.unify(parameter, other));
    try store.unify(a, parameter);
    try std.testing.expectEqual(@as(u32, 7), store.node(try store.resolve(a, 0)).tail.parameter);
}

test "inference retains repeated operations while reflection returns a distinct set" {
    var store = try E.Store.init(std.testing.allocator);
    defer store.deinit();
    const repeated = try store.row(&.{ 8, 3, 8, 3 }, .closed);
    const reordered = try store.row(&.{ 3, 8, 3, 8 }, .closed);
    try store.unify(repeated, reordered);
    try std.testing.expectEqual(@as(u32, 4), store.node(repeated).labels.len);
    const labels = try store.operationSet(repeated);
    defer store.allocator.free(labels);
    try std.testing.expectEqualSlices(E.Label, &.{ 3, 8 }, labels);
}

test "row rebuilding preserves borrowed label spans across buffer growth" {
    var store = try E.Store.init(std.testing.allocator);
    defer store.deinit();
    var labels: [1024]E.Label = undefined;
    for (&labels, 0..) |*label, index| label.* = @intCast(index);
    const original = try store.row(&labels, .closed);
    const copied = try store.row(store.list(store.node(original).labels), .closed);
    try std.testing.expectEqualSlices(E.Label, &labels, store.list(store.node(copied).labels));
    const variable = try store.fresh();
    const open = try store.row(&.{7}, store.node(variable).tail);
    const replaced = try store.substitute(open, store.node(variable).tail.variable, original);
    try std.testing.expectEqual(@as(u32, 1025), store.node(replaced).labels.len);
    const free = try store.freeVariables(open);
    defer store.allocator.free(free);
    try std.testing.expectEqualSlices(u32, &.{store.node(variable).tail.variable}, free);
    try std.testing.expectError(error.EffectMismatch, store.operationSet(open));
}

test "generated row histories match sequential replacement at every cursor" {
    var random: u32 = 12345;
    for (0..12) |_| {
        var store = try E.Store.init(std.testing.allocator);
        defer store.deinit();
        var roots: [6]E.Id = undefined;
        for (&roots) |*root| root.* = try store.fresh();
        for (0..24) |_| {
            random = random *% 1664525 +% 1013904223;
            const variable = store.node(roots[random % roots.len]).tail.variable;
            random = random *% 1664525 +% 1013904223;
            const tail: E.Tail = if (random % 4 == 0) .closed else store.node(roots[(random >> 4) % roots.len]).tail;
            const replacement_id = try store.row(&.{random % 5}, tail);
            try store.appendVersionAt(variable, replacement_id, store.next_position + random % 3);
        }
        const history_end = store.next_position;
        for (roots) |root| {
            for (0..@as(usize, history_end) + 1) |cursor| {
                var expected: std.ArrayList(E.Label) = .empty;
                defer expected.deinit(store.allocator);
                var tail = store.node(root).tail;
                var position: E.Cursor = @intCast(cursor);
                // Independent oracle scans the entire chronological sequence;
                // it never uses the candidate's per-variable version index.
                for (store.versions.items) |write| {
                    if (write.position < position or tail != .variable or write.variable != tail.variable) continue;
                    const replacement_ = store.node(write.replacement);
                    try expected.appendSlice(store.allocator, store.list(replacement_.labels));
                    tail = replacement_.tail;
                    position = write.position + 1;
                }
                const actual = store.node(try store.resolve(root, @intCast(cursor)));
                try std.testing.expectEqualSlices(E.Label, expected.items, store.list(actual.labels));
                try std.testing.expect(std.meta.eql(tail, actual.tail));
                if (tail == .variable) try std.testing.expectEqual(position, actual.cursor);
            }
        }
    }
}

test "edge extraction shares immutable labels while retaining independent historical headers" {
    var store = try E.Store.init(std.testing.allocator);
    defer store.deinit();
    const variable = try store.fresh();
    const original = try store.rowAt(&.{ 7, 3, 7 }, store.node(variable).tail, 9);
    const first = try store.extract(original, 7);
    try std.testing.expect(first.remaining != original);
    try std.testing.expectEqual(store.node(original).labels.start + 1, store.node(first.remaining).labels.start);
    try std.testing.expectEqualSlices(E.Label, &.{ 3, 7 }, store.list(store.node(first.remaining).labels));
    try std.testing.expectEqual(@as(E.Cursor, 0), store.node(first.remaining).cursor);
    try std.testing.expectEqual(@as(E.Cursor, 9), store.node(original).cursor);
    const replacement = try store.row(&.{11}, .closed);
    try store.appendVersionAt(store.node(variable).tail.variable, replacement, 5);
    try std.testing.expectEqualSlices(E.Label, &.{ 3, 7, 11 }, store.list(store.node(try store.resolve(first.remaining, 0)).labels));
    try std.testing.expectEqualSlices(E.Label, &.{ 7, 3, 7 }, store.list(store.node(try store.resolve(original, 0)).labels));
    const reordered = try store.rowAt(&.{ 7, 3, 11 }, .closed, 17);
    const last = try store.extract(reordered, 11);
    try std.testing.expectEqual(store.node(reordered).labels.start, store.node(last.remaining).labels.start);
    try std.testing.expectEqualSlices(E.Label, &.{ 7, 3 }, store.list(store.node(last.remaining).labels));
    try std.testing.expectEqual(@as(E.Cursor, 0), store.node(last.remaining).cursor);
    const middle = try store.extract(original, 3);
    try std.testing.expectEqualSlices(E.Label, &.{ 7, 7 }, store.list(store.node(middle.remaining).labels));
    const only = try store.row(&.{3}, .closed);
    try std.testing.expectEqual(@as(E.Id, 0), (try store.extract(only, 3)).remaining);
}

fn edgeSpanOwnership(allocator: std.mem.Allocator) !void {
    var store = try E.Store.init(allocator);
    defer store.deinit();
    const original = try store.row(&.{ 1, 2, 3, 2 }, .closed);
    const edge = (try store.extract(original, 1)).remaining;
    const point = store.mark();
    var growth: [1024]E.Label = undefined;
    for (&growth, 0..) |*label, index| label.* = @intCast(index + 20);
    _ = try store.row(&growth, .closed);
    try std.testing.expectEqualSlices(E.Label, &.{ 2, 3, 2 }, store.list(store.node(edge).labels));
    store.rollback(point);
    _ = try store.row(&.{ 99, 98, 97 }, .closed);
    try std.testing.expectEqualSlices(E.Label, &.{ 2, 3, 2 }, store.list(store.node(edge).labels));
    while (store.rows.items.len < store.rows.capacity) _ = try store.row(&.{}, .{ .parameter = 1 });
    const full = store.mark();
    const another = store.extract(edge, 2) catch |err| {
        try std.testing.expectEqual(full, store.mark());
        return err;
    };
    try std.testing.expectEqualSlices(E.Label, &.{ 3, 2 }, store.list(store.node(another.remaining).labels));
    store.rollback(full);
    _ = try store.row(&.{}, .{ .parameter = 8 });
    try std.testing.expectEqualSlices(E.Label, &.{ 2, 3, 2 }, store.list(store.node(edge).labels));
}
test "edge spans survive growth rollback recycled row IDs and allocation failure" {
    try edgeSpanOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, edgeSpanOwnership, .{});
}
