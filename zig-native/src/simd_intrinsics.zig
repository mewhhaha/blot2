//! Fixed-width operations on ordinary four-scalar products. Their source type
//! is transparent; only these explicit compiler operations request SIMD.
const std = @import("std");
const core = @import("core.zig");
pub const Intrinsic = struct { op: core.Op, arity: u8, floating: bool, conversion: bool = false };
pub fn lookup(name: []const u8) ?Intrinsic {
    const floating = std.mem.startsWith(u8, name, "@simd.f32x4.");
    if (!floating and !std.mem.startsWith(u8, name, "@simd.u32x4.")) return null;
    const member = name[12..];
    inline for (.{ .{ "add", core.Op.add }, .{ "sub", core.Op.sub }, .{ "mul", core.Op.mul } }) |entry|
        if (std.mem.eql(u8, member, entry[0])) return .{ .op = entry[1], .arity = 2, .floating = floating };
    if (floating) {
        if (std.mem.eql(u8, member, "div")) return .{ .op = .div, .arity = 2, .floating = true };
        inline for (.{ .{ "abs", core.Op.abs }, .{ "neg", core.Op.neg }, .{ "ceil", core.Op.ceil }, .{ "floor", core.Op.floor }, .{ "trunc", core.Op.trunc }, .{ "sqrt", core.Op.sqrt } }) |entry|
            if (std.mem.eql(u8, member, entry[0])) return .{ .op = entry[1], .arity = 1, .floating = true };
        if (std.mem.eql(u8, member, "to_u32")) return .{ .op = .convert_f32_u32, .arity = 1, .floating = true, .conversion = true };
    } else {
        inline for (.{ .{ "bit_and", core.Op.bit_and }, .{ "bit_or", core.Op.bit_or }, .{ "bit_xor", core.Op.bit_xor } }) |entry|
            if (std.mem.eql(u8, member, entry[0])) return .{ .op = entry[1], .arity = 2, .floating = false };
        if (std.mem.eql(u8, member, "to_f32")) return .{ .op = .convert_u32_f32, .arity = 1, .floating = false, .conversion = true };
    }
    return null;
}
