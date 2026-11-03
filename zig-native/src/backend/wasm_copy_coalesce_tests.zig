const std = @import("std");
const ir = @import("runtime_ir.zig");
const coalesce = @import("wasm_copy_coalesce.zig");
const A = std.mem.Allocator;
const a = std.testing.allocator;
fn fixture(parameters: []ir.ValueType, locals: []const ir.ValueType, code: []const ir.Instruction) !ir.Function {
    var result: ir.Function = .{ .parameters = parameters, .result = .i32, .signature = 0 };
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, locals);
    try result.instructions.appendSlice(a, code);
    return result;
}
fn single(source: *const ir.Function) [1]coalesce.Body {
    return .{.{ .function = 4, .instructions = source.instructions.items }};
}
fn checkTree(allocator: A, source: *const ir.Function, bodies: []const coalesce.Body) !void {
    var output = (try coalesce.run(allocator, source, bodies)).?;
    defer output.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), output.removed_copies);
    try std.testing.expectEqual(@as(usize, 7), output.forwarded_reads);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0 }, output.aliases);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .call, .operand = 7 },
        .{ .op = .local_get, .origin = 11 },
        .{ .op = .drop },
        .{ .op = .local_get },
        .{ .op = .drop },
        .{ .op = .local_get },
    }, output.bodies[0].instructions);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .call, .operand = 8 }, .{ .op = .local_get }, .{ .op = .drop },
    }, output.bodies[1].instructions);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .local_get }, .{ .op = .drop }, .{ .op = .local_get }, .{ .op = .drop }, .{ .op = .local_get },
    }, output.bodies[2].instructions);
}
test "scoped copy coalescing follows nested logical helpers and transitive multiuse aliases through OOM" {
    var parameters = [_]ir.ValueType{.i32};
    const root = [_]ir.Instruction{
        .{ .op = .local_get },          .{ .op = .local_set, .operand = 1 },
        .{ .op = .call, .operand = 7 }, .{ .op = .local_get, .operand = 3, .origin = 11 },
        .{ .op = .drop },               .{ .op = .local_get, .operand = 2 },
        .{ .op = .drop },               .{ .op = .local_get, .operand = 1 },
    };
    var source = try fixture(&parameters, &.{ .i32, .i32, .i32 }, &root);
    defer source.deinit(a);
    const bodies = [_]coalesce.Body{
        .{ .function = 4, .instructions = source.instructions.items },
        .{ .function = 7, .instructions = &.{
            .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 },
            .{ .op = .call, .operand = 8 },      .{ .op = .local_get, .operand = 2 },
            .{ .op = .drop },
        } },
        .{ .function = 8, .instructions = &.{
            .{ .op = .local_get, .operand = 2 }, .{ .op = .local_set, .operand = 3 },
            .{ .op = .local_get, .operand = 3 }, .{ .op = .drop },
            .{ .op = .local_get, .operand = 1 }, .{ .op = .drop },
            .{ .op = .local_get, .operand = 3 },
        } },
    };
    try checkTree(a, &source, &bodies);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkTree, .{ @as(*const ir.Function, &source), @as([]const coalesce.Body, &bodies) });
    try std.testing.expectEqualSlices(ir.Instruction, &root, source.instructions.items);
    try std.testing.expectEqual(@as(usize, 3), source.locals.items.len);
}
test "scoped copy coalescing handles wide chains without recursive alias walks" {
    const width = 256;
    var parameters: [width]ir.ValueType = @splat(.i32);
    var source = try fixture(&parameters, &.{}, &.{});
    defer source.deinit(a);
    for (0..3) |stage| for (0..width) |lane| {
        try source.locals.append(a, .i32);
        try source.instructions.appendSlice(a, &.{
            .{ .op = .local_get, .operand = @intCast(stage * width + lane) },
            .{ .op = .local_set, .operand = @intCast((stage + 1) * width + lane) },
        });
    };
    for (0..width) |lane| try source.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = @intCast(3 * width + lane) },
        .{ .op = .local_get, .operand = @intCast(3 * width + lane) },
        .{ .op = .i32_add },
        .{ .op = .drop },
    });
    var output = (try coalesce.run(a, &source, &single(&source))).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 3 * width), output.removed_copies);
    try std.testing.expectEqual(@as(usize, 2 * width), output.forwarded_reads);
    try std.testing.expectEqual(@as(usize, 4 * width), output.bodies[0].instructions.len);
    for (output.aliases, 0..) |alias, id| try std.testing.expectEqual(@as(u32, @intCast(id % width)), alias);
    for (0..width) |lane| {
        try std.testing.expectEqual(@as(u32, @intCast(lane)), output.bodies[0].instructions[lane * 4].operand);
        try std.testing.expectEqual(@as(u32, @intCast(lane)), output.bodies[0].instructions[lane * 4 + 1].operand);
    }
}
test "scoped copy coalescing retains every read after unsafe late source writes and tee" {
    var parameters = [_]ir.ValueType{.i32};
    const code = [_]ir.Instruction{
        .{ .op = .local_get },                             .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },               .{ .op = .drop },
        .{ .op = .i32_const, .operand = 9 },               .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },               .{ .op = .drop },
        .{ .op = .local_get },                             .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get, .operand = 2, .origin = 19 },
    };
    var source = try fixture(&parameters, &.{ .i32, .i32 }, &code);
    defer source.deinit(a);
    for ([_]ir.Op{ .local_set, .local_tee }) |write| {
        source.instructions.items[5].op = write;
        var output = (try coalesce.run(a, &source, &single(&source))).?;
        defer output.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), output.removed_copies);
        try std.testing.expectEqual(@as(usize, 1), output.forwarded_reads);
        try std.testing.expectEqualSlices(u32, &.{ 0, 1, 0 }, output.aliases);
        try std.testing.expectEqualSlices(ir.Instruction, source.instructions.items[0..8], output.bodies[0].instructions[0..8]);
        try std.testing.expectEqual(ir.Instruction{ .op = .local_get, .origin = 19 }, output.bodies[0].instructions[8]);
    }
}
test "scoped copy coalescing retains zero reads control crossings parameters and repeated writes" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .nop },       .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    for ([_]ir.Op{ .block, .loop, .if_, .else_, .end, .br, .br_if, .return_, .unreachable_ }) |op| {
        source.instructions.items[2] = .{ .op = op };
        try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    }
    source.instructions.items[2] = .{ .op = .nop };
    try source.instructions.insertSlice(a, 0, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .drop } });
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    source.instructions.items[0].operand = 0;
    source.instructions.items[4] = .{ .op = .local_set, .operand = 1 };
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    source.instructions.clearRetainingCapacity();
    try source.instructions.appendSlice(a, &.{
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set }, .{ .op = .local_get },
    });
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
}
test "scoped copy coalescing preserves opaque stack effects calls globals and symbolic metadata" {
    var parameters = [_]ir.ValueType{.i32};
    const code = [_]ir.Instruction{
        .{ .op = .call, .operand = 99 },
        .{ .op = .local_get, .origin = 17 },
        .{ .op = .local_set, .operand = 1, .origin = 21 },
        .{ .op = .call_import },
        .{ .op = .call_indirect },
        .{ .op = .global_get },
        .{ .op = .global_set },
        .{ .op = .i32_load },
        .{ .op = .i32_store },
        .{ .op = .memory_grow },
        .{ .op = .i32_div_u },
        .{ .op = .i32_const, .operand = 7, .table_reference = true, .table_kind = .callable, .origin = 23 },
        .{ .op = .local_get, .operand = 1, .origin = 29 },
        .{ .op = .i32_sub },
    };
    var source = try fixture(&parameters, &.{.i32}, &code);
    defer source.deinit(a);
    var output = (try coalesce.run(a, &source, &single(&source))).?;
    defer output.deinit(a);
    try std.testing.expectEqual(source.instructions.items[0], output.bodies[0].instructions[0]);
    try std.testing.expectEqualSlices(ir.Instruction, code[3..12], output.bodies[0].instructions[1..10]);
    try std.testing.expectEqual(ir.Instruction{ .op = .local_get, .origin = 29 }, output.bodies[0].instructions[10]);
    try std.testing.expectEqual(source.instructions.items[13], output.bodies[0].instructions[11]);
}
test "scoped copy coalescing declines hidden and flagged local identities anywhere" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .nop },
    });
    defer source.deinit(a);
    for ([_]ir.Instruction{
        .{ .op = .ownership },                        .{ .op = .resource_retire },                    .{ .op = .wide_layouts },
        .{ .op = .local_get, .operand = 2 },          .{ .op = .local_get, .table_reference = true }, .{ .op = .local_set, .table_kind = .callable },
        .{ .op = .local_tee, .table_kind = .demand },
    }) |hidden| {
        source.instructions.items[3] = hidden;
        try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    }
    source.instructions.items[3] = .{ .op = .nop };
    source.locals.items[0] = .f32;
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    source.locals.items[0] = .i32;
    parameters[0] = .externref;
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
}
test "scoped copy coalescing declines cyclic duplicate disconnected and multiply called helpers" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 }, .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    var bodies = [_]coalesce.Body{
        .{ .function = 4, .instructions = source.instructions.items },
        .{ .function = 7, .instructions = &.{} },
    };
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
    bodies[1].function = 4;
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
    bodies[1].function = 7;
    bodies[1].instructions = &.{.{ .op = .call, .operand = 7 }};
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
    try source.instructions.appendSlice(a, &.{ .{ .op = .call, .operand = 7 }, .{ .op = .call, .operand = 7 } });
    bodies[0].instructions = source.instructions.items;
    bodies[1].instructions = &.{};
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
    source.instructions.items[source.instructions.items.len - 1] = .{ .op = .call, .operand = 4 };
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
}
test "scoped copy coalescing retains canonical sources with earlier zero reads" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{ .i32, .i32 }, &.{
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    // Local two captured local one's default zero, then one was overwritten.
    try std.testing.expect((try coalesce.run(a, &source, &single(&source))) == null);
    source.instructions.items[2] = .{ .op = .nop };
    source.instructions.items[3] = .{ .op = .nop };
    var output = (try coalesce.run(a, &source, &single(&source))).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 1 }, output.aliases);
    try std.testing.expectEqual(@as(u32, 1), output.bodies[0].instructions[2].operand);
}
test "scoped copy coalescing publishes through accepted copies and stops at retained intermediates" {
    var parameters = [_]ir.ValueType{.i32};
    const code = [_]ir.Instruction{
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .drop },
        .{ .op = .i32_const, .operand = 9 }, .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },
    };
    var source = try fixture(&parameters, &.{ .i32, .i32 }, &code);
    defer source.deinit(a);
    var output = (try coalesce.run(a, &source, &single(&source))).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), output.removed_copies);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 1 }, output.aliases);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        code[0], code[1], .{ .op = .local_get, .operand = 1 }, code[5], code[6], code[7], code[8],
    }, output.bodies[0].instructions);
    // Moving E's read across the source write keeps its snapshot. D's only
    // remaining read is the copy into E, so that earlier copy can disappear.
    source.instructions.items[4] = .{ .op = .i32_const };
    source.instructions.items[8] = .{ .op = .local_get, .operand = 2 };
    var retained = (try coalesce.run(a, &source, &single(&source))).?;
    defer retained.deinit(a);
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 2 }, retained.aliases);
    try std.testing.expectEqual(@as(usize, 1), retained.removed_copies);
    try std.testing.expectEqual(ir.Instruction{ .op = .local_get }, retained.bodies[0].instructions[0]);
    try std.testing.expectEqual(code[3], retained.bodies[0].instructions[1]);
    try std.testing.expectEqual(ir.Instruction{ .op = .local_get, .operand = 2 }, retained.bodies[0].instructions[6]);
}
test "scoped copy coalescing observes helper writes before later caller reads" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get },          .{ .op = .local_set, .operand = 1 },
        .{ .op = .call, .operand = 7 }, .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    const bodies = [_]coalesce.Body{
        .{ .function = 4, .instructions = source.instructions.items },
        .{ .function = 7, .instructions = &.{ .{ .op = .i32_const, .operand = 9 }, .{ .op = .local_set } } },
    };
    try std.testing.expect((try coalesce.run(a, &source, &bodies)) == null);
}
test "scoped copy coalescing walks deeply nested helpers iteratively" {
    const depth = 4_096;
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{.i32}, &.{
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 }, .{ .op = .call, .operand = 1 },
    });
    defer source.deinit(a);
    const calls = try a.alloc(ir.Instruction, depth);
    defer a.free(calls);
    const bodies = try a.alloc(coalesce.Body, depth + 1);
    defer a.free(bodies);
    bodies[0] = .{ .function = 0, .instructions = source.instructions.items };
    for (1..depth + 1) |index| {
        calls[index - 1] = .{ .op = .call, .operand = @intCast(index + 1) };
        bodies[index] = .{ .function = @intCast(index), .instructions = calls[index - 1 .. index] };
    }
    calls[depth - 1] = .{ .op = .local_get, .operand = 1 };
    var output = (try coalesce.run(a, &source, bodies)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 1), output.removed_copies);
    try std.testing.expectEqual(@as(usize, 1), output.forwarded_reads);
    try std.testing.expectEqualSlices(ir.Instruction, &.{.{ .op = .local_get }}, output.bodies[depth].instructions);
}
fn checkSingle(allocator: A, source: *const ir.Function) !void {
    var output = (try coalesce.runSingle(allocator, source)).?;
    defer output.deinit(allocator);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .f32, .v128, .i32 }, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 },
        .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_tee, .operand = 4 },
        .{ .op = .drop },                    .{ .op = .local_get, .origin = 17 },
        .{ .op = .local_get },               .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 4 }, .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .drop },
    }, output.instructions.items);
}
test "scoped copy coalescing standalone prunes only removed destinations and remaps typed locals through OOM" {
    var parameters = [_]ir.ValueType{ .i32, .f32 };
    const code = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 },
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 3 },
        .{ .op = .local_get, .operand = 3 }, .{ .op = .local_set, .operand = 4 },
        .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_tee, .operand = 6 },
        .{ .op = .drop },                    .{ .op = .local_get, .operand = 4, .origin = 17 },
        .{ .op = .local_get, .operand = 3 }, .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 6 }, .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .drop },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .drop },
    };
    var source = try fixture(&parameters, &.{ .f32, .i32, .i32, .v128, .i32 }, &code);
    defer source.deinit(a);
    try checkSingle(a, &source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkSingle, .{@as(*const ir.Function, &source)});
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .f32, .i32, .i32, .v128, .i32 }, source.locals.items);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .i32, .f32 }, source.parameters);
}
