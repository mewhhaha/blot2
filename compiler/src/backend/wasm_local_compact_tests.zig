const std = @import("std");
const ir = @import("runtime_ir.zig");
const run = @import("wasm_local_compact.zig").run;
const A = std.mem.Allocator;
const a = std.testing.allocator;

fn fixture(parameters: []ir.ValueType, machines: []const ir.ValueType, code: []const ir.Instruction) !ir.Function {
    var result: ir.Function = .{ .parameters = parameters, .result = .i32, .signature = 0 };
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, machines);
    try result.instructions.appendSlice(a, code);
    return result;
}
fn checkReplacement(allocator: A, source: *const ir.Function) !void {
    var result = (try run(allocator, source)).?;
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .f32, .v128, .i32, .i32 }, result.locals.items);
    try std.testing.expectEqual(source.instructions.items.len, result.instructions.items.len);
    for (source.instructions.items, result.instructions.items) |before, after| {
        var restored = after;
        if (before.op == .local_get or before.op == .local_set or before.op == .local_tee) restored.operand = before.operand;
        try std.testing.expectEqual(@as(u64, @bitCast(before)), @as(u64, @bitCast(restored)));
    }
    try std.testing.expectEqual(@as(u32, 0), result.instructions.items[0].operand);
    const first = result.instructions.items[1].operand;
    const second = result.instructions.items[3].operand;
    const third = result.instructions.items[10].operand;
    try std.testing.expect(first != second);
    try std.testing.expect(third == first or third == second);
}
test "scoped local slots preserve overlapping values tee results parameters and packed metadata through OOM" {
    var parameters = [_]ir.ValueType{.i32};
    const code = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 0, .origin = 912 },
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .i32_const, .operand = 7, .table_reference = true, .table_kind = .callable, .origin = 19 },
        .{ .op = .local_tee, .operand = 2 },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_add },
        .{ .op = .drop },
        .{ .op = .i32_const, .operand = 9 },
        .{ .op = .local_set, .operand = 3 },
        .{ .op = .local_get, .operand = 3 },
        .{ .op = .drop },
        .{ .op = .local_get },
    };
    var source = try fixture(&parameters, &.{ .i32, .i32, .i32, .f32, .v128 }, &code);
    defer source.deinit(a);
    try checkReplacement(a, &source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkReplacement, .{@as(*const ir.Function, &source)});
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    try std.testing.expectEqual(@as(usize, 5), source.locals.items.len);
}
test "scoped local slots pin zero initialized multiple definition and cross control locals" {
    var source = try fixture(&.{}, &.{ .i32, .i32, .i32, .i32, .i32, .i32, .i32 }, &.{
        .{ .op = .local_get },               .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .drop },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 2 },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 2 },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 3 },
        .{ .op = .i32_const },               .{ .op = .if_, .operand = 0x40 },
        .{ .op = .local_get, .operand = 3 }, .{ .op = .drop },
        .{ .op = .else_ },                   .{ .op = .end },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 4 },
        .{ .op = .loop, .operand = 0x40 },   .{ .op = .local_get, .operand = 4 },
        .{ .op = .drop },                    .{ .op = .end },
        .{ .op = .i32_const },               .{ .op = .local_tee, .operand = 5 },
        .{ .op = .drop },                    .{ .op = .i32_const },
        .{ .op = .local_tee, .operand = 6 }, .{ .op = .drop },
        .{ .op = .i32_const },
    });
    defer source.deinit(a);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 6), output.locals.items.len);
    for (source.instructions.items, output.instructions.items) |before, after| {
        if ((before.op == .local_get or before.op == .local_set) and before.operand < 5) try std.testing.expectEqual(before.operand, after.operand);
    }
    try std.testing.expectEqual(output.instructions.items[25].operand, output.instructions.items[28].operand);
}
test "scoped local slots decline hidden identities malformed controls and invalid local indices" {
    var source = try fixture(&.{}, &.{ .i32, .i32 }, &.{
        .{ .op = .i32_const }, .{ .op = .local_set },
        .{ .op = .i32_const }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .nop },
    });
    defer source.deinit(a);
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .end }, .{ .op = .br, .operand = 1 }, .{ .op = .local_get, .operand = 2 } }) |invalid| {
        source.instructions.items[4] = invalid;
        try std.testing.expect((try run(a, &source)) == null);
    }
}
test "scoped local slots reduce large straight line bodies below the engine local limit" {
    var source: ir.Function = .{ .parameters = &.{}, .result = .i32, .signature = 0 };
    defer source.deinit(a);
    for (0..50_001) |index| {
        try source.locals.append(a, .i32);
        try source.instructions.appendSlice(a, &.{ .{ .op = .i32_const }, .{ .op = .local_tee, .operand = @intCast(index) }, .{ .op = .drop } });
    }
    try source.instructions.append(a, .{ .op = .i32_const });
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), output.locals.items.len);
    try std.testing.expectEqual(source.instructions.items.len, output.instructions.items.len);
}
test "runtime pipeline compacts scoped locals in both tiers after final replacements" {
    const wasm = @import("wasm.zig");
    for ([_]@import("../compilation_tier.zig").Tier{ .development, .optimized }) |tier| {
        for ([_]bool{ false, true }) |scoped| {
            var module = wasm.Module.init(a);
            defer module.deinit();
            if (scoped) module.memory_model = .data_stacks;
            const id = try module.addFunction(&.{}, .i32);
            const source = &module.functions.items[id];
            try source.locals.appendSlice(a, &.{ .i32, .i32 });
            try source.instructions.appendSlice(a, &.{
                .{ .op = .i32_const }, .{ .op = .local_tee },               .{ .op = .drop },
                .{ .op = .i32_const }, .{ .op = .local_tee, .operand = 1 },
            });
            var pipeline = try @import("runtime_pipeline.zig").Session.init(a, &module);
            defer pipeline.deinit();
            pipeline.tier = tier;
            var output = try pipeline.optimize(source);
            defer if (output) |*body| body.deinit(a);
            try std.testing.expectEqual(@as(usize, if (scoped) 1 else 2), if (output) |body| body.locals.items.len else source.locals.items.len);
            try std.testing.expectEqual(@as(usize, 2), source.locals.items.len);
        }
    }
}
