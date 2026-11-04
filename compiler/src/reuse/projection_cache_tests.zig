const std = @import("std");
const T = @import("../check/types.zig");
const E = @import("../eval/type_evidence.zig");
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
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, historyScenario, .{});
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

fn ownedLabelsScenario(a: Allocator) !void {
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    const point = try source.nominal(.{ .unit = 3, .decl = 7 }, &.{ T.u32_type, T.f32_type });
    const read = try source.internOperation(.{ .unit = 3, .decl = 8 }, &.{point});
    const write = try source.internOperation(.{ .unit = 3, .decl = 9 }, &.{ point, try source.array(point) });
    const tick = try source.internOperation(.{ .unit = 3, .decl = 10 }, &.{});
    const inner_row = try source.effects.row(&.{ read, tick }, .closed);
    const callback = try source.functionWithEffects(point, T.unit, inner_row);
    const nested = try source.internOperation(.{ .unit = 3, .decl = 11 }, &.{callback});
    const rows = [_]u32{
        try source.effects.row(&.{read}, .closed),
        try source.effects.row(&.{ read, write }, .closed),
        try source.effects.row(&.{ write, read, read }, .closed),
        try source.effects.row(&.{ nested, tick, read }, .closed),
        inner_row,
    };
    var results: [rows.len * 2]u32 = undefined;
    for (rows, 0..) |row, index| {
        results[index * 2] = try compare(&cache, &source, &target, try source.functionWithEffects(T.u32_type, T.boolean, row));
        results[index * 2 + 1] = try compare(&cache, &source, &target, try source.functionWithEffects(T.f32_type, callback, row));
    }
    try std.testing.expectEqual(@as(u32, 4), cache.labels.count());
    // Repeated owners reuse every label and still equal fresh projection.
    for (rows, 0..) |row, index| {
        try std.testing.expectEqual(results[index * 2], try compare(&cache, &source, &target, try source.functionWithEffects(T.u32_type, T.boolean, row)));
        const wrapped = try compare(&cache, &source, &target, try source.product(&.{try source.functionWithEffects(T.f32_type, callback, row)}));
        try std.testing.expectEqual(results[index * 2 + 1], target.children(wrapped)[0]);
    }
    // A recycled label ID after rollback projects its new arguments.
    const mark = source.mark();
    const recycled = try source.internOperation(.{ .unit = 3, .decl = 12 }, &.{T.u32_type});
    const recycled_row = try source.effects.row(&.{recycled}, .closed);
    const old = try compare(&cache, &source, &target, try source.functionWithEffects(T.u32_type, T.u32_type, recycled_row));
    source.rollback(mark);
    try std.testing.expectEqual(recycled, try source.internOperation(.{ .unit = 3, .decl = 12 }, &.{T.f32_type}));
    const fresh_row = try source.effects.row(&.{recycled}, .closed);
    try std.testing.expect(old != try compare(&cache, &source, &target, try source.functionWithEffects(T.u32_type, T.u32_type, fresh_row)));
    // A physical write to a label's arguments revokes its memo.
    const before = try compare(&cache, &source, &target, try source.functionWithEffects(T.unit, T.unit, fresh_row));
    source.replaceListItem(source.operation(recycled).arguments, 0, T.boolean);
    try std.testing.expect(before != try compare(&cache, &source, &target, try source.functionWithEffects(T.unit, T.unit, fresh_row)));
}
test "owned projection memoizes operation labels exactly with invalidation and allocation failures" {
    try ownedLabelsScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownedLabelsScenario, .{});
}
test "owned projection label hits charge exact argument visits and depth" {
    const a = std.testing.allocator;
    var source = try T.Store.initWithOptions(a, .{ .closed_graphs = true });
    defer source.deinit();
    var target = try E.Store.init(a);
    defer target.deinit();
    var cache: Cache = .{};
    defer cache.deinit(a);
    // A label over a 2^19-visit DAG: one occurrence fits the budget, a
    // repeated occurrence exceeds it whether or not the label is memoized.
    var dag: u32 = T.u32_type;
    for (0..18) |_| dag = try source.product(&.{ dag, dag });
    const heavy = try source.internOperation(.{ .unit = 3, .decl = 8 }, &.{dag});
    const single = try source.effects.row(&.{heavy}, .closed);
    try std.testing.expectEqual(try target.project(&source, try source.functionWithEffects(T.unit, T.unit, single), &.{}), try target.projectOwned(&source, try source.functionWithEffects(T.unit, T.unit, single), &cache));
    try std.testing.expect(cache.labels.contains(heavy));
    const twice = try source.effects.row(&.{ heavy, heavy }, .closed);
    try std.testing.expectError(error.EvidenceLimit, target.project(&source, try source.functionWithEffects(T.boolean, T.unit, twice), &.{}));
    try std.testing.expectError(error.EvidenceLimit, target.projectOwned(&source, try source.functionWithEffects(T.boolean, T.unit, twice), &cache));
    // A memoized label fails at the same depth as its re-projection: the
    // row of a function nested k arrays deep holds an argument m arrays tall.
    var tall: u32 = T.u32_type;
    for (0..100) |_| tall = try source.array(tall);
    const deep = try source.internOperation(.{ .unit = 3, .decl = 9 }, &.{tall});
    const deep_row = try source.effects.row(&.{deep}, .closed);
    _ = try target.projectOwned(&source, try source.functionWithEffects(T.unit, T.unit, deep_row), &cache);
    try std.testing.expect(cache.labels.contains(deep));
    for ([_]usize{ 1021 - 100, 1022 - 100 }) |k| {
        var root = try source.functionWithEffects(T.f32_type, T.unit, deep_row);
        for (0..k) |_| root = try source.array(root);
        const expected = target.project(&source, root, &.{});
        const actual = target.projectOwned(&source, root, &cache);
        if (expected) |value| try std.testing.expectEqual(value, try actual) else |err| try std.testing.expectError(err, actual);
        if (k == 1022 - 100) try std.testing.expectError(error.EvidenceLimit, actual);
    }
}
