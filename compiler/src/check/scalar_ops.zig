//! Which scalar operations have a machine instruction, and U32 constant
//! folding, for the checker's numeric and package proofs.
const std = @import("std");
const core = @import("core.zig");

/// Whether `op` is one scalar instruction on F32 operands (`floating`) or on
/// U32 and Bool operands.
pub fn supported(op: core.Op, floating: bool) bool {
    return switch (op) {
        .add, .sub, .mul, .div, .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .convert_u32_f32, .convert_f32_u32 => true,
        .rem, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right, .from_bits => !floating,
        .neg, .abs, .ceil, .floor, .trunc, .sqrt, .min, .max, .bits => floating,
        .none, .continue_, .and_, .or_, .shift_right_signed, .bit_not, .bit_andnot, .any_true, .all_true, .select, .shuffle, .swizzle, .broadcast, .relaxed_madd, .relaxed_nmadd, .convert_i32_f32, .convert_f32_i32 => false,
    };
}

/// Constant folding of a scalar operation on two U32 operands, as the guest
/// computes it: the U32 result, `not_u32` when the result has another type
/// (a comparison or a conversion to F32), or `none` when the guest has no
/// such U32 instruction or would trap (division by zero).
pub const Folded = union(enum) { value: u32, not_u32, none };
pub fn foldU32(op: core.Op, a: u32, b: u32) Folded {
    switch (op) {
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal, .convert_u32_f32, .from_bits => return .not_u32,
        .div, .rem => if (b == 0) return .none,
        else => {},
    }
    const value: u32 = switch (op) {
        .add => a +% b,
        .sub => a -% b,
        .mul => a *% b,
        .div => a / b,
        .rem => a % b,
        .bit_and => a & b,
        .bit_or => a | b,
        .bit_xor => a ^ b,
        .shift_left => a << @as(u5, @truncate(b)),
        .shift_right => a >> @as(u5, @truncate(b)),
        .convert_f32_u32 => truncate(@bitCast(a)),
        else => return .none,
    };
    return .{ .value = value };
}
fn truncate(x: f32) u32 {
    if (std.math.isNan(x) or x <= 0) return 0;
    if (x >= 4294967296.0) return 0xffff_ffff;
    return @intFromFloat(x);
}

test "U32 folding matches the guest's wrapping and shift semantics" {
    try std.testing.expectEqual(Folded{ .value = 0 }, foldU32(.add, 0xffff_ffff, 1));
    try std.testing.expectEqual(Folded{ .value = 0xffff_ffff }, foldU32(.sub, 0, 1));
    try std.testing.expectEqual(Folded{ .value = 2 }, foldU32(.shift_left, 1, 33));
    try std.testing.expectEqual(Folded.none, foldU32(.div, 1, 0));
    try std.testing.expectEqual(Folded.none, foldU32(.sqrt, 1, 0));
    try std.testing.expectEqual(Folded.not_u32, foldU32(.less, 1, 2));
    try std.testing.expect(supported(.rem, false) and !supported(.rem, true));
    try std.testing.expect(supported(.sqrt, true) and !supported(.sqrt, false));
}
