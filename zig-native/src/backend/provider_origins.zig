//! Checked source provider-frame construction facts. These survive body replay;
//! they grant no operation specialization without complete frame-flow coverage.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const heap = @import("../runtime/runtime_layout.zig");

pub const begin_chunk = 8;
pub const end_chunk = 9;
pub const Fact = struct {
    local: u32,
    kind: u32,
    value_role: ir.Role,
    value_machine: ir.ValueType,
    read: u32,
    write: ?u32,
    allocation: usize,
    end: usize,
};
fn marker(inst: ir.Instruction, chunk: u4) ?u26 {
    if (inst.op != .ownership) return null;
    const fact: ir.Ownership = @bitCast(inst.operand);
    if (fact.kind != .rest or fact.chunk != chunk) return null;
    return fact.roles;
}
fn operation(instructions: []const ir.Instruction, at: usize) ?u32 {
    if (at + 1 >= instructions.len or instructions[at].op != .i32_const or instructions[at].table_reference or instructions[at].operand == 0 or instructions[at + 1].op != .drop) return null;
    return instructions[at].operand;
}
pub fn frameBytes(kind: u32) ?u32 {
    return switch (kind) {
        0 => @sizeOf(heap.ProviderFrame),
        3 => @sizeOf(heap.RequestFrame),
        4 => @sizeOf(heap.StateFrame),
        5 => @sizeOf(heap.ScopedStateFrame),
        6 => @sizeOf(heap.ScopedFrame),
        7 => @sizeOf(heap.ScopedRequestFrame),
        else => null,
    };
}
fn wordRole(kind: u32, value: ir.Role, word: usize) ir.Role {
    if (word == 0 or word == 3) return .scalar;
    if (word == 1) return value;
    if ((kind == 4 or kind == 5) and word == 4) return .scalar;
    return .reference;
}
/// A bounded exact initializer must allocate its own local once, describe every
/// field, initialize every word once, and publish the matching immutable kind.
/// Host/source calls, aliases, incomplete stores and forged roles decline.
pub fn constructor(module: *const wasm.Module, body: *const ir.Function, at: usize) ?Fact {
    const instructions = body.instructions.items;
    if (at >= instructions.len) return null;
    const local = marker(instructions[at], begin_chunk) orelse return null;
    if (local < body.parameters.len or local >= body.parameters.len + body.locals.items.len) return null;
    const read = operation(instructions, at + 1) orelse return null;
    var finish = at + 3;
    var write: ?u32 = null;
    if (finish < instructions.len and marker(instructions[finish], end_chunk) == null) {
        write = operation(instructions, finish) orelse return null;
        finish += 2;
    }
    if (finish >= instructions.len) return null;
    const encoded = marker(instructions[finish], end_chunk) orelse return null;
    if (encoded >> 5 != 0) return null;
    const kind: u32 = encoded & 7;
    const role: ir.Role = @fromBackingInt(@as(u2, @truncate(encoded >> 3)));
    if (role != .scalar and role != .reference) return null;
    if ((kind == 4 or kind == 5) != (write != null)) return null;
    if (kind != 4 and kind != 5 and role != .reference) return null;
    const bytes = frameBytes(kind) orelse return null;
    const arena = module.arena orelse return null;
    var allocation: ?usize = null;
    for (instructions[0..at], 0..) |inst, index| {
        if ((inst.op != .local_set and inst.op != .local_tee) or inst.operand != local) continue;
        if (allocation != null or inst.op != .local_set or index < 2 or instructions[index - 1].op != .call or (instructions[index - 1].operand != arena.allocate and (module.regions == null or instructions[index - 1].operand != module.regions.?.runtime.frame_allocate or bytes != module.regions.?.plan.frame_bytes)) or instructions[index - 2].op != .i32_const or instructions[index - 2].operand != bytes) return null;
        const roles = ir.allocationAnnotations(instructions, index - 1);
        if (roles.len == 0) return null;
        for (0..bytes / 4) |word| if (ir.Ownership.wordRole(roles, word) != wordRole(kind, role, word)) return null;
        allocation = index - 1;
    }
    const allocated = allocation orelse return null;
    if (at - allocated > 96) return null;
    const Value = struct { frame: bool = false, constant: ?u32 = null, machine: ir.ValueType = .i32 };
    var stack: [16]Value = undefined;
    var height: usize = 0;
    var fields: u32 = 0;
    var value_machine: ir.ValueType = .i32;
    for (instructions[allocated + 2 .. at]) |inst| switch (inst.op) {
        .local_get => {
            if (height == stack.len or inst.operand >= body.parameters.len + body.locals.items.len) return null;
            const machine = if (inst.operand < body.parameters.len) body.parameters[inst.operand] else body.locals.items[inst.operand - body.parameters.len];
            stack[height] = .{ .frame = inst.operand == local, .machine = machine };
            height += 1;
        },
        .i32_const, .f32_const => {
            if (height == stack.len or inst.table_reference) return null;
            stack[height] = .{ .constant = inst.operand, .machine = if (inst.op == .f32_const) .f32 else .i32 };
            height += 1;
        },
        .i32_load, .f32_load => {
            if (height == 0 or stack[height - 1].frame) return null;
            if (stack[height - 1].machine != .i32) return null;
            stack[height - 1] = .{ .machine = if (inst.op == .f32_load) .f32 else .i32 };
        },
        .i32_store, .f32_store => {
            if (height < 2 or !stack[height - 2].frame or inst.operand % 4 != 0 or inst.operand >= bytes) return null;
            const bit = @as(u32, 1) << @intCast(inst.operand / 4);
            if (fields & bit != 0) return null;
            const stored = stack[height - 1];
            if (stored.frame) return null;
            const machine: ir.ValueType = if (inst.op == .f32_store) .f32 else .i32;
            if (stack[height - 2].machine != .i32 or stored.machine != machine) return null;
            if (machine == .f32 and (inst.operand != 4 or role != .scalar or (kind != 4 and kind != 5))) return null;
            if (inst.operand == 4) value_machine = machine;
            if (inst.operand == 0 and (stored.constant == null or stored.constant.? != read)) return null;
            if ((kind == 4 or kind == 5) and inst.operand == heap.offset(heap.StateFrame, "write") and (stored.constant == null or stored.constant.? != write.?)) return null;
            if (inst.operand == heap.offset(heap.ProviderFrame, "kind") and (inst.op != .i32_store or stack[height - 1].constant == null or stack[height - 1].constant.? != kind)) return null;
            fields |= bit;
            height -= 2;
        },
        .ownership => {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .scope or fact.kind == .call_result) return null;
        },
        else => return null,
    };
    if (height != 0 or fields != (@as(u32, 1) << @intCast(bytes / 4)) - 1) return null;
    return .{ .local = local, .kind = kind, .value_role = role, .value_machine = value_machine, .read = read, .write = write, .allocation = allocated, .end = finish };
}

fn constructionScenario(a: std.mem.Allocator) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const id = try module.addTypedFunction(&.{ .i32, .i32 }, .i32, .scalar);
    try module.setParameterRoles(id, ir.packParameterRoles(&.{ .reference, .reference }));
    try module.setProviderParameter(id, 1);
    const local = try module.addLocal(id, .i32);
    var annotations: [ir.max_annotations]ir.Instruction = undefined;
    const first = module.functions.items[id].instructions.items.len;
    try module.emitSlice(id, ir.annotations(&.{ .scalar, .reference, .reference, .scalar, .scalar }, .unknown, &annotations));
    try module.emitSlice(id, &.{ .{ .op = .i32_const, .operand = 20 }, .{ .op = .call, .operand = arena.allocate }, .{ .op = .local_set, .operand = local } });
    for (0..5) |word| {
        try module.emit(id, .{ .op = .local_get, .operand = local });
        if (word == 0 or word == 4) {
            try module.emit(id, .{ .op = .i32_const, .operand = if (word == 0) 3 else 4 });
        } else if (word == 3) {
            try module.emit(id, .{ .op = .i32_const, .operand = 4 });
        } else if (word == 2) {
            try module.emit(id, .{ .op = .local_get, .operand = 1 });
        } else {
            try module.emit(id, .{ .op = .local_get });
            try module.emit(id, .{ .op = .i32_load, .operand = @intCast(word * 4) });
        }
        try module.emit(id, .{ .op = .i32_store, .operand = @intCast(word * 4) });
    }
    const at = module.functions.items[id].instructions.items.len;
    try module.emitSlice(id, &.{
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .rest, .chunk = begin_chunk, .roles = @intCast(local) }) },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .drop },
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .drop },
        .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .rest, .chunk = end_chunk, .roles = 4 | @as(u26, @backingInt(ir.Role.reference)) << 3 }) },
        .{ .op = .i32_const },
    });
    const body = &module.functions.items[id];
    const fact = constructor(&module, body, at).?;
    try std.testing.expectEqual(local, fact.local);
    try std.testing.expectEqual(@as(u32, 4), fact.kind);
    try std.testing.expectEqual(@as(?u32, 4), fact.write);
    const before = try a.dupe(ir.Instruction, body.instructions.items);
    defer a.free(before);
    // A type edit, forged local, absent field or changed initializer must not
    // turn the same machine words into private State-frame authority.
    body.instructions.items[first].operand = @bitCast(ir.Ownership{ .kind = .words, .roles = @backingInt(ir.Role.scalar) | @as(u26, @backingInt(ir.Role.scalar)) << 2 | @as(u26, @backingInt(ir.Role.reference)) << 4 | @as(u26, @backingInt(ir.Role.scalar)) << 6 | @as(u26, @backingInt(ir.Role.scalar)) << 8 });
    try std.testing.expect(constructor(&module, body, at) == null);
    body.instructions.items[first] = before[first];
    body.instructions.items[at].operand = @bitCast(ir.Ownership{ .kind = .rest, .chunk = begin_chunk, .roles = 1 });
    try std.testing.expect(constructor(&module, body, at) == null);
    body.instructions.items[at] = before[at];
    for (body.instructions.items[fact.allocation + 2 .. at], fact.allocation + 2..) |*inst, index| if (inst.op == .i32_store and inst.operand == 12) {
        body.instructions.items[index - 1].operand = 0;
        try std.testing.expect(constructor(&module, body, at) == null);
        body.instructions.items[index - 1] = before[index - 1];
        break;
    };
    body.instructions.items[at + 1].table_reference = true;
    try std.testing.expect(constructor(&module, body, at) == null);
    body.instructions.items[at + 1] = before[at + 1];
    for (body.instructions.items[fact.allocation + 2 .. at], fact.allocation + 2..) |inst, index| if (inst.op == .i32_store and inst.operand == 0) {
        body.instructions.items[index - 1].operand = 17;
        try std.testing.expect(constructor(&module, body, at) == null);
        body.instructions.items[index - 1] = before[index - 1];
        break;
    };
    try std.testing.expectEqualSlices(ir.Instruction, before, body.instructions.items);
}
test "provider construction facts require exact allocation roles locals complete initialization and kind through OOM" {
    const immortal: ir.Ownership = @bitCast(ir.immortalReference().operand);
    try std.testing.expectEqual(immortal, immortal.relocated(32));
    const carrier: ir.Ownership = @bitCast(ir.journalCarrier().operand);
    try std.testing.expectEqual(carrier, carrier.relocated(32));
    try constructionScenario(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, constructionScenario, .{});
}
