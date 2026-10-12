//! Vectorize independent numeric stores in counted construction loops. This
//! pass consumes symbolic instructions and follows bounded, pure call bodies.
//! It recognizes no source declarations. Private numeric locals must be
//! defined before each lane reads them and have no use outside the kernel.
//! Loads, traps, effects, conditional branches and reductions stay scalar.
const std = @import("std");
const w = @import("wasm.zig");
const ops = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const Id = u16;
const none = std.math.maxInt(Id);
const Node = struct { op: w.Op, operand: u32 = 0, left: Id = none, right: Id = none, machine: w.ValueType = .i32 };
const Block = struct { base: usize, result: ?w.ValueType };
const Plan = struct {
    nodes: [256]Node = undefined,
    len: usize = 0,
    budget: usize = 1024,
    index: u32,
    fn add(self: *Plan, node: Node) ?Id {
        if (self.len == self.nodes.len) return null;
        const id: Id = @intCast(self.len);
        self.nodes[self.len] = node;
        self.len += 1;
        return id;
    }
    fn parse(self: *Plan, module: *const w.Module, instructions: []const w.Instruction, initial: []const Id, depth: usize) ?Id {
        if (depth > 6 or initial.len > 256) return null;
        var locals: [256]Id = @splat(none);
        @memcpy(locals[0..initial.len], initial);
        var stack: [256]Id = undefined;
        var len: usize = 0;
        var blocks: [16]Block = undefined;
        var block_count: usize = 0;
        var at: usize = 0;
        while (at < instructions.len) : (at += 1) {
            const inst = instructions[at];
            // Ownership annotations are not code and cost no budget.
            if (inst.op == .ownership) continue;
            if (inst.table_reference or self.budget == 0) return null;
            self.budget -= 1;
            const result: ?Id = switch (inst.op) {
                .block => blk: {
                    if (block_count == blocks.len) return null;
                    const machine: ?w.ValueType = switch (inst.operand) {
                        0 => null,
                        @backingInt(w.ValueType.i32) => .i32,
                        @backingInt(w.ValueType.f32) => .f32,
                        else => return null,
                    };
                    blocks[block_count] = .{ .base = len, .result = machine };
                    block_count += 1;
                    break :blk null;
                },
                .end => blk: {
                    if (block_count == 0) return null;
                    block_count -= 1;
                    const block = blocks[block_count];
                    if (len != block.base + @intFromBool(block.result != null)) return null;
                    if (block.result) |machine| if (self.nodes[stack[len - 1]].machine != machine) return null;
                    break :blk null;
                },
                .br => blk: {
                    // Only a lexical block inside this parsed kernel can be
                    // exited. An enclosing loop/function branch stays scalar.
                    if (inst.operand >= block_count) return null;
                    const target = block_count - 1 - inst.operand;
                    const block = blocks[target];
                    if (block.result) |machine| {
                        if (len <= block.base or self.nodes[stack[len - 1]].machine != machine) return null;
                        stack[block.base] = stack[len - 1];
                    }
                    len = block.base + @intFromBool(block.result != null);
                    at = (self.exitBlock(instructions, at + 1, inst.operand) orelse return null) - 1;
                    block_count = target + 1;
                    break :blk null;
                },
                .local_get => if (inst.operand < initial.len and locals[inst.operand] != none) locals[inst.operand] else return null,
                .local_set, .local_tee => blk: {
                    if (len == 0 or inst.operand >= initial.len) return null;
                    locals[inst.operand] = stack[len - 1];
                    if (inst.op == .local_set) len -= 1;
                    break :blk null;
                },
                .i32_const, .f32_const => self.add(.{ .op = inst.op, .operand = inst.operand, .machine = if (inst.op == .f32_const) .f32 else .i32 }) orelse return null,
                .nop => null,
                .drop => blk: {
                    if (len == 0) return null;
                    len -= 1;
                    break :blk null;
                },
                // A known helper's unconditional scalar return discards only
                // unreachable code. Caller control remains outside the plan.
                .return_ => return if (depth != 0 and len == 1) stack[0] else null,
                .call => blk: {
                    if (inst.operand >= module.functions.items.len) return null;
                    const target = module.functions.items[inst.operand];
                    const slots = std.math.add(usize, target.parameters.len, target.locals.items.len) catch return null;
                    if (target.parameters.len > len or slots > 256 or (target.result != .i32 and target.result != .f32)) return null;
                    var args: [256]Id = @splat(none);
                    @memcpy(args[0..target.parameters.len], stack[len - target.parameters.len ..][0..target.parameters.len]);
                    for (target.locals.items, target.parameters.len..) |ty, i| {
                        if (ty != .i32 and ty != .f32) return null;
                        args[i] = self.add(.{ .op = if (ty == .f32) .f32_const else .i32_const, .machine = ty }) orelse return null;
                    }
                    len -= target.parameters.len;
                    break :blk self.parse(module, target.instructions.items, args[0..slots], depth + 1) orelse return null;
                },
                else => blk: {
                    _ = ops.lift(inst.op) orelse return null;
                    const signature = ops.fixed(inst.op);
                    if (signature.effect != .pure or signature.may_trap) return null;
                    const arity = signature.arity;
                    const unary = arity == 1;
                    if (len < arity) return null;
                    const left = stack[len - arity];
                    const right = if (unary) none else stack[len - 1];
                    len -= arity;
                    for (stack[len .. len + arity], signature.inputs[0..arity]) |operand, expected| {
                        if (self.nodes[operand].machine != expected) return null;
                    }
                    const machine = signature.result;
                    break :blk self.add(.{ .op = inst.op, .left = left, .right = right, .machine = machine }) orelse return null;
                },
            };
            if (result) |value| {
                if (len == stack.len) return null;
                stack[len] = value;
                len += 1;
            }
        }
        return if (block_count == 0 and len == 1) stack[0] else null;
    }
    fn exitBlock(self: *Plan, instructions: []const w.Instruction, start: usize, labels: usize) ?usize {
        var nested: usize = 0;
        var remaining = labels;
        for (instructions[start..], start..) |inst, at| {
            if (self.budget == 0) return null;
            self.budget -= 1;
            switch (inst.op) {
                .block, .loop, .if_ => nested += 1,
                .end => {
                    if (nested != 0) {
                        nested -= 1;
                    } else if (remaining != 0) {
                        remaining -= 1;
                    } else return at;
                },
                else => {},
            }
        }
        return null;
    }
};
pub const Output = ops.Body;
fn expression(self: *Output, a: A, plan: *const Plan, id: Id, ready: *[256]?u32, parameters: usize) A.Error!u32 {
    if (ready[id]) |local| return local;
    const node = plan.nodes[id];
    const left = if (node.left == none) null else try expression(self, a, plan, node.left, ready, parameters);
    const right = if (node.right == none) null else try expression(self, a, plan, node.right, ready, parameters);
    switch (node.op) {
        .local_get, .i32_const, .f32_const => {
            try self.emit(a, node.op, node.operand);
            try self.emit(a, if (node.machine == .f32) .f32x4_splat else .i32x4_splat, 0);
            if (node.op == .local_get and node.operand == plan.index) {
                // Consecutive indices; no integer overflow is possible in
                // a four-element run admitted by count-index >= 4.
                try self.emit(a, .i32_const, 0);
                try self.emit(a, .i32x4_splat, 0);
                for (1..4) |lane| {
                    try self.emit(a, .i32_const, @intCast(lane));
                    try self.emit(a, .i32x4_replace_lane, @intCast(lane));
                }
                try self.emit(a, .i32x4_add, 0);
            }
        },
        else => {
            try self.emit(a, .local_get, left.?);
            if (right) |local| try self.emit(a, .local_get, local);
            try self.emit(a, ops.lift(node.op).?, 0);
        },
    }
    const local: u32 = @intCast(parameters + self.locals.items.len);
    try self.locals.append(a, .v128);
    try self.emit(a, .local_set, local);
    ready[id] = local;
    return local;
}

fn is(inst: w.Instruction, op: w.Op, operand: u32) bool {
    return inst.op == op and inst.operand == operand;
}
fn privateLocals(function: *const w.Function, start: usize, end: usize, slots: usize) bool {
    const source = function.instructions.items;
    var written: std.bit_set.Static(128) = .empty;
    for (source[start..end]) |inst| if (inst.op == .local_set or inst.op == .local_tee) {
        if (inst.operand < function.parameters.len or inst.operand >= slots) return false;
        written.set(inst.operand);
    };
    if (written.count() == 0) return true;
    if (source.len > 4096) return false;
    for (source, 0..) |inst, at| {
        if (at >= start and at < end) continue;
        if ((inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) and inst.operand < slots and written.isSet(inst.operand)) return false;
    }
    var defined: std.bit_set.Static(128) = .empty;
    for (source[start..end]) |inst| {
        // An unwritten incoming local is a loop-carried value, even when
        // nobody reads it after the loop. Such lanes are not independent.
        if (inst.op == .local_get and inst.operand < slots and written.isSet(inst.operand) and !defined.isSet(inst.operand)) return false;
        if (inst.op == .local_set or inst.op == .local_tee) defined.set(inst.operand);
    }
    return true;
}
pub fn run(a: A, module: *const w.Module, function: *const w.Function) A.Error!?Output {
    const source = function.instructions.items;
    var out: Output = .{};
    errdefer out.deinit(a);
    var changed = false;
    var copied: usize = 0;
    var at: usize = 5;
    while (at + 18 < source.len) : (at += 1) {
        if (!is(source[at], .block, 0) or !is(source[at + 1], .loop, 0) or source[at + 2].op != .local_get or source[at + 3].op != .local_get or source[at + 4].op != .i32_ge_u or !is(source[at + 5], .br_if, 1)) continue;
        const index = source[at + 2].operand;
        const count = source[at + 3].operand;
        if (source[at + 6].op != .local_get) continue;
        const target = source[at + 6].operand;
        if (!is(source[at - 5], .local_get, target) or !is(source[at - 4], .local_get, count) or !is(source[at - 3], .i32_store, 0) or !is(source[at - 2], .i32_const, 0) or !is(source[at - 1], .local_set, index)) continue;
        if (!is(source[at + 7], .local_get, index) or !is(source[at + 8], .i32_const, 4) or source[at + 9].op != .i32_mul or source[at + 10].op != .i32_add) continue;
        var end = at + 11;
        while (end < @min(source.len, at + 64) and source[end].op != .i32_store and source[end].op != .f32_store) : (end += 1) {}
        if (end + 7 >= source.len or source[end].operand != 4 or (source[end].op != .i32_store and source[end].op != .f32_store)) continue;
        if (!is(source[end + 1], .local_get, index) or !is(source[end + 2], .i32_const, 1) or source[end + 3].op != .i32_add or !is(source[end + 4], .local_set, index) or !is(source[end + 5], .br, 0) or source[end + 6].op != .end or source[end + 7].op != .end) continue;
        var plan: Plan = .{ .index = index };
        const local_count = std.math.add(usize, function.parameters.len, function.locals.items.len) catch continue;
        if (local_count > 128) continue;
        var initial: [128]Id = undefined;
        var allowed = true;
        for (initial[0..local_count], 0..) |*value, i| {
            const machine = if (i < function.parameters.len) function.parameters[i] else function.locals.items[i - function.parameters.len];
            if (machine != .i32 and machine != .f32) {
                allowed = false;
                break;
            }
            value.* = plan.add(.{ .op = .local_get, .operand = @intCast(i), .machine = machine }).?;
        }
        if (!allowed) continue;
        if (!privateLocals(function, at + 11, end, local_count)) continue;
        const result = plan.parse(module, source[at + 11 .. end], initial[0..local_count], 0) orelse continue;
        const machine: w.ValueType = if (source[end].op == .f32_store) .f32 else .i32;
        if (plan.nodes[result].machine != machine) continue;
        if (!changed) try out.locals.appendSlice(a, function.locals.items);
        changed = true;
        try out.instructions.appendSlice(a, source[copied..at]);
        try out.emit(a, .block, 0);
        try out.emit(a, .loop, 0);
        try out.emit(a, .local_get, count);
        try out.emit(a, .local_get, index);
        try out.emit(a, .i32_sub, 0);
        try out.emit(a, .i32_const, 4);
        try out.emit(a, .i32_lt_u, 0);
        try out.emit(a, .br_if, 1);
        var ready: [256]?u32 = @splat(null);
        const vector = try expression(&out, a, &plan, result, &ready, function.parameters.len);
        try out.instructions.appendSlice(a, source[at + 6 .. at + 11]);
        try out.emit(a, .local_get, vector);
        try out.emit(a, .v128_store, 4);
        try out.emit(a, .local_get, index);
        try out.emit(a, .i32_const, 4);
        try out.emit(a, .i32_add, 0);
        try out.emit(a, .local_set, index);
        try out.emit(a, .br, 0);
        try out.emit(a, .end, 0);
        try out.emit(a, .end, 0);
        // Preserve the scalar loop verbatim for the zero-to-three tail lanes.
        try out.instructions.appendSlice(a, source[at .. end + 8]);
        copied = end + 8;
        at = copied - 1;
    }
    if (!changed) return null;
    try out.instructions.appendSlice(a, source[copied..]);
    return out;
}

fn fixture(module: *w.Module, kernel: []const w.Instruction) !u32 {
    const callback = try module.addFunction(&.{.i32}, .i32);
    try module.emitSlice(callback, kernel);
    const function = try module.addFunction(&.{ .i32, .i32 }, .i32);
    const index = try module.addLocal(function, .i32);
    try module.emitSlice(function, &.{
        .{ .op = .local_get, .operand = 0 },     .{ .op = .local_get, .operand = 1 },     .{ .op = .i32_store },
        .{ .op = .i32_const },                   .{ .op = .local_set, .operand = index }, .{ .op = .block },
        .{ .op = .loop },                        .{ .op = .local_get, .operand = index }, .{ .op = .local_get, .operand = 1 },
        .{ .op = .i32_ge_u },                    .{ .op = .br_if, .operand = 1 },         .{ .op = .local_get, .operand = 0 },
        .{ .op = .local_get, .operand = index }, .{ .op = .i32_const, .operand = 4 },     .{ .op = .i32_mul },
        .{ .op = .i32_add },                     .{ .op = .local_get, .operand = index }, .{ .op = .call, .operand = callback },
        .{ .op = .i32_store, .operand = 4 },     .{ .op = .local_get, .operand = index }, .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },                     .{ .op = .local_set, .operand = index }, .{ .op = .br },
        .{ .op = .end },                         .{ .op = .end },                         .{ .op = .local_get, .operand = 0 },
    });
    return function;
}
fn vectorizationOwnership(a: A) !void {
    var module = w.Module.init(a);
    defer module.deinit();
    const id = try fixture(&module, &.{ .{ .op = .block, .operand = @backingInt(w.ValueType.i32) }, .{ .op = .local_get }, .{ .op = .i32_const, .operand = 3 }, .{ .op = .i32_mul }, .{ .op = .br }, .{ .op = .unreachable_ }, .{ .op = .end }, .{ .op = .return_ } });
    const before = try a.dupe(w.Instruction, module.functions.items[id].instructions.items);
    defer a.free(before);
    var out = (try run(a, &module, &module.functions.items[id])).?;
    defer out.deinit(a);
    var stores: usize = 0;
    for (out.instructions.items) |inst| {
        if (inst.op == .v128_store) stores += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), stores);
    // Every scalar tail instruction and the retained source fragment survive.
    try std.testing.expectEqualSlices(w.Instruction, before[5..], out.instructions.items[out.instructions.items.len - (before.len - 5) ..]);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[id].instructions.items);
}
test "vectorization owns its assembly copy through allocation failures" {
    try vectorizationOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, vectorizationOwnership, .{});
}
test "vectorization declines memory reads, traps, unknown calls and enclosing local writes" {
    const a = std.testing.allocator;
    const kernels = [_][]const w.Instruction{
        &.{ .{ .op = .local_get }, .{ .op = .i32_load } },
        &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 2 }, .{ .op = .i32_div_u } },
        &.{ .{ .op = .local_get }, .{ .op = .call_import } },
        &.{ .{ .op = .local_get }, .{ .op = .global_set }, .{ .op = .i32_const } },
    };
    for (kernels) |kernel| {
        var module = w.Module.init(a);
        defer module.deinit();
        const id = try fixture(&module, kernel);
        try std.testing.expect(try run(a, &module, &module.functions.items[id]) == null);
    }
    var module = w.Module.init(a);
    defer module.deinit();
    const id = try fixture(&module, &.{.{ .op = .local_get }});
    // A local.tee can change a subsequent iteration even when the stored lane
    // still looks pure. It must not disappear in the vector prefix.
    module.functions.items[id].instructions.items[17] = .{ .op = .local_tee, .operand = 1 };
    try std.testing.expect(try run(a, &module, &module.functions.items[id]) == null);
}

fn replaceKernel(a: A, module: *w.Module, id: u32, kernel: []const w.Instruction) !void {
    const function = &module.functions.items[id];
    const before = try a.dupe(w.Instruction, function.instructions.items);
    defer a.free(before);
    var end: usize = 16;
    while (before[end].op != .i32_store and before[end].op != .f32_store) : (end += 1) {}
    function.instructions.clearRetainingCapacity();
    try function.instructions.appendSlice(a, before[0..16]);
    try function.instructions.appendSlice(a, kernel);
    try function.instructions.appendSlice(a, before[end..]);
}
test "vectorization proves private kernel definitions and rejects carried or externally read locals" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const id = try fixture(&module, &.{.{ .op = .local_get }});
    const temporary = try module.addLocal(id, .i32);
    try replaceKernel(a, &module, id, &.{
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .local_set, .operand = temporary },
        .{ .op = .local_get, .operand = temporary },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .i32_mul },
    });
    const before = try a.dupe(w.Instruction, module.functions.items[id].instructions.items);
    defer a.free(before);
    var output = (try run(a, &module, &module.functions.items[id])).?;
    defer output.deinit(a);
    try std.testing.expectEqualSlices(w.Instruction, before, module.functions.items[id].instructions.items);
    try module.emitSlice(id, &.{ .{ .op = .local_get, .operand = temporary }, .{ .op = .drop } });
    try std.testing.expect(try run(a, &module, &module.functions.items[id]) == null);
    module.functions.items[id].instructions.shrinkRetainingCapacity(before.len);
    try replaceKernel(a, &module, id, &.{
        .{ .op = .local_get, .operand = temporary },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },
        .{ .op = .local_tee, .operand = temporary },
    });
    try std.testing.expect(try run(a, &module, &module.functions.items[id]) == null);
}
test "vectorization follows unconditional helper returns but preserves caller control" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const id = try fixture(&module, &.{
        .{ .op = .local_get }, .{ .op = .i32_const, .operand = 3 }, .{ .op = .i32_mul }, .{ .op = .return_ }, .{ .op = .unreachable_ },
    });
    var output = (try run(a, &module, &module.functions.items[id])).?;
    defer output.deinit(a);
    try replaceKernel(a, &module, id, &.{ .{ .op = .local_get, .operand = 2 }, .{ .op = .return_ } });
    try std.testing.expect(try run(a, &module, &module.functions.items[id]) == null);
}
