const std = @import("std");
const wasm = @import("wasm.zig");
const patches = @import("scalar_live_patch.zig");
const a = std.testing.allocator;

pub fn fixture(allocator: std.mem.Allocator, increment: u32) !wasm.Module {
    var module = wasm.Module.init(allocator);
    errdefer module.deinit();
    const helper = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(helper, &.{
        .{ .op = .local_get },                       .{ .op = .i32_eqz }, .{ .op = .if_, .operand = @backingInt(wasm.ValueType.i32) },
        .{ .op = .i32_const, .operand = increment }, .{ .op = .else_ },   .{ .op = .local_get },
        .{ .op = .i32_const, .operand = 1 },         .{ .op = .i32_sub }, .{ .op = .call, .operand = helper },
        .{ .op = .i32_const, .operand = 1 },         .{ .op = .i32_add }, .{ .op = .end },
    });
    const caller = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(caller, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = helper }, .{ .op = .i32_const, .operand = 2 }, .{ .op = .i32_mul } });
    try module.exportFunction(caller, "answer", .u32, .u32);
    const trap = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(trap, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .local_get }, .{ .op = .i32_div_u } });
    try module.exportFunction(trap, "divide", .u32, .u32);
    const float = try module.addFunction(&.{.f32}, .f32);
    try module.emitSlice(float, &.{ .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .local_get }, .{ .op = .f32_div } });
    try module.exportFunction(float, "floating", .f32, .f32);
    return module;
}
fn image(allocator: std.mem.Allocator, increment: u32) !patches.Image {
    var module = try fixture(allocator, increment);
    defer module.deinit();
    return (try patches.Image.capture(allocator, &module)).?;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var before = try image(allocator, 1);
    defer before.deinit();
    var after = try image(allocator, 7);
    defer after.deinit();
    const initial = try before.initial();
    defer allocator.free(initial);
    var delta = (try after.delta(&before)).?;
    defer delta.deinit();
    try std.testing.expectEqualSlices(u32, &.{0}, delta.slots);
    try std.testing.expectEqualSlices(u8, &before.digest, &delta.base);
    try std.testing.expectEqualSlices(u8, &after.digest, &delta.next);
    try std.testing.expect(delta.bytes.len < initial.len);
    var noop = (try after.delta(&after)).?;
    defer noop.deinit();
    try std.testing.expectEqual(@as(usize, 0), noop.slots.len);
}
test "scalar live patches retain owned code and emit only changed functions through allocation failures" {
    try scenario(a);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{});
}
test "scalar live patches reject state and changed public ABI" {
    var module = try fixture(a, 1);
    defer module.deinit();
    var original = (try patches.Image.capture(a, &module)).?;
    defer original.deinit();
    module.exports.items[0].parameter = .bool;
    var different = (try patches.Image.capture(a, &module)).?;
    defer different.deinit();
    try std.testing.expect(try different.delta(&original) == null);
    _ = try module.addGlobal(.u32, 0, true);
    try std.testing.expect(try patches.Image.capture(a, &module) == null);
    module.globals.clearRetainingCapacity();
    try module.emit(0, .{ .op = .i32_load });
    try std.testing.expect(try patches.Image.capture(a, &module) == null);
}
