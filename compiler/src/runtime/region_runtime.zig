//! Candidate-only owner publication for a compiler-proved interior region.
//! Descriptors describe storage; installation grants no Source rewrite authority.
const std = @import("std");
const w = @import("../backend/wasm.zig");
const ir = @import("../backend/runtime_ir.zig");
const rc = @import("shared_rc.zig");
const h = @import("runtime_layout.zig");
const gen = @import("../backend/runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
const Error = std.mem.Allocator.Error;
pub const flag: u32 = 16384;
pub const Member = struct { offset: u32, bytes: u32, demand: bool = false };
pub const Plan = struct {
    frame_bytes: u32,
    bytes: u32,
    mask: u32,
    members: []const Member,
    pub fn valid(self: Plan) bool {
        if (self.frame_bytes == 0 or self.frame_bytes % 4 != 0 or self.bytes % 4 != 0 or self.bytes > 124 or self.members.len == 0 or self.members.len > 32) return false;
        var end = self.frame_bytes;
        for (self.members) |member| {
            if (member.offset < end or member.offset % 4 != 0 or member.bytes == 0 or member.bytes % 4 != 0 or member.offset > self.bytes or member.bytes > self.bytes - member.offset) return false;
            if (member.demand and member.bytes != @sizeOf(h.Demand)) return false;
            end = member.offset + member.bytes;
            for (member.offset / 4..end / 4) |word| if (self.mask & (@as(u32, 1) << @intCast(word)) != 0) return false;
        }
        return end == self.bytes and self.mask >> @intCast(self.frame_bytes / 4) == 0;
    }
};
pub const Runtime = struct {
    allocate: u32,
    project: u32,
    store: u32,
    close: u32,
    force: u32,
    force_target: u32,
    frame_allocate: u32,
    member_at: u32,
    raw_store: u32,
    pub fn contains(self: Runtime, id: usize) bool {
        inline for (@typeInfo(Runtime).@"struct".field_names) |field| if (id == @field(self, field)) return true;
        return false;
    }
};
pub const Scope = struct { function: u32, parameter: u32 };
pub const Prepared = struct {
    runtime: Runtime,
    plan: Plan,
    scopes: []const Scope,
    pub fn valid(self: Prepared, module: *const w.Module) bool {
        if (!self.plan.valid()) return false;
        const Contract = struct { id: u32, parameters: []const ir.ValueType, result: ir.ValueType, result_role: ir.Role, roles: u64 };
        const reference_pair = ir.packParameterRoles(&.{ .reference, .reference });
        const contracts = [_]Contract{
            .{ .id = self.runtime.allocate, .parameters = &.{}, .result = .i32, .result_role = .reference, .roles = 0 },
            .{ .id = self.runtime.project, .parameters = &.{ .i32, .i32 }, .result = .i32, .result_role = .reference, .roles = reference_pair },
            .{ .id = self.runtime.store, .parameters = &.{ .i32, .i32, .i32 }, .result = .none, .result_role = .scalar, .roles = ir.packParameterRoles(&.{ .scalar, .reference, .reference }) },
            .{ .id = self.runtime.close, .parameters = &.{ .i32, .i32 }, .result = .none, .result_role = .scalar, .roles = reference_pair },
            .{ .id = self.runtime.force, .parameters = &.{ .i32, .i32 }, .result = .none, .result_role = .scalar, .roles = reference_pair },
            .{ .id = self.runtime.force_target, .parameters = &.{ .i32, .i32 }, .result = .i32, .result_role = .reference, .roles = ir.packParameterRoles(&.{ .reference, .scalar }) },
            .{ .id = self.runtime.frame_allocate, .parameters = &.{.i32}, .result = .i32, .result_role = .reference, .roles = ir.packParameterRoles(&.{.scalar}) },
            .{ .id = self.runtime.member_at, .parameters = &.{ .i32, .i32 }, .result = .i32, .result_role = .reference, .roles = ir.packParameterRoles(&.{ .reference, .scalar }) },
            .{ .id = self.runtime.raw_store, .parameters = &.{ .i32, .i32, .i32 }, .result = .none, .result_role = .scalar, .roles = ir.packParameterRoles(&.{ .reference, .value, .value }) },
        };
        for (contracts, 0..) |contract, at| {
            if (contract.id >= module.functions.items.len) return false;
            for (contracts[0..at]) |previous| if (previous.id == contract.id) return false;
            const body = &module.functions.items[contract.id];
            if (body.entry or body.result != contract.result or body.result_role != contract.result_role or body.parameter_roles != contract.roles or !std.mem.eql(ir.ValueType, body.parameters, contract.parameters)) return false;
        }
        for (self.scopes, 0..) |entry, at| {
            if (entry.function >= module.functions.items.len or self.runtime.contains(entry.function)) return false;
            for (self.scopes[0..at]) |previous| if (previous.function == entry.function) return false;
            const body = &module.functions.items[entry.function];
            if (body.entry or entry.parameter != body.provider_parameter or entry.parameter >= body.parameters.len or body.parameterRole(entry.parameter) != .reference or body.parameters[entry.parameter] != .i32) return false;
        }
        return true;
    }
};
pub fn scope(module: *const w.Module, function: usize) ?Scope {
    const regions = module.regions orelse return null;
    for (regions.scopes) |entry| if (entry.function == function) return entry;
    return null;
}

fn complete(c: Code, arena: w.Arena) Error!void {
    try c.trap(.{ .i32_eqz, .{ .global, arena.rc_enabled } });
    try c.trap(.{ .i32_ne, .{ .global, arena.root_enabled }, @import("root_runtime.zig").enabled | @import("root_runtime.zig").complete });
}
fn owner(c: Code, arena: w.Arena, plan: Plan, value: Local) Error!Local {
    try complete(c, arena);
    try c.trap(.{ .i32_lt_u, value, .{ .global, arena.static_end } });
    const head = try rc.checkedHead(c, value);
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, @offsetOf(h.ArenaHeader, "flags") }, flag } });
    try c.trap(.{ .i32_and, .{ .load, head, @offsetOf(h.ArenaHeader, "flags") }, rc.dead | rc.resource_owner });
    try c.trap(.{ .i32_ne, .{ .load, head, @offsetOf(h.ArenaHeader, "requested") }, plan.bytes });
    try c.trap(.{ .i32_eqz, .{ .load, head, @offsetOf(h.ArenaHeader, "strong") } });
    return head;
}
fn demand(c: Code, plan: Plan, value: Local, parent: Local) Error!void {
    const matched = try c.temp();
    for (plan.members) |member| if (member.demand) {
        try c.set(matched, .{ .i32_or, matched, .{ .i32_eq, value, .{ .i32_add, parent, member.offset } } });
    };
    try c.trap(.{ .i32_eqz, matched });
}
fn emitAllocate(c: Code, arena: w.Arena, plan: Plan) Error!void {
    try complete(c, arena);
    const value = try c.temp();
    try c.set(value, .{ .call, arena.root_allocate, plan.bytes, plan.mask });
    if (plan.mask == 0) try c.zero(value, plan.bytes);
    const head = try c.temp();
    try c.set(head, .{ .i32_sub, value, @sizeOf(h.ArenaHeader) });
    try c.store(head, @offsetOf(h.ArenaHeader, "flags"), .{ .i32_or, .{ .load, head, @offsetOf(h.ArenaHeader, "flags") }, flag });
    try c.value(value);
}
fn emitProject(c: Code, arena: w.Arena, plan: Plan) Error!void {
    const value: Local = .{ .id = 0 };
    const parent: Local = .{ .id = 1 };
    _ = try owner(c, arena, plan, parent);
    for (plan.members) |member| {
        try c.when(.{ .i32_eq, value, .{ .i32_add, parent, member.offset } });
        try c.ret(parent);
        try c.end();
    }
    // An address inside a member is not its typed reference endpoint.
    try c.trap(.{ .i32_and, .{ .i32_ge_u, value, .{ .i32_add, parent, plan.frame_bytes } }, .{ .i32_lt_u, value, .{ .i32_add, parent, plan.bytes } } });
    try c.value(value);
}
fn emitForce(c: Code, arena: w.Arena, plan: Plan) Error!void {
    const memo: Local = .{ .id = 0 };
    const parent: Local = .{ .id = 1 };
    _ = try owner(c, arena, plan, parent);
    try demand(c, plan, memo, parent);
    const slot = try c.temp();
    try c.set(slot, .{ .call, arena.root_reserve });
    try c.value(.{ .call, arena.root_store, slot, parent });
    // The owner is published before this record can observe an evaluating Memo.
    try c.store(slot, 4, .{ .i32_or, memo, 1 });
}
fn emitForceTarget(c: Code, arena: w.Arena, plan: Plan) Error!void {
    const value: Local = .{ .id = 0 };
    const metadata: Local = .{ .id = 1 };
    try c.when(.{ .i32_lt_u, value, .{ .global, arena.static_end } });
    try c.ret(value);
    try c.end();
    const head = try rc.checkedHead(c, value);
    try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, head, @offsetOf(h.ArenaHeader, "flags") }, flag } });
    try c.ret(value);
    try c.end();
    _ = try owner(c, arena, plan, value);
    const memo = try c.temp();
    try c.set(memo, .{ .i32_and, metadata, ~@as(u32, 3) });
    try demand(c, plan, memo, value);
    try c.value(memo);
}
pub fn install(module: *w.Module, plan: Plan) !Runtime {
    if (!plan.valid()) return error.InvalidRegion;
    const arena = module.arena orelse return error.MissingArena;
    const result: Runtime = .{
        .allocate = try module.addTypedFunction(&.{}, .i32, .reference),
        .project = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .reference),
        .store = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar),
        .close = try module.addTypedFunction(&.{ .i32, .i32 }, .none, .scalar),
        .force = try module.addTypedFunction(&.{ .i32, .i32 }, .none, .scalar),
        .force_target = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .reference),
        .frame_allocate = try module.addTypedFunction(&.{.i32}, .i32, .reference),
        .member_at = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .reference),
        .raw_store = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .none, .scalar),
    };
    try module.setParameterRoles(result.project, ir.packParameterRoles(&.{ .reference, .reference }));
    try module.setParameterRoles(result.store, ir.packParameterRoles(&.{ .scalar, .reference, .reference }));
    try module.setParameterRoles(result.close, ir.packParameterRoles(&.{ .reference, .reference }));
    try module.setParameterRoles(result.force, ir.packParameterRoles(&.{ .reference, .reference }));
    try module.setParameterRoles(result.force_target, ir.packParameterRoles(&.{ .reference, .scalar }));
    try module.setParameterRoles(result.frame_allocate, ir.packParameterRoles(&.{.scalar}));
    try module.setParameterRoles(result.member_at, ir.packParameterRoles(&.{ .reference, .scalar }));
    try module.setParameterRoles(result.raw_store, ir.packParameterRoles(&.{ .reference, .value, .value }));
    const frame: Code = .{ .module = module, .function = result.frame_allocate };
    try frame.trap(.{ .i32_ne, Local{ .id = 0 }, plan.frame_bytes });
    try frame.value(.{ .call, result.allocate });
    const member: Code = .{ .module = module, .function = result.member_at };
    _ = try owner(member, arena, plan, .{ .id = 0 });
    const matched = try member.temp();
    for (plan.members) |entry| try member.set(matched, .{ .i32_or, matched, .{ .i32_eq, Local{ .id = 1 }, entry.offset } });
    try member.trap(.{ .i32_eqz, matched });
    try member.value(.{ .i32_add, Local{ .id = 0 }, Local{ .id = 1 } });
    // Only freshly intersected internal stores are rewritten to this helper.
    // Its endpoints retain their reference/value roles; no public primitive
    // or header flag authorizes a raw store.
    const raw: Code = .{ .module = module, .function = result.raw_store };
    try raw.store(Local{ .id = 1 }, 0, Local{ .id = 2 });
    try emitAllocate(.{ .module = module, .function = result.allocate }, arena, plan);
    try emitProject(.{ .module = module, .function = result.project }, arena, plan);
    try emitForce(.{ .module = module, .function = result.force }, arena, plan);
    try emitForceTarget(.{ .module = module, .function = result.force_target }, arena, plan);
    const store: Code = .{ .module = module, .function = result.store };
    try store.value(.{ .call, arena.root_store, Local{ .id = 0 }, .{ .call, result.project, Local{ .id = 1 }, Local{ .id = 2 } } });
    const close: Code = .{ .module = module, .function = result.close };
    try close.value(.{ .call, arena.root_close, .{ .call, result.project, Local{ .id = 0 }, Local{ .id = 1 } } });
    return result;
}
/// Return an owned candidate root-pop body. The original helper stays immutable.
pub fn forcePop(a: std.mem.Allocator, module: *const w.Module, runtime: Runtime) !ir.Body {
    const source = &module.functions.items[module.arena.?.root_pop];
    var body: ir.Body = .{};
    errdefer body.deinit(a);
    try body.locals.appendSlice(a, source.locals.items);
    const code = source.instructions.items;
    var loads: usize = 0;
    var stores: usize = 0;
    for (code, 0..) |inst, at| {
        try body.instructions.append(a, inst);
        if (inst.op != .local_get or at + 2 >= code.len) continue;
        const next = code[at + 1];
        const last = code[at + 2];
        const load = next.op == .i32_load and next.operand == @offsetOf(h.Demand, "status") and last.op == .i32_const and last.operand == @backingInt(h.DemandStatus.evaluating);
        const store = next.op == .i32_const and next.operand == @backingInt(h.DemandStatus.terminal) and last.op == .i32_store and last.operand == @offsetOf(h.Demand, "status");
        if (!load and !store) continue;
        // Compiler-owned pop emits page, slot and value locals in that order.
        if (inst.operand != 2) return error.UnsupportedRootPop;
        try body.emit(a, .local_get, 1);
        try body.emit(a, .i32_load, 4);
        try body.emit(a, .call, runtime.force_target);
        if (load) loads += 1;
        if (store) stores += 1;
    }
    if (loads != 1 or stores != 1) return error.UnsupportedRootPop;
    return body;
}
