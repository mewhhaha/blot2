//! Exact operation modes over every private checked source provider frame.
//! A completed flow proof grants authority; retained matching compares the
//! complete catalog, including collisions and opaque callback/request routes.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const origins = @import("provider_origins.zig");
const A = std.mem.Allocator;
pub const Access = enum { unsupported, read, write };
pub const Mode = struct { operation: u32, access: Access, role: ir.Role, machine: ir.ValueType };
pub const Catalog = struct {
    entries: std.ArrayList(Mode) = .empty,
    saturated: bool = false,
    pub fn deinit(self: *Catalog, a: A) void {
        self.entries.deinit(a);
    }
    pub fn init(a: A, module: *const wasm.Module) A.Error!Catalog {
        return try initMode(a, module, false) orelse .{};
    }
    /// The stronger fresh flow includes ordinary provider validity and also
    /// proves activation heads remain protected for the entire call.
    pub fn initProtected(a: A, module: *const wasm.Module) A.Error!?Catalog {
        return initMode(a, module, true);
    }
    fn initMode(a: A, module: *const wasm.Module, comptime protected: bool) A.Error!?Catalog {
        var result: Catalog = .{};
        errdefer result.deinit(a);
        var found = false;
        for (module.functions.items) |body| for (body.instructions.items) |inst| {
            if (inst.op != .ownership) continue;
            const marker: ir.Ownership = @bitCast(inst.operand);
            if (marker.kind == .rest and marker.chunk == origins.begin_chunk) found = true;
        };
        if (!found) return null;
        if (protected) {
            if (!try @import("provider_flow.zig").protectedActivations(a, module)) return null;
        } else if (!try @import("provider_flow.zig").complete(a, module)) return null;
        for (module.functions.items) |*body| for (body.instructions.items, 0..) |inst, at| {
            if (inst.op != .ownership) continue;
            const mark: ir.Ownership = @bitCast(inst.operand);
            if (mark.kind != .rest or mark.chunk != origins.begin_chunk) continue;
            const fact = origins.constructor(module, body, at).?;
            try result.add(a, .{ .operation = fact.read, .access = if (fact.kind == 4 and fact.write != fact.read) .read else .unsupported, .role = fact.value_role, .machine = fact.value_machine });
            if (fact.write) |operation| try result.add(a, .{ .operation = operation, .access = if (fact.kind == 4 and fact.read != operation) .write else .unsupported, .role = fact.value_role, .machine = fact.value_machine });
        };
        std.mem.sort(Mode, result.entries.items, {}, less);
        return result;
    }
    fn less(_: void, left: Mode, right: Mode) bool {
        return left.operation < right.operation;
    }
    fn add(self: *Catalog, a: A, mode: Mode) A.Error!void {
        if (self.saturated) return;
        for (self.entries.items) |*existing| if (existing.operation == mode.operation) {
            if (!std.meta.eql(existing.*, mode)) existing.* = .{ .operation = mode.operation, .access = .unsupported, .role = .unknown, .machine = .none };
            return;
        };
        // Optional proof work stays bounded; saturated catalogs authorize none.
        if (self.entries.items.len == 4096) {
            self.entries.clearRetainingCapacity();
            self.saturated = true;
            return;
        }
        try self.entries.append(a, mode);
    }
    fn lookup(self: *const Catalog, operation: u32) ?Mode {
        for (self.entries.items) |item| if (item.operation == operation) return item;
        return null;
    }
};
fn exact(inst: ir.Instruction, op: ir.Op, operand: u32) bool {
    return inst.op == op and inst.operand == operand and !inst.table_reference;
}
const Lookup = struct { mode: Mode, local: u32 };
const Expected = struct { op: ir.Op, operand: u32 = 0 };
fn match(code: []const ir.Instruction, expected: []const Expected) bool {
    if (code.len < expected.len) return false;
    for (expected, code[0..expected.len]) |want, inst| if (!exact(inst, want.op, want.operand)) return false;
    return true;
}
/// Shared checked lookup, including null/kind/operation guards and next links.
fn lookup(catalog: *const Catalog, source: *const ir.Function, comptime access: Access) ?Lookup {
    if (source.entry or source.provider_parameter != 2 or source.parameters.len != 3 or source.parameters[0] != .i32 or source.parameters[2] != .i32) return null;
    if (access == .read and (source.parameters[1] != .i32 or source.parameter_roles != ir.packParameterRoles(&.{ .reference, .scalar, .reference }))) return null;
    const code = source.instructions.items;
    if (code.len < 50 or code.len > 4096 or code[1].op != .local_set or code[11].op != .i32_const or code[11].table_reference) return null;
    const selected = catalog.lookup(code[11].operand) orelse return null;
    if (selected.access != access or (selected.machine != .i32 and selected.machine != .f32)) return null;
    switch (access) {
        .read => if (selected.role != source.result_role or selected.machine != source.result) return null,
        .write => if ((selected.role != .scalar and selected.role != .reference) or source.parameters[1] != selected.machine or source.parameter_roles != ir.packParameterRoles(&.{ .reference, selected.role, .reference }) or source.result != .i32 or source.result_role != .scalar) return null,
        .unsupported => return null,
    }
    const local = code[1].operand;
    if (local < source.parameters.len or local >= source.parameters.len + source.locals.items.len or source.locals.items[local - source.parameters.len] != .i32) return null;
    if (!match(code, &.{
        .{ .op = .local_get, .operand = 2 },     .{ .op = .local_set, .operand = local },              .{ .op = .block },                       .{ .op = .loop },
        .{ .op = .local_get, .operand = local }, .{ .op = .i32_eqz },                                  .{ .op = .if_ },                         .{ .op = .unreachable_ },
        .{ .op = .end },                         .{ .op = .local_get, .operand = local },              .{ .op = .i32_load },                    .{ .op = .i32_const, .operand = selected.operation },
        .{ .op = .i32_eq },                      .{ .op = .br_if, .operand = 1 },                      .{ .op = .local_get, .operand = local }, .{ .op = .i32_load, .operand = 12 },
        .{ .op = .i32_const, .operand = 4 },     .{ .op = .i32_eq },                                   .{ .op = .if_ },                         .{ .op = .local_get, .operand = local },
        .{ .op = .i32_load, .operand = 16 },     .{ .op = .i32_const, .operand = selected.operation }, .{ .op = .i32_eq },                      .{ .op = .br_if, .operand = 2 },
        .{ .op = .end },                         .{ .op = .local_get, .operand = local },              .{ .op = .i32_load, .operand = 8 },      .{ .op = .local_set, .operand = local },
        .{ .op = .br },                          .{ .op = .end },                                      .{ .op = .end },
    })) return null;
    return .{ .mode = selected, .local = local };
}
fn alternative(code: []const ir.Instruction) bool {
    var depth: usize = 1;
    for (code, 0..) |inst, at| switch (inst.op) {
        .block, .loop, .if_ => depth += 1,
        .end => {
            if (depth == 0) return false;
            depth -= 1;
            if (depth == 0 and at + 1 != code.len) return false;
        },
        else => {},
    };
    return depth == 0;
}
/// Match the complete checked, unscoped operation lookup and State read arm.
/// Its opaque alternative ends at the function exit and is impossible under
/// the global read-only mode. All original lookup guards and traps remain.
pub fn readOperation(catalog: *const Catalog, source: *const ir.Function) ?Mode {
    const found = lookup(catalog, source, .read) orelse return null;
    const selected = found.mode;
    const local = found.local;
    const code = source.instructions.items;
    if (!match(code[31..], &.{
        .{ .op = .local_get, .operand = local },                .{ .op = .i32_load, .operand = 12 },                    .{ .op = .i32_const, .operand = 4 },     .{ .op = .i32_eq },
        .{ .op = .if_, .operand = @backingInt(source.result) }, .{ .op = .local_get, .operand = local },                .{ .op = .i32_load },                    .{ .op = .i32_const, .operand = selected.operation },
        .{ .op = .i32_eq },                                     .{ .op = .if_, .operand = @backingInt(source.result) }, .{ .op = .local_get, .operand = local }, .{ .op = if (source.result == .f32) .f32_load else .i32_load, .operand = 4 },
        .{ .op = .else_ },                                      .{ .op = .unreachable_ },                               .{ .op = .end },                         .{ .op = .else_ },
    }) or !alternative(code[47..])) return null;
    return selected;
}
/// Exact owning publication of argument1 into the selected State frame's value
/// field. The completed catalog excludes callback/request/scoped alternatives;
/// call-site flow must still prove which installation the receiver reaches.
/// This grants no nonescape, owner retirement, or retain/release omission.
pub fn writeOperation(module: *const wasm.Module, catalog: *const Catalog, source: *const ir.Function) ?Mode {
    const arena = module.arena orelse return null;
    const found = lookup(catalog, source, .write) orelse return null;
    const selected = found.mode;
    const local = found.local;
    const code = source.instructions.items;
    if (!match(code[31..], &.{
        .{ .op = .local_get, .operand = local },                   .{ .op = .i32_load, .operand = 12 },                       .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_eq },
        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) }, .{ .op = .local_get, .operand = local },                   .{ .op = .i32_load },                .{ .op = .i32_const, .operand = selected.operation },
        .{ .op = .i32_eq },                                        .{ .op = .if_, .operand = @backingInt(ir.ValueType.i32) }, .{ .op = .unreachable_ },            .{ .op = .else_ },
        .{ .op = .local_get, .operand = local },                   .{ .op = .local_get, .operand = local },                   .{ .op = .i32_const, .operand = 4 }, .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 1 },
    })) return null;
    var at: usize = 48;
    if (selected.machine == .f32) {
        if (!exact(code[at], .i32_reinterpret_f32, 0)) return null;
        at += 1;
    }
    if (!match(code[at..], &.{ .{ .op = .call, .operand = arena.store_word }, .{ .op = .i32_const }, .{ .op = .end }, .{ .op = .else_ } }) or !alternative(code[at + 4 ..])) return null;
    return selected;
}
pub fn specialize(a: A, catalog: *const Catalog, source: *const ir.Function) A.Error!?ir.Body {
    _ = readOperation(catalog, source) orelse return null;
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.appendSlice(a, source.locals.items);
    try result.instructions.appendSlice(a, source.instructions.items[0..47]);
    try result.emit(a, .unreachable_, 0);
    try result.emit(a, .end, 0);
    return result;
}
