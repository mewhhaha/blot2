//! Suspendable ownership journals. Counted source edges remain instance-wide;
//! only the private root stack and cancellation owner switch with a task.
//! Saved journal pages are private allocator storage, never source heap nodes.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const heap = @import("runtime_layout.zig");
const runtime = @import("../backend/runtime_code.zig");
const Code = runtime.Code;
const Local = runtime.Local;
const magic: u32 = 0x7461736b;
const fields = .{ "root_page", "root_top", "root_frame", "root_active", "root_external", "root_started", "root_host_cursor", "root_host_active" };
const bytes = (fields.len + 2) * 4;
pub const Functions = struct { create: u32, save: u32, restore: u32, drop: u32 };

fn code(module: *wasm.Module, function: u32) Code {
    return .{ .module = module, .function = function };
}
fn valid(c: Code, context: Local) !void {
    try c.trap(.{ .i32_eqz, context });
    try c.trap(.{ .i32_ne, .{ .load, context, bytes - 4 }, magic });
}
pub fn emit(module: *wasm.Module, request_owner: ?u32) !Functions {
    const arena = try module.ensureArena();
    const current = try module.addGlobal(.u32, 0, true);
    const functions: Functions = .{
        .create = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .save = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .restore = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
        .drop = try module.addTypedFunction(&.{.i32}, .i32, .scalar),
    };
    const context: Local = .{ .id = 0 };
    {
        const c = code(module, functions.create);
        // A tracer only sees the installed journal. Task roots require the
        // complete counted ownership contract before the first stack detaches.
        try c.trap(.{ .i32_ne, .{ .i32_and, .{ .global, arena.root_enabled }, 3 }, 3 });
        const fresh = try c.temp();
        try c.set(fresh, .{ .call, arena.allocate, bytes });
        try c.zero(fresh, bytes);
        try c.store(.{ .i32_sub, fresh, @sizeOf(heap.ArenaHeader) }, heap.offset(heap.ArenaHeader, "flags"), 2);
        try c.trap(.{ .i32_gt_u, context, 1 });
        if (module.host_references) |references| {
            // The allocation-free baseline precedes root_enter's marker
            // reservation, so even failed child entry preserves parent handles.
            try c.when(context);
            try c.store(fresh, 6 * 4, .{ .global, references.cursor });
            try c.store(fresh, 7 * 4, .{ .global, references.active });
            try c.end();
        }
        try c.store(fresh, bytes - 4, magic);
        try c.value(fresh);
    }
    {
        const c = code(module, functions.save);
        try valid(c, context);
        try c.trap(.{ .i32_and, .{ .global, current }, .{ .i32_ne, .{ .global, current }, context } });
        inline for (fields, 0..) |name, index| try c.store(context, index * 4, .{ .global, @field(arena, name) });
        if (request_owner) |owner| try c.store(context, fields.len * 4, .{ .global, owner });
        try c.value(context);
        try c.op(.global_set, current);
        try c.value(0);
    }
    {
        const c = code(module, functions.restore);
        try valid(c, context);
        try c.when(.{ .global, current });
        try c.value(.{ .call, functions.save, .{ .global, current } });
        try c.op(.drop, 0);
        try c.end();
        // Read before installing anything. A malformed buffer cannot replace
        // half a journal and leave the previous live stack unreachable.
        var saved: [fields.len + 1]Local = undefined;
        for (&saved, 0..) |*local, index| {
            local.* = try c.temp();
            try c.set(local.*, .{ .load, context, @as(u32, @intCast(index * 4)) });
        }
        inline for (fields, 0..) |name, index| {
            try c.value(saved[index]);
            try c.op(.global_set, @field(arena, name));
        }
        if (request_owner) |owner| {
            try c.value(saved[fields.len]);
            try c.op(.global_set, owner);
        }
        try c.value(context);
        try c.op(.global_set, current);
        try c.value(0);
    }
    {
        const c = code(module, functions.drop);
        try valid(c, context);
        try c.when(.{ .i32_eq, context, .{ .global, current } });
        try c.value(.{ .call, functions.save, context });
        try c.op(.drop, 0);
        try c.end();
        try c.trap(.{ .i32_or, .{ .load, context, 8 }, .{ .load, context, 12 } });
        const page = try c.temp();
        try c.set(page, .{ .load, context, 0 });
        try c.when(page);
        // A completed child retains at most one empty private journal page.
        // A module's persistent parent journal cannot pass this admission.
        try c.trap(.{ .i32_or, .{ .load, page, 0 }, .{ .i32_ne, .{ .load, context, 4 }, 8 } });
        try c.value(.{ .call, arena.free, page });
        try c.end();
        try c.store(context, bytes - 4, 0);
        try c.value(.{ .call, arena.free, context });
        try c.when(.{ .i32_eq, context, .{ .global, current } });
        inline for (fields) |name| {
            try c.value(0);
            try c.op(.global_set, @field(arena, name));
        }
        try c.value(0);
        try c.op(.global_set, current);
        try c.end();
        try c.value(0);
    }
    return functions;
}
