//! Exact machine-body graph matching across incidental function-index changes.
//! Hashes narrow candidates. A bounded walk checks every reachable call pair,
//! including recursive cycles, and constructs an unambiguous relocation map.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
pub const Pair = struct { before: u32, after: u32 };
pub const Walk = struct {
    targets: std.AutoHashMapUnmanaged(u32, u32) = .empty,
    pending: std.ArrayList(Pair) = .empty,
    pub fn deinit(self: *Walk, a: A) void {
        self.targets.deinit(a);
        self.pending.deinit(a);
    }
    pub fn clear(self: *Walk) void {
        self.targets.clearRetainingCapacity();
        self.pending.clearRetainingCapacity();
    }
    pub fn add(self: *Walk, a: A, before: u32, after: u32) A.Error!bool {
        if (self.targets.get(before)) |known| return known == after;
        if (self.targets.count() >= 4096) return false;
        try self.pending.ensureUnusedCapacity(a, 1);
        try self.targets.put(a, before, after);
        self.pending.appendAssumeCapacity(.{ .before = before, .after = after });
        return true;
    }
};
pub fn hash(function: ir.Function) u64 {
    var state = std.hash.Wyhash.init(0);
    std.hash.autoHash(&state, function.parameters.len);
    state.update(std.mem.sliceAsBytes(function.parameters));
    std.hash.autoHash(&state, function.result);
    std.hash.autoHash(&state, function.locals.items.len);
    state.update(std.mem.sliceAsBytes(function.locals.items));
    for (function.instructions.items) |inst| {
        std.hash.autoHash(&state, inst.op);
        if (inst.op != .call) std.hash.autoHash(&state, inst.operand);
    }
    return state.final();
}
pub fn equalLocal(before: ir.Function, after: ir.Function) bool {
    if (before.result != after.result or !std.mem.eql(ir.ValueType, before.parameters, after.parameters) or !std.mem.eql(ir.ValueType, before.locals.items, after.locals.items) or before.instructions.items.len != after.instructions.items.len) return false;
    for (before.instructions.items, after.instructions.items) |left, right| {
        if (left.op != right.op or (left.op != .call and left.operand != right.operand)) return false;
    }
    return true;
}
