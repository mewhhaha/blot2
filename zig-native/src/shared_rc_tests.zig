const std = @import("std");
const w = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const lifetimes = @import("wasm_lifetimes.zig");
const a = std.testing.allocator;

fn allocation(module: *w.Module, function: u32, local: u32, roles: []const ir.Role) !void {
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    try module.emitSlice(function, ir.annotations(roles, .unknown, &buffer));
    try module.emitSlice(function, &.{ .{ .op = .i32_const, .operand = @intCast(roles.len * 4) }, .{ .op = .call, .operand = module.arena.?.allocate }, .{ .op = .local_set, .operand = local } });
}
fn scenario(allocator: std.mem.Allocator, erased: bool) !void {
    var module = w.Module.init(allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addFunction(&.{.i32}, .i32);
    const child = try module.addLocal(function, .i32);
    const parent = try module.addLocal(function, .i32);
    try allocation(&module, function, child, &.{.scalar});
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = child }, .{ .op = .local_get, .operand = 0 }, .{ .op = .i32_store } });
    const role: ir.Role = if (erased) .value else .reference;
    try allocation(&module, function, parent, &.{ role, role });
    inline for (.{ 0, 4 }) |offset| try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .local_get, .operand = child }, .{ .op = .i32_store, .operand = offset } });
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = parent }, .{ .op = .i32_load }, .{ .op = .i32_load } });
    const before = try allocator.dupe(ir.Instruction, module.functions.items[function].instructions.items);
    defer allocator.free(before);
    var summaries = try lifetimes.Summaries.init(allocator, &module);
    defer summaries.deinit();
    try summaries.prepare();
    var proof = try lifetimes.rcPlan(allocator, &module, &module.functions.items[function], &summaries);
    defer proof.deinit(allocator);
    try std.testing.expectEqual(!erased, proof.admitted);
    var output = try lifetimes.runRc(allocator, &module, &module.functions.items[function], &summaries);
    defer if (output) |*body| body.deinit(allocator);
    try std.testing.expectEqual(!erased, output != null);
    if (output) |body| {
        var allocations: usize = 0;
        var writes: usize = 0;
        var scalar_writes: usize = 0;
        for (body.instructions.items) |inst| {
            if (inst.op == .i32_store) scalar_writes += 1;
            if (inst.op != .call) continue;
            if (inst.operand == arena.allocate_typed) allocations += 1;
            if (inst.operand == arena.store_word) writes += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), allocations);
        try std.testing.expectEqual(@as(usize, 2), writes);
        try std.testing.expectEqual(@as(usize, 1), scalar_writes);
    }
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[function].instructions.items);
    const bytes = try module.assembleWithOptions(.{ .tier = .development });
    defer allocator.free(bytes);
    const offset = std.mem.find(u8, bytes, "blot:ownership") orelse return error.TestExpectedOwnershipManifest;
    try std.testing.expectEqual(@as(u8, 1), bytes[offset + "blot:ownership".len]);
    try std.testing.expectEqual(@as(u8, @intFromBool(!erased)), bytes[offset + "blot:ownership".len + 1]);
    var fallback = w.OwnershipFallback.none;
    if (erased) fallback = .unproven_body;
    try std.testing.expectEqual(@backingInt(fallback), bytes[offset + "blot:ownership".len + 2]);
}
test "shared RC prepares duplicate typed fields and declines erased whole-module graphs without mutating inputs" {
    try scenario(a, false);
    try scenario(a, true);
}
test "shared RC ownership preparation and emission release every allocation on OOM" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{false});
}
test "shared RC compact field masks preserve scalar and owner-token words" {
    const layout = @import("runtime_layout.zig");
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(layout.ArenaHeader));
    try std.testing.expectEqual(@as(u32, 0x30), layout.referenceMask(&.{ .scalar, .scalar, .scalar, .scalar, .reference, .reference }, .scalar).?);
    try std.testing.expectEqual(@as(u32, 0xfffffff0), layout.referenceMask(&.{ .scalar, .scalar, .scalar, .scalar }, .reference).?);
    try std.testing.expect(!layout.referenceWord(0xfffffff0, 0));
    try std.testing.expect(layout.referenceWord(0xfffffff0, 20000));
    try std.testing.expectEqual(@as(?u32, null), layout.referenceMask(&.{.value}, .scalar));
}

test "shared RC admits only a full zero fill before fresh payload access" {
    for (0..4) |variant| {
        var module = w.Module.init(a);
        defer module.deinit();
        const arena = try module.ensureArena();
        const function = try module.addFunction(&.{}, .i32);
        const local = try module.addLocal(function, .i32);
        try allocation(&module, function, local, &.{.reference});
        if (variant == 3) try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = local }, .{ .op = .i32_load }, .{ .op = .drop } });
        try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = local }, .{ .op = .i32_const, .operand = @intFromBool(variant == 1) }, .{ .op = .i32_const, .operand = if (variant == 2) 3 else 4 }, .{ .op = .memory_fill }, .{ .op = .local_get, .operand = local } });
        var summaries = try lifetimes.Summaries.init(a, &module);
        defer summaries.deinit();
        try summaries.prepare();
        var plan = try lifetimes.rcPlan(a, &module, &module.functions.items[function], &summaries);
        defer plan.deinit(a);
        try std.testing.expectEqual(variant == 0, plan.admitted);
        if (variant == 0) {
            var output = (try lifetimes.runRc(a, &module, &module.functions.items[function], &summaries)).?;
            defer output.deinit(a);
            var typed = false;
            var zero = false;
            for (output.instructions.items) |inst| {
                if (inst.op == .call and inst.operand == arena.allocate_typed) typed = true;
                if (inst.op == .memory_fill) zero = true;
            }
            try std.testing.expect(typed and zero);
        }
    }
}
