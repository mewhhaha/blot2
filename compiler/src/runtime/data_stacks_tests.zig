const std = @import("std");
const stacks = @import("data_stacks.zig");
fn scenario(a: std.mem.Allocator) !void {
    var module = try @import("data_stacks_fixture.zig").build(a);
    defer module.deinit();
    try std.testing.expect(module.arena == null);
    try std.testing.expectEqual(@as(usize, 0), module.data.items.len);
    try std.testing.expectEqual(stacks.data_base + 32768 + 4096 + 8192, module.fixed_memory_bytes);
    try std.testing.expectError(error.ModuleTooLarge, module.ensureArena());
    for (module.functions.items) |function| for (function.instructions.items) |instruction| {
        try std.testing.expect(instruction.op != .memory_grow and instruction.op != .call_import);
    };
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer a.free(bytes);
    try std.testing.expect(bytes.len > 8);
}
test "data stacks have no counted heap and release every compiler allocation on failure" {
    try scenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}

test "data stack plans account for metadata and reject address-space overflow" {
    const plan: stacks.Plan = .{ .region_capacities = &.{ 4096, 8192 }, .owner_capacity = 300 };
    const memory = try stacks.layout(plan);
    try std.testing.expectEqual(@as(u32, 65536), memory.data_base);
    try std.testing.expectEqual(@as(u32, 65536 + 4096), try stacks.regionBase(plan, 1));
    try std.testing.expectEqual(@as(u32, 65536 + 4096 + 8192), memory.total_bytes);
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{0xfffffffc}, .owner_capacity = 1 }));
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{17}, .owner_capacity = 1 }));
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{4096}, .owner_capacity = 0 }));
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{}, .owner_capacity = 1 }));
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{0}, .owner_capacity = 1 }));
    try std.testing.expectError(error.InvalidPlan, stacks.layout(.{ .region_capacities = &.{16}, .owner_capacity = std.math.maxInt(u32) }));
}

// Retains the prototype's incompatible-profile boundary on the primary emitter.
test "data stacks reject incompatible profiles before installing any runtime state" {
    const a = std.testing.allocator;
    const wasm = @import("../backend/wasm.zig");
    const artifacts = @import("../reuse/artifact_emitter.zig");
    for (0..4) |profile| {
        var journal = artifacts.Recorder.init(a);
        defer journal.deinit();
        var module = wasm.Module.init(a);
        defer module.deinit();
        switch (profile) {
            0 => {
                _ = try module.ensureArena();
            },
            1 => module.fixed_memory_bytes = 65536,
            2 => try module.data.append(a, 0),
            3 => module.artifacts = &journal,
            else => unreachable,
        }
        const before = [_]usize{ module.functions.items.len, module.globals.items.len, module.signatures.items.len, module.imports.items.len, module.exports.items.len, module.data.items.len, journal.records.items.len, journal.pending_instructions.items.len };
        const bytes = module.fixed_memory_bytes;
        const model = module.memory_model;
        const had_arena = module.arena != null;
        const recorder = module.artifacts;
        try std.testing.expectError(error.InvalidStorageConfiguration, stacks.emit(&module));
        const after = [_]usize{ module.functions.items.len, module.globals.items.len, module.signatures.items.len, module.imports.items.len, module.exports.items.len, module.data.items.len, journal.records.items.len, journal.pending_instructions.items.len };
        try std.testing.expectEqualSlices(usize, &before, &after);
        try std.testing.expectEqual(bytes, module.fixed_memory_bytes);
        try std.testing.expectEqual(model, module.memory_model);
        try std.testing.expectEqual(had_arena, module.arena != null);
        try std.testing.expectEqual(recorder, module.artifacts);
    }
}

fn literalDataOwnership(allocator: std.mem.Allocator) !void {
    const wasm = @import("../backend/wasm.zig");
    var module = wasm.Module.init(allocator);
    defer module.deinit();
    const runtime = try stacks.emit(&module);
    const mark = module.tailCheckpoint().?;
    _ = try module.scopedDataWord(runtime.literal_base, 0x80000000);
    _ = try module.scopedDataWord(runtime.literal_base, 0x7fc01234);
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 128, 52, 18, 192, 127 }, module.data.items);
    module.rollbackTail(mark);
    try std.testing.expectEqual(@as(usize, 0), module.data.items.len);
    try std.testing.expectEqual(@as(u32, 0), try module.scopedDataWord(runtime.literal_base, 0xffffffff));
    const plan: stacks.Plan = .{ .region_capacities = &.{4096}, .owner_capacity = 16 };
    const memory = try stacks.layout(plan);
    try stacks.finishPlan(&module, runtime, plan);
    try std.testing.expect(module.arena == null);
    try std.testing.expectEqual(memory.total_bytes, module.globals.items[runtime.literal_base].bits);
    try std.testing.expectEqual(memory.total_bytes + 4, module.fixed_memory_bytes);
    try std.testing.expectError(error.InvalidFunctionReference, module.scopedDataWord(runtime.literal_base, 0));
    const bytes = try module.assembleWithOptions(.{ .export_memory = true });
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len > 8);
}
test "scoped literal data owns exact bits rolls back tails and finalizes after owner regions through OOM" {
    try literalDataOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, literalDataOwnership, .{});
}
test "scoped literal data rejects foreign profiles and checked final address overflow" {
    const wasm = @import("../backend/wasm.zig");
    var counted = wasm.Module.init(std.testing.allocator);
    defer counted.deinit();
    const base = try counted.addGlobal(.u32, 0, false);
    try std.testing.expectError(error.InvalidFunctionReference, counted.scopedDataWord(base, 1));
    var module = wasm.Module.init(std.testing.allocator);
    defer module.deinit();
    const runtime = try stacks.emit(&module);
    _ = try module.scopedDataWord(runtime.literal_base, 0);
    _ = try module.scopedDataWord(runtime.literal_base, 0);
    try std.testing.expectError(error.InvalidPlan, stacks.finishPlan(&module, runtime, .{ .region_capacities = &.{0xfffefffc}, .owner_capacity = 1 }));
}
