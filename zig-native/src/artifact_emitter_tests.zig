const std = @import("std");
const wasm = @import("wasm.zig");
const artifact = @import("artifact_emitter.zig");
const operations = @import("runtime_operations.zig");
const evidence = @import("type_evidence.zig");
const failures = @import("allocation_failures.zig");

fn scenario(allocator: std.mem.Allocator) !void {
    var journal = artifact.Recorder.init(allocator);
    defer journal.deinit();
    var original = wasm.Module.init(allocator);
    var alive = true;
    defer if (alive) original.deinit();
    original.artifacts = &journal;
    var proof = try evidence.Store.init(allocator);
    defer proof.deinit();
    var symbols = operations.Store.init(allocator);
    defer symbols.deinit();
    const label = try proof.effects.internOperation(.{ .unit = 1, .decl = 9 }, &.{});
    const operation = try symbols.intern(proof.view(), label);
    const parent = try original.addFunction(&.{}, .i32);
    const child = try original.addFunction(&.{}, .i32);
    _ = try original.addLocal(parent, .i32);
    try symbols.emit(&original, child, operation);
    try original.emit(parent, .{ .op = .call, .operand = child });
    const imported = try original.importFunction("fixture", "f", &.{}, .i32);
    try original.emit(parent, .{ .op = .call_import, .operand = imported });
    try original.emit(parent, .{ .op = .drop });
    const signature = try original.internType(&.{.i32}, .i32);
    try original.emit(parent, .{ .op = .i32_const });
    try original.emitReference(parent, .{ .op = .i32_const, .operand = child }, .table_function);
    try original.emit(parent, .{ .op = .call_indirect, .operand = signature });
    try original.emit(parent, .{ .op = .drop });
    const payload = try original.dataWords(&.{42});
    const closure = try original.dataWords(&.{ child, payload, 0 });
    try original.dataReference(closure, .{ .role = .table_function, .value = child });
    try original.dataReference(closure + 4, .{ .role = .static_address, .value = payload });
    try symbols.dataWord(&original, closure + 8, operation);
    try original.emitReference(parent, .{ .op = .i32_const, .operand = closure }, .static_address);
    try original.exportFunction(parent, "parent", .unit, .u32);
    try original.exportConstant("literal", .u32, 8);
    _ = try original.ensureHostReferences();
    try journal.captureOperations(symbols.entries.items);
    try symbols.finish(&original);
    const expected = try original.assemble();
    defer allocator.free(expected);
    const expected_count = original.functions.items.len;
    const expected_data = try allocator.dupe(u8, original.data.items);
    defer allocator.free(expected_data);
    journal.seal();
    try journal.freezeFunctions(&.{});
    original.deinit();
    alive = false;
    var replayed = try journal.materialize(allocator);
    defer replayed.deinit();
    try std.testing.expectEqual(expected_count, replayed.functions.items.len);
    try std.testing.expectEqualSlices(u8, expected_data, replayed.data.items);
    const actual = try replayed.assemble();
    defer allocator.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
    // Relocations use the newly allocated resource handles, not old indexes.
    var shifted = wasm.Module.init(allocator);
    defer shifted.deinit();
    _ = try shifted.addFunction(&.{.f32}, .f32);
    _ = try shifted.importFunction("unrelated", "other", &.{.f32}, .f32);
    _ = try shifted.addGlobal(.u32, 7, false);

    try journal.replayInto(&shifted);
    try std.testing.expectEqual(@as(u32, child + 1), shifted.functions.items[parent + 1].instructions.items[0].operand);
    try std.testing.expectEqual(@as(u32, imported + 1), shifted.functions.items[parent + 1].instructions.items[1].operand);
    try std.testing.expectEqual(@as(u32, closure), shifted.functions.items[parent + 1].instructions.items[7].operand);
    try std.testing.expectEqual(@as(u32, child + 1), std.mem.readInt(u32, shifted.data.items[closure..][0..4], .little));
    try std.testing.expectEqual(@as(u32, payload), std.mem.readInt(u32, shifted.data.items[closure + 4 ..][0..4], .little));
    var unsupported = wasm.Module.init(allocator);
    defer unsupported.deinit();
    _ = try unsupported.dataWords(&.{99});
    try std.testing.expectError(error.UnsupportedArenaComposition, journal.replayInto(&unsupported));
}

test "owned typed emission reconstruction survives original module destruction and shifted resources" {
    try scenario(std.testing.allocator);
}

test "capture and replay allocations leave owners releasable on every failure" {
    try failures.checkAllAllocationFailures(std.testing.allocator, scenario, .{});
}
