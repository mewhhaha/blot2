const std = @import("std");
const wasm = @import("wasm.zig");
const sharing = @import("machine_code_sharing.zig");
const retained = @import("optimized_bodies.zig");

test "machine body sharing preserves exported identities and exact immediates signatures and calls" {
    const a = std.testing.allocator;
    var module = wasm.Module.init(a);
    defer module.deinit();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    const public = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second, public }) |id| try module.emit(id, .{ .op = .local_get });
    try module.exportFunction(public, "public", .u32, .u32);
    const positive = try module.addFunction(&.{}, .f32);
    const negative = try module.addFunction(&.{}, .f32);
    try module.emit(positive, .{ .op = .f32_const, .operand = 0 });
    try module.emit(negative, .{ .op = .f32_const, .operand = 0x80000000 });
    const caller1 = try module.addFunction(&.{.i32}, .i32);
    const caller2 = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(caller1, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = first } });
    try module.emitSlice(caller2, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = second } });
    var index = try sharing.Index.init(a, &module, true);
    defer index.deinit();
    try std.testing.expectEqual(@as(usize, 6), index.unique);
    try std.testing.expectEqual(index.function(first), index.function(second));
    try std.testing.expect(index.function(public) != index.function(first));
    try std.testing.expect(index.function(positive) != index.function(negative));
    // No normalization guesses across distinct call identities.
    try std.testing.expect(index.function(caller1) != index.function(caller2));
    try std.testing.expect(index.emits(first) and !index.emits(second));
}

fn sharingScenario(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const first = try module.addFunction(&.{.i32}, .i32);
    const second = try module.addFunction(&.{.i32}, .i32);
    for ([_]u32{ first, second }) |id| {
        const local = try module.addLocal(id, .i32);
        try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 128 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = local }, .{ .op = .i32_load } });
    }
    var old: retained.Capture = .{ .allocator = a };
    defer old.deinit();
    var stats: retained.Stats = .{};
    const before = try module.assembleWithOptions(.{ .share_machine_code = true, .current = &old, .stats = &stats });
    defer a.free(before);
    try std.testing.expect(stats.shared >= 1);
    try std.testing.expect(old.output(first) != null);
    try std.testing.expect(old.output(second) != null);
    try module.emitSlice(first, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    var changed: retained.Capture = .{ .allocator = a };
    defer changed.deinit();
    stats = .{};
    const after = try module.assembleWithOptions(.{ .share_machine_code = true, .previous = &old, .current = &changed, .stats = &stats });
    defer a.free(after);
    // Each source identity retains its independently prepared body before
    // sharing. Separating a duplicate keeps retained cleanup exact.
    try std.testing.expect(changed.output(second) != null);
    const fresh = try module.assembleWithOptions(.{ .share_machine_code = true });
    defer a.free(fresh);
    try std.testing.expectEqualSlices(u8, fresh, after);
    try std.testing.expectEqual(module.functions.items.len, stats.reused + stats.optimized);
}

test "machine body sharing rebuilds separated retained bodies and releases failed allocations" {
    try sharingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, sharingScenario, .{});
}

fn typedSharingScenario(a: std.mem.Allocator) !void {
    const ir = @import("runtime_ir.zig");
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    var factories: [2]u32 = undefined;
    for (&factories, 0..) |*id, index| {
        var role: ir.Role = .scalar;
        if (index != 0) role = .reference;
        id.* = try module.addTypedFunction(&.{.i32}, .i32, .reference);
        try module.setParameterRoles(id.*, ir.packParameterRoles(&.{role}));
        const local = try module.addLocal(id.*, .i32);
        var annotations: [ir.max_annotations]ir.Instruction = undefined;
        try module.emitSlice(id.*, ir.annotations(&.{ .scalar, role }, .unknown, &annotations));
        try module.emitSlice(id.*, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_store }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store, .operand = 4 }, .{ .op = .local_get, .operand = local } });
    }
    // Raw instructions alone intentionally erase the checked field roles.
    var source_index = try sharing.Index.init(a, &module, true);
    defer source_index.deinit();
    try std.testing.expectEqual(source_index.function(factories[0]), source_index.function(factories[1]));
    var capture: retained.Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .share_machine_code = true, .current = &capture });
    defer a.free(bytes);
    const marker = std.mem.findLast(u8, bytes, "blot:ownership").? + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 2, 2, 0 }, bytes[marker..][0..3]);
    const first = capture.output(factories[0]).?;
    const second = capture.output(factories[1]).?;
    var left = module.functions.items[factories[0]];
    left.locals = first.locals;
    left.instructions = first.instructions;
    var right = module.functions.items[factories[1]];
    right.locals = second.locals;
    right.instructions = second.instructions;
    try std.testing.expect(!@import("runtime_function_key.zig").equal(left, right));
}
test "prepared machine sharing preserves distinct scalar and owning publications with complete admission" {
    try typedSharingScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, typedSharingScenario, .{});
}

fn tableSlotSharing(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    var last: u32 = 0;
    for (0..4) |_| {
        last = try module.addTypedFunction(&.{}, .i32, .scalar);
        try module.emit(last, .{ .op = .i32_const, .operand = 41 });
    }
    const caller = try module.addTypedFunction(&.{}, .i32, .scalar);
    try module.emitReference(caller, .{ .op = .i32_const, .operand = last }, .table_function);
    try module.exportFunction(caller, "slot", .unit, .u32);
    var index = try sharing.Index.init(a, &module, true);
    defer index.deinit();
    try std.testing.expect(last >= index.unique);
    var capture: retained.Capture = .{ .allocator = a };
    defer capture.deinit();
    const bytes = try module.assembleWithOptions(.{ .share_machine_code = true, .current = &capture });
    defer a.free(bytes);
    const replay = try module.assembleWithOptions(.{ .share_machine_code = true, .previous = &capture });
    defer a.free(replay);
    try std.testing.expectEqualSlices(u8, bytes, replay);
    module.functions.items[caller].instructions.items[0].operand = @intCast(module.functions.items.len);
    const rejected = module.assembleWithOptions(.{ .share_machine_code = true }) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectEqual(error.InvalidFunctionReference, err);
        return;
    };
    defer a.free(rejected);
    return error.TestExpectedError;
}
test "machine sharing validates original indirect table slots separately from compact function indexes through OOM" {
    try tableSlotSharing(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, tableSlotSharing, .{});
}
