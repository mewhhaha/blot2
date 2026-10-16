//! Lexical cleanup obligations for private runtime storage and demand forcing.
//! Branch exits discharge only scopes they leave. Cancellation discharges the
//! entire current function, including scopes inherited by an inlined body.
//! Payload values are not released: private provider/request cells cannot
//! escape, but their values and ordinary callback arguments can.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const ir = @import("../backend/runtime_ir.zig");
const heap = @import("runtime_layout.zig");
const A = std.mem.Allocator;

pub const Mark = enum(usize) { _ };
pub const Action = union(enum) { task_group: struct { owner: ir.LocalId, close: u32 }, resource: struct { token: ir.LocalId, release: u32 }, release: ir.LocalId, release_if_nonzero: ir.LocalId, reset_demand: ir.LocalId, root_scope: void, revoke_effect: ir.LocalId };
pub const Stack = struct {
    parent: ?*const Stack = null,
    actions: std.ArrayList(Action) = .empty,

    /// Snapshot the active force-site obligations before borrowing a lexical
    /// emitter. Flattening avoids a parent cycle when that emitter is already
    /// an ancestor of the force site.
    pub fn snapshot(self: *const Stack, a: A) A.Error!Stack {
        var result: Stack = .{};
        errdefer result.deinit(a);
        try result.inherit(a, self);
        return result;
    }
    fn inherit(self: *Stack, a: A, source: *const Stack) A.Error!void {
        if (source.parent) |parent| try self.inherit(a, parent);
        try self.actions.appendSlice(a, source.actions.items);
    }
    pub fn deinit(self: *Stack, a: A) void {
        self.actions.deinit(a);
    }
    pub fn mark(self: *const Stack) Mark {
        return @fromBackingInt(@intCast(self.actions.items.len));
    }
    pub fn restore(self: *Stack, checkpoint: Mark) void {
        self.actions.shrinkRetainingCapacity(@backingInt(checkpoint));
    }
    /// The obligations of scopes opened after `checkpoint`, oldest first.
    pub fn since(self: *const Stack, checkpoint: Mark) []const Action {
        return self.actions.items[@backingInt(checkpoint)..];
    }
    pub fn append(self: *Stack, a: A, action: Action) A.Error!void {
        try self.actions.append(a, action);
    }
    pub fn emitTo(self: *const Stack, module: *wasm.Module, function: ir.FunctionId, checkpoint: Mark) A.Error!void {
        try self.emitToResult(module, function, checkpoint, null);
    }
    pub fn emitToResult(self: *const Stack, module: *wasm.Module, function: ir.FunctionId, checkpoint: Mark, result: ?u32) A.Error!void {
        var task_index = self.actions.items.len;
        while (task_index > @backingInt(checkpoint)) {
            task_index -= 1;
            if (self.actions.items[task_index] == .task_group) try emit(self.actions.items[task_index], module, function, result);
        }
        for (self.actions.items[@backingInt(checkpoint)..]) |action| if (action == .revoke_effect) try emit(action, module, function, result);
        var index = self.actions.items.len;
        std.debug.assert(@backingInt(checkpoint) <= index);
        while (index > @backingInt(checkpoint)) {
            index -= 1;
            if (self.actions.items[index] != .revoke_effect and self.actions.items[index] != .task_group) try emit(self.actions.items[index], module, function, result);
        }
    }
    pub fn emitAll(self: *const Stack, module: *wasm.Module, function: ir.FunctionId) A.Error!void {
        try self.emitTo(module, function, @fromBackingInt(@intCast(0)));
        if (self.parent) |parent| try parent.emitAll(module, function);
    }
};
fn emit(action: Action, module: *wasm.Module, function: ir.FunctionId, result: ?u32) A.Error!void {
    const id = @backingInt(function);
    switch (action) {
        .task_group => |group| {
            try module.emitSlice(id, &.{ .{ .op = .local_get, .operand = @backingInt(group.owner) }, .{ .op = .i32_load, .operand = heap.offset(heap.EffectAuthority, "active") }, .{ .op = .call_import, .operand = group.close } });
        },
        .resource => |journal| {
            if (module.taskImportNamed("drain")) |drain| try module.emit(id, .{ .op = .call_import, .operand = drain });
            try module.emit(id, .{ .op = .local_get, .operand = @backingInt(journal.token) });
            try module.emit(id, .{ .op = .call_import, .operand = journal.release });
        },
        .revoke_effect => |local| {
            try module.emitSlice(id, &.{ .{ .op = .local_get, .operand = @backingInt(local) }, .{ .op = .i32_const }, .{ .op = .i32_store, .operand = heap.offset(heap.EffectAuthority, "active") } });
        },
        .root_scope => {
            const scope: ir.Ownership = .{ .kind = .scope, .chunk = if (result != null) 2 else 1, .roles = @intCast(result orelse 0) };
            try module.emit(id, .{ .op = .ownership, .operand = @bitCast(scope) });
        },
        .release => |local| {
            try module.emit(id, .{ .op = .local_get, .operand = @backingInt(local) });
            try module.emit(id, .{ .op = .call, .operand = module.arena.?.recycle });
        },
        .release_if_nonzero => |local| {
            try module.emit(id, .{ .op = .local_get, .operand = @backingInt(local) });
            try module.emit(id, .{ .op = .if_ });
            try module.emit(id, .{ .op = .local_get, .operand = @backingInt(local) });
            try module.emit(id, .{ .op = .call, .operand = module.arena.?.recycle });
            try module.emit(id, .{ .op = .end });
        },
        .reset_demand => |local| {
            try module.emitSlice(id, &.{
                .{ .op = .local_get, .operand = @backingInt(local) },                     .{ .op = .local_get, .operand = @backingInt(local) },
                .{ .op = .i32_const, .operand = heap.offset(heap.Demand, "status") },     .{ .op = .i32_add },
                .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.pending) }, .{ .op = .call, .operand = module.arena.?.store_word },
            });
        },
    }
}
