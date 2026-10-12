//! Final lowering of immutable ownership flags after complete module admission.
//! Cached bodies stay symbolic. Blocks preserve every structured branch depth.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const w = @import("wasm.zig");
const roots = @import("root_runtime.zig");

pub const Facts = struct {
    module: *const w.Module,
    root_mode: u32,
    rc_admitted: bool,

    fn value(self: Facts, inst: ir.Instruction) ?u32 {
        if (inst.op != .global_get) return null;
        const arena = self.module.arena orelse return null;
        if (inst.operand >= self.module.globals.items.len) return null;
        const global = self.module.globals.items[inst.operand];
        if (global.mutable or global.scalar != .u32) return null;
        if (inst.operand == arena.root_enabled) return self.root_mode;
        if (inst.operand == arena.rc_enabled) return @intFromBool(self.rc_admitted);
        return null;
    }
    pub fn complete(self: Facts) bool {
        const arena = self.module.arena orelse return false;
        if (!self.rc_admitted or self.root_mode != (roots.enabled | roots.complete)) return false;
        return self.value(.{ .op = .global_get, .operand = arena.root_enabled }) != null and
            self.value(.{ .op = .global_get, .operand = arena.rc_enabled }) != null;
    }
    pub fn tracer(self: Facts, id: usize) bool {
        const arena = self.module.arena orelse return false;
        return id == arena.collect or id == arena.mark or id == arena.root_mark;
    }
    pub fn helper(self: Facts, id: usize, reset: *[7]ir.Instruction) ?[]const ir.Instruction {
        if (!self.complete()) return null;
        const arena = self.module.arena.?;
        if (id == arena.collect or id == arena.mark or id == arena.root_mark) return &.{.{ .op = .unreachable_ }};
        if (id != arena.reset) return null;
        reset.* = .{
            .{ .op = .global_get, .operand = arena.cycle_head },
            .{ .op = .if_ },
            .{ .op = .i32_const, .operand = 1 },
            .{ .op = .call, .operand = arena.cycle_safe },
            .{ .op = .end },
            .{ .op = .global_get, .operand = arena.heap },
            .{ .op = .return_ },
        };
        return reset;
    }
};
const Condition = struct { after: usize, value: bool, result: u32 };
fn condition(facts: Facts, instructions: []const ir.Instruction, start: usize) ?Condition {
    if (start >= instructions.len) return null;
    var value = facts.value(instructions[start]) orelse return null;
    var at = start + 1;
    if (at + 1 < instructions.len and instructions[at].op == .i32_const and instructions[at + 1].op == .i32_and) {
        value &= instructions[at].operand;
        at += 2;
    }
    if (at < instructions.len and instructions[at].op == .i32_eqz) {
        value = @intFromBool(value == 0);
        at += 1;
    }
    if (at >= instructions.len or instructions[at].op != .if_) return null;
    return .{ .after = at + 1, .value = value != 0, .result = instructions[at].operand };
}
fn boundary(instructions: []const ir.Instruction, start: usize, alternate: bool) ?usize {
    var depth: usize = 0;
    for (instructions[start..], start..) |inst, at| switch (inst.op) {
        .block, .loop, .if_ => depth += 1,
        .end => {
            if (depth == 0) return at;
            depth -= 1;
        },
        .else_ => if (alternate and depth == 0) return at,
        else => {},
    };
    return null;
}
fn opening(instructions: []const ir.Instruction, alternate: usize) ?usize {
    var at = alternate;
    var depth: usize = 0;
    while (at != 0) {
        at -= 1;
        switch (instructions[at].op) {
            .end => depth += 1,
            .block, .loop, .if_ => {
                if (depth == 0) return at;
                depth -= 1;
            },
            else => {},
        }
    }
    return null;
}

pub const Iterator = struct {
    facts: Facts,
    instructions: []const ir.Instruction,
    at: usize = 0,

    pub fn next(self: *Iterator) ?ir.Instruction {
        while (self.at < self.instructions.len) {
            const at = self.at;
            var inst = self.instructions[at];
            self.at += 1;
            if (condition(self.facts, self.instructions, at)) |known| {
                if (boundary(self.instructions, known.after, !known.value)) |end| {
                    self.at = known.after;
                    if (!known.value) {
                        self.at = end;
                        if (self.instructions[end].op == .else_) self.at += 1;
                    }
                    return .{ .op = .block, .operand = known.result };
                }
            }
            if (inst.op == .else_) if (opening(self.instructions, at)) |begin| {
                var start = begin -| 4;
                while (start < begin) : (start += 1) if (condition(self.facts, self.instructions, start)) |known| {
                    if (known.after != begin + 1 or !known.value) continue;
                    if (boundary(self.instructions, at + 1, false)) |end| {
                        self.at = end;
                        break;
                    }
                };
                if (self.at != at + 1) continue;
            };
            if (self.facts.value(inst)) |value| inst = .{ .op = .i32_const, .operand = value };
            return inst;
        }
        return null;
    }
};

fn expectLowered(facts: Facts, input: []const ir.Instruction, expected: []const ir.Instruction) !void {
    var iterator: Iterator = .{ .facts = facts, .instructions = input };
    for (expected) |inst| try std.testing.expectEqualDeep(inst, iterator.next().?);
    try std.testing.expect(iterator.next() == null);
}
test "immutable ownership lowering preserves result blocks and nested branch depths" {
    var module = w.Module.init(std.testing.allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    const facts: Facts = .{ .module = &module, .root_mode = roots.enabled | roots.complete, .rc_admitted = true };
    const input = [_]ir.Instruction{
        .{ .op = .block, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .i32_const, .operand = 42 },
        .{ .op = .br, .operand = 1 },
        .{ .op = .else_ },
        .{ .op = .i32_const },
        .{ .op = .end },
        .{ .op = .end },
    };
    try expectLowered(facts, &input, &.{ input[0], .{ .op = .block, .operand = input[2].operand }, input[3], input[4], input[7], input[8] });
    try expectLowered(facts, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .i32_const, .operand = roots.complete },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) },
        .{ .op = .block },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .else_ },
        .{ .op = .i32_const, .operand = 42 },
        .{ .op = .end },
    }, &.{ .{ .op = .block, .operand = @backingInt(ir.ValueType.i32) }, .{ .op = .i32_const, .operand = 42 }, .{ .op = .end } });
    module.globals.items[arena.root_enabled].mutable = true;
    try std.testing.expect(!facts.complete());
    try expectLowered(facts, &input, &input);
}

test "complete lowering rejects surviving tracer references and preserves partial helpers" {
    const a = std.testing.allocator;
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{}, .none, .scalar);
    try module.emitSlice(function, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .i32_const, .operand = roots.complete },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .i32_const },
        .{ .op = .i32_const },
        .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.collect },
        .{ .op = .drop },
        .{ .op = .end },
    });
    const before = try a.dupe(ir.Instruction, module.functions.items[function].instructions.items);
    defer a.free(before);
    const bytes = try module.assemble();
    defer a.free(bytes);
    try std.testing.expectEqualDeep(before, module.functions.items[function].instructions.items);
    try module.emitSlice(function, &.{ .{ .op = .i32_const }, .{ .op = .i32_const }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.collect }, .{ .op = .drop } });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
    module.functions.items[function].instructions.shrinkRetainingCapacity(before.len);
    try module.emit(function, .{ .op = .i32_const, .operand = arena.collect, .table_reference = true });
    try module.emit(function, .{ .op = .drop });
    try std.testing.expectError(error.InvalidFunctionReference, module.assemble());
    module.functions.items[function].instructions.shrinkRetainingCapacity(before.len);
    module.globals.items[arena.root_enabled].mutable = true;
    const partial: Facts = .{ .module = &module, .root_mode = roots.enabled, .rc_admitted = true };
    var reset: [7]ir.Instruction = undefined;
    try std.testing.expect(partial.helper(arena.collect, &reset) == null);
    const mutable_bytes = try module.assemble();
    defer a.free(mutable_bytes);
}

test "late incomplete admission reuses symbolic guards across retained and portable replay" {
    const a = std.testing.allocator;
    const bodies = @import("optimized_bodies.zig");
    const portable = @import("optimized_archive.zig");
    var module = w.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const guarded = try module.addTypedFunction(&.{}, .none, .scalar);
    try module.emitSlice(guarded, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .i32_const, .operand = roots.complete },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .i32_const },
        .{ .op = .i32_const },
        .{ .op = .i32_const },
        .{ .op = .call, .operand = arena.collect },
        .{ .op = .drop },
        .{ .op = .end },
    });
    const owning = try module.addTypedFunction(&.{}, .i32, .reference);
    try module.emitSlice(owning, &.{ .{ .op = .i32_const, .operand = 4 }, .{ .op = .call, .operand = arena.allocate_scalar } });
    var before: bodies.Capture = .{ .allocator = a };
    defer before.deinit();
    const initial = try module.assembleWithOptions(.{ .current = &before });
    defer a.free(initial);
    try std.testing.expect(before.roots and before.needs_roots);
    const compiler: [32]u8 = @splat(35);
    const archived = try portable.encode(a, compiler, &before);
    defer a.free(archived);
    var checkpoint = try portable.decode(a, compiler, archived);
    defer checkpoint.deinit();
    // Raw allocation changes final admission without changing frame demand.
    const raw = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(raw, ir.packParameterRoles(&.{.scalar}));
    try module.emitSlice(raw, &.{ .{ .op = .local_get }, .{ .op = .call, .operand = arena.allocate } });
    const fresh = try module.assemble();
    defer a.free(fresh);
    const marker = (std.mem.findLast(u8, fresh, "blot:ownership") orelse return error.TestExpectedRootManifest) + "blot:ownership".len;
    try std.testing.expectEqualSlices(u8, &.{ 1, 0 }, fresh[marker..][0..2]);
    for ([_]*const bodies.Capture{ &before, &checkpoint }) |previous| {
        var current: bodies.Capture = .{ .allocator = a };
        defer current.deinit();
        const retained = try module.assembleWithOptions(.{ .previous = previous, .current = &current });
        defer a.free(retained);
        try std.testing.expectEqualSlices(u8, fresh, retained);
        try std.testing.expect(current.roots and current.needs_roots);
        var matcher = try bodies.Matcher.init(a, previous, &current);
        defer matcher.deinit();
        try std.testing.expect(matcher.matches(guarded));
        const output = current.entries.items[guarded].output orelse return error.TestExpectedSymbolicOutput;
        var symbolic = false;
        for (output.instructions.items) |inst| if (inst.op == .global_get and inst.operand == arena.root_enabled) {
            symbolic = true;
        };
        try std.testing.expect(symbolic);
    }
}
