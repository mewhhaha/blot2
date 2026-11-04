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
        var op: ir.Op = .i32_const;
        if (index == 0) op = .local_get;
        try std.testing.expectEqual(op, root.instructions.items[index * 2].op);
        try std.testing.expectEqual(@as(u32, 0), root.instructions.items[index * 2].operand);
        try std.testing.expectEqual(ir.Op.global_set, root.instructions.items[index * 2 + 1].op);
    }
    try std.testing.expectEqual(ir.Op.call, root.instructions.items[8].op);
    try std.testing.expectEqual(@as(u32, 1), root.instructions.items[8].operand);
    try std.testing.expectError(error.InvalidOutline, context.finalize());
}
test "scoped machine helpers preserve future references zero lanes tee metadata and loop state through OOM" {
    try exactState(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, exactState, .{});
}

test "nested scoped machine helpers credit each body once and preserve cross helper registers" {
    var module = try moduleWithRoot(a, &.{.i32}, .i32, &.{ .i32, .i32, .i32, .i32 });
    defer module.deinit();
    var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1, .verify_copy_inputs = true });
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
    try std.testing.expectEqual(@as(u64, 2), stats.globals);
    try std.testing.expectEqual(@as(u64, 3), stats.copies_removed);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[0].instructions.items[4].op);
    try std.testing.expectEqual(@as(u32, 2), module.functions.items[0].instructions.items[4].operand);
    try std.testing.expectEqual(ir.Op.call, module.functions.items[2].instructions.items[0].op);
    try std.testing.expectEqual(@as(u32, 1), module.functions.items[2].instructions.items[0].operand);
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

fn executeBank(module: *const wasm.Module, function: u32, parameters: []const u32, globals: []u32, calls: *std.ArrayList(u32)) A.Error!u32 {
    try calls.append(a, function);
    const body = module.functions.items[function];
    const locals = try a.alloc(u32, body.parameters.len + body.locals.items.len);
    defer a.free(locals);
    @memset(locals, 0);
    @memcpy(locals[0..parameters.len], parameters);
    var stack: std.ArrayList(u32) = .empty;
    defer stack.deinit(a);
    for (body.instructions.items) |inst| switch (inst.op) {
        .i32_const => try stack.append(a, inst.operand),
        .local_get => try stack.append(a, locals[inst.operand]),
        .global_get => try stack.append(a, globals[inst.operand]),
        .global_set => globals[inst.operand] = stack.pop().?,
        .drop => _ = stack.pop(),
        .i32_add => {
            const right = stack.pop().?;
            const left = stack.pop().?;
            try stack.append(a, left +% right);
        },
        .call => {
            const result = try executeBank(module, inst.operand, &.{}, globals, calls);
            if (module.functions.items[inst.operand].result != .none) try stack.append(a, result);
        },
        else => unreachable,
    };
    if (body.result == .none) return 0;
    return stack.pop().?;
}

test "scoped bank frequency ordering crosses LEB thresholds deterministically and preserves repeated invocations" {
    for ([_]usize{ 126, 16_382 }) |existing_globals| {
        var module = try moduleWithRoot(a, &.{.i32}, .i32, &.{ .i32, .i32, .i32 });
        defer module.deinit();
        for (0..existing_globals) |_| _ = try module.addGlobal(.u32, 0, true);
        var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
        defer context.deinit();
        try context.registerRoot(0);
        for (1..4) |id| try emit(&module, 0, &.{ .{ .op = .i32_const, .operand = @intCast(id * 7) }, .{ .op = .local_set, .operand = @intCast(id) } });
        const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
        try emit(&module, 0, &.{
            .{ .op = .local_get, .operand = 1 },  .{ .op = .drop },
            .{ .op = .local_get, .operand = 2 },  .{ .op = .drop },
            .{ .op = .local_get, .operand = 1 },  .{ .op = .drop },
            .{ .op = .local_get, .operand = 2 },  .{ .op = .drop },
            .{ .op = .i32_const, .operand = 13 }, .{ .op = .local_tee, .operand = 3 },
            .{ .op = .drop },                     .{ .op = .local_get },
            .{ .op = .local_get, .operand = 3 },  .{ .op = .i32_add },
            .{ .op = .local_set, .operand = 3 },
        });
        try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 0 })) != null);
        try emit(&module, 0, &.{.{ .op = .local_get, .operand = 3 }});
        const stats = try context.finalize();
        try std.testing.expectEqual(@as(u64, 4), stats.globals);
        try std.testing.expectEqual(@as(u64, 5), stats.bank_operand_bytes_saved);
        const root = module.functions.items[0].instructions.items;
        // Local 3 is hottest; equal-weight locals 1 and 2 retain their order.
        const mapping = [_]u32{ @intCast(existing_globals + 3), @intCast(existing_globals + 1), @intCast(existing_globals + 2), @intCast(existing_globals) };
        for (mapping, 0..) |global, id| try std.testing.expectEqual(global, root[id * 2 + 1].operand);
        const globals = try a.alloc(u32, module.globals.items.len);
        defer a.free(globals);
        @memset(globals, 99);
        var calls: std.ArrayList(u32) = .empty;
        defer calls.deinit(a);
        try std.testing.expectEqual(@as(u32, 18), try executeBank(&module, 0, &.{5}, globals, &calls));
        try std.testing.expectEqual(@as(u32, 22), try executeBank(&module, 0, &.{9}, globals, &calls));
        try std.testing.expectEqualSlices(u32, &.{ 0, 1, 0, 1 }, calls.items);
        try std.testing.expectEqual(@as(u32, 99), globals[0]);
    }
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
            try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
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

fn recursiveCalleeBank(allocator: A, mutual: bool) !void {
    var module = try moduleWithRoot(allocator, &.{.i32}, .i32, &.{.i32});
    defer module.deinit();
    const runtime_global = try module.addGlobal(.u32, 0, true);
    const callee = try module.addTypedFunction(&.{.i32}, .none, .scalar);
    var target = callee;
    if (mutual) target = try module.addTypedFunction(&.{.i32}, .none, .scalar);
    for (callee..target + 1) |function| {
        var backedge = callee;
        if (function == callee) backedge = target;
        try module.functions.items[function].locals.append(allocator, .i32);
        try emit(&module, @intCast(function), &.{
            .{ .op = .local_get },                             .{ .op = .local_set, .operand = 1 },
            .{ .op = .local_get },                             .{ .op = .if_ },
            .{ .op = .local_get },                             .{ .op = .i32_const, .operand = 1 },
            .{ .op = .i32_sub },                               .{ .op = .call, .operand = backedge },
            .{ .op = .end },                                   .{ .op = .i32_const, .operand = 17 },
            .{ .op = .global_set, .operand = runtime_global },
        });
    }
    var context = outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    try emit(&module, 0, &.{
        .{ .op = .local_get }, .{ .op = .call, .operand = callee },
        .{ .op = .local_get }, .{ .op = .local_set, .operand = 1 },
    });
    try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 0 })) != null);
    try emit(&module, 0, &.{.{ .op = .local_get, .operand = 1 }});
    const helper = context.helpers.items[0].function;
    const root_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[0].instructions.items));
    const helper_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[helper].instructions.items));
    const callee_hash = std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[callee].instructions.items));
    const stats = context.finalize() catch |err| {
        // The graph proof and all preparation precede bank/body publication.
        try std.testing.expectEqual(@as(usize, 1), module.globals.items.len);
        try std.testing.expectEqual(root_hash, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[0].instructions.items)));
        try std.testing.expectEqual(helper_hash, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[helper].instructions.items)));
        try std.testing.expectEqual(@as(usize, 1), module.functions.items[0].locals.items.len);
        try std.testing.expect(!context.finalized);
        try std.testing.expectEqual(@as(u64, 0), context.stats.regions);
        return err;
    };
    try std.testing.expectEqual(@as(u64, 1), stats.regions);
    try std.testing.expectEqual(@as(u64, 1), stats.globals);
    try std.testing.expectEqual(callee_hash, std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(module.functions.items[callee].instructions.items)));
    try std.testing.expectEqual(@as(usize, 1), module.functions.items[callee].locals.items.len);
    const bytes = try module.assembleWithOptions(.{});
    defer allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109, 1, 0, 0, 0 }, bytes[0..8]);
}

test "scoped bank callers admit ordinary self recursive callees transactionally through OOM" {
    try recursiveCalleeBank(a, false);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, recursiveCalleeBank, .{false});
}

test "scoped bank machine proof admits disjoint mutual recursion without granting source admission" {
    try recursiveCalleeBank(a, true);
}

test "scoped bank SCC proof rejects reentry through explored ordinary cycles and unknown dispatch" {
    for (0..5) |mode| {
        var module = try moduleWithRoot(a, &.{.i32}, .none, &.{});
        defer module.deinit();
        const first = try module.addTypedFunction(&.{}, .none, .scalar);
        const second = try module.addTypedFunction(&.{}, .none, .scalar);
        var context = outline.Context.init(a, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
        defer context.deinit();
        try context.registerRoot(0);
        var target = first;
        if (mode == 2) {
            // Enter the ordinary SCC before its later path enters the helper.
            try emit(&module, 0, &.{.{ .op = .call, .operand = first }});
            target = second;
        }
        const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
        try emit(&module, 0, &.{ .{ .op = .local_get }, .{ .op = .drop }, .{ .op = .call, .operand = target } });
        try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 1, .layouts = 0 })) != null);
        const helper = context.helpers.items[0].function;
        try emit(&module, first, &.{.{ .op = .call, .operand = second }});
        try emit(&module, second, &.{.{ .op = .call, .operand = first }});
        switch (mode) {
            0 => try emit(&module, second, &.{ .{ .op = .i32_const }, .{ .op = .call } }),
            1 => try emit(&module, second, &.{.{ .op = .call, .operand = helper }}),
            // The ordinary backedge is visited before this helper joins its SCC.
            2 => try emit(&module, first, &.{.{ .op = .call, .operand = helper }}),
            3 => try emit(&module, second, &.{.{ .op = .call_indirect }}),
            4 => try emit(&module, helper, &.{.{ .op = .call, .operand = helper }}),
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidOutline, context.finalize());
        try std.testing.expectEqual(@as(usize, 0), module.globals.items.len);
        try std.testing.expect(!context.finalized);
        try std.testing.expectEqual(@as(u64, 0), context.stats.regions);
    }
}

fn branchMembershipChurn(allocator: A) !void {
    const rounds = 24;
    const locals: [33 + 2 * rounds]ir.ValueType = @splat(.i32);
    var module = try moduleWithRoot(allocator, &.{}, .none, &locals);
    defer module.deinit();
    var context = outline.Context.init(allocator, &module, .scoped_numeric_adapter_nonreentrant, .{ .minimum_instructions = 1 });
    defer context.deinit();
    try context.registerRoot(0);
    const ticket = context.begin(0, .{ .expressions = 0, .layouts = 0 }).?;
    for (0..8) |id| try emit(&module, 0, &.{ .{ .op = .i32_const }, .{ .op = .local_set, .operand = @intCast(id) } });
    // These writes are not definite after the implicit false arm. Rollback
    // leaves inactive entries; later reads must not treat presence as true.
    try emit(&module, 0, &.{ .{ .op = .i32_const }, .{ .op = .if_ } });
    for (8..32) |id| try emit(&module, 0, &.{ .{ .op = .i32_const }, .{ .op = .local_set, .operand = @intCast(id) } });
    try emit(&module, 0, &.{.{ .op = .end }});
    for (0..rounds) |round| {
        const id: u32 = @intCast(32 + 2 * round);
        try emit(&module, 0, &.{
            .{ .op = .i32_const },                    .{ .op = .if_ },
            .{ .op = .i32_const },                    .{ .op = .local_set, .operand = id },
            .{ .op = .else_ },                        .{ .op = .i32_const },
            .{ .op = .local_set, .operand = id + 1 }, .{ .op = .end },
            .{ .op = .local_get, .operand = id },     .{ .op = .drop },
            .{ .op = .local_get },                    .{ .op = .drop },
        });
    }
    const common = 32 + 2 * rounds;
    try emit(&module, 0, &.{
        .{ .op = .i32_const },                    .{ .op = .if_ },
        .{ .op = .i32_const },                    .{ .op = .local_set, .operand = common },
        .{ .op = .else_ },                        .{ .op = .i32_const },
        .{ .op = .local_set, .operand = common }, .{ .op = .end },
        .{ .op = .local_get, .operand = common }, .{ .op = .drop },
    });
    try std.testing.expect((try context.tryExtract(ticket, .{ .expressions = 100, .layouts = 0 })) != null);
    const inputs = context.helpers.items[0].read_before_def;
    try std.testing.expectEqual(@as(usize, rounds), inputs.len);
    for (0..common + 1) |index| {
        var expected = false;
        if (index >= 32 and index < common and (index - 32) % 2 == 0) expected = true;
        try std.testing.expectEqual(expected, std.mem.findScalar(u32, inputs, @intCast(index)) != null);
    }
    const stats = try context.finalize();
    try std.testing.expectEqual(@as(u64, rounds), stats.globals);
}

test "scoped helper initialization retains exact branch intersections through churn and OOM" {
    try branchMembershipChurn(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, branchMembershipChurn, .{});
}
