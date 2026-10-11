//! Expose small straight-line allocation producers to scalar replacement.
//! This consumes the complete direct callee body, already part of optimized
//! body reuse identity. No source names or collection-specific calls participate.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const A = std.mem.Allocator;

fn admitted(module: *const wasm.Module, body: *const ir.Function) bool {
    const arena = module.arena orelse return false;
    if (body.result != .i32 or body.codeLength() > 96 or body.codeLength() == 0) return false;
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
        .ownership => {
            const scope: ir.Ownership = @bitCast(inst.operand);
            if (scope.kind != .scope) continue;
            switch (scope.chunk) {
                2, 5, 6 => if (scope.roles >= count or !defined[scope.roles]) return false,
                3 => {
                    if (scope.roles >= count) return false;
                    defined[scope.roles] = true;
                },
                4 => {
                    const slot = scope.roles & 8191;
                    const value = scope.roles >> 13;
                    if (slot >= count or value >= count or !defined[slot] or !defined[value]) return false;
                },
                else => {},
            }
        },
        .call => {
            if (!arena.isAllocation(inst.operand) or i == 0) return false;
            const size = body.instructions.items[i - 1];
            if (size.table_reference or size.op != .i32_const or size.operand == 0 or size.operand > 64 or size.operand % 4 != 0) return false;
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
    if (module.arena == null or ir.codeLength(source.instructions.items) > 4096) return null;
    var selected = false;
    for (source.instructions.items) |inst| if (inst.op == .call and admitted(module, &module.functions.items[inst.operand])) {
        selected = true;
        break;
    };
    if (!selected) return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    // Ownership annotations are copied but are not code for this budget.
    var code: usize = 0;
    for (source.instructions.items) |inst| {
        if (inst.op == .call and code < 4096 and admitted(module, &module.functions.items[inst.operand]) and source.parameters.len + result.locals.items.len + module.functions.items[inst.operand].parameters.len + module.functions.items[inst.operand].locals.items.len < 8192) {
            const callee = &module.functions.items[inst.operand];
            const base: u32 = @intCast(source.parameters.len + result.locals.items.len);
            try result.locals.appendSlice(a, callee.parameters);
            try result.locals.appendSlice(a, callee.locals.items);
            var parameter = callee.parameters.len;
            while (parameter != 0) {
                parameter -= 1;
                try result.instructions.append(a, .{ .op = .local_set, .operand = base + @as(u32, @intCast(parameter)) });
            }
            code += callee.parameters.len + callee.codeLength();
            for (callee.instructions.items) |instruction| {
                var copy = instruction;
                if (copy.op == .local_get or copy.op == .local_set or copy.op == .local_tee) copy.operand += base;
                if (copy.op == .ownership) copy.operand = @bitCast(@as(ir.Ownership, @bitCast(copy.operand)).relocated(base));
                try result.instructions.append(a, copy);
            }
        } else {
            code += @intFromBool(inst.op != .ownership);
            try result.instructions.append(a, inst);
        }
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

fn scopedProducer(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const producer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const row = try module.addLocal(producer, .i32);
    const slot = try module.addLocal(producer, .i32);
    try module.emitSlice(producer, &.{
        .{ .op = .i32_const, .operand = 4 },   .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = row },
        .{ .op = .local_get, .operand = row }, .{ .op = .local_get },                       .{ .op = .i32_store },
    });
    const scopes = [_]ir.Ownership{
        .{ .kind = .scope, .chunk = 3, .roles = @intCast(slot) },
        .{ .kind = .scope, .chunk = 4, .roles = @intCast(slot + row * 8192) },
        .{ .kind = .scope, .chunk = 5, .roles = @intCast(row) },
    };
    for (scopes) |scope| try module.emit(producer, .{ .op = .ownership, .operand = @bitCast(scope) });
    try module.emitSlice(producer, &.{ .{ .op = .local_get, .operand = row }, .{ .op = .i32_load } });
    const consumer = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    const untouched = try module.addLocal(consumer, .i32);
    try module.emitSlice(consumer, &.{
        .{ .op = .i32_const, .operand = 42 }, .{ .op = .local_set, .operand = untouched },
        .{ .op = .local_get },                .{ .op = .call, .operand = producer },
        .{ .op = .drop },                     .{ .op = .local_get, .operand = untouched },
    });
    var body = (try run(a, &module, &module.functions.items[consumer])).?;
    defer body.deinit(a);
    const base: u32 = @intCast(module.functions.items[consumer].parameters.len + module.functions.items[consumer].locals.items.len);
    var scope_index: usize = 0;
    for (body.instructions.items) |inst| if (inst.op == .ownership) {
        try std.testing.expectEqual(scopes[scope_index].relocated(base), @as(ir.Ownership, @bitCast(inst.operand)));
        scope_index += 1;
    };
    try std.testing.expectEqual(scopes.len, scope_index);
    var view = module.functions.items[consumer];
    view.locals = body.locals;
    view.instructions = body.instructions;
    // Publication keeps a heap identity; removing its allocation would leave
    // the scope reading an uninitialized pointer local.
    try std.testing.expect((try @import("wasm_sroa.zig").run(a, &module, &view)) == null);
    var plan = try @import("wasm_lifetimes.zig").analyze(a, &module, &view);
    defer plan.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), plan.releases.items.len);
    try std.testing.expectEqual(@as(ir.Ownership, .{ .kind = .scope, .chunk = 2, .roles = @intCast(row + base) }), (ir.Ownership{ .kind = .scope, .chunk = 2, .roles = @intCast(row) }).relocated(base));
}
test "inlined scope locals preserve caller locals and heap identities through OOM" {
    try scopedProducer(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, scopedProducer, .{});
}
