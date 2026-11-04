//! Physical callable construction endpoints. Layout IDs belong to the emission's
//! owned layout graph; they are neither ABI identities nor dispatch authority.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
/// Initial field origin, not an owned heap identity. A local must be resolved at
/// this construction point; a data word belongs to the emission's static data.
pub const Environment = union(enum) { zero, local: u32, data_word: u32 };
pub const Construction = struct {
    target: u32,
    kind: ir.TableKind,
    layout: u32,
    bytes: u32,
    local: ?u32 = null,
    allocation: ?usize = null,
    /// Exclusive instruction index, or byte offset for static data.
    end: usize,
    environment: Environment,
};
/// Rederive the constructor and exact environment input from current body/data.
/// This describes creation only: later writes, calls and escapes
/// need an independent heap-flow proof. It grants no dispatch or retirement.
pub fn construction(module: *const wasm.Module, origin: wasm.Module.TableOrigin) ?Construction {
    if (origin.kind == .unknown or origin.target >= module.functions.items.len or module.runtimeHelper(origin.target)) return null;
    const target = &module.functions.items[origin.target];
    if (target.callable_layout == 0 or target.callable_layout >= 1 << 26 or target.entry) return null;
    const environment_role = target.parameterRole(0);
    if (environment_role != .reference and environment_role != .scalar) return null;
    if (origin.kind == .demand and environment_role != .reference) return null;
    const bytes: u32 = if (origin.kind == .callable) 8 else 16;
    var result: Construction = .{ .target = origin.target, .kind = origin.kind, .layout = target.callable_layout, .bytes = bytes, .end = 0, .environment = .zero };
    if (origin.function) |id| {
        if (id >= module.functions.items.len) return null;
        const arena = module.arena orelse return null;
        const body = &module.functions.items[id];
        const code = body.instructions.items;
        if (code.len > 4096) return null;
        const at = origin.place;
        if (at == 0 or at + 1 >= code.len or code[at].op != .i32_const or !code[at].table_reference or code[at].table_kind != origin.kind or code[at].operand != origin.target or code[at - 1].op != .local_get or code[at + 1].op != .i32_store or code[at + 1].operand != 0) return null;
        const local = code[at - 1].operand;
        if (local < body.parameters.len or local >= body.parameters.len + body.locals.items.len) return null;
        if (body.locals.items[local - body.parameters.len] != .i32) return null;
        var allocation: ?usize = null;
        for (code, 0..) |inst, point| {
            if ((inst.op != .local_set and inst.op != .local_tee) or inst.operand != local) continue;
            if (allocation != null or inst.op != .local_set or point < 2 or point >= at or code[point - 1].op != .call or code[point - 1].operand != arena.allocate) return null;
            allocation = point - 1;
        }
        const alloc = allocation orelse return null;
        if (at != alloc + 3 or code[alloc - 1].op != .i32_const or code[alloc - 1].operand != bytes) return null;
        const roles = ir.allocationAnnotations(code, alloc);
        if (ir.Ownership.wordRole(roles, 0) != .scalar or ir.Ownership.wordRole(roles, 1) != environment_role) return null;
        if (origin.kind == .demand and (ir.Ownership.wordRole(roles, 2) != .scalar or ir.Ownership.wordRole(roles, 3) != target.result_role)) return null;
        var point = at + 2;
        for (1..bytes / 4) |word| {
            if (point + 2 >= code.len or code[point].op != .local_get or code[point].operand != local or code[point + 2].op != .i32_store or code[point + 2].operand != word * 4) return null;
            const value = code[point + 1];
            if (word == 1) {
                if (value.op == .i32_const) {
                    if (value.operand != 0 or value.table_reference) return null;
                } else if (value.op == .local_get) {
                    if (value.operand == local or value.operand >= body.parameters.len + body.locals.items.len) return null;
                    if (value.operand < body.parameters.len) {
                        if (body.parameters[value.operand] != .i32 or body.parameterRole(value.operand) != environment_role) return null;
                    } else if (body.locals.items[value.operand - body.parameters.len] != .i32) return null;
                    result.environment = .{ .local = value.operand };
                } else return null;
            } else if (value.op != .i32_const or value.operand != 0 or value.table_reference) return null;
            point += 3;
        }
        result.local = local;
        result.allocation = alloc;
        result.end = point;
    } else {
        if (origin.place % 4 != 0 or origin.place > module.data.items.len or bytes > module.data.items.len - origin.place) return null;
        if (std.mem.readInt(u32, module.data.items[origin.place..][0..4], .little) != origin.target) return null;
        for (module.static_fields.items) |field| if (field & ~@as(u32, 3) == origin.place) return null;
        result.environment = .{ .data_word = origin.place + 4 };
        result.end = origin.place + bytes;
    }
    return result;
}
pub fn constructionLayout(module: *const wasm.Module, origin: wasm.Module.TableOrigin) ?u32 {
    return (construction(module, origin) orelse return null).layout;
}

/// Complete straight-line factory result, including its retained input edge.
/// This is not a borrowing summary: the new descriptor owns its environment.
/// It permits graph composition, never replacement of a later code read.
pub fn resultConstruction(module: *const wasm.Module, id: u32) ?Construction {
    if (id >= module.functions.items.len or module.runtimeHelper(id) or module.table_origins.items.len > 128) return null;
    const body = &module.functions.items[id];
    const code = body.instructions.items;
    if (body.entry or body.result != .i32 or body.result_role != .reference or body.parameters.len > 16 or body.locals.items.len != 1 or code.len > 32) return null;
    for (module.table_origins.items) |origin| {
        if (origin.function != id or origin.kind == .unknown) continue;
        const fact = construction(module, origin) orelse continue;
        if (fact.local.? != body.parameters.len) continue;
        const allocation = fact.allocation.?;
        for (code[0 .. allocation - 1]) |inst| {
            if (inst.op != .ownership) return null;
            const marker: ir.Ownership = @bitCast(inst.operand);
            if (marker.kind == .scope or marker.kind == .call_result) return null;
        }
        switch (fact.environment) {
            .zero => {},
            .local => |local| if (local >= body.parameters.len) return null,
            .data_word => return null,
        }
        if (fact.end >= code.len or code[fact.end].op != .local_get or code[fact.end].operand != fact.local.?) return null;
        const tail = code[fact.end + 1 ..];
        if (tail.len != 0 and (tail.len != 1 or tail[0].op != .return_)) return null;
        return fact;
    }
    return null;
}

fn environmentRoles(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const target = try module.addTypedFunction(&.{ .i32, .i32, .i32 }, .i32, .scalar);
    try module.setParameterRoles(target, ir.packParameterRoles(&.{ .scalar, .scalar, .reference }));
    try module.setCallableLayout(target, 3);
    try module.emit(target, .{ .op = .local_get, .operand = 1 });
    const factory = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.setParameterRoles(factory, ir.packParameterRoles(&.{.scalar}));
    const local = try module.addLocal(factory, .i32);
    var buffer: [ir.max_annotations]ir.Instruction = undefined;
    try module.emitSlice(factory, ir.annotations(&.{ .scalar, .scalar }, .scalar, &buffer));
    try module.emitSlice(factory, &.{ .{ .op = .i32_const, .operand = 8 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local }, .{ .op = .local_get, .operand = local } });
    try module.emitReference(factory, .{ .op = .i32_const, .operand = target }, .callable_function);
    try module.emitSlice(factory, &.{ .{ .op = .i32_store }, .{ .op = .local_get, .operand = local }, .{ .op = .local_get }, .{ .op = .i32_store, .operand = 4 }, .{ .op = .local_get, .operand = local } });
    const origin = module.table_origins.items[module.table_origins.items.len - 1];
    const fact = construction(&module, origin) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(target, fact.target);
    try std.testing.expectEqual(Environment{ .local = 0 }, fact.environment);
    for ([_]ir.Role{ .reference, .unknown, .value }) |role| {
        try module.setParameterRoles(target, ir.packParameterRoles(&.{ role, .scalar, .reference }));
        try std.testing.expect(construction(&module, origin) == null);
    }
    try module.setParameterRoles(target, ir.packParameterRoles(&.{ .scalar, .scalar, .reference }));
    const scalar = module.functions.items[factory].instructions.items[0];
    module.functions.items[factory].instructions.items[0] = ir.annotations(&.{ .scalar, .reference }, .scalar, &buffer)[0];
    try std.testing.expect(construction(&module, origin) == null);
    try module.setParameterRoles(target, ir.packParameterRoles(&.{ .reference, .scalar, .reference }));
    try std.testing.expect(construction(&module, origin) == null);
    try module.setParameterRoles(factory, ir.packParameterRoles(&.{.reference}));
    try std.testing.expect(construction(&module, origin) != null);
    module.functions.items[factory].instructions.items[0] = scalar;
    try std.testing.expect(construction(&module, origin) == null);
}
test "callable environment construction requires matching input header and target roles through OOM" {
    try environmentRoles(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, environmentRoles, .{});
}
