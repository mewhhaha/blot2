//! Instance-bound public leases retain checked owners outside invocation frames.
//! Tokens are scalar identities; no public entry accepts a heap address.
const w = @import("../backend/wasm.zig");
const h = @import("runtime_layout.zig");
const ir = @import("../backend/runtime_ir.zig");
const gen = @import("../backend/runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
pub const Runtime = struct { head: u32, count: u32, next: u32, publish: u32, take: u32, release: u32, token: u32 };
fn code(m: *w.Module, id: u32) Code {
    return .{ .module = m, .function = id };
}
fn global(c: Code, id: u32, value: anytype) !void {
    try c.value(value);
    try c.op(.global_set, id);
}
pub fn emit(m: *w.Module) !Runtime {
    const a = try m.ensureArena();
    if (m.start == null) {
        const initializer = try m.addTypedFunction(&.{}, .none, .scalar);
        if (m.artifacts) |journal| try journal.append(.{ .start = initializer });
        m.start = initializer;
    }
    const r: Runtime = .{
        .head = try m.addGlobal(.pointer, 0, true),
        .count = try m.addGlobal(.u32, 0, true),
        .next = try m.addGlobal(.u32, 1, true),
        .publish = try m.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .scalar),
        .take = try m.addTypedFunction(&.{ .i32, .i32, .i32, .i32 }, .i32, .reference),
        .release = try m.addTypedFunction(&.{.i32}, .none, .scalar),
        .token = try m.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .scalar),
    };
    try m.setParameterRoles(r.publish, ir.packParameterRoles(&.{ .reference, .scalar, .scalar }));
    try m.setParameterRoles(r.take, ir.packParameterRoles(&.{ .scalar, .scalar, .scalar, .scalar }));
    try m.setParameterRoles(r.release, ir.packParameterRoles(&.{.scalar}));
    try m.setParameterRoles(r.token, ir.packParameterRoles(&.{ .scalar, .scalar, .scalar }));
    {
        const c = code(m, r.publish);
        try c.trap(.{ .i32_or, .{ .i32_ge_u, .{ .global, r.count }, 4096 }, .{ .i32_eqz, .{ .global, r.next } } });
        try c.trap(.{ .i32_eqz, Local{ .id = 0 } });
        try c.trap(.{ .i32_or, .{ .i32_eqz, Local{ .id = 1 } }, .{ .i32_or, .{ .i32_eqz, Local{ .id = 2 } }, .{ .i32_gt_u, Local{ .id = 2 }, 2 } } });
        const lease = try c.temp();
        var scratch: [ir.max_annotations]w.Instruction = undefined;
        for (ir.annotations(&.{ .reference, .reference, .scalar, .scalar, .scalar }, .scalar, &scratch)) |annotation| try m.emit(r.publish, annotation);
        try c.set(lease, .{ .call, a.allocate, @sizeOf(h.PublicOwnerLease) });
        try c.store(lease, h.offset(h.PublicOwnerLease, "owner"), Local{ .id = 0 });
        try c.store(lease, h.offset(h.PublicOwnerLease, "next"), .{ .global, r.head });
        try c.store(lease, h.offset(h.PublicOwnerLease, "token"), .{ .global, r.next });
        try c.store(lease, h.offset(h.PublicOwnerLease, "schema"), Local{ .id = 1 });
        try c.store(lease, h.offset(h.PublicOwnerLease, "kind"), Local{ .id = 2 });
        try global(c, r.head, lease);
        try global(c, r.count, .{ .i32_add, .{ .global, r.count }, 1 });
        try global(c, r.next, .{ .i32_add, .{ .global, r.next }, 1 });
        try c.value(.{ .load, lease, h.offset(h.PublicOwnerLease, "token") });
    }
    {
        const c = code(m, r.take);
        const token: Local = .{ .id = 0 };
        const schema: Local = .{ .id = 1 };
        const kind: Local = .{ .id = 2 };
        const consume: Local = .{ .id = 3 };
        const node = try c.temp();
        const previous = try c.temp();
        const next = try c.temp();
        const owner = try c.temp();
        const steps = try c.temp();
        try c.trap(.{ .i32_eqz, token });
        try c.trap(.{ .i32_gt_u, consume, 1 });
        try c.set(node, .{ .global, r.head });
        try c.loop(node);
        try c.trap(.{ .i32_ge_u, steps, 4096 });
        try c.next(steps);
        try c.when(.{ .i32_eq, .{ .load, node, h.offset(h.PublicOwnerLease, "token") }, token });
        try c.trap(.{ .i32_and, .{ .i32_ne, schema, 0 }, .{ .i32_ne, .{ .load, node, h.offset(h.PublicOwnerLease, "schema") }, schema } });
        try c.trap(.{ .i32_and, .{ .i32_ne, kind, 0 }, .{ .i32_ne, .{ .load, node, h.offset(h.PublicOwnerLease, "kind") }, kind } });
        try c.set(owner, .{ .load, node, h.offset(h.PublicOwnerLease, "owner") });
        try c.trap(.{ .i32_eqz, owner });
        try c.when(consume);
        // Unlinking can retire the old list head. Keep both the lease cell and
        // its returned owner alive until this checked invocation transfers it.
        for ([_]Local{ node, owner }) |live| {
            const scope: ir.Ownership = .{ .kind = .scope, .chunk = 5, .roles = @intCast(live.id) };
            try c.op(.ownership, @bitCast(scope));
        }
        try c.set(next, .{ .load, node, h.offset(h.PublicOwnerLease, "next") });
        try c.when(previous);
        try c.value(.{ .call, a.store_word, previous, .{ .i32_add, previous, h.offset(h.PublicOwnerLease, "next") }, next });
        try c.op(.else_, 0);
        try global(c, r.head, next);
        try c.end();
        try c.value(.{ .call, a.store_word, node, node, 0 });
        try c.value(.{ .call, a.store_word, node, .{ .i32_add, node, h.offset(h.PublicOwnerLease, "next") }, 0 });
        try global(c, r.count, .{ .i32_sub, .{ .global, r.count }, 1 });
        try c.end();
        try c.ret(owner);
        try c.end();
        try c.set(previous, node);
        try c.set(node, .{ .load, node, h.offset(h.PublicOwnerLease, "next") });
        try c.again();
        try c.op(.unreachable_, 0);
    }
    {
        const c = code(m, r.release);
        try c.value(.{ .call, r.take, Local{ .id = 0 }, 0, 0, 1 });
        try c.op(.drop, 0);
    }
    {
        const c = code(m, r.token);
        try c.trap(.{ .i32_eqz, Local{ .id = 1 } });
        try c.trap(.{ .i32_or, .{ .i32_eqz, Local{ .id = 2 } }, .{ .i32_gt_u, Local{ .id = 2 }, 2 } });
        const owner = try c.temp();
        const size = try c.temp();
        const steps = try c.temp();
        try c.set(owner, .{ .call, r.take, Local{ .id = 0 }, Local{ .id = 1 }, Local{ .id = 2 }, 0 });
        try c.loop(1);
        try c.trap(.{ .i32_ge_u, steps, 128 });
        try c.next(steps);
        try c.set(size, .{ .load, .{ .i32_sub, owner, @sizeOf(h.ArenaHeader) }, h.offset(h.ArenaHeader, "requested") });
        try c.when(.{ .i32_eq, size, @sizeOf(h.Owning) });
        try c.ret(.{ .load, owner, h.offset(h.Owning, "token") });
        try c.end();
        try c.trap(.{ .i32_ne, size, @sizeOf(h.OwningView) });
        try c.set(owner, .{ .load, owner, h.offset(h.OwningView, "owner") });
        try c.trap(.{ .i32_eqz, owner });
        try c.again();
        try c.op(.unreachable_, 0);
    }
    if (m.artifacts) |journal| try journal.append(.{ .public_owners = r });
    return r;
}
