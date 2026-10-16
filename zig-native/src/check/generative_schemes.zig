//! Owned invocation binders. Arrow and selected-value roots share one type owner;
//! result/capture identity is fresh only when that declaring arrow is called.
const std = @import("std");
const T = @import("types.zig");
pub const Binder = struct { owner: u32 = 0, origin: u32 = 0, arrow: T.Id = 0, selection: T.Id };
pub const limit = 16;
pub fn sameArrow(store: *T.Store, left: T.Id, right: T.Id) T.Error!bool {
    const a = store.node(try store.resolve(left, 0));
    const b = store.node(try store.resolve(right, 0));
    if (a.tag != .function or b.tag != .function) return false;
    if (!try store.equalSymbolic(a.a, b.a)) return false;
    const left_rows = try store.freeRowVariables(a.b);
    defer store.allocator.free(left_rows);
    const right_rows = try store.freeRowVariables(b.b);
    defer store.allocator.free(right_rows);
    const left_result = try store.closeCovariant(try store.resolve(a.b, 0), left_rows, &.{});
    const right_result = try store.closeCovariant(try store.resolve(b.b, 0), right_rows, &.{});
    if (!try store.equalSymbolic(left_result, right_result)) return false;
    // Closing/reopening the owned ambient tail does not create another lambda.
    const ar = try store.resolveEffects(a.c, 0);
    const br = try store.resolveEffects(b.c, 0);
    return std.mem.eql(T.Effects.Label, store.rowLabels(ar), store.rowLabels(br));
}
pub fn collect(store: *T.Store, allocator: std.mem.Allocator, root: T.Id, binders: []const Binder) T.Error!T.List {
    if (binders.len == 0) return .{};
    var pending: std.ArrayList(T.Id) = .empty;
    defer pending.deinit(allocator);
    var visited: std.AutoHashMapUnmanaged(T.Id, void) = .empty;
    defer visited.deinit(allocator);
    var result: std.ArrayList(T.Id) = .empty;
    defer result.deinit(allocator);
    try pending.append(allocator, root);
    while (pending.pop()) |original| {
        const id = try store.resolve(original, 0);
        if (visited.contains(id)) continue;
        if (visited.count() >= 4096) return error.TypeLimit;
        try visited.put(allocator, id, {});
        const node = store.node(id);
        if (node.tag == .function) {
            for (binders) |binder| {
                if (binder.arrow == 0 or !try sameArrow(store, binder.arrow, id)) continue;
                const selected = try store.resolve(binder.selection, 0);
                var duplicate = false;
                for (0..result.items.len / 2) |index| if (result.items[index * 2] == id and result.items[index * 2 + 1] == selected) {
                    duplicate = true;
                    break;
                };
                if (duplicate) continue;
                if (result.items.len == limit * 2) return error.TypeLimit;
                try result.appendSlice(allocator, &.{ id, selected });
            }
            try pending.appendSlice(allocator, &.{ node.a, node.b });
        } else switch (node.tag) {
            .usage, .array, .list, .cursor, .demand, .resolver, .provider => try pending.append(allocator, node.a),
            .state_provider => try pending.appendSlice(allocator, &.{ node.a, node.b, node.c }),
            .product => try pending.appendSlice(allocator, store.list(.{ .start = node.a, .len = node.b })),
            .record => for (0..node.b) |index| try pending.append(allocator, store.recordField(node, index).ty),
            .nominal => try pending.appendSlice(allocator, store.nominalArguments(node)),
            else => {},
        }
    }
    return store.saveList(result.items);
}
