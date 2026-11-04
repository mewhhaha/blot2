const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const Session = @import("runtime_pipeline.zig").Session;
const a = std.testing.allocator;

fn checkForwarding(allocator: std.mem.Allocator, module: *const wasm.Module) !void {
    var passes = try Session.init(allocator, module);
    defer passes.deinit();
    try std.testing.expect(passes.roots);
}

test "generic word adapters preserve permuted formals through finite private chains and OOM" {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const leaf = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .value);
    try module.setParameterRoles(leaf, ir.packParameterRoles(&.{ .value, .reference }));
    try module.emit(leaf, .{ .op = .local_get });
    const middle = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .value);
    try module.setParameterRoles(middle, ir.packParameterRoles(&.{ .reference, .value, .reference }));
    try module.emitSlice(middle, &.{
        .{ .op = .local_get, .operand = 1 }, .{ .op = .local_get, .operand = 2 },
        .{ .op = .call, .operand = leaf },   .{ .op = .return_ },
    });
    const outer = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .value);
    try module.setParameterRoles(outer, ir.packParameterRoles(&.{ .reference, .reference, .value }));
    try module.emitSlice(outer, &.{
        .{ .op = .local_get },               .{ .op = .local_get, .operand = 2 },
        .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = middle },
    });
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, checkForwarding, .{&module});
    for ([_]@import("../compilation_tier.zig").Tier{ .optimized, .development }) |tier| {
        const bytes = try module.assembleCheckedWithOptions(.{ .tier = tier });
        defer a.free(bytes);
        try std.testing.expectEqual(ir.Role.value, module.functions.items[outer].result_role);
        try std.testing.expectEqual(ir.Role.value, module.functions.items[outer].parameterRole(2));
    }
    const original = try a.dupe(ir.Instruction, module.functions.items[middle].instructions.items);
    defer a.free(original);
    for (0..5) |scenario| {
        module.functions.items[middle].instructions.clearRetainingCapacity();
        try module.functions.items[middle].instructions.appendSlice(a, original);
        module.functions.items[leaf].instructions.shrinkRetainingCapacity(1);
        switch (scenario) {
            0 => module.functions.items[middle].instructions.items[0].operand = 0,
            1 => {
                module.functions.items[middle].instructions.items[2] = .{ .op = .i32_const };
                module.functions.items[middle].instructions.items[3] = .{ .op = .call_indirect, .operand = module.functions.items[leaf].signature };
                try module.emit(middle, .{ .op = .return_ });
            },
            2 => try module.emitSlice(leaf, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .call, .operand = leaf } }),
            3 => module.functions.items[middle].instructions.items[0] = .{ .op = .i32_const, .operand = 41 },
            4 => module.functions.items[middle].instructions.items[3] = .{ .op = .i32_load },
            else => unreachable,
        }
        var rejected = try Session.init(a, &module);
        defer rejected.deinit();
        try std.testing.expect(!rejected.roots);
    }
}

test "generic word forwarding preserves result and input authority in both runtime tiers" {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const id = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .value);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{ .reference, .value, .reference }));
    try module.emit(id, .{ .op = .local_get, .operand = 1 });
    for ([_]@import("../compilation_tier.zig").Tier{ .optimized, .development }) |tier| {
        var passes = try Session.init(a, &module);
        defer passes.deinit();
        passes.tier = tier;
        try std.testing.expect(passes.roots);
        try std.testing.expect(passes.summaries.functions[id].parameters[1].escapes);
        try std.testing.expectEqual(@as(?u32, null), passes.summaries.functions[id].owned_result_bytes);
        var output = try passes.optimize(&module.functions.items[id]);
        defer if (output) |*body| body.deinit(a);
        const instructions = if (output) |body| body.instructions.items else module.functions.items[id].instructions.items;
        try std.testing.expectEqualSlices(ir.Instruction, &.{.{ .op = .local_get, .operand = 1 }}, instructions);
        const bytes = try module.assembleCheckedWithOptions(.{ .tier = tier });
        defer a.free(bytes);
        try std.testing.expectEqual(ir.Role.value, module.functions.items[id].result_role);
        try std.testing.expectEqual(ir.Role.value, module.functions.items[id].parameterRole(1));
    }
    try module.emit(id, .{ .op = .return_ });
    var explicit = try Session.init(a, &module);
    defer explicit.deinit();
    try std.testing.expect(explicit.roots);
}

test "generic word forwarding rejects unknown results different formals and extra actions" {
    var module = wasm.Module.init(a);
    defer module.deinit();
    _ = try module.ensureArena();
    const id = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .value);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{ .reference, .value, .reference }));
    try module.emit(id, .{ .op = .local_get, .operand = 1 });
    const original = module.functions.items[id];
    const first = original.instructions.items[0];
    for (0..8) |scenario| {
        var function = &module.functions.items[id];
        function.result_role = original.result_role;
        function.entry = false;
        function.parameter_roles = original.parameter_roles;
        function.instructions.items[0] = first;
        function.instructions.shrinkRetainingCapacity(1);
        function.locals.clearRetainingCapacity();
        switch (scenario) {
            0 => function.result_role = .unknown,
            1 => function.instructions.items[0].operand = 0,
            2 => function.parameter_roles = ir.packParameterRoles(&.{ .reference, .unknown, .reference }),
            3 => function.entry = true,
            4 => try function.locals.append(a, .i32),
            5 => function.instructions.items[0] = .{ .op = .i32_const, .operand = 42 },
            6 => try module.emit(id, .{ .op = .i32_load }),
            7 => try module.emit(id, .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope }) }),
            else => unreachable,
        }
        var passes = try Session.init(a, &module);
        defer passes.deinit();
        try std.testing.expect(!passes.roots);
        for ([_]@import("../compilation_tier.zig").Tier{ .optimized, .development }) |tier| {
            try std.testing.expectError(error.IncompleteOwnership, module.assembleCheckedWithOptions(.{ .tier = tier }));
        }
    }
}
