const std = @import("std");
const wasm = @import("wasm.zig");
const retained = @import("optimized_bodies.zig");

fn assemble(a: std.mem.Allocator, module: *const wasm.Module, old: ?*const retained.Capture, current: *retained.Capture, stats: *retained.Stats) ![]u8 {
    _ = a;
    return module.assembleWithOptions(.{ .previous = old, .current = current, .stats = stats });
}

test "optimized bodies survive unrelated edits and keep immutable owned results" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second }) |id| try module.emitSlice(id, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try assemble(a, &module, null, &old, &stats);
    defer a.free(before);
    try std.testing.expectEqual(@as(usize, 2), stats.optimized);
    module.functions.items[second].instructions.items[1].operand = 2;
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    stats = .{};
    const edited = try assemble(a, &module, &old, &current, &stats);
    defer a.free(edited);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expectEqual(@as(usize, 1), stats.reused);
    try std.testing.expectEqual(@as(usize, 1), stats.optimized);
    module.functions.items[second].instructions.items[1].operand = 1;
    var reverted: retained.Capture = .{ .allocator = a };
    defer reverted.deinit();
    stats = .{};
    const original = try assemble(a, &module, &old, &reverted, &stats);
    defer a.free(original);
    try std.testing.expectEqualSlices(u8, before, original);
    try std.testing.expectEqual(@as(usize, 2), stats.reused);
}

test "unchanged callers invalidate when transitive ownership facts change" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const escaped = try module.addGlobal(.pointer, 0, true);
    const read = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .i32_load } });
    const middle = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(middle, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = read } });
    const caller = try module.addFunction(&.{}, .i32);
    const object = try module.addLocal(caller, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .call, .operand = middle } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try assemble(a, &module, null, &old, &stats);
    defer a.free(before);
    try std.testing.expect(old.output(caller) != null);
    module.functions.items[read].instructions.clearRetainingCapacity();
    try module.emitSlice(read, &.{ .{ .op = .local_get }, .{ .op = .global_set, .operand = escaped }, .{ .op = .local_get }, .{ .op = .i32_load } });
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    stats = .{};
    const edited = try assemble(a, &module, &old, &current, &stats);
    defer a.free(edited);
    const fresh = try module.assemble();
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, edited);
    try std.testing.expect(current.output(caller) == null);
    var matches = try retained.Matcher.init(a, &old, &current);
    defer matches.deinit();
    try std.testing.expect(!matches.matches(caller));
    try std.testing.expect(stats.reused > 0);
}

fn failureScenario(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const id = try module.addFunction(&.{.i32}, .i32);
    try module.emit(id, .{ .op = .local_get });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const first = try assemble(a, &module, null, &old, &stats);
    defer a.free(first);
    var current: retained.Capture = .{ .allocator = a };
    defer current.deinit();
    const next = try assemble(a, &module, &old, &current, &stats);
    defer a.free(next);
    try std.testing.expectEqualSlices(u8, first, next);
}
test "optimized input and output publication releases every failed allocation" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, failureScenario, .{});
}

test "development tier keeps lifetime cleanup and rejects optimized body captures from another tier" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const id = try module.addFunction(&.{.i32}, .i32);
    const object = try module.addLocal(id, .i32);
    try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = object }, .{ .op = .local_get, .operand = object }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = object }, .{ .op = .i32_load } });
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    const optimized = try module.assembleWithOptions(.{ .current = &old });
    defer a.free(optimized);
    var dev: retained.Capture = .{ .allocator = a };
    defer dev.deinit();
    var stats: retained.Stats = .{};
    const development = try module.assembleWithOptions(.{ .tier = .development, .previous = &old, .current = &dev, .stats = &stats });
    defer a.free(development);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
    try std.testing.expectEqual(.development, dev.tier);
    try std.testing.expectEqual(.development, stats.tier);
    const body = dev.output(id) orelse return error.TestUnexpectedResult;
    try std.testing.expect(for (body.instructions.items) |inst| {
        if (inst.op == .call and inst.operand == arena.recycle) break true;
    } else false);
    var next: retained.Capture = .{ .allocator = a };
    defer next.deinit();
    stats = .{};
    const reused = try module.assembleWithOptions(.{ .tier = .development, .previous = &dev, .current = &next, .stats = &stats });
    defer a.free(reused);
    try std.testing.expectEqualSlices(u8, development, reused);
    try std.testing.expectEqual(module.functions.items.len, stats.reused);
    var restored: retained.Capture = .{ .allocator = a };
    defer restored.deinit();
    stats = .{};
    const back = try module.assembleWithOptions(.{ .previous = &next, .current = &restored, .stats = &stats });
    defer a.free(back);
    try std.testing.expectEqualSlices(u8, optimized, back);
    try std.testing.expectEqual(@as(usize, 0), stats.reused);
}
