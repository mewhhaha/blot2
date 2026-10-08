//! Expose small straight-line allocation producers to scalar replacement.
//! This consumes the complete direct callee body, already part of optimized
//! body reuse identity. No source names or collection-specific calls participate.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const A = std.mem.Allocator;

fn admitted(module: *const wasm.Module, body: *const ir.Function) bool {
    const arena = module.arena orelse return false;
    if (body.result != .i32 or body.instructions.items.len > 96 or body.instructions.items.len == 0) return false;
    if (body.parameters.len > 64 or body.locals.items.len > 64 - body.parameters.len) return false;
    const count = body.parameters.len + body.locals.items.len;
    var defined: [64]bool = @splat(false);
    @memset(defined[0..body.parameters.len], true);
    var allocations: usize = 0;
    for (body.instructions.items, 0..) |inst, i| switch (inst.op) {
        .local_get => if (inst.operand >= count or !defined[inst.operand]) {
            // A fresh call zeroes its locals. Do not reuse a loop's old value.
            return false;
        },
        .local_set, .local_tee => {
            if (inst.operand >= count) return false;
            defined[inst.operand] = true;
        },
        .call => {
            if (!arena.isAllocation(inst.operand) or i == 0) return false;
            const size = body.instructions.items[i - 1];
            if (size.op != .i32_const or size.operand == 0 or size.operand > 64 or size.operand % 4 != 0) return false;
            allocations += 1;
        },
        .i32_const, .f32_const, .i32_load, .f32_load, .i32_store, .f32_store, .drop => {},
        else => {
            // Scalar arithmetic/conversions can trap, but execute at exactly
            // the original call position. Control, host and global operations
            // stay in their original functions.
            const contract = ir.contract(module, body, inst);
            if (contract.effect != .pure) return false;
        },
    };
    return allocations == 1;
}

pub fn run(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?ir.Body {
    if (module.arena == null or source.instructions.items.len > 4096) return null;
    var selected = false;
    for (source.instructions.items) |inst| if (inst.op == .call and admitted(module, &module.functions.items[inst.operand])) {
        selected = true;
        break;
    };
    if (!selected) return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    for (source.instructions.items) |inst| {
        if (inst.op == .call and result.instructions.items.len < 4096 and admitted(module, &module.functions.items[inst.operand])) {
            const callee = &module.functions.items[inst.operand];
            const base: u32 = @intCast(source.parameters.len + result.locals.items.len);
            try result.locals.appendSlice(a, callee.parameters);
            try result.locals.appendSlice(a, callee.locals.items);
            var parameter = callee.parameters.len;
            while (parameter != 0) {
                parameter -= 1;
                try result.instructions.append(a, .{ .op = .local_set, .operand = base + @as(u32, @intCast(parameter)) });
            }
            for (callee.instructions.items) |instruction| {
                var copy = instruction;
                if (copy.op == .local_get or copy.op == .local_set or copy.op == .local_tee) copy.operand += base;
                try result.instructions.append(a, copy);
            }
        } else try result.instructions.append(a, inst);
    }
    return result;
}

fn ownership(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addFunction(&.{.i32}, .i32);
    const row = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },   .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = row },
        .{ .op = .local_get, .operand = row }, .{ .op = .local_get, .operand = 0 },         .{ .op = .i32_store },
        .{ .op = .local_get, .operand = row },
    });
    const consumer = try module.addFunction(&.{.i32}, .i32);
    const captured = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .local_get, .operand = 0 },        .{ .op = .call, .operand = producer }, .{ .op = .local_set, .operand = captured },
        .{ .op = .local_get, .operand = captured }, .{ .op = .i32_load },
    });
    const before = module.functions.items[consumer].instructions.items.len;
    var inline_body = (try run(a, &module, &module.functions.items[consumer])).?;
    defer inline_body.deinit(a);
    var view = module.functions.items[consumer];
    view.locals = inline_body.locals;
    view.instructions = inline_body.instructions;
    var scalar = (try @import("wasm_sroa.zig").run(a, &module, &view)).?;
    defer scalar.deinit(a);
    for (scalar.instructions.items) |inst| try std.testing.expect(inst.op != .call);
    try std.testing.expectEqual(before, module.functions.items[consumer].instructions.items.len);
    // Even a straight-line body must preserve fresh-call local initialization.
    module.functions.items[producer].instructions.items[0] = .{ .op = .local_get, .operand = row };
    try std.testing.expect((try run(a, &module, &module.functions.items[consumer])) == null);
}
test "allocation producer inlining preserves owners and fresh local initialization" {
    try ownership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}
