//! Explicit storage operations survive typed Core without becoming counted
//! collection operations. The storage planner proves their roots and exits.
const std = @import("std");
pub const Op = enum(u32) { ref, at, link, view, load, write, length, read, push, pop, truncate, freeze, copy, reserve };
pub fn lookup(name: []const u8) ?Op {
    const prefix = "@storage.";
    if (!std.mem.startsWith(u8, name, prefix)) return null;
    return std.meta.stringToEnum(Op, name[prefix.len..]);
}
pub fn arity(op: Op) u32 {
    return switch (op) {
        .ref, .load, .length, .pop, .freeze, .copy => 1,
        .at, .link, .write, .read, .push, .truncate, .reserve => 2,
        .view => 3,
    };
}
// reserve is an observable planning marker even though it mutates no data.
pub fn writes(op: Op) bool {
    return switch (op) {
        .write, .push, .pop, .truncate, .freeze, .reserve => true,
        else => false,
    };
}
