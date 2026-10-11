//! Shared stack emission for the arena and collection helpers.
const std = @import("std");
const wasm = @import("wasm.zig");
const Error = std.mem.Allocator.Error;
pub const Local = struct { id: u32 };

// Tuple expressions are expanded while emitting instructions. They create no
// temporary expression graph or allocator traffic in the compiler.
pub const Code = struct {
    module: *wasm.Module,
    function: u32,
    pub fn op(c: Code, opcode: wasm.Op, operand: u32) Error!void {
        try c.module.emit(c.function, .{ .op = opcode, .operand = operand });
    }
    pub fn value(c: Code, x: anytype) Error!void {
        const T = @TypeOf(x);
        if (T == Local) {
            try c.op(.local_get, x.id);
        } else if (@typeInfo(T) == .int or @typeInfo(T) == .comptime_int) {
            try c.op(.i32_const, @intCast(x));
        } else switch (x[0]) {
            .global => try c.op(.global_get, x[1]),
            .load => {
                try c.value(x[1]);
                try c.op(.i32_load, x[2]);
            },
            .cell => {
                try c.value(.{ .i32_add, x[1], .{ .i32_mul, x[2], 4 } });
                try c.value(x[3]);
                try c.op(.i32_add, 0);
            },
            .call => {
                inline for (2..x.len) |i| try c.value(x[i]);
                try c.op(.call, x[1]);
            },
            else => {
                inline for (1..x.len) |i| try c.value(x[i]);
                try c.op(x[0], 0);
            },
        }
    }
    pub fn temp(c: Code) Error!Local {
        return .{ .id = try c.module.addLocal(c.function, .i32) };
    }
    pub fn set(c: Code, local: Local, x: anytype) Error!void {
        try c.value(x);
        try c.op(.local_set, local.id);
    }
    pub fn store(c: Code, address: anytype, offset: u32, x: anytype) Error!void {
        try c.value(address);
        try c.value(x);
        try c.op(.i32_store, offset);
    }
    pub fn copy(c: Code, target: anytype, source: anytype, bytes: anytype) Error!void {
        try c.value(target);
        try c.value(source);
        try c.value(bytes);
        try c.op(.memory_copy, 0);
    }
    pub fn zero(c: Code, address: anytype, bytes: anytype) Error!void {
        try c.value(address);
        try c.value(0);
        try c.value(bytes);
        try c.op(.memory_fill, 0);
    }
    pub fn when(c: Code, condition: anytype) Error!void {
        try c.value(condition);
        try c.op(.if_, 0);
    }
    pub fn end(c: Code) Error!void {
        try c.op(.end, 0);
    }
    pub fn ret(c: Code, x: anytype) Error!void {
        try c.value(x);
        try c.op(.return_, 0);
    }
    pub fn trap(c: Code, condition: anytype) Error!void {
        try c.when(condition);
        try c.op(.unreachable_, 0);
        try c.end();
    }
    pub fn loop(c: Code, condition: anytype) Error!void {
        try c.op(.block, 0);
        try c.op(.loop, 0);
        try c.value(.{ .i32_eqz, condition });
        try c.op(.br_if, 1);
    }
    pub fn again(c: Code) Error!void {
        try c.op(.br, 0);
        try c.end();
        try c.end();
    }
    pub fn next(c: Code, local: Local) Error!void {
        try c.set(local, .{ .i32_add, local, 1 });
    }
};
