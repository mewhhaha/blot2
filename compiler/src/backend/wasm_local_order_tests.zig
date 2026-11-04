const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const run = @import("wasm_local_order.zig").run;
const A = std.mem.Allocator;
const a = std.testing.allocator;

fn fixture(parameters: []ir.ValueType, locals: []const ir.ValueType, code: []const ir.Instruction) !ir.Function {
    var result: ir.Function = .{ .parameters = parameters, .result = .none, .signature = 0 };
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, locals);
    try result.instructions.appendSlice(a, code);
    return result;
}
fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
fn execute(source: *const ir.Function, parameters: []const u128) ![7]u128 {
    const locals = try a.alloc(u128, source.parameters.len + source.locals.items.len);
    defer a.free(locals);
    @memset(locals, 0);
    @memcpy(locals[0..parameters.len], parameters);
    var flow = try @import("wasm_control_flow.zig").Graph.init(a, source.instructions.items);
    defer flow.deinit(a);
    try std.testing.expect(flow.valid);
    var stack: std.ArrayList(u128) = .empty;
    defer stack.deinit(a);
    var output: [7]u128 = @splat(0);
    var pc: usize = 0;
    var steps: usize = 0;
    while (pc < source.instructions.items.len) {
        steps += 1;
        try std.testing.expect(steps < 10_000);
        const inst = source.instructions.items[pc];
        var next = flow.nodes[pc].next[0];
        switch (inst.op) {
            .i32_const, .f32_const => try stack.append(a, inst.operand),
            .local_get => try stack.append(a, locals[inst.operand]),
            .local_set => locals[inst.operand] = stack.pop().?,
            .local_tee => locals[inst.operand] = stack.items[stack.items.len - 1],
            .global_set => output[inst.operand] = stack.pop().?,
            .drop => _ = stack.pop().?,
            .i32x4_splat => {
                const bits: u128 = @as(u32, @truncate(stack.pop().?));
                try stack.append(a, bits | (bits << 32) | (bits << 64) | (bits << 96));
            },
            .i32_add, .i32_sub => {
                const right: u32 = @truncate(stack.pop().?);
                const left: u32 = @truncate(stack.pop().?);
                var bits = left +% right;
                if (inst.op == .i32_sub) bits = left -% right;
                try stack.append(a, bits);
            },
            .i32_eqz => try stack.append(a, @intFromBool(stack.pop().? == 0)),
            .if_ => if (stack.pop().? == 0) {
                next = flow.nodes[pc].next[1];
            },
            .br_if => if (stack.pop().? == 0) {
                next = flow.nodes[pc].next[1];
            },
            .block, .loop, .else_, .end, .br => {},
            else => unreachable,
        }
        pc = next;
    }
    try std.testing.expectEqual(@as(usize, 0), stack.items.len);
    return output;
}
fn permutation(allocator: A, source: *const ir.Function) !void {
    var output = (try run(allocator, source)).?;
    defer output.deinit(allocator);
    try std.testing.expectEqual(source.locals.items.len, output.locals.items.len);
    try std.testing.expectEqual(source.instructions.items.len, output.instructions.items.len);
    var identities: [133]?u32 = @splat(null);
    var occupied: [133]bool = @splat(false);
    for (source.instructions.items, output.instructions.items) |before, after| {
        var restored = after;
        if (local(before.op)) {
            restored.operand = before.operand;
            if (before.operand < source.parameters.len) {
                try std.testing.expectEqual(before.operand, after.operand);
            } else {
                try std.testing.expect(after.operand >= source.parameters.len);
                try std.testing.expectEqual(source.locals.items[before.operand - source.parameters.len], output.locals.items[after.operand - source.parameters.len]);
                if (identities[before.operand]) |known| {
                    try std.testing.expectEqual(known, after.operand);
                } else {
                    try std.testing.expect(!occupied[after.operand]);
                    identities[before.operand] = after.operand;
                    occupied[after.operand] = true;
                }
            }
        }
        try std.testing.expectEqual(@as(u64, @bitCast(before)), @as(u64, @bitCast(restored)));
    }
    try std.testing.expect(identities[129].? < 128);
    var view = source.*;
    view.locals = output.locals;
    view.instructions = output.instructions;
    for ([_]u128{ 0, 1, 7, 100, 0 }) |input| {
        const parameters = [_]u128{ input, 0xdeadbeef };
        const before = try execute(source, &parameters);
        try std.testing.expectEqualDeep(before, try execute(&view, &parameters));
        try std.testing.expectEqual(@as(u128, 0), before[0]);
        var float_bits: u128 = 0x80000000;
        if (input != 0) float_bits = 0x7fc00123;
        try std.testing.expectEqual(float_bits, before[1]);
        try std.testing.expectEqual(@as(u128, 0x80000001800000018000000180000001), before[2]);
        try std.testing.expectEqual(@as(u128, 0xdeadbeef), before[3]);
        try std.testing.expectEqual(5 + input * (input + 1) / 2, before[4]);
        try std.testing.expectEqual(input, before[5]);
        try std.testing.expectEqual(@as(u128, 2), before[6]);
    }
    try std.testing.expect((try run(allocator, &view)) == null);
}
test "local ordering preserves typed bits zero reads parameters control and metadata through OOM" {
    var parameters = [_]ir.ValueType{ .i32, .externref };
    var locals: [131]ir.ValueType = @splat(.i32);
    locals[128] = .f32;
    locals[129] = .v128;
    locals[130] = .externref;
    const code = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 127, .origin = 31 }, .{ .op = .global_set },
        .{ .op = .local_get },                               .{ .op = .local_set, .operand = 129 },
        .{ .op = .f32_const, .operand = 0x80000000 },        .{ .op = .local_set, .operand = 130 },
        .{ .op = .local_get },                               .{ .op = .if_ },
        .{ .op = .f32_const, .operand = 0x7fc00123 },        .{ .op = .local_set, .operand = 130 },
        .{ .op = .end },                                     .{ .op = .local_get, .operand = 130 },
        .{ .op = .global_set, .operand = 1 },                .{ .op = .i32_const, .operand = 0x80000001 },
        .{ .op = .i32x4_splat },                             .{ .op = .local_set, .operand = 131 },
        .{ .op = .local_get, .operand = 131 },               .{ .op = .global_set, .operand = 2 },
        .{ .op = .local_get, .operand = 1 },                 .{ .op = .local_set, .operand = 132 },
        .{ .op = .local_get, .operand = 132 },               .{ .op = .global_set, .operand = 3 },
        .{ .op = .i32_const, .operand = 5 },                 .{ .op = .local_tee, .operand = 128, .origin = 912 },
        .{ .op = .drop },                                    .{ .op = .block },
        .{ .op = .loop },                                    .{ .op = .local_get, .operand = 129 },
        .{ .op = .i32_eqz },                                 .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = 128 },               .{ .op = .local_get, .operand = 129 },
        .{ .op = .i32_add },                                 .{ .op = .local_set, .operand = 128 },
        .{ .op = .local_get, .operand = 129 },               .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_sub },                                 .{ .op = .local_set, .operand = 129 },
        .{ .op = .br },                                      .{ .op = .end },
        .{ .op = .end },                                     .{ .op = .local_get, .operand = 128 },
        .{ .op = .global_set, .operand = 4 },                .{ .op = .local_get },
        .{ .op = .global_set, .operand = 5 },                .{ .op = .i32_const, .operand = 2 },
        .{ .op = .local_set },                               .{ .op = .local_get },
        .{ .op = .global_set, .operand = 6 },                .{ .op = .i32_const, .operand = 17, .table_reference = true, .table_kind = .callable, .origin = 19 },
        .{ .op = .drop },
    };
    var source = try fixture(&parameters, &locals, &code);
    defer source.deinit(a);
    try permutation(a, &source);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, permutation, .{@as(*const ir.Function, &source)});
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
    try std.testing.expectEqualSlices(ir.ValueType, &locals, source.locals.items);
}

test "local ordering crosses both ULEB thresholds with deterministic equal weight ties" {
    for ([_]usize{ 127, 16_383 }) |count| {
        const parameters = try a.alloc(ir.ValueType, count);
        defer a.free(parameters);
        @memset(parameters, .i32);
        const cold: u32 = @intCast(count);
        const first = cold + 1;
        const second = cold + 2;
        var source = try fixture(parameters, &.{ .i32, .i32, .i32 }, &.{
            .{ .op = .local_get, .operand = cold },   .{ .op = .drop },
            .{ .op = .local_get, .operand = first },  .{ .op = .drop },
            .{ .op = .local_get, .operand = second }, .{ .op = .drop },
            .{ .op = .local_get, .operand = first },  .{ .op = .drop },
            .{ .op = .local_get, .operand = second }, .{ .op = .drop },
        });
        defer source.deinit(a);
        var output = (try run(a, &source)).?;
        defer output.deinit(a);
        try std.testing.expectEqual(second, output.instructions.items[0].operand);
        try std.testing.expectEqual(cold, output.instructions.items[2].operand);
        try std.testing.expectEqual(first, output.instructions.items[4].operand);
    }
}

test "local ordering declines declaration growth hidden identities and uniform width without mutation" {
    var parameters: [127]ir.ValueType = @splat(.i32);
    var source = try fixture(&parameters, &.{ .i32, .f32, .f32 }, &.{ .{ .op = .local_get, .operand = 129 }, .{ .op = .drop } });
    defer source.deinit(a);
    // Saving one operand byte would add two declaration bytes.
    try std.testing.expect((try run(a, &source)) == null);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .wide_layouts }, .{ .op = .local_get, .operand = 130 } }) |invalid| {
        source.instructions.items[1] = invalid;
        try std.testing.expect((try run(failing.allocator(), &source)) == null);
        try std.testing.expectEqual(invalid, source.instructions.items[1]);
    }
    source.parameters = &.{};
    source.instructions.items[0] = .{ .op = .local_get, .operand = 2 };
    source.instructions.items[1] = .{ .op = .drop };
    try std.testing.expect((try run(failing.allocator(), &source)) == null);
}

test "local ordering reaches both pipeline tiers and retains immutable source coordinates" {
    for ([_]@import("../compilation_tier.zig").Tier{ .development, .optimized }) |tier| {
        var module = wasm.Module.init(a);
        defer module.deinit();
        module.memory_model = .data_stacks;
        const id = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
        const source = &module.functions.items[id];
        try source.locals.appendNTimes(a, .i32, 140);
        for (0..32) |_| try source.instructions.appendSlice(a, &.{ .{ .op = .local_get, .operand = 140, .origin = 71 }, .{ .op = .drop } });
        try source.instructions.append(a, .{ .op = .local_get });
        const site: wasm.Module.SemanticSite = .{ .function = id, .place = 0, .unit = 1, .node = 2, .root = 3, .mappings = 0, .rows = 0, .kind = .call };
        try module.semantic_sites.append(a, site);
        var pipeline = try @import("runtime_pipeline.zig").Session.init(a, &module);
        defer pipeline.deinit();
        pipeline.tier = tier;
        var output = (try pipeline.optimize(source)).?;
        defer output.deinit(a);
        try std.testing.expectEqual(@as(u32, 1), output.instructions.items[0].operand);
        try std.testing.expectEqual(@as(u32, 0), output.instructions.items[output.instructions.items.len - 1].operand);
        try std.testing.expectEqual(@as(u32, 140), source.instructions.items[0].operand);
        try std.testing.expectEqualDeep(site, module.semantic_sites.items[0]);
    }
}
