//! Exact machine-body graph matching across incidental function-index changes.
//! Hashes narrow candidates. A bounded walk checks every reachable call pair,
//! including recursive cycles, and constructs an unambiguous relocation map.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
pub const Pair = struct { before: u32, after: u32 };

pub fn reference(inst: ir.Instruction) bool {
    if (inst.table_reference) return true;
    return switch (inst.op) {
        .call, .call_import, .call_indirect, .global_get, .global_set => true,
        else => false,
    };
}
pub const Kind = enum { function, import_, signature, global };
const Key = struct { kind: Kind, index: u32 };
pub const Walk = struct {
    targets: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    reverse: std.AutoHashMapUnmanaged(Key, u32) = .empty,
    pending: std.ArrayList(Pair) = .empty,
    /// Shared across candidates. Clearing a failed proof never replenishes it.
    remaining: usize = 1_000_000,
    pub fn deinit(self: *Walk, a: A) void {
        self.targets.deinit(a);
        self.reverse.deinit(a);
        self.pending.deinit(a);
    }
    pub fn clear(self: *Walk) void {
        self.targets.clearRetainingCapacity();
        self.reverse.clearRetainingCapacity();
        self.pending.clearRetainingCapacity();
    }
    pub fn spend(self: *Walk, amount: usize) bool {
        if (amount > self.remaining) {
            self.remaining = 0;
            return false;
        }
        self.remaining -= amount;
        return true;
    }
    pub fn get(self: *const Walk, kind: Kind, before: u32) ?u32 {
        return self.targets.get(.{ .kind = kind, .index = before });
    }
    pub fn add(self: *Walk, a: A, kind: Kind, before: u32, after: u32) A.Error!bool {
        if (!self.spend(1)) return false;
        if (self.get(kind, before)) |known| return known == after;
        if (self.reverse.get(.{ .kind = kind, .index = after })) |_| return false;
        if (self.targets.count() >= 4096) return false;
        if (kind == .function) try self.pending.ensureUnusedCapacity(a, 1);
        try self.targets.ensureUnusedCapacity(a, 1);
        try self.reverse.ensureUnusedCapacity(a, 1);
        self.targets.putAssumeCapacity(.{ .kind = kind, .index = before }, after);
        self.reverse.putAssumeCapacity(.{ .kind = kind, .index = after }, before);
        if (kind == .function) self.pending.appendAssumeCapacity(.{ .before = before, .after = after });
        return true;
    }
};
pub fn referenceKind(inst: ir.Instruction) ?Kind {
    if (inst.table_reference) return .function;
    return switch (inst.op) {
        .call => .function,
        .call_import => .import_,
        .call_indirect => .signature,
        .global_get, .global_set => .global,
        else => null,
    };
}
pub fn hash(function: ir.Function) u64 {
    var state = std.hash.Wyhash.init(0);
    std.hash.autoHash(&state, function.parameters.len);
    state.update(std.mem.sliceAsBytes(function.parameters));
    std.hash.autoHash(&state, function.result);
    std.hash.autoHash(&state, function.result_role);
    std.hash.autoHash(&state, function.entry);
    std.hash.autoHash(&state, function.parameter_roles);
    std.hash.autoHash(&state, function.locals.items.len);
    state.update(std.mem.sliceAsBytes(function.locals.items));
    for (function.instructions.items) |inst| {
        std.hash.autoHash(&state, inst.op);
        std.hash.autoHash(&state, inst.table_reference);
        if (!reference(inst)) std.hash.autoHash(&state, inst.operand);
    }
    return state.final();
}
pub fn equalLocal(before: ir.Function, after: ir.Function) bool {
    if (before.result_role != after.result_role or before.entry != after.entry or before.parameter_roles != after.parameter_roles or before.result != after.result or !std.mem.eql(ir.ValueType, before.parameters, after.parameters) or !std.mem.eql(ir.ValueType, before.locals.items, after.locals.items) or before.instructions.items.len != after.instructions.items.len) return false;
    for (before.instructions.items, after.instructions.items) |left, right| {
        if (left.op != right.op or left.table_reference != right.table_reference or (!reference(left) and left.operand != right.operand)) return false;
    }
    return true;
}
