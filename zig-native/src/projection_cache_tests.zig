const std = @import("std");
const T = @import("types.zig");
const E = @import("type_evidence.zig");
const Cache = @import("projection_cache.zig").Cache;
const Allocator = std.mem.Allocator;
fn compare(cache: *Cache, source: *T.Store, target: *E.Store, root: u32) !u32 {
    const resolved = try source.resolve(root, 0);
    const expected = target.project(source, resolved, &.{}) catch |err| switch (err) {
        error.UnresolvedType => @as(u32, 0),
        else => return err,
    };
    const actual = target.projectOwned(source, resolved, cache) catch |err| switch (err) {
        error.UnresolvedType => @as(u32, 0),
        else => return err,
    };
    try std.testing.expectEqual(expected, actual);
    return actual;
}
fn historyScenario(a: Allocator) !void {
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const variable = try source.fresh();
    const open = try source.array(variable);
    try std.testing.expectEqual(@as(u32, 0), try compare(&cache, &source, &target, open));
    try source.appendVersion(variable, T.u32_type);
    const selected = try compare(&cache, &source, &target, open);
    try std.testing.expectEqual(E.Tag.array, target.node(selected).tag);
    try source.appendVersion(variable, T.f32_type);
    try std.testing.expectEqual(selected, try compare(&cache, &source, &target, open));
    const point = source.mark();
    const previous = try source.array(T.boolean);
    const old = try compare(&cache, &source, &target, previous);
    source.rollback(point);
    const replacement = try source.sequence(.list, T.f32_type);
    try std.testing.expectEqual(previous, replacement);
    const new = try compare(&cache, &source, &target, replacement);
    try std.testing.expect(old != new);
    try std.testing.expectEqual(E.Tag.list, target.node(new).tag);
    const record = try source.record(&.{.{ .name = 17, .ty = replacement }});
    const before = try compare(&cache, &source, &target, record);
    const node = source.node(record);
    source.replaceListItem(.{ .start = node.a, .len = node.b * 2 }, 1, T.u32_type);
    try std.testing.expect(before != try compare(&cache, &source, &target, record));
    source.closed_generation = std.math.maxInt(u16);
    try std.testing.expectEqual(try compare(&cache, &source, &target, replacement), new);
}
test "subtree projection preserves chronology collection identity rollback physical writes and allocation failures" {
    try historyScenario(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, historyScenario, .{});
}
test "subtree projection invalidates independently recycled effect rows" {
    const a = std.testing.allocator;
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const integer = try source.internOperation(.{ .unit = 3, .decl = 9 }, &.{T.u32_type});
    const floating = try source.internOperation(.{ .unit = 3, .decl = 9 }, &.{T.f32_type});
    const point = source.effects.mark();
    const row = try source.effects.row(&.{integer}, .closed);
    const callable = try source.functionWithEffects(T.u32_type, T.boolean, row);
    const old = try target.projectOwned(&source, callable, &cache);
    source.effects.rollback(point);
    try std.testing.expectEqual(row, try source.effects.row(&.{floating}, .closed));
    const fresh = try target.projectOwned(&source, callable, &cache);
    try std.testing.expect(old != fresh);
    try std.testing.expectEqual(try target.project(&source, callable, &.{}), fresh);
}
test "subtree projection charges repeated DAG visits and exact recursive depth on cache hits" {
    const a = std.testing.allocator;
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    var root: u32 = T.u32_type;
    for (0..18) |_| root = try source.product(&.{ root, root });
    try std.testing.expectEqual(try target.project(&source, root, &.{}), try target.projectOwned(&source, root, &cache));
    root = try source.product(&.{ root, root });
    try std.testing.expectError(error.EvidenceLimit, target.project(&source, root, &.{}));
    try std.testing.expectError(error.EvidenceLimit, target.projectOwned(&source, root, &cache));
    root = T.u32_type;
    for (0..1023) |_| root = try source.array(root);
    try std.testing.expectEqual(try target.project(&source, root, &.{}), try target.projectOwned(&source, root, &cache));
    root = try source.array(root);
    try std.testing.expectError(error.EvidenceLimit, target.project(&source, root, &.{}));
    try std.testing.expectError(error.EvidenceLimit, target.projectOwned(&source, root, &cache));
}

test "subtree projection keys belong to both source and semantic owners" {
    const a = std.testing.allocator;
    var first = try T.Store.init(a);
    defer first.deinit();
    var second = try T.Store.init(a);
    defer second.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var another = try E.Store.init(a);
    defer another.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const list = try first.sequence(.list, T.u32_type);
    const array = try second.array(T.u32_type);
    try std.testing.expectEqual(list, array);
    const left = try target.projectOwned(&first, list, &cache);
    const right = try target.projectOwned(&second, array, &cache);
    try std.testing.expectEqual(E.Tag.list, target.node(left).tag);
    try std.testing.expectEqual(E.Tag.array, target.node(right).tag);
    _ = try another.intern(.nominal, 11, 7, &.{T.f32_type});
    const moved = try another.projectOwned(&first, list, &cache);
    try std.testing.expect(moved != left);
    try std.testing.expectEqual(E.Tag.list, another.node(moved).tag);
    try std.testing.expectEqual(try another.project(&first, list, &.{}), moved);
}

test "subtree projection shares all semantic forms while preserving phantom and effect arguments" {
    const a = std.testing.allocator;
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const integer = try source.nominal(.{ .unit = 3, .decl = 7 }, &.{T.u32_type});
    const floating = try source.nominal(.{ .unit = 3, .decl = 7 }, &.{T.f32_type});
    const read = try source.nominal(.{ .unit = 3, .decl = 8 }, &.{integer});
    const write = try source.nominal(.{ .unit = 3, .decl = 9 }, &.{integer});
    const operation = try source.internOperation(.{ .unit = 3, .decl = 8 }, &.{integer});
    const row = try source.effects.row(&.{operation}, .closed);
    const constructor = try source.typeConstructor(.{ .unit = 3, .decl = 7 });
    const shapes = [_]u32{
        T.unit,                                                 T.boolean,                                                                               T.u32_type,                                 T.f32_type,                     T.never,                                        integer,     floating,
        try source.array(integer),                              try source.sequence(.list, integer),                                                     try source.demandWithEffects(integer, row), try source.provider(read, row), try source.stateProvider(read, write, integer), constructor, try source.resolver(constructor),
        try source.functionWithEffects(floating, integer, row), try source.record(&.{ .{ .name = 11, .ty = integer }, .{ .name = 3, .ty = floating } }),
    };
    const root = try source.product(&shapes);
    const expected = try compare(&cache, &source, &target, root);
    try std.testing.expectEqual(expected, try compare(&cache, &source, &target, root));
    try std.testing.expect(try compare(&cache, &source, &target, integer) != try compare(&cache, &source, &target, floating));
    source.effects.physical_epoch = std.math.maxInt(u64);
    try std.testing.expectEqual(expected, try compare(&cache, &source, &target, root));
}
