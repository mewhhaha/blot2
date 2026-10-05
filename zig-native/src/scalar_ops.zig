//! One scalar operation contract for typed-IR evaluation and Wasm lowering.
const std = @import("std");
const core = @import("core.zig");
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
        .convert_u32_f32 => .f32_convert_i32_u,
        .convert_f32_u32 => .i32_trunc_sat_f32_u,
        .none, .and_, .or_ => null,
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
            break :blk if (machine_op == .i32_div_u) a.bits / b.bits else a.bits % b.bits;
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
        .f32_abs => @bitCast(@abs(x)),
        .f32_neg => @bitCast(-x),
        .f32_ceil => @bitCast(@ceil(x)),
        .f32_floor => @bitCast(@floor(x)),
        .f32_trunc => @bitCast(@trunc(x)),
        .f32_sqrt => @bitCast(@sqrt(x)),
        .f32_convert_i32_u => @bitCast(@as(f32, @floatFromInt(a.bits))),
        .i32_trunc_sat_f32_u => if (std.math.isNan(x) or x <= 0) 0 else if (x >= 4294967296.0) std.math.maxInt(u32) else @intFromFloat(x),
        else => return error.Unsupported,
    };
    const scalar: wasm.Scalar = switch (op) {
        .equal, .not_equal, .less, .less_equal, .greater, .greater_equal => .bool,
        .convert_u32_f32 => .f32,
        .convert_f32_u32 => .u32,
        else => a.scalar,
    };
    return .{ .scalar = scalar, .bits = bits };
}

test "scalar evaluation matches wrapping and signed-zero contracts" {
    const wrapped = try evaluate(.add, .{ .scalar = .u32, .bits = 0xffffffff }, .{ .scalar = .u32, .bits = 1 });
    try std.testing.expectEqual(@as(u32, 0), wrapped.bits);
    try std.testing.expectError(error.IntegerDivideByZero, evaluate(.div, .{ .scalar = .u32, .bits = 1 }, .{ .scalar = .u32, .bits = 0 }));
    const negative_zero = try evaluate(.neg, .{ .scalar = .f32, .bits = 0 }, .{ .scalar = .unit, .bits = 0 });
    try std.testing.expectEqual(@as(u32, 0x80000000), negative_zero.bits);
    const nan = try evaluate(.convert_f32_u32, .{ .scalar = .f32, .bits = 0x7fc00000 }, .{ .scalar = .unit, .bits = 0 });
    try std.testing.expectEqual(@as(u32, 0), nan.bits);
}
