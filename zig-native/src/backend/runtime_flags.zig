//! Final lowering of immutable ownership flags after complete module admission.
//! Cached bodies stay symbolic. Blocks preserve every structured branch depth.
const ir = @import("runtime_ir.zig");
const w = @import("wasm.zig");
const roots = @import("../runtime/root_runtime.zig");

pub const Facts = struct {
    module: *const w.Module,
    root_mode: u32,
    rc_admitted: bool,

    fn wide(self: Facts) bool {
        const arena = self.module.arena orelse return false;
        if (self.module.globals.items[arena.rc_enabled].bits & @import("../runtime/shared_rc.zig").shaped_mode != 0) return true;
        for (self.module.exports.items) |item| {
            if (!item.global and (item.index == arena.allocate_shaped or item.index == arena.root_allocate_shaped)) return true;
        }
        return false;
    }
    fn value(self: Facts, inst: ir.Instruction) ?u32 {
        if (inst.op == .wide_layouts) return @intFromBool(self.wide());
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
    pending: [18]ir.Instruction = undefined,
    pending_at: usize = 18,

    pub fn next(self: *Iterator) ?ir.Instruction {
        if (self.pending_at < self.pending.len) {
            const inst = self.pending[self.pending_at];
            self.pending_at += 1;
            return inst;
        }
        while (self.at < self.instructions.len) {
            const at = self.at;
            var inst = self.instructions[at];
            self.at += 1;
            if (inst.op == .resource_retire) {
                const enqueue = self.facts.module.resourceRetireImport() orelse continue;
                self.pending = .{
                    .{ .op = .local_get, .operand = inst.operand },
                    .{ .op = .i32_const, .operand = @sizeOf(@import("../runtime/runtime_layout.zig").ArenaHeader) },
                    .{ .op = .i32_sub },
                    .{ .op = .i32_load, .operand = @import("../runtime/runtime_layout.zig").offset(@import("../runtime/runtime_layout.zig").ArenaHeader, "flags") },
                    .{ .op = .i32_const, .operand = @import("../runtime/shared_rc.zig").resource_owner },
                    .{ .op = .i32_and },
                    .{ .op = .if_ },
                    .{ .op = .local_get, .operand = inst.operand },
                    .{ .op = .i32_load, .operand = 4 },
                    .{ .op = .if_ },
                    .{ .op = .local_get, .operand = inst.operand },
                    .{ .op = .i32_load, .operand = 4 },
                    .{ .op = .local_get, .operand = inst.operand },
                    .{ .op = .i32_const },
                    .{ .op = .i32_store, .operand = 4 },
                    .{ .op = .call_import, .operand = enqueue },
                    .{ .op = .end },
                    .{ .op = .end },
                };
                self.pending_at = 1;
                return self.pending[0];
            }
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
