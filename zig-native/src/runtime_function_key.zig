//! Exact identities of resolved machine bodies. Hashes only select candidates;
//! equality includes every type, opcode and immediate (including raw F32 bits).
const std = @import("std");
const ir = @import("runtime_ir.zig");

pub fn equal(left: ir.Function, right: ir.Function) bool {
    if (left.result != right.result or !std.mem.eql(ir.ValueType, left.parameters, right.parameters) or !std.mem.eql(ir.ValueType, left.locals.items, right.locals.items) or left.instructions.items.len != right.instructions.items.len) return false;
    for (left.instructions.items, right.instructions.items) |a, b| if (!std.meta.eql(a, b)) return false;
    return true;
}
pub fn hash(function: ir.Function) u64 {
    var state = std.hash.Wyhash.init(0);
    std.hash.autoHash(&state, function.parameters.len);
    state.update(std.mem.sliceAsBytes(function.parameters));
    std.hash.autoHash(&state, function.result);
    std.hash.autoHash(&state, function.locals.items.len);
    state.update(std.mem.sliceAsBytes(function.locals.items));
    for (function.instructions.items) |inst| {
        std.hash.autoHash(&state, inst.op);
        std.hash.autoHash(&state, inst.operand);
    }
    return state.final();
}
