//! Isolated storage experiment using actual checked layout IDs and arena helpers.
//! The returned row arrays escape their constructors, preventing scalar removal.
const std = @import("std");
const w = @import("wasm.zig");
const layout = @import("layout.zig");
const dense_layout = @import("packed_layout.zig");
const Code = struct {
    m: *w.Module,
    f: u32,
    fn op(self: Code, opcode: w.Op, operand: u32) !void {
        try self.m.emit(self.f, .{ .op = opcode, .operand = operand });
    }
    fn row(self: Code, index: u32, stride: u32) !void {
        try self.op(.local_get, 0);
        try self.op(.local_get, index);
        try self.op(.i32_const, stride);
        try self.op(.i32_mul, 0);
        try self.op(.i32_add, 0);
        try self.op(.i32_const, 4);
        try self.op(.i32_add, 0);
    }
};
fn constructors(m: *w.Module, plan: dense_layout.Plan, dense: bool) !void {
    const arena = try m.ensureArena();
    const f = try m.addFunction(&.{ .i32, .i32 }, .i32);
    const c: Code = .{ .m = m, .f = f };
    const result = try m.addLocal(f, .i32);
    const row = try m.addLocal(f, .i32);
    const index = try m.addLocal(f, .i32);
    const stride = if (dense) plan.stride() else 4;
    try c.op(.local_get, 0);
    try c.op(.i32_const, (0x3ffffff0 - 4) / stride);
    try c.op(.i32_gt_u, 0);
    try c.op(.if_, 0);
    try c.op(.unreachable_, 0);
    try c.op(.end, 0);
    try c.op(.local_get, 0);
    try c.op(.i32_const, stride);
    try c.op(.i32_mul, 0);
    try c.op(.i32_const, 4);
    try c.op(.i32_add, 0);
    try c.op(.call, if (dense) arena.allocate_scalar else arena.allocate);
    try c.op(.local_set, result);
    try c.op(.local_get, result);
    try c.op(.local_get, 0);
    try c.op(.i32_store, 0);
    try c.op(.block, 0);
    try c.op(.loop, 0);
    try c.op(.local_get, index);
    try c.op(.local_get, 0);
    try c.op(.i32_ge_u, 0);
    try c.op(.br_if, 1);
    if (dense) {
        try c.op(.local_get, result);
        try c.op(.local_get, index);
        try c.op(.i32_const, stride);
        try c.op(.i32_mul, 0);
        try c.op(.i32_add, 0);
        try c.op(.i32_const, 4);
        try c.op(.i32_add, 0);
    } else {
        try c.op(.i32_const, plan.stride());
        try c.op(.call, arena.allocate_scalar);
    }
    try c.op(.local_set, row);
    for (plan.leaves[0..plan.count], 0..) |leaf, i| {
        std.debug.assert(leaf.depth == 1); // This fixture measures flat rows.
        try c.op(.local_get, row);
        try c.op(.local_get, index);
        try c.op(.local_get, 1);
        try c.op(.i32_add, 0);
        try c.op(.i32_const, @intCast(i * 0x100000));
        try c.op(.i32_xor, 0);
        if (leaf.floating) try c.op(.f32_reinterpret_i32, 0);
        try c.op(if (leaf.floating) .f32_store else .i32_store, @intCast(i * 4));
    }
    if (!dense) {
        try c.op(.local_get, result);
        try c.op(.local_get, index);
        try c.op(.i32_const, 4);
        try c.op(.i32_mul, 0);
        try c.op(.i32_add, 0);
        try c.op(.local_get, row);
        try c.op(.i32_store, 4);
    }
    try c.op(.local_get, index);
    try c.op(.i32_const, 1);
    try c.op(.i32_add, 0);
    try c.op(.local_set, index);
    try c.op(.br, 0);
    try c.op(.end, 0);
    try c.op(.end, 0);
    try c.op(.local_get, result);
    try m.exportFunction(f, if (dense) "packed" else "boxed", .u32, .u32);
}
fn reduction(m: *w.Module, plan: dense_layout.Plan, dense: bool) !void {
    const f = try m.addFunction(&.{.i32}, .i32);
    const c: Code = .{ .m = m, .f = f };
    const index = try m.addLocal(f, .i32);
    const row = try m.addLocal(f, .i32);
    const sum = try m.addLocal(f, .i32);
    try c.op(.block, 0);
    try c.op(.loop, 0);
    try c.op(.local_get, index);
    try c.op(.local_get, 0);
    try c.op(.i32_load, 0);
    try c.op(.i32_ge_u, 0);
    try c.op(.br_if, 1);
    try c.row(index, if (dense) plan.stride() else 4);
    if (!dense) try c.op(.i32_load, 0);
    try c.op(.local_set, row);
    for (0..plan.count) |i| {
        try c.op(.local_get, sum);
        try c.op(.local_get, row);
        try c.op(.i32_load, @intCast(i * 4));
        try c.op(.i32_add, 0);
        try c.op(.local_set, sum);
    }
    try c.op(.local_get, index);
    try c.op(.i32_const, 1);
    try c.op(.i32_add, 0);
    try c.op(.local_set, index);
    try c.op(.br, 0);
    try c.op(.end, 0);
    try c.op(.end, 0);
    try c.op(.local_get, sum);
    try m.exportFunction(f, if (dense) "sum_packed" else "sum_boxed", .u32, .u32);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var layouts = try layout.Store.init(init.gpa);
    defer layouts.deinit();
    const row = try layouts.intern(.product, 0, 0, &.{ 3, 4, 4 });
    const plan = dense_layout.analyze(&layouts, row).?;
    var m = w.Module.init(init.gpa);
    defer m.deinit();
    m.public_arena = true;
    try constructors(&m, plan, false);
    try constructors(&m, plan, true);
    try reduction(&m, plan, false);
    try reduction(&m, plan, true);
    const heap = try m.addFunction(&.{}, .i32);
    try m.emit(heap, .{ .op = .global_get, .operand = m.arena.?.heap });
    try m.exportFunction(heap, "heap", .unit, .u32);
    const bytes = try m.assemble();
    defer init.gpa.free(bytes);
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = args[1], .data = bytes });
}
