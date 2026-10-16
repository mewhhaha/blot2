//! Bounded activation cohorts. A normal leased owner holds each member until
//! its ordinary retirement; internal edges are erased only by a separate proof.
const std = @import("std");
const w = @import("../backend/wasm.zig");
const h = @import("runtime_layout.zig");
const rc = @import("shared_rc.zig");
const gen = @import("../backend/runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
const Error = std.mem.Allocator.Error;
pub const Runtime = struct { begin: u32, allocate: u32, retire_members: u32 };
pub const member: u32 = 4096;
pub const owner: u32 = 8192;
pub const capacity: u32 = 64;
const header = @sizeOf(h.ArenaHeader);
const f = struct {
    const flags = h.offset(h.ArenaHeader, "flags");
    const strong = h.offset(h.ArenaHeader, "strong");
    const next = h.offset(h.ArenaHeader, "candidate_next");
};
fn complete(c: Code, a: w.Arena) Error!void {
    try c.trap(.{ .i32_eqz, .{ .global, a.rc_enabled } });
    try c.trap(.{ .i32_ne, .{ .global, a.root_enabled }, @import("root_runtime.zig").enabled | @import("root_runtime.zig").complete });
}
fn checked(c: Code, a: w.Arena, p: Local) Error!Local {
    try c.trap(.{ .i32_lt_u, p, .{ .global, a.static_end } });
    return rc.checkedHead(c, p);
}
fn excluded() u32 {
    return @import("cycles_runtime.zig").queued | rc.dead | rc.resource_owner;
}
fn begin(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    try complete(c, a);
    const head = try checked(c, a, p);
    try c.trap(.{ .i32_and, .{ .load, head, f.flags }, excluded() | member | owner });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, rc.lease } });
    try c.trap(.{ .i32_ne, .{ .load, head, f.strong }, 1 });
    try c.trap(.{ .load, head, f.next });
    try c.store(head, f.flags, .{ .i32_or, .{ .load, head, f.flags }, owner });
}
fn allocate(c: Code, a: w.Arena) Error!void {
    const bytes: Local = .{ .id = 0 };
    const mask: Local = .{ .id = 1 };
    const parent: Local = .{ .id = 2 };
    try complete(c, a);
    const head = try checked(c, a, parent);
    try c.trap(.{ .i32_eqz, bytes });
    try c.trap(.{ .i32_and, .{ .load, head, f.flags }, excluded() | member });
    try c.trap(.{ .i32_ne, .{ .i32_and, .{ .load, head, f.flags }, owner | rc.lease }, owner | rc.lease });
    const current = try c.temp();
    const count = try c.temp();
    try c.set(current, .{ .load, head, f.next });
    try c.loop(current);
    try c.trap(.{ .i32_ge_u, count, capacity });
    const item = try checked(c, a, current);
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, item, f.flags }, member } });
    try c.set(current, .{ .load, item, f.next });
    try c.next(count);
    try c.again();
    try c.trap(.{ .i32_ge_u, count, capacity });
    const value = try c.temp();
    try c.set(value, .{ .call, a.allocate_typed, bytes, mask });
    const allocated = try c.temp();
    try c.set(allocated, .{ .i32_sub, value, header });
    // Transfer the fresh strong reference to the already-rooted owner. No
    // safepoint or owner mutation can occur before the member is linked.
    try c.store(allocated, f.flags, .{ .i32_or, .{ .i32_and, .{ .load, allocated, f.flags }, ~rc.lease }, member });
    try c.value(.{ .i32_sub, .{ .global, a.rc_leases }, 1 });
    try c.op(.global_set, a.rc_leases);
    try c.store(allocated, f.next, .{ .load, head, f.next });
    try c.store(head, f.next, value);
    try c.value(value);
}
fn retire(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    try c.when(.{ .i32_lt_u, p, .{ .global, a.static_end } });
    try c.op(.return_, 0);
    try c.end();
    const head = try checked(c, a, p);
    try c.when(.{ .i32_and, .{ .load, head, f.flags }, member });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, rc.dead } });
    try c.end();
    try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, owner } });
    try c.op(.return_, 0);
    try c.end();
    try complete(c, a);
    try c.trap(.{ .i32_and, .{ .load, head, f.flags }, excluded() | member | rc.lease });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, owner } });
    try c.trap(.{ .load, head, f.strong });
    const current = try c.temp();
    const count = try c.temp();
    try c.set(current, .{ .load, head, f.next });
    try c.loop(current);
    try c.trap(.{ .i32_ge_u, count, capacity });
    const item = try checked(c, a, current);
    try c.trap(.{ .i32_and, .{ .load, item, f.flags }, excluded() | owner | rc.lease });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, item, f.flags }, member } });
    try c.trap(.{ .i32_ne, .{ .load, item, f.strong }, 1 });
    try c.set(current, .{ .load, item, f.next });
    try c.next(count);
    try c.again();
    // Validate the complete set before changing any member's liveness.
    try c.store(head, f.flags, .{ .i32_or, .{ .load, head, f.flags }, rc.dead });
    try c.set(current, .{ .load, head, f.next });
    try c.loop(current);
    const classified = try c.temp();
    try c.set(classified, .{ .i32_sub, current, header });
    try c.store(classified, f.flags, .{ .i32_or, .{ .load, classified, f.flags }, rc.dead });
    try c.store(classified, f.strong, 0);
    try c.value(.{ .i32_add, .{ .global, a.rc_releases }, 1 });
    try c.op(.global_set, a.rc_releases);
    try c.set(current, .{ .load, classified, f.next });
    try c.again();
    try c.set(current, .{ .load, head, f.next });
    try c.store(head, f.next, 0);
    try c.loop(current);
    const next = try c.temp();
    try c.set(next, .{ .load, .{ .i32_sub, current, header }, f.next });
    try c.value(.{ .call, a.retire, current });
    try c.set(current, next);
    try c.again();
}
/// The caller owns a private module extension after ordinary Source admission.
/// Installing the helpers grants no authority to rewrite allocations or stores.
pub fn install(m: *w.Module) !Runtime {
    if (m.cohorts) |runtime| return runtime;
    const a = m.arena orelse return error.MissingArena;
    const runtime: Runtime = .{
        .begin = try m.addTypedFunction(&.{.i32}, .none, .scalar),
        .allocate = try m.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .reference),
        .retire_members = try m.addTypedFunction(&.{.i32}, .none, .scalar),
    };
    try m.setParameterRoles(runtime.begin, @import("../backend/runtime_ir.zig").packParameterRoles(&.{.reference}));
    try m.setParameterRoles(runtime.allocate, @import("../backend/runtime_ir.zig").packParameterRoles(&.{ .scalar, .scalar, .reference }));
    try m.setParameterRoles(runtime.retire_members, @import("../backend/runtime_ir.zig").packParameterRoles(&.{.reference}));
    try begin(.{ .module = m, .function = runtime.begin }, a);
    try allocate(.{ .module = m, .function = runtime.allocate }, a);
    try retire(.{ .module = m, .function = runtime.retire_members }, a);
    m.cohorts = runtime;
    return runtime;
}
