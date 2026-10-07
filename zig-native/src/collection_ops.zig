//! Shared collection operations; the source prefix fixes the collection type.
const std = @import("std");
pub const Op = enum(u32) { length, get, set, fill, generate, append, prepend, identity, convert, cursor, cursor_has, cursor_value, cursor_advance, concat, slice };
pub fn arity(op: Op) u8 {
    return switch (op) {
        .length, .identity, .convert, .cursor, .cursor_has, .cursor_value, .cursor_advance => 1,
        .get, .fill, .generate, .append, .prepend, .concat => 2,
        .set, .slice => 3,
    };
}
pub const Primitive = struct { op: Op, arity: u8, is_list: bool };
pub fn lookup(name: []const u8) ?Primitive {
    inline for (.{ .{ "@cursor.has", Op.cursor_has }, .{ "@cursor.value", Op.cursor_value }, .{ "@cursor.advance", Op.cursor_advance } }) |entry|
        if (std.mem.eql(u8, name, entry[0])) return .{ .op = entry[1], .arity = 1, .is_list = false };
    const is_list = std.mem.startsWith(u8, name, "@list.");
    if (!is_list and !std.mem.startsWith(u8, name, "@array.")) return null;
    const member = name[if (is_list) @as(usize, 6) else 7..];
    const op: Op = if (std.mem.eql(u8, member, if (is_list) "from_array" else "from_list")) .convert else blk: {
        inline for (.{ Op.length, Op.get, Op.set, Op.fill, Op.generate, Op.append, Op.prepend, Op.identity, Op.cursor, Op.concat, Op.slice }) |candidate|
            if (std.mem.eql(u8, member, @tagName(candidate))) break :blk candidate;
        return null;
    };
    // Indexed operations are an Array API. List traversal uses compiler-private
    // Core operations, so it does not need source-visible indexing intrinsics.
    if (is_list and (op == .get or op == .set)) return null;
    return .{ .op = op, .arity = arity(op), .is_list = is_list };
}
