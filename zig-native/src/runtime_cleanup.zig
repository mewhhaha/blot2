//! Lexical cleanup obligations for private runtime storage and demand forcing.
//! Branch exits discharge only scopes they leave. Cancellation discharges the
//! entire current function, including scopes inherited by an inlined body.
//! Payload values are not released: private provider/request cells cannot
//! escape, but their values and ordinary callback arguments can.
const std = @import("std");
const wasm = @import("wasm.zig");
const ir = @import("runtime_ir.zig");
const heap = @import("runtime_layout.zig");
const A = std.mem.Allocator;

pub const Mark = enum(usize) { _ };
pub const Action = union(enum) { release: ir.LocalId, release_if_nonzero: ir.LocalId, reset_demand: ir.LocalId };
pub const Stack = struct {
    parent: ?*const Stack = null,
    actions: std.ArrayList(Action) = .empty,

    pub fn deinit(self: *Stack, a: A) void {
        self.actions.deinit(a);
    }
    pub fn mark(self: *const Stack) Mark {
        return @fromBackingInt(@intCast(self.actions.items.len));
    }
    pub fn restore(self: *Stack, checkpoint: Mark) void {
        self.actions.shrinkRetainingCapacity(@backingInt(checkpoint));
    }
    pub fn append(self: *Stack, a: A, action: Action) A.Error!void {
        try self.actions.append(a, action);
    }
    pub fn emitTo(self: *const Stack, module: *wasm.Module, function: ir.FunctionId, checkpoint: Mark) A.Error!void {
        var index = self.actions.items.len;
        std.debug.assert(@backingInt(checkpoint) <= index);
        while (index > @backingInt(checkpoint)) {
            index -= 1;
            try emit(self.actions.items[index], module, function);
        }
    }
    pub fn emitAll(self: *const Stack, module: *wasm.Module, function: ir.FunctionId) A.Error!void {
        try self.emitTo(module, function, @fromBackingInt(@intCast(0)));
        if (self.parent) |parent| try parent.emitAll(module, function);
    }
};
fn emit(action: Action, module: *wasm.Module, function: ir.FunctionId) A.Error!void {
    const id = @backingInt(function);
    switch (action) {
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
            try module.emit(id, .{ .op = .local_get, .operand = @backingInt(local) });
            try module.emit(id, .{ .op = .i32_const, .operand = @backingInt(heap.DemandStatus.pending) });
            try module.emit(id, .{ .op = .i32_store, .operand = heap.offset(heap.Demand, "status") });
        },
    }
}
