//! Request cancellation carries an owner, never a guest result.
const wasm = @import("wasm.zig");
const cleanup = @import("runtime_cleanup.zig");
const heap = @import("runtime_layout.zig");
pub const Status = heap.RequestStatus;
pub const Cell = heap.RequestCell;
pub const Frame = heap.RequestFrame;
pub const request_kind: u32 = @backingInt(heap.ProviderKind.request);

pub fn dummy(module: *wasm.Module, function: u32, cleanups: *const cleanup.Stack) !void {
    try cleanups.emitAll(module, @fromBackingInt(@intCast(function)));
    const result = module.functions.items[function].result;
    if (result != .none) try module.emit(function, .{ .op = if (result == .f32) .f32_const else .i32_const });
    try module.emit(function, .{ .op = .return_ });
}
/// A called expression may leave any typed operand stack. Return unwinds that
/// stack using the caller's own result type. Demand forcing first resets state.
pub fn guard(module: *wasm.Module, function: u32, owner: u32, cleanups: *const cleanup.Stack) !void {
    try module.emit(function, .{ .op = .global_get, .operand = owner });
    try module.emit(function, .{ .op = .if_ });
    try dummy(module, function, cleanups);
    try module.emit(function, .{ .op = .end });
}
/// A nested runner must preserve an outer cancellation. Only its owner clears
/// the guard; the cell's typed payload then controls its normal local dispatch.
pub fn runner(module: *wasm.Module, function: u32, owner: u32, cell: u32, cleanups: *const cleanup.Stack) !void {
    try module.emit(function, .{ .op = .global_get, .operand = owner });
    try module.emit(function, .{ .op = .if_ });
    try module.emit(function, .{ .op = .global_get, .operand = owner });
    try module.emit(function, .{ .op = .local_get, .operand = cell });
    try module.emit(function, .{ .op = .i32_ne });
    try module.emit(function, .{ .op = .if_ });
    try dummy(module, function, cleanups);
    try module.emit(function, .{ .op = .end });
    try module.emit(function, .{ .op = .i32_const });
    try module.emit(function, .{ .op = .global_set, .operand = owner });
    try module.emit(function, .{ .op = .end });
}
pub fn cancel(module: *wasm.Module, function: u32, owner: u32, cell: u32, status: Status, cleanups: *const cleanup.Stack) !void {
    try module.emit(function, .{ .op = .local_get, .operand = cell });
    try module.emit(function, .{ .op = .i32_const, .operand = @backingInt(status) });
    try module.emit(function, .{ .op = .i32_store, .operand = heap.offset(Cell, "status") });
    try module.emit(function, .{ .op = .local_get, .operand = cell });
    try module.emit(function, .{ .op = .global_set, .operand = owner });
    try dummy(module, function, cleanups);
}
