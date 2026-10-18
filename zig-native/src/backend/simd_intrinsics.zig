//! Fixed-width operations on ordinary four-scalar products. Their source type
//! is transparent; only these explicit compiler operations request SIMD.
//! Every operation's first operand is a four-lane product, so a product left
//! operand distinguishes a SIMD application from its scalar counterpart.
const std = @import("std");
const core = @import("../check/core.zig");
pub const Lane = enum { u32, f32 };
/// Operand and result shapes, with V the namespace's lane vector:
/// unary V -> V; convert V -> W; binary V -> V -> V; compare V -> V -> U32x4;
/// shift V -> U32 -> V; reduce U32x4 -> Bool; select U32x4 -> (V, V) -> V;
/// madd V -> (V, V) -> V; shuffle U32x4 -> (V, V) -> V; swizzle U32x4 -> V -> V;
/// broadcast V -> U32 -> V. Lane indices are literal operands.
pub const Shape = enum { unary, convert, binary, compare, shift, reduce, select, madd, shuffle, swizzle, broadcast };
pub const Intrinsic = struct {
    op: core.Op,
    arity: u8,
    floating: bool,
    shape: Shape,
    /// The lanes of the namespace's vector operands.
    pub fn lane(self: Intrinsic) Lane {
        return if (self.floating) .f32 else .u32;
    }
    /// A convert's result lanes; every other shape keeps its own lanes,
    /// except comparisons, whose masks are U32 lanes.
    pub fn resultLane(self: Intrinsic) Lane {
        return switch (self.shape) {
            .convert => if (self.floating) .u32 else .f32,
            .compare => .u32,
            else => self.lane(),
        };
    }
};
const Entry = struct { []const u8, core.Op, Shape };
const shared = [_]Entry{
    .{ "add", .add, .binary },              .{ "sub", .sub, .binary },        .{ "mul", .mul, .binary },
    .{ "min", .min, .binary },              .{ "max", .max, .binary },        .{ "eq", .equal, .compare },
    .{ "ne", .not_equal, .compare },        .{ "lt", .less, .compare },       .{ "le", .less_equal, .compare },
    .{ "gt", .greater, .compare },          .{ "ge", .greater_equal, .compare }, .{ "select", .select, .select },
    .{ "shuffle", .shuffle, .shuffle },     .{ "swizzle", .swizzle, .swizzle }, .{ "broadcast", .broadcast, .broadcast },
};
const floating_only = [_]Entry{
    .{ "div", .div, .binary },           .{ "abs", .abs, .unary },     .{ "neg", .neg, .unary },
    .{ "ceil", .ceil, .unary },          .{ "floor", .floor, .unary }, .{ "trunc", .trunc, .unary },
    .{ "sqrt", .sqrt, .unary },          .{ "to_u32", .convert_f32_u32, .convert }, .{ "bits", .bits, .convert },
    .{ "relaxed_madd", .relaxed_madd, .madd },
};
const integer_only = [_]Entry{
    .{ "bit_and", .bit_and, .binary },         .{ "bit_or", .bit_or, .binary },         .{ "bit_xor", .bit_xor, .binary },
    .{ "andnot", .bit_andnot, .binary },       .{ "not", .bit_not, .unary },            .{ "to_f32", .convert_u32_f32, .convert },
    .{ "from_bits", .from_bits, .convert },    .{ "shl", .shift_left, .shift },         .{ "shr", .shift_right, .shift },
    .{ "sar", .shift_right_signed, .shift },   .{ "any_true", .any_true, .reduce },     .{ "all_true", .all_true, .reduce },
};
pub fn lookup(name: []const u8) ?Intrinsic {
    const floating = std.mem.startsWith(u8, name, "@simd.f32x4.");
    if (!floating and !std.mem.startsWith(u8, name, "@simd.u32x4.")) return null;
    const member = name[12..];
    const specific: []const Entry = if (floating) &floating_only else &integer_only;
    for (shared) |entry| if (std.mem.eql(u8, member, entry[0])) return .{ .op = entry[1], .arity = arity(entry[2]), .floating = floating, .shape = entry[2] };
    for (specific) |entry| if (std.mem.eql(u8, member, entry[0])) return .{ .op = entry[1], .arity = arity(entry[2]), .floating = floating, .shape = entry[2] };
    return null;
}
pub fn arity(shape: Shape) u8 {
    return switch (shape) {
        .unary, .convert, .reduce => 1,
        else => 2,
    };
}
/// Operations that exist only on four-lane products.
pub fn vectorOnly(op: core.Op) bool {
    return switch (op) {
        .shift_right_signed, .min, .max, .bit_not, .bit_andnot, .any_true, .all_true, .select, .shuffle, .swizzle, .broadcast, .bits, .from_bits, .relaxed_madd => true,
        else => false,
    };
}
/// The second operand pairs two vectors.
pub fn pairs(op: core.Op) bool {
    return op == .select or op == .relaxed_madd or op == .shuffle;
}
/// Lane indices are compile-time literals: the first operand of a shuffle or
/// swizzle, or the second operand of a broadcast.
pub fn literalLanes(op: core.Op) bool {
    return op == .shuffle or op == .swizzle or op == .broadcast;
}
/// The largest lane index a literal may select: shuffles read eight lanes.
pub fn laneLimit(op: core.Op) u32 {
    return if (op == .shuffle) 8 else 4;
}

test "every SIMD spelling resolves to one shape and arity" {
    const add = lookup("@simd.f32x4.add").?;
    try std.testing.expectEqual(Shape.binary, add.shape);
    try std.testing.expectEqual(Lane.u32, lookup("@simd.f32x4.lt").?.resultLane());
    try std.testing.expectEqual(Lane.u32, lookup("@simd.f32x4.bits").?.resultLane());
    try std.testing.expectEqual(Lane.f32, lookup("@simd.u32x4.from_bits").?.resultLane());
    try std.testing.expectEqual(@as(u8, 1), lookup("@simd.u32x4.any_true").?.arity);
    try std.testing.expect(lookup("@simd.u32x4.div") == null);
    try std.testing.expect(lookup("@simd.f32x4.shl") == null);
    try std.testing.expect(lookup("@simd.u32x4.relaxed_madd") == null);
}
