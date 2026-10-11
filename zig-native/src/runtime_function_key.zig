//! Exact identities of resolved machine bodies. Hashes only select candidates;
//! equality includes every type, opcode and immediate (including raw F32 bits).
const std = @import("std");
const ir = @import("runtime_ir.zig");

/// Ownership annotations and parameter roles are analysis facts, not code:
/// bodies that differ only there are the same machine body.
pub fn equal(left: ir.Function, right: ir.Function) bool {
    if (left.result != right.result or !std.mem.eql(ir.ValueType, left.parameters, right.parameters) or !std.mem.eql(ir.ValueType, left.locals.items, right.locals.items)) return false;
    var i: usize = 0;
    var j: usize = 0;
    while (true) {
        while (i < left.instructions.items.len and left.instructions.items[i].op == .ownership) i += 1;
        while (j < right.instructions.items.len and right.instructions.items[j].op == .ownership) j += 1;
        if (i == left.instructions.items.len or j == right.instructions.items.len) return i == left.instructions.items.len and j == right.instructions.items.len;
        if (!std.meta.eql(left.instructions.items[i], right.instructions.items[j])) return false;
        i += 1;
        j += 1;
    }
}
pub fn hash(function: ir.Function) u64 {
    var state = std.hash.Wyhash.init(0);
    std.hash.autoHash(&state, function.parameters.len);
    state.update(std.mem.sliceAsBytes(function.parameters));
    std.hash.autoHash(&state, function.result);
    std.hash.autoHash(&state, function.locals.items.len);
    state.update(std.mem.sliceAsBytes(function.locals.items));
    for (function.instructions.items) |inst| {
        if (inst.op == .ownership) continue;
        std.hash.autoHash(&state, inst.op);
        std.hash.autoHash(&state, inst.operand);
    }
    return state.final();
}
