//! Four checked F32 lane products may share one vector product. The first
//! original complete load stays in place; scalar reduction order stays exact.
//! A store, call, local write, control edge or unproved operation ends the scan.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const A = std.mem.Allocator;
const Product = struct { base: ir.Instruction, load: ir.Instruction, factor: ir.Instruction, lane: u32 };

fn product(source: []const ir.Instruction, at: usize) ?Product {
    if (at + 5 > source.len) return null;
    const part = source[at..][0..5];
    for (part) |inst| if (inst.table_reference) return null;
    if (part[0].op != .local_get or part[1].op != .v128_load or part[2].op != .f32x4_extract_lane or part[2].operand >= 4 or part[4].op != .f32_mul) return null;
    if (part[3].op != .local_get and part[3].op != .f32_const) return null;
    return .{ .base = part[0], .load = part[1], .factor = part[3], .lane = part[2].operand };
}
fn same(left: Product, right: Product) bool {
    return std.meta.eql(left.base, right.base) and std.meta.eql(left.load, right.load) and std.meta.eql(left.factor, right.factor);
}
fn pure(inst: ir.Instruction) bool {
    if (inst.table_reference) return false;
    switch (inst.op) {
        .local_get, .i32_const, .f32_const, .drop, .nop => return true,
        else => {
            _ = ir.lift(inst.op) orelse return false;
            const facts = ir.fixed(inst.op);
            return facts.effect == .pure and !facts.may_trap;
        },
    }
}
pub fn run(a: A, function: *const ir.Function) A.Error!?ir.Body {
    const source = function.instructions.items;
    if (source.len > 4096) return null;
    var output: ir.Body = .{};
    errdefer output.deinit(a);
    var changed = false;
    var copied: usize = 0;
    var at: usize = 0;
    while (at + 5 <= source.len) : (at += 1) {
        const first = product(source, at) orelse continue;
        var sites: [4]usize = undefined;
        var count: usize = 0;
        var lanes: u4 = 0;
        var next = at;
        while (next + 5 <= @min(source.len, at + 96) and count < sites.len) {
            if (product(source, next)) |candidate| {
                if (!same(first, candidate)) break;
                const bit = @as(u4, 1) << @intCast(candidate.lane);
                if (lanes & bit != 0) break;
                lanes |= bit;
                sites[count] = next;
                count += 1;
                next += 5;
            } else {
                if (!pure(source[next])) break;
                next += 1;
            }
        }
        if (count != 4 or lanes != 15) continue;
        if (!changed) try output.locals.appendSlice(a, function.locals.items);
        changed = true;
        const vector: u32 = @intCast(function.parameters.len + output.locals.items.len);
        try output.locals.append(a, .v128);
        try output.instructions.appendSlice(a, source[copied..at]);
        try output.instructions.appendSlice(a, &.{ first.base, first.load, first.factor });
        try output.emit(a, .f32x4_splat, 0);
        try output.emit(a, .f32x4_mul, 0);
        try output.emit(a, .local_set, vector);
        var cursor = at;
        for (sites) |site| {
            try output.instructions.appendSlice(a, source[cursor..site]);
            try output.emit(a, .local_get, vector);
            try output.instructions.append(a, source[site + 2]);
            cursor = site + 5;
        }
        copied = cursor;
        at = cursor - 1;
    }
    if (!changed) return null;
    try output.instructions.appendSlice(a, source[copied..]);
    return output;
}

fn fixture(module: *wasm.Module) !u32 {
    const id = try module.addFunction(&.{ .i32, .f32 }, .f32);
    for (0..4) |lane| {
        try module.emitSlice(id, &.{
            .{ .op = .local_get }, .{ .op = .v128_load }, .{ .op = .f32x4_extract_lane, .operand = @intCast(lane) }, .{ .op = .local_get, .operand = 1 }, .{ .op = .f32_mul },
        });
        if (lane != 0) try module.emit(id, .{ .op = .f32_add });
    }
    return id;
}
fn ownershipFailures(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const id = try fixture(&module);
    const before = try a.dupe(ir.Instruction, module.functions.items[id].instructions.items);
    defer a.free(before);
    var output = (try run(a, &module.functions.items[id])).?;
    defer output.deinit(a);
    var vectors: usize = 0;
    var scalar_products: usize = 0;
    var adds: usize = 0;
    var loads: usize = 0;
    for (output.instructions.items) |inst| switch (inst.op) {
        .f32x4_mul => vectors += 1,
        .f32_mul => scalar_products += 1,
        .f32_add => adds += 1,
        .v128_load => loads += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), vectors);
    try std.testing.expectEqual(@as(usize, 0), scalar_products);
    try std.testing.expectEqual(@as(usize, 3), adds);
    try std.testing.expectEqual(@as(usize, 1), loads);
    try std.testing.expectEqualSlices(ir.Instruction, before, module.functions.items[id].instructions.items);
}
test "checked row products retain scalar reduction order and owned output through OOM" {
    try ownershipFailures(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownershipFailures, .{});
}
test "checked row products decline writes calls changed factors and incomplete lanes" {
    const a = std.testing.allocator;
    for (0..4) |mode| {
        var module = wasm.Module.init(a);
        defer module.deinit();
        const id = try fixture(&module);
        const source = &module.functions.items[id].instructions;
        switch (mode) {
            0 => try source.insertSlice(a, 11, &.{ .{ .op = .local_get }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = 8 } }),
            1 => try source.insert(a, 11, .{ .op = .call_import }),
            2 => source.items[20] = .{ .op = .local_get },
            3 => source.items[19].operand = 2,
            else => unreachable,
        }
        try std.testing.expect(try run(a, &module.functions.items[id]) == null);
    }
}
