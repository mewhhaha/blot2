//! Numeric arrays cross the host boundary by copy. The existing wire format
//! is one length word followed by scalar words; no application pointer crosses
//! this boundary. Transport scratch is independent of every data-stack owner.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const Code = @import("../backend/runtime_code.zig").Code;
const Local = @import("../backend/runtime_code.zig").Local;
pub const Runtime = struct { allocate: u32, reset: u32, length: u32, base: u32, end: u32, top: u32 };

/// The planner reserves transport separately from application owners. Patch the
/// globals only after the complete region layout and memory budget are known.
pub fn configure(module: *wasm.Module, runtime: Runtime, base: u32, capacity: u32) error{InvalidTransportRegion}!void {
    const end: u64 = @as(u64, base) + capacity;
    if (base == 0 or capacity < 4 or (base | capacity) & 3 != 0 or end > module.fixed_memory_bytes) return error.InvalidTransportRegion;
    module.globals.items[runtime.base].bits = base;
    module.globals.items[runtime.end].bits = @intCast(end);
    module.globals.items[runtime.top].bits = base;
}

pub fn emit(module: *wasm.Module) !Runtime {
    std.debug.assert(module.arena == null and module.array_transport == null);
    const runtime: Runtime = .{
        .allocate = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .reset = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .length = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .base = try module.addGlobal(.u32, 0, false),
        .end = try module.addGlobal(.u32, 0, false),
        .top = try module.addGlobal(.u32, 0, true),
    };
    {
        const c: Code = .{ .module = module, .function = runtime.allocate };
        const bytes: Local = .{ .id = 0 };
        const address = try c.temp();
        try c.trap(.{ .i32_or, .{ .i32_eqz, bytes }, .{ .i32_and, bytes, 3 } });
        try c.trap(.{ .i32_gt_u, bytes, .{ .i32_sub, .{ .global, runtime.end }, .{ .global, runtime.top } } });
        try c.set(address, .{ .global, runtime.top });
        try c.zero(address, bytes);
        try c.value(.{ .i32_add, address, bytes });
        try c.op(.global_set, runtime.top);
        try c.value(address);
    }
    {
        const c: Code = .{ .module = module, .function = runtime.reset };
        try c.value(.{ .global, runtime.base });
        try c.op(.global_set, runtime.top);
        try c.value(0);
    }
    {
        const c: Code = .{ .module = module, .function = runtime.length };
        const address: Local = .{ .id = 0 };
        const length = try c.temp();
        try c.trap(.{ .i32_or, .{ .i32_lt_u, address, .{ .global, runtime.base } }, .{ .i32_and, address, 3 } });
        try c.trap(.{ .i32_gt_u, address, .{ .global, runtime.top } });
        try c.trap(.{ .i32_lt_u, .{ .i32_sub, .{ .global, runtime.top }, address }, 4 });
        try c.set(length, .{ .load, address, 0 });
        try c.trap(.{ .i32_gt_u, length, .{ .i32_div_u, .{ .i32_sub, .{ .i32_sub, .{ .global, runtime.top }, address }, 4 }, 4 } });
        try c.value(length);
    }
    module.array_transport = .{ .allocate = runtime.allocate, .reset = runtime.reset };
    return runtime;
}
