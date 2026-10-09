//! Private, monotone traversal of an immutable List tree. Pending right
//! subtrees are allocation bases; each edge is visited at most once. Word zero
//! roots the collection for the entire traversal; later words hold the path.
const std = @import("std");
const wasm = @import("wasm.zig");
const heap = @import("runtime_layout.zig");
const Error = std.mem.Allocator.Error;

pub const capacity = 64;
pub const bytes = (capacity + 1) * 4;
pub const Walk = struct { storage: u32, top: u32, limit: u32, node: u32 };

pub fn initialize(module: *wasm.Module, function: u32, source: u32, walk: Walk) Error!void {
    try module.emitSlice(function, &.{
        .{ .op = .local_get, .operand = walk.storage },
        .{ .op = .local_get, .operand = source },
        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = walk.storage },
        .{ .op = .local_get, .operand = source },
        .{ .op = .i32_load, .operand = heap.offset(heap.ListDescriptor, "root") },
        .{ .op = .i32_store, .operand = 4 },
        .{ .op = .local_get, .operand = walk.storage },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = walk.top },
        .{ .op = .local_get, .operand = walk.storage },
        .{ .op = .i32_const, .operand = bytes },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = walk.limit },
    });
}

fn descend(module: *wasm.Module, function: u32, walk: Walk) Error!void {
    try module.emitSlice(function, &.{
        .{ .op = .block },                                                      .{ .op = .loop },
        .{ .op = .local_get, .operand = walk.node },                            .{ .op = .i32_load, .operand = heap.offset(heap.ListNode, "height") },
        .{ .op = .i32_eqz },                                                    .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = walk.top },                             .{ .op = .local_get, .operand = walk.limit },
        .{ .op = .i32_ge_u },                                                   .{ .op = .if_ },
        .{ .op = .unreachable_ },                                               .{ .op = .end },
        .{ .op = .local_get, .operand = walk.top },                             .{ .op = .local_get, .operand = walk.node },
        .{ .op = .i32_load, .operand = heap.offset(heap.ListBranch, "right") }, .{ .op = .i32_store },
        .{ .op = .local_get, .operand = walk.top },                             .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_add },                                                    .{ .op = .local_set, .operand = walk.top },
        .{ .op = .local_get, .operand = walk.node },                            .{ .op = .i32_load, .operand = heap.offset(heap.ListBranch, "left") },
        .{ .op = .local_set, .operand = walk.node },                            .{ .op = .br, .operand = 0 },
        .{ .op = .end },                                                        .{ .op = .end },
    });
}

// Callers consume every field in order, so a requested span is always the
// immediately next leaf. No arbitrary seek or transitive search is admitted.
pub fn next(module: *wasm.Module, function: u32, span: [3]u32, walk: Walk) Error!void {
    try module.emitSlice(function, &.{
        .{ .op = .local_get, .operand = walk.top },
        .{ .op = .local_get, .operand = walk.storage },
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_add },
        .{ .op = .i32_le_u },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = walk.top },
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_sub },
        .{ .op = .local_tee, .operand = walk.top },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = walk.node },
    });
    try descend(module, function, walk);
    try module.emitSlice(function, &.{
        .{ .op = .local_get, .operand = walk.node },
        .{ .op = .local_set, .operand = span[0] },
        .{ .op = .local_get, .operand = span[2] },
        .{ .op = .local_tee, .operand = span[1] },
        .{ .op = .local_get, .operand = walk.node },
        .{ .op = .i32_load, .operand = heap.offset(heap.ListNode, "length") },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = span[2] },
    });
}
