//! One scalar operation contract for typed-IR evaluation and Wasm lowering.
const std = @import("std");
const core = @import("../check/core.zig");
const wasm = @import("wasm.zig");
pub const Value = struct { scalar: wasm.Scalar, bits: u32 };
pub const Error = error{ Unsupported, IntegerDivideByZero };

pub fn opcode(op: core.Op, scalar: wasm.Scalar) ?wasm.Op {
    const floating = scalar == .f32;
    return switch (op) {
        .add => if (floating) .f32_add else .i32_add,
        .sub => if (floating) .f32_sub else .i32_sub,
        .mul => if (floating) .f32_mul else .i32_mul,
        .div => if (floating) .f32_div else .i32_div_u,
        .rem => if (floating) null else .i32_rem_u,
        .equal => if (floating) .f32_eq else .i32_eq,
        .not_equal => if (floating) .f32_ne else .i32_ne,
        .less => if (floating) .f32_lt else .i32_lt_u,
        .less_equal => if (floating) .f32_le else .i32_le_u,
        .greater => if (floating) .f32_gt else .i32_gt_u,
        .greater_equal => if (floating) .f32_ge else .i32_ge_u,
        .bit_and => if (floating) null else .i32_and,
        .bit_or => if (floating) null else .i32_or,
        .bit_xor => if (floating) null else .i32_xor,
        .shift_left => if (floating) null else .i32_shl,
        .shift_right => if (floating) null else .i32_shr_u,
        .neg => if (floating) .f32_neg else null,
        .abs => if (floating) .f32_abs else null,
        .ceil => if (floating) .f32_ceil else null,
        .floor => if (floating) .f32_floor else null,
        .trunc => if (floating) .f32_trunc else null,
        .sqrt => if (floating) .f32_sqrt else null,
        .min => {
            if (floating) return .f32_min;
            return null;
        },
        .max => {
            if (floating) return .f32_max;
            return null;
        },
        .bits => {
            if (floating) return .i32_reinterpret_f32;
            return null;
        },
        .from_bits => {
            if (!floating) return .f32_reinterpret_i32;
            return null;
        },
        .convert_u32_f32 => .f32_convert_i32_u,
        .convert_f32_u32 => .i32_trunc_sat_f32_u,
        // Lane-only operations have no scalar instruction.
        .none, .continue_, .and_, .or_, .shift_right_signed, .bit_not, .bit_andnot, .any_true, .all_true, .select, .shuffle, .swizzle, .broadcast, .relaxed_madd, .relaxed_nmadd, .convert_i32_f32, .convert_f32_i32 => null,
    };
}

pub fn resultScalar(op: core.Op, scalar: wasm.Scalar) wasm.Scalar {
    return switch (op) {
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => .bool,
        .convert_u32_f32, .from_bits => .f32,
        .convert_f32_u32, .bits => .u32,
        else => scalar,
    };
}

pub fn evaluate(op: core.Op, a: Value, b: Value) Error!Value {
    const machine_op = opcode(op, a.scalar) orelse return error.Unsupported;
    const x: f32 = @bitCast(a.bits);
    const y: f32 = @bitCast(b.bits);
    const bits: u32 = switch (machine_op) {
        .i32_add => a.bits +% b.bits,
        .i32_sub => a.bits -% b.bits,
        .i32_mul => a.bits *% b.bits,
        .i32_div_u, .i32_rem_u => blk: {
            if (b.bits == 0) return error.IntegerDivideByZero;
            if (machine_op == .i32_div_u) break :blk a.bits / b.bits;
            break :blk a.bits % b.bits;
        },
        .i32_and => a.bits & b.bits,
        .i32_or => a.bits | b.bits,
        .i32_xor => a.bits ^ b.bits,
        .i32_shl => a.bits << @as(u5, @truncate(b.bits)),
        .i32_shr_u => a.bits >> @as(u5, @truncate(b.bits)),
        .i32_eq => @intFromBool(a.bits == b.bits),
        .i32_ne => @intFromBool(a.bits != b.bits),
        .i32_lt_u => @intFromBool(a.bits < b.bits),
        .i32_gt_u => @intFromBool(a.bits > b.bits),
        .i32_le_u => @intFromBool(a.bits <= b.bits),
        .i32_ge_u => @intFromBool(a.bits >= b.bits),
        .f32_eq => @intFromBool(x == y),
        .f32_ne => @intFromBool(x != y),
        .f32_lt => @intFromBool(x < y),
        .f32_gt => @intFromBool(x > y),
        .f32_le => @intFromBool(x <= y),
        .f32_ge => @intFromBool(x >= y),
        .f32_add => @bitCast(x + y),
        .f32_sub => @bitCast(x - y),
        .f32_mul => @bitCast(x * y),
        .f32_div => @bitCast(x / y),
        .f32_abs => a.bits & 0x7fffffff,
        .f32_neg => a.bits ^ 0x80000000,
        .f32_ceil => @bitCast(@ceil(x)),
        .f32_floor => @bitCast(@floor(x)),
        .f32_trunc => @bitCast(@trunc(x)),
        .f32_sqrt => @bitCast(@sqrt(x)),
        .f32_min, .f32_max => blk: {
            if (std.math.isNan(x) or std.math.isNan(y)) break :blk 0x7fc00000;
            // Wasm min prefers -0; max prefers +0, independent of operand order.
            if (x == y) {
                if (machine_op == .f32_min) break :blk a.bits | b.bits;
                break :blk a.bits & b.bits;
            }
            if (machine_op == .f32_min) {
                if (x < y) break :blk a.bits;
                break :blk b.bits;
            }
            if (x > y) break :blk a.bits;
            break :blk b.bits;
        },
        .i32_reinterpret_f32, .f32_reinterpret_i32 => a.bits,
        .f32_convert_i32_u => @bitCast(@as(f32, @floatFromInt(a.bits))),
        .i32_trunc_sat_f32_u => blk: {
            if (std.math.isNan(x) or x <= 0) break :blk 0;
            if (x >= 4294967296.0) break :blk std.math.maxInt(u32);
            break :blk @intFromFloat(x);
        },
        else => return error.Unsupported,
    };
    return .{ .scalar = resultScalar(op, a.scalar), .bits = bits };
}

/// Optional exact-bit folding retains ordinary evaluation's valid NaNs without
/// claiming that the guest must choose the same arithmetic NaN payload.
pub fn evaluateExact(op: core.Op, a: Value, b: Value) Error!Value {
    const result = try evaluate(op, a, b);
    if (result.scalar == .f32) switch (op) {
        .add, .sub, .mul, .div, .ceil, .floor, .trunc, .sqrt, .min, .max => {
            if (std.math.isNan(@as(f32, @bitCast(result.bits)))) return error.Unsupported;
        },
        else => {},
    };
    return result;
}

fn expectEvaluation(op: core.Op, scalar: wasm.Scalar, a: u32, b: u32, result_scalar: wasm.Scalar, bits: u32) !void {
    const actual = try evaluateExact(op, .{ .scalar = scalar, .bits = a }, .{ .scalar = scalar, .bits = b });
    try std.testing.expectEqual(result_scalar, actual.scalar);
    try std.testing.expectEqual(bits, actual.bits);
}

test "scalar evaluation preserves U32 wrapping masked shifts and division traps" {
    try expectEvaluation(.add, .u32, 0xffffffff, 1, .u32, 0);
    try expectEvaluation(.sub, .u32, 0, 1, .u32, 0xffffffff);
    try expectEvaluation(.mul, .u32, 0xffffffff, 2, .u32, 0xfffffffe);
    try expectEvaluation(.shift_left, .u32, 3, 32, .u32, 3);
    try expectEvaluation(.shift_left, .u32, 1, 63, .u32, 0x80000000);
    try expectEvaluation(.shift_right, .u32, 0x80000000, 0xffffffff, .u32, 1);
    try expectEvaluation(.shift_right, .u32, 0x80000000, 32, .u32, 0x80000000);
    try expectEvaluation(.div, .u32, 0xffffffff, 2, .u32, 0x7fffffff);
    try expectEvaluation(.rem, .u32, 0xffffffff, 2, .u32, 1);
    for ([_]core.Op{ .div, .rem }) |op| {
        try std.testing.expectError(error.IntegerDivideByZero, evaluate(op, .{ .scalar = .u32, .bits = 1 }, .{ .scalar = .u32, .bits = 0 }));
    }
}

test "scalar evaluation preserves F32 signed zero and exact NaN bit operations" {
    try expectEvaluation(.neg, .f32, 0, 0, .f32, 0x80000000);
    try expectEvaluation(.abs, .f32, 0x80000000, 0, .f32, 0);
    try expectEvaluation(.add, .f32, 0x80000000, 0x80000000, .f32, 0x80000000);
    try expectEvaluation(.add, .f32, 0x80000000, 0, .f32, 0);
    try expectEvaluation(.sub, .f32, 0x80000000, 0, .f32, 0x80000000);
    try expectEvaluation(.mul, .f32, 0, 0xbf800000, .f32, 0x80000000);
    try expectEvaluation(.ceil, .f32, 0xbf000000, 0, .f32, 0x80000000);
    try expectEvaluation(.trunc, .f32, 0xbf000000, 0, .f32, 0x80000000);
    try expectEvaluation(.floor, .f32, 0xbf000000, 0, .f32, 0xbf800000);
    try expectEvaluation(.sqrt, .f32, 0x80000000, 0, .f32, 0x80000000);
    for ([_]u32{ 0x7fc01234, 0xffc01234, 0x7f801234, 0xff801234 }) |nan| {
        try expectEvaluation(.neg, .f32, nan, 0, .f32, nan ^ 0x80000000);
        try expectEvaluation(.abs, .f32, nan, 0, .f32, nan & 0x7fffffff);
        try expectEvaluation(.bits, .f32, nan, 0, .u32, nan);
        try expectEvaluation(.from_bits, .u32, nan, 0, .f32, nan);
        try expectEvaluation(.equal, .f32, nan, nan, .bool, 0);
        try expectEvaluation(.not_equal, .f32, nan, nan, .bool, 1);
        try expectEvaluation(.less, .f32, nan, 0, .bool, 0);
    }
    try expectEvaluation(.equal, .f32, 0x80000000, 0, .bool, 1);
}

test "scalar exact evaluation declines arithmetic NaN payload choices while ordinary evaluation preserves NaNs" {
    for ([_]core.Op{ .add, .sub, .mul, .div, .ceil, .floor, .trunc, .sqrt, .min, .max }) |op| {
        const left: Value = .{ .scalar = .f32, .bits = 0x7fc01234 };
        const right: Value = .{ .scalar = .f32, .bits = 0x3f800000 };
        const result = try evaluate(op, left, right);
        try std.testing.expectEqual(wasm.Scalar.f32, result.scalar);
        try std.testing.expect(std.math.isNan(@as(f32, @bitCast(result.bits))));
        try std.testing.expectError(error.Unsupported, evaluateExact(op, left, right));
    }
    const zero: Value = .{ .scalar = .f32, .bits = 0 };
    const divided = try evaluate(.div, zero, zero);
    try std.testing.expect(std.math.isNan(@as(f32, @bitCast(divided.bits))));
    try std.testing.expectError(error.Unsupported, evaluateExact(.div, zero, zero));
    const negative: Value = .{ .scalar = .f32, .bits = 0xbf800000 };
    const square_root = try evaluate(.sqrt, negative, zero);
    try std.testing.expect(std.math.isNan(@as(f32, @bitCast(square_root.bits))));
    try std.testing.expectError(error.Unsupported, evaluateExact(.sqrt, negative, zero));
}

test "scalar evaluation saturates F32 to U32 at exact boundaries" {
    for ([_]u32{ 0x7fc01234, 0xffc01234, 0x7f801234, 0xff801234, 0, 0x80000000, 0xbf800000, 0xff800000 }) |bits| {
        try expectEvaluation(.convert_f32_u32, .f32, bits, 0, .u32, 0);
    }
    try expectEvaluation(.convert_f32_u32, .f32, 0x414c0000, 0, .u32, 12);
    try expectEvaluation(.convert_f32_u32, .f32, 0x4f7fffff, 0, .u32, 0xffffff00);
    try expectEvaluation(.convert_f32_u32, .f32, 0x4f800000, 0, .u32, 0xffffffff);
    try expectEvaluation(.convert_f32_u32, .f32, 0x7f800000, 0, .u32, 0xffffffff);
    try expectEvaluation(.convert_u32_f32, .u32, 0xffffffff, 0, .f32, 0x4f800000);
}

test "scalar min max follow Wasm signed zero and scalar catalog boundaries" {
    for ([_]u32{ 0, 0x80000000 }) |zero| {
        try expectEvaluation(.min, .f32, zero, 0x80000000, .f32, 0x80000000);
        try expectEvaluation(.min, .f32, 0x80000000, zero, .f32, 0x80000000);
        try expectEvaluation(.max, .f32, zero, 0, .f32, 0);
        try expectEvaluation(.max, .f32, 0, zero, .f32, 0);
    }
    try expectEvaluation(.min, .f32, 0, 0, .f32, 0);
    try expectEvaluation(.max, .f32, 0x80000000, 0x80000000, .f32, 0x80000000);
    try expectEvaluation(.min, .f32, 0xbf800000, 0x3f800000, .f32, 0xbf800000);
    try expectEvaluation(.max, .f32, 0xbf800000, 0x3f800000, .f32, 0x3f800000);
    try std.testing.expectEqual(wasm.Op.f32_min, opcode(.min, .f32).?);
    try std.testing.expectEqual(wasm.Op.f32_max, opcode(.max, .f32).?);
    try std.testing.expectEqual(wasm.Op.i32_reinterpret_f32, opcode(.bits, .f32).?);
    try std.testing.expectEqual(wasm.Op.f32_reinterpret_i32, opcode(.from_bits, .u32).?);
    try std.testing.expectEqual(@as(?wasm.Op, null), opcode(.min, .u32));
    try std.testing.expectEqual(@as(?wasm.Op, null), opcode(.max, .u32));
    try std.testing.expectEqual(@as(?wasm.Op, null), opcode(.bits, .u32));
    try std.testing.expectEqual(@as(?wasm.Op, null), opcode(.from_bits, .f32));
}
