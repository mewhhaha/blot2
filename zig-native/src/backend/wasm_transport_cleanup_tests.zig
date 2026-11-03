const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const run = @import("wasm_transport_cleanup.zig").run;
const A = std.mem.Allocator;
const a = std.testing.allocator;

fn fixture(parameters: []ir.ValueType, locals: []const ir.ValueType, code: []const ir.Instruction) !ir.Function {
    var result: ir.Function = .{ .parameters = parameters, .result = .i32, .signature = 0 };
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, locals);
    try result.instructions.appendSlice(a, code);
    return result;
}
fn replacement(allocator: A, source: *const ir.Function) !void {
    const original_locals = source.locals.items.ptr;
    const original_code = source.instructions.items.ptr;
    var output = (try run(allocator, source)).?;
    defer output.deinit(allocator);
    try std.testing.expectEqualSlices(ir.ValueType, source.locals.items, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .i32_const, .operand = 19, .origin = 31 },
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .local_tee, .operand = 1, .origin = 55 },
        .{ .op = .i32_add, .origin = 88 },
        .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },
    }, output.instructions.items);
    try std.testing.expect(output.locals.items.ptr != original_locals);
    try std.testing.expect(output.instructions.items.ptr != original_code);
}
test "scoped transport removes self copies and folds tee above live stack values through OOM" {
    const code = [_]ir.Instruction{
        .{ .op = .i32_const, .operand = 19, .origin = 31 },
        .{ .op = .local_get, .origin = 42 },
        .{ .op = .local_set, .origin = 43 },
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .local_set, .operand = 1, .origin = 55 },
        .{ .op = .local_get, .operand = 1, .origin = 56 },
        .{ .op = .i32_add, .origin = 88 },
        // Unequal indices are a real copy and must remain.
        .{ .op = .local_set },
        .{ .op = .local_get, .operand = 1 },
    };
    var source = try fixture(&.{}, &.{ .i32, .i32 }, &code);
    defer source.deinit(a);
    try replacement(a, &source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, replacement, .{@as(*const ir.Function, &source)});
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .i32, .i32 }, source.locals.items);
}
test "scoped transport removes identities created by final slot reuse" {
    var source = try fixture(&.{}, &.{ .i32, .i32 }, &.{
        .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_set },
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },
    });
    defer source.deinit(a);
    var compacted = (try @import("wasm_local_compact.zig").run(a, &source)).?;
    defer compacted.deinit(a);
    try std.testing.expectEqual(compacted.instructions.items[2].operand, compacted.instructions.items[3].operand);
    var view = source;
    view.locals = compacted.locals;
    view.instructions = compacted.instructions;
    var output = (try run(a, &view)).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(ir.Instruction, &.{ .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_tee } }, output.instructions.items);
    try std.testing.expectEqual(@as(usize, 5), source.instructions.items.len);
    try std.testing.expectEqual(@as(usize, 5), compacted.instructions.items.len);
}
test "scoped transport preserves parameters typed zeros and nested control boundaries" {
    var parameters = [_]ir.ValueType{.i32};
    var source = try fixture(&parameters, &.{ .f32, .v128, .externref, .i32 }, &.{
        .{ .op = .local_get },                        .{ .op = .local_set },
        .{ .op = .block, .operand = 0x40 },           .{ .op = .loop, .operand = 0x40 },
        .{ .op = .local_get, .operand = 1 },          .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 2 },          .{ .op = .local_set, .operand = 2 },
        .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },          .{ .op = .drop },
        .{ .op = .i32_const },                        .{ .op = .i32x4_splat },
        .{ .op = .local_set, .operand = 2 },          .{ .op = .local_get, .operand = 2 },
        .{ .op = .drop },                             .{ .op = .host_ref_null },
        .{ .op = .local_set, .operand = 3 },          .{ .op = .local_get, .operand = 3 },
        .{ .op = .drop },                             .{ .op = .local_get, .operand = 4 },
        .{ .op = .drop },                             .{ .op = .local_get, .operand = 1 },
        .{ .op = .local_set, .operand = 1 },          .{ .op = .end },
        .{ .op = .end },                              .{ .op = .local_get },
    });
    defer source.deinit(a);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(ir.ValueType, source.locals.items, output.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .block, .operand = 0x40 },           .{ .op = .loop, .operand = 0x40 },
        .{ .op = .f32_const, .operand = 0x80000000 }, .{ .op = .local_tee, .operand = 1 },
        .{ .op = .drop },                             .{ .op = .i32_const },
        .{ .op = .i32x4_splat },                      .{ .op = .local_tee, .operand = 2 },
        .{ .op = .drop },                             .{ .op = .host_ref_null },
        .{ .op = .local_tee, .operand = 3 },          .{ .op = .drop },
        .{ .op = .local_get, .operand = 4 },          .{ .op = .drop },
        .{ .op = .end },                              .{ .op = .end },
        .{ .op = .local_get },
    }, output.instructions.items);
}
test "scoped transport conserves packed flags declines hidden operands and allocates nothing unchanged" {
    var source = try fixture(&.{}, &.{.i32}, &.{
        .{ .op = .local_get }, .{ .op = .local_set }, .{ .op = .nop },
    });
    defer source.deinit(a);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .local_get, .operand = 1 } }) |invalid| {
        source.instructions.items[2] = invalid;
        try std.testing.expect((try run(failing.allocator(), &source)) == null);
    }
    source.instructions.items[2] = .{ .op = .i32_const };
    for (0..2) |which| {
        for ([_]ir.Instruction{ .{ .op = .local_get, .table_reference = true }, .{ .op = .local_get, .table_kind = .callable }, .{ .op = .local_get, .table_kind = .demand } }) |flagged| {
            source.instructions.items[0] = .{ .op = .local_get };
            source.instructions.items[1] = .{ .op = .local_set };
            source.instructions.items[which] = flagged;
            if (which == 1) source.instructions.items[which].op = .local_set;
            try std.testing.expect((try run(failing.allocator(), &source)) == null);
        }
    }
    source.instructions.items[0] = .{ .op = .local_get };
    source.instructions.items[1] = .{ .op = .drop };
    source.instructions.items[2] = .{ .op = .local_get };
    try std.testing.expect((try run(failing.allocator(), &source)) == null);
    // Metadata on untouched instructions is copied bit for bit next to a clean pair.
    source.instructions.items[0] = .{ .op = .i32_const, .operand = 9, .table_reference = true, .table_kind = .callable, .origin = 71 };
    source.instructions.items[1] = .{ .op = .local_get };
    source.instructions.items[2] = .{ .op = .local_set };
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(source.instructions.items[0], output.instructions.items[0]);
    try std.testing.expectEqual(@as(usize, 1), output.instructions.items.len);
}
fn pipelineReplacement(allocator: A, module: *const wasm.Module) !void {
    var pipeline = try @import("runtime_pipeline.zig").Session.init(allocator, module);
    defer pipeline.deinit();
    var output = (try pipeline.optimize(&module.functions.items[0])).?;
    defer output.deinit(allocator);
    try std.testing.expectEqualSlices(ir.Instruction, &.{ .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_tee } }, output.instructions.items);
}
test "scoped transport pipeline preserves source coordinates and final body identity in both tiers through OOM" {
    var module = wasm.Module.init(a);
    defer module.deinit();
    module.memory_model = .data_stacks;
    const id = try module.addFunction(&.{}, .i32);
    const code = [_]ir.Instruction{
        .{ .op = .i32_const, .operand = 7 }, .{ .op = .local_set },
        .{ .op = .local_get },               .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },
    };
    try module.functions.items[id].locals.appendSlice(a, &.{ .i32, .i32 });
    try module.emitSlice(id, &code);
    const site: wasm.Module.SemanticSite = .{ .function = id, .place = 4, .unit = 1, .node = 2, .root = 3, .mappings = 0, .rows = 0, .kind = .call };
    const origin: wasm.Module.TableOrigin = .{ .target = id, .kind = .callable, .function = id, .place = 4 };
    try module.semantic_sites.append(a, site);
    try module.table_origins.append(a, origin);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, pipelineReplacement, .{@as(*const wasm.Module, &module)});
    for ([_]@import("../compilation_tier.zig").Tier{ .development, .optimized }) |tier| {
        var pipeline = try @import("runtime_pipeline.zig").Session.init(a, &module);
        defer pipeline.deinit();
        pipeline.tier = tier;
        var output = (try pipeline.optimize(&module.functions.items[id])).?;
        defer output.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), output.locals.items.len);
        try std.testing.expectEqual(@as(usize, 2), output.instructions.items.len);
        // Assembly captures the actual final prepared body, not source coordinates.
        var capture: @import("optimized_bodies.zig").Capture = .{ .allocator = a };
        defer capture.deinit();
        const encoded = try module.assembleWithOptions(.{ .tier = tier, .current = &capture });
        defer a.free(encoded);
        try std.testing.expect(encoded.len > 8);
        try std.testing.expectEqualSlices(ir.Instruction, output.instructions.items, capture.entries.items[id].output.?.instructions.items);
        try std.testing.expectEqualSlices(ir.Instruction, &code, module.functions.items[id].instructions.items);
        try std.testing.expectEqualSlices(ir.ValueType, &.{ .i32, .i32 }, module.functions.items[id].locals.items);
        try std.testing.expectEqualDeep(site, module.semantic_sites.items[0]);
        try std.testing.expectEqualDeep(origin, module.table_origins.items[0]);
    }
}

test "scoped final transport strips neutral reservation nops without moving source coordinates" {
    var source: ir.Function = .{ .parameters = &.{}, .result = .none, .signature = 0 };
    defer source.deinit(a);
    try source.locals.append(a, .i32);
    const instructions = [_]ir.Instruction{
        .{ .op = .local_set, .origin = 31 },
        .{ .op = .nop, .origin = 419 },
        .{ .op = .local_get, .origin = 51 },
        .{ .op = .nop, .table_reference = true },
        .{ .op = .nop, .table_kind = .callable },
    };
    try source.instructions.appendSlice(a, &instructions);
    var output = (try run(a, &source)).?;
    defer output.deinit(a);
    try std.testing.expectEqual(@as(usize, 3), output.instructions.items.len);
    try std.testing.expectEqual(ir.Op.local_tee, output.instructions.items[0].op);
    try std.testing.expectEqual(@as(u21, 31), output.instructions.items[0].origin);
    try std.testing.expectEqual(instructions[3], output.instructions.items[1]);
    try std.testing.expectEqual(instructions[4], output.instructions.items[2]);
    try std.testing.expectEqualSlices(ir.Instruction, &instructions, source.instructions.items);
}
