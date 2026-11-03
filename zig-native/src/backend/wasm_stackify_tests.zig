const std = @import("std");
const ir = @import("runtime_ir.zig");
const run = @import("wasm_stackify.zig").run;
const A = std.mem.Allocator;
const a = std.testing.allocator;
fn fixture(parameters: []ir.ValueType, locals: []const ir.ValueType, code: []const ir.Instruction) !ir.Function {
    var result: ir.Function = .{ .parameters = parameters, .result = .i32, .signature = 0 };
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, locals);
    try result.instructions.appendSlice(a, code);
    return result;
}
fn checkTree(allocator: A, source: *const ir.Function) !void {
    var output = (try run(allocator, source)).?;
    defer output.deinit(allocator);
    try std.testing.expectEqualSlices(ir.ValueType, &.{.i32}, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .local_get, .operand = 0, .origin = 14 },
        .{ .op = .i32_const, .operand = 7, .origin = 19 },
        .{ .op = .i32_sub, .origin = 23 },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .i32_mul },
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .i32_add },
    }, output.instructions.items);
}
test "scoped stack expressions retain ordered single use trees and original coordinates through OOM" {
    var parameters = [_]ir.ValueType{.i32};
    const code = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 0, .origin = 14 },
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .i32_const, .operand = 7, .origin = 19 },
        .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_sub, .origin = 23 },
        .{ .op = .local_set, .operand = 3 },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_mul },
        .{ .op = .local_get, .operand = 4 },
        .{ .op = .i32_add },
    };
    var source = try fixture(&parameters, &.{ .i32, .i32, .i32, .i32 }, &code);
    defer source.deinit(a);
    // Multiplication's operands retain their source order, too.
    source.instructions.items[8] = .{ .op = .local_get, .operand = 3 };
    source.instructions.items[9] = .{ .op = .i32_const, .operand = 3 };
    try checkTree(a, &source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkTree, .{@as(*const ir.Function, &source)});
    try std.testing.expectEqual(@as(usize, 4), source.locals.items.len);
    try std.testing.expectEqual(ir.Op.local_set, source.instructions.items[1].op);
    try std.testing.expectEqual(@as(u21, 23), source.instructions.items[6].origin);
}
test "scoped stack expressions flush at effects traps writes control and symbolic operands" {
    const barriers = [_]ir.Instruction{
        .{ .op = .call, .operand = 9 },                               .{ .op = .call_import },            .{ .op = .call_indirect },
        .{ .op = .global_get },                                       .{ .op = .global_set },             .{ .op = .i32_load },
        .{ .op = .i32_store },                                        .{ .op = .memory_grow },            .{ .op = .i32_div_u },
        .{ .op = .i32_rem_u },                                        .{ .op = .block, .operand = 0x40 }, .{ .op = .loop, .operand = 0x40 },
        .{ .op = .if_, .operand = 0x40 },                             .{ .op = .br_if },                  .{ .op = .else_ },
        .{ .op = .end },                                              .{ .op = .return_ },                .{ .op = .unreachable_ },
        .{ .op = .local_set },                                        .{ .op = .local_tee },              .{ .op = .i32_const, .operand = 7, .table_reference = true, .table_kind = .callable },
        .{ .op = .i32_const, .operand = 7, .table_kind = .callable },
    };
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .nop },       .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    for (barriers) |barrier| {
        source.instructions.items[2] = barrier;
        try std.testing.expect((try run(a, &source)) == null);
        try std.testing.expectEqual(barrier, source.instructions.items[2]);
    }
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .wide_layouts }, .{ .op = .local_get, .operand = 2 } }) |hidden| {
        source.instructions.items[2] = hidden;
        try std.testing.expect((try run(a, &source)) == null);
    }
}
test "scoped stack expressions retain opaque prefixes reused locals zero reads and tee" {
    var source = try fixture(&.{}, &.{ .i32, .i32, .i32, .i32 }, &.{
        .{ .op = .call },                    .{ .op = .local_set },               .{ .op = .local_get },               .{ .op = .drop },
        .{ .op = .i32_const, .operand = 2 }, .{ .op = .local_set, .operand = 1 }, .{ .op = .local_get, .operand = 1 }, .{ .op = .local_get, .operand = 1 },
        .{ .op = .i32_sub },                 .{ .op = .drop },                    .{ .op = .local_get, .operand = 2 }, .{ .op = .drop },
        .{ .op = .i32_const },               .{ .op = .local_set, .operand = 2 }, .{ .op = .i32_const },               .{ .op = .local_tee, .operand = 3 },
        .{ .op = .drop },                    .{ .op = .local_get, .operand = 3 },
    });
    defer source.deinit(a);
    try std.testing.expect((try run(a, &source)) == null);
    // An operation consuming an unknown call result also stays in place.
    source.instructions.items[1] = .{ .op = .i32_eqz };
    try std.testing.expect((try run(a, &source)) == null);
}
test "scoped stack expressions preserve float signed zero NaN vector and flagged bits" {
    var source = try fixture(&.{}, &.{ .f32, .v128, .i32 }, &.{
        .{ .op = .f32_const, .operand = 0x80000000, .origin = 13 }, .{ .op = .local_set },
        .{ .op = .local_get },                                      .{ .op = .f32_const, .operand = 0x7fc00123 },
        .{ .op = .f32_add },                                        .{ .op = .i32_reinterpret_f32 },
        .{ .op = .drop },                                           .{ .op = .i32_const, .operand = 11 },
        .{ .op = .i32x4_splat },                                    .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },                        .{ .op = .i32x4_extract_lane, .operand = 2 },
        .{ .op = .local_set, .operand = 2 },                        .{ .op = .local_get, .operand = 2 },
    });
    defer source.deinit(a);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), output.locals.items.len);
    try std.testing.expectEqual(source.instructions.items[0], output.instructions.items[0]);
    try std.testing.expectEqual(source.instructions.items[3], output.instructions.items[1]);
    try std.testing.expectEqual(ir.Op.i32x4_extract_lane, output.instructions.items[7].op);
    try std.testing.expectEqual(@as(u32, 2), output.instructions.items[7].operand);
}
test "scoped stack expressions handle long chains iteratively and remove eliminated locals" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{}, &.{.{ .op = .local_get }});
    defer source.deinit(a);
    for (0..50_001) |index| {
        try source.locals.append(a, .i32);
        try source.instructions.appendSlice(a, &.{
            .{ .op = .i32_const, .operand = 3 },                   .{ .op = .i32_sub },
            .{ .op = .local_set, .operand = @intCast(index + 1) }, .{ .op = .local_get, .operand = @intCast(index + 1) },
        });
    }
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), output.locals.items.len);
    try std.testing.expectEqual(@as(usize, 100_003), output.instructions.items.len);
}

test "scoped stack expressions retain old mutable reads and opaque prefixes in successful rewrites" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{ .i32, .i32 }, &.{
        .{ .op = .call, .operand = 9 },
        .{ .op = .local_get },
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .i32_const, .operand = 9 },
        .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .i32_sub },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_add },
    });
    defer source.deinit(a);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(ir.ValueType, &.{.i32}, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .call, .operand = 9 },
        .{ .op = .local_get },
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .i32_const, .operand = 9 },
        .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .i32_sub },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .i32_add },
    }, output.instructions.items);
    // A mismatched typed producer cannot be silently repaired by elimination.
    source.instructions.items[7] = .{ .op = .f32_const, .operand = 0x80000000 };
    try std.testing.expect((try run(a, &source)) == null);
}

test "scoped stack expression fast rejection never adds barriers to other viable trees" {
    var source = try fixture(&.{}, &.{ .i32, .i32 }, &.{
        .{ .op = .i32_const, .operand = 1 }, .{ .op = .local_set },
        .{ .op = .i32_const, .operand = 2 }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get },               .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .return_ },
    });
    defer source.deinit(a);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(ir.ValueType, &.{.i32}, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .i32_const, .operand = 2 }, .{ .op = .local_set },
        .{ .op = .i32_const, .operand = 1 }, .{ .op = .drop },
        .{ .op = .local_get },               .{ .op = .return_ },
    }, output.instructions.items);
}
