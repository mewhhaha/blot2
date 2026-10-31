const std = @import("std");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const outline = @import("wasm_scope_outline.zig");
const A = std.mem.Allocator;
const a = std.testing.allocator;

fn moduleWithRoot(allocator: A, parameters: []const ir.ValueType, result: ir.ValueType, locals: []const ir.ValueType) !wasm.Module {
    var module = wasm.Module.init(allocator);
    errdefer module.deinit();
    module.memory_model = .data_stacks;
    const root = try module.addTypedFunction(parameters, result, .scalar);
    try std.testing.expectEqual(@as(u32, 0), root);
    try module.functions.items[root].locals.appendSlice(allocator, locals);
    return module;
}
fn emit(module: *wasm.Module, function: u32, instructions: []const ir.Instruction) !void {
    try module.functions.items[function].instructions.appendSlice(module.allocator, instructions);
}
fn exactState(allocator: A) !void {
    var module = try moduleWithRoot(allocator, &.{.i32}, .i32, &.{ .i32, .i32, .i32, .i32, .i32 });
    defer module.deinit();
    var context = outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 } });
    const ticket = context.begin(0, .{ .expressions = 10, .layouts = 5 }).?;
    try emit(&module, 0, &.{
        .{ .op = .local_get, .operand = 1 },
        .{ .op = .local_tee, .operand = 2, .origin = 912 },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = 3 }, // Never written: always zero.
        .{ .op = .drop },
        .{ .op = .i32_const, .operand = 9 },
        .{ .op = .local_set, .operand = 4 }, // Used later in the caller.
        .{ .op = .local_get, .operand = 5 }, // Written RBD: keep loop state.
        .{ .op = .drop },
        .{ .op = .i32_const, .operand = 10 },
        .{ .op = .local_set, .operand = 5 },
        .{ .op = .i32_const, .operand = 0, .table_reference = true, .table_kind = .callable, .origin = 19 },
        .{ .op = .drop },
    });
    const credit = (try context.tryExtract(ticket, .{ .expressions = 17, .layouts = 8 })).?;
    try std.testing.expectEqual(@as(usize, 7), credit.expressions);
    try std.testing.expectEqual(@as(usize, 3), credit.layouts);
    try emit(&module, 0, &.{
        .{ .op = .local_get, .operand = 4 }, .{ .op = .drop },
        .{ .op = .local_get, .operand = 2 }, .{ .op = .local_get, .operand = 5 },
        .{ .op = .i32_add },
    });
    const stats = try context.finalize();
    try std.testing.expectEqual(@as(u64, 1), stats.regions);
    try std.testing.expectEqual(@as(u64, 4), stats.globals);
    try std.testing.expectEqual(@as(usize, 4), module.globals.items.len);
    const helper = &module.functions.items[1];
    try std.testing.expectEqual(@as(usize, 0), helper.parameters.len);
    try std.testing.expectEqual(ir.ValueType.none, helper.result);
    try std.testing.expectEqual(@as(usize, 1), helper.locals.items.len);
    try std.testing.expectEqual(ir.Op.global_get, helper.instructions.items[0].op);
    const tee_set = helper.instructions.items[1];
    const tee_get = helper.instructions.items[2];
    try std.testing.expectEqual(ir.Op.global_set, tee_set.op);
    try std.testing.expectEqual(ir.Op.global_get, tee_get.op);
    try std.testing.expectEqual(tee_set.operand, tee_get.operand);
    try std.testing.expectEqual(@as(u21, 912), tee_set.origin);
    try std.testing.expectEqual(tee_set.origin, tee_get.origin);
    const symbolic = helper.instructions.items[helper.instructions.items.len - 2];
    try std.testing.expectEqual(@as(u64, @bitCast(ir.Instruction{ .op = .i32_const, .operand = 0, .table_reference = true, .table_kind = .callable, .origin = 19 })), @as(u64, @bitCast(symbolic)));
    const root = &module.functions.items[0];
    for (0..4) |index| {
        try std.testing.expectEqual(ir.Op.i32_const, root.instructions.items[index * 2].op);
        try std.testing.expectEqual(@as(u32, 0), root.instructions.items[index * 2].operand);
        try std.testing.expectEqual(ir.Op.global_set, root.instructions.items[index * 2 + 1].op);
    }
    try std.testing.expectEqual(ir.Op.call, root.instructions.items[10].op);
    try std.testing.expectEqual(@as(u32, 1), root.instructions.items[10].operand);
    try std.testing.expectError(error.InvalidOutline, context.finalize());
}
test "scoped machine helpers preserve future references zero lanes tee metadata and loop state through OOM" {
    try exactState(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, exactState, .{});
}

test "nested scoped machine helpers credit each body once and preserve cross helper registers" {
    var module = try moduleWithRoot(a, &.{.i32}, .i32, &.{ .i32, .i32, .i32, .i32 });
    defer module.deinit();
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 } });
    const parent = context.begin(0, .{ .expressions = 10, .layouts = 5 }).?;
    try emit(&module, 0, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = 2 } });
    const child = context.begin(0, .{ .expressions = 20, .layouts = 8 }).?;
    try emit(&module, 0, &.{ .{ .op = .local_get, .operand = 2 }, .{ .op = .local_tee, .operand = 3 }, .{ .op = .drop } });
    const child_credit = (try context.tryExtract(child, .{ .expressions = 35, .layouts = 12 })).?;
    try std.testing.expectEqual(@as(usize, 15), child_credit.expressions);
    try std.testing.expectEqual(@as(usize, 4), child_credit.layouts);
    try emit(&module, 0, &.{ .{ .op = .local_get, .operand = 3 }, .{ .op = .local_set, .operand = 4 } });
    // The caller has already removed the committed child's work.
    const parent_credit = (try context.tryExtract(parent, .{ .expressions = 25, .layouts = 10 })).?;
    try std.testing.expectEqual(@as(usize, 15), parent_credit.expressions);
    try std.testing.expectEqual(@as(usize, 5), parent_credit.layouts);
    try emit(&module, 0, &.{.{ .op = .local_get, .operand = 4 }});
    const stats = try context.finalize();
    try std.testing.expectEqual(@as(u64, 2), stats.regions);
    try std.testing.expectEqual(@as(u64, 4), stats.globals);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[0].instructions.items[10].op);
    try std.testing.expectEqual(@as(u32, 2), module.functions.items[0].instructions.items[10].operand);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[2].instructions.items[2].op);
    try std.testing.expectEqual(@as(u32, 1), module.functions.items[2].instructions.items[2].operand);
}

test "scoped machine helpers decline externref parents while preserving committed numeric children" {
    var module = try moduleWithRoot(a, &.{.externref}, .none, &.{.i32});
    defer module.deinit();
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const parent = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    const child = context.begin(0, .{ .expressions = 1, .layouts = 0 }).?;
    try emit(&module, 0, &.{ .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_set, .operand = 1 } });
    try std.testing.expect((try context.tryExtract(child, .{ .expressions = 3, .layouts = 0 })) != null);
    try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .drop } });
    try std.testing.expect((try context.tryExtract(parent, .{ .expressions = 3, .layouts = 0 })) == null);
    const stats = try context.finalize();
    try std.testing.expectEqual(@as(u64, 1), stats.regions);
    try std.testing.expectEqual(@as(u64, 0), stats.globals);
    try std.testing.expectEqual(ir.ValueType.externref, module.functions.items[0].parameters[0]);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[0].instructions.items[0].op);
    try std.testing.expectEqual(ir.Op.local_get, module.functions.items[0].instructions.items[1].op);
}

test "scoped machine helper banks initialize parameters from each root invocation" {
    var module = try moduleWithRoot(a, &.{.i32}, .none, &.{});
    defer module.deinit();
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .drop } });
    try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 0 })) != null);
    try std.testing.expectEqual(@as(u64, 1), (try context.finalize()).globals);
    const root = module.functions.items[0].instructions.items;
    try std.testing.expectEqual(ir.Op.local_get, root[0].op);
    try std.testing.expectEqual(@as(u32, 0), root[0].operand);
    try std.testing.expectEqual(ir.Op.global_set, root[1].op);
    try std.testing.expectEqual(ir.Op.call, root[2].op);
    try std.testing.expectEqual(ir.Op.global_get, module.functions.items[1].instructions.items[0].op);
}

test "scoped final encoding counts parameters with declared locals at the existing engine bound" {
    for ([_]usize{ 49_999, 50_000 }) |count| {
        var module = try moduleWithRoot(a, &.{.i32}, .i32, &.{});
        defer module.deinit();
        // Non-i32 unused locals remain pinned by final temporary compaction.
        try module.functions.items[0].locals.appendNTimes(a, .f32, count);
        try emit(&module, 0, &.{.{ .op = .i32_const }});
        if (count == 50_000) {
            try std.testing.expectError(error.ModuleTooLarge, module.assembleWithOptions(.{}));
        } else {
            const bytes = try module.assembleWithOptions(.{});
            defer a.free(bytes);
            try std.testing.expect(bytes.len > count);
        }
    }
}

test "scoped machine helpers require closed typed controls and use complete call signatures" {
    var module = try moduleWithRoot(a, &.{}, .none, &.{.i32});
    defer module.deinit();
    const callee = try module.addTypedFunction(&.{ .i32, .i32, .i32, .i32 }, .none, .scalar);
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const invalid = [_][]const ir.Instruction{
        &.{.{ .op = .br }},
        &.{.{ .op = .return_ }},
        &.{.{ .op = .end }},
        &.{.{ .op = .ownership }},
        &.{.{ .op = .resource_retire }},
        &.{.{ .op = .local_get, .operand = 99 }},
        &.{.{ .op = .i32_const }},
        &.{ .{ .op = .block }, .{ .op = .br, .operand = 1 }, .{ .op = .end } },
        &.{ .{ .op = .block }, .{ .op = .else_ }, .{ .op = .end } },
        &.{ .{ .op = .i32_const }, .{ .op = .i32_const }, .{ .op = .i32_const }, .{ .op = .call, .operand = callee } },
    };
    for (invalid) |code| {
        const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
        try emit(&module, 0, code);
        try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 1 })) == null);
        try std.testing.expectEqualSlices(ir.Instruction, code, module.functions.items[0].instructions.items);
        module.functions.items[0].instructions.clearRetainingCapacity();
    }
    const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    try emit(&module, 0, &.{
        .{ .op = .i32_const },               .{ .op = .i32_const }, .{ .op = .i32_const }, .{ .op = .i32_const },
        .{ .op = .call, .operand = callee }, .{ .op = .block },     .{ .op = .br },        .{ .op = .end },
    });
    try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 1 })) != null);
    try std.testing.expectEqual(@as(u64, 1), (try context.finalize()).regions);
}

test "scoped machine helpers keep written lanes when one branch leaves them unchanged" {
    for ([_]bool{ false, true }) |complete| {
        var module = try moduleWithRoot(a, &.{}, .none, &.{.i32});
        defer module.deinit();
        var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
        defer context.deinit();
        try context.registerRoot(0);
        const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
        try emit(&module, 0, &.{ .{ .op = .i32_const }, .{ .op = .if_ }, .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_set } });
        if (complete) try emit(&module, 0, &.{ .{ .op = .else_ }, .{ .op = .i32_const, .operand = 9 }, .{ .op = .local_set } });
        try emit(&module, 0, &.{ .{ .op = .end }, .{ .op = .local_get }, .{ .op = .drop } });
        try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 1 })) != null);
        const stats = try context.finalize();
        try std.testing.expectEqual(@as(u64, if (complete) 0 else 1), stats.globals);
    }
}

test "scoped machine helper banks reject internal cycles unknown dispatch and global overflow" {
    for (0..3) |mode| {
        var module = try moduleWithRoot(a, &.{}, .none, &.{ .i32, .i32 });
        defer module.deinit();
        const callee = try module.addTypedFunction(&.{}, .none, .scalar);
        if (mode == 0) try emit(&module, callee, &.{.{ .op = .call }});
        var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1, .maximum_globals = if (mode == 2) 1 else 1_000_000 });
        defer context.deinit();
        try context.registerRoot(0);
        const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
        try emit(&module, 0, &.{ .{ .op = .i32_const }, .{ .op = .local_set }, .{ .op = .i32_const }, .{ .op = .local_set, .operand = 1 }, .{ .op = .call, .operand = callee } });
        try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 1 })) != null);
        if (mode == 1) try emit(&module, 0, &.{.{ .op = .call_indirect }});
        if (mode == 2) try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .drop }, .{ .op = .local_get, .operand = 1 }, .{ .op = .drop } });
        if (mode == 2) try std.testing.expectError(error.OutlineLimit, context.finalize()) else try std.testing.expectError(error.InvalidOutline, context.finalize());
        try std.testing.expectEqual(@as(usize, 0), module.globals.items.len);
    }
}
