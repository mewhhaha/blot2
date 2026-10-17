//! Address-preserving allocation and direct reclamation. Payload pointers never
//! change; per-class free lists reuse retired blocks. Partial assembly owns
//! its separate legacy scanner and emits none of it into retained source bodies.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const heap = @import("runtime_layout.zig");
const Error = std.mem.Allocator.Error;
// Size classes include the arena header. Power-of-two class 2^k keeps its
// free-list head k at address 32 + 4k; the first-fit list for blocks above
// 2 GiB uses head 32. A header plus one payload byte needs more than 2^5
// bytes, so heads 0..5 never hold a power class. They hold the 1.5x
// companions 3 * 2^(k-2) of power classes 6..11: 48, 96, 192, 384, 768 and
// 1536 bytes. Each class is a multiple of 16 bytes, so a heap starting at
// 64 KiB keeps 16-byte aligned payloads.
const first_class = 6;
const companion_classes = 6;
comptime {
    std.debug.assert(@sizeOf(heap.ArenaHeader) + 1 > 1 << (first_class - 1));
    std.debug.assert(companion_classes <= first_class);
}
// Reserved arena metadata follows the 33 free-list heads (bytes 32..164).
// These pointer-free immutable descriptors are shared by every list helper,
// including helpers reconstructed from a retained executable fragment.
pub const empty_list_address: u32 = 168;
pub const empty_scalar_list_address: u32 = empty_list_address + @sizeOf(heap.ListDescriptor);
// Canonical width-two through width-sixteen empty descriptors are arena
// resources, never source-owned payloads replayed beside rebuilt helpers.
pub const empty_rows_address: u32 = 256;
pub const metadata_bytes: u32 = empty_rows_address + 15 * @sizeOf(heap.ListDescriptor);

pub fn emit(module: *wasm.Module, arena: wasm.Arena) Error!void {
    try allocate(module, arena);
    try allocateScalar(module, arena);
    try recycle(module, arena);
    try @import("shared_rc.zig").emit(module, arena);
}

/// The checked layout proves that every payload word is scalar. The existing
/// leaf flag prevents integer bits from being interpreted as child pointers.
/// Keeping this contract explicit also supplies the zero-child case for RC.
fn allocateScalar(module: *wasm.Module, arena: wasm.Arena) Error!void {
    const result = try module.addLocal(arena.allocate_scalar, .i32);
    try module.emitSlice(arena.allocate_scalar, &.{
        .{ .op = .local_get, .operand = 0 },
        .{ .op = .call, .operand = arena.allocate },
        .{ .op = .local_set, .operand = result },
        // Zero-size allocation has no header and returns the arena cursor.
        .{ .op = .local_get, .operand = 0 },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = result },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) - heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .i32_sub },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_store },
        .{ .op = .end },
        .{ .op = .local_get, .operand = result },
    });
}

/// Compiler-proven final ownership releases storage directly. This entry point
/// is private: callers must prove that no pointer or borrowed address survives.
/// It does not inspect payload words or follow children. Retained children keep
/// their own lifetimes, and shared objects remain under the collection policy.
fn recycle(module: *wasm.Module, arena: wasm.Arena) Error!void {
    const pointer = 0;
    const head = try module.addLocal(arena.free, .i32);
    const size = try module.addLocal(arena.free, .i32);
    const bin = try module.addLocal(arena.free, .i32);
    try module.emitSlice(arena.free, &.{
        .{ .op = .local_get, .operand = pointer },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_sub },
        .{ .op = .local_tee, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "requested") },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "block_size") },
        .{ .op = .local_tee, .operand = size },
        .{ .op = .i32_const, .operand = 0x80000000 },
        .{ .op = .i32_gt_u },
        .{ .op = .if_, .operand = 0x7f },
        .{ .op = .i32_const, .operand = 160 },
        .{ .op = .else_ },
        .{ .op = .i32_const, .operand = 32 },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_ctz },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shl },
        .{ .op = .i32_add },
        // A companion 3 * 2^(k-2) has k - 2 trailing zeros and head k - 6.
        .{ .op = .local_get, .operand = size },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_sub },
        .{ .op = .i32_and },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_ne },
        .{ .op = .i32_const, .operand = 4 * (first_class - 2) },
        .{ .op = .i32_mul },
        .{ .op = .i32_sub },
        .{ .op = .end },
        .{ .op = .local_set, .operand = bin },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "requested") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = bin },
        .{ .op = .i32_load },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "next") },
        .{ .op = .local_get, .operand = bin },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_store },
    });
}

fn allocate(module: *wasm.Module, arena: wasm.Arena) Error!void {
    const bytes = 0;
    const class = try module.addLocal(arena.allocate, .i32);
    const size = try module.addLocal(arena.allocate, .i32);
    const head = try module.addLocal(arena.allocate, .i32);
    const end = try module.addLocal(arena.allocate, .i32);
    const pages = try module.addLocal(arena.allocate, .i32);
    const bin = try module.addLocal(arena.allocate, .i32);
    const code = [_]wasm.Instruction{
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .return_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_const, .operand = std.math.maxInt(u32) - @sizeOf(heap.ArenaHeader) - 3 },
        .{ .op = .i32_gt_u },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_const, .operand = 0x80000000 - @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_gt_u },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 32 },
        .{ .op = .local_set, .operand = class },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) + 3 },
        .{ .op = .i32_add },
        .{ .op = .i32_const, .operand = 0xfffffffc },
        .{ .op = .i32_and },
        .{ .op = .local_set, .operand = size },
        .{ .op = .else_ },
        .{ .op = .i32_const, .operand = 32 },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) - 1 },
        .{ .op = .i32_add },
        .{ .op = .i32_clz },
        .{ .op = .i32_sub },
        .{ .op = .local_set, .operand = class },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .local_get, .operand = class },
        .{ .op = .i32_shl },
        .{ .op = .local_set, .operand = size },
        // Below 2 KiB, a block that fits three quarters of its power class
        // uses that class's companion and free-list head.
        .{ .op = .local_get, .operand = class },
        .{ .op = .i32_const, .operand = first_class + companion_classes },
        .{ .op = .i32_lt_u },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = size },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_sub },
        .{ .op = .i32_le_u },
        .{ .op = .i32_and },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = class },
        .{ .op = .i32_const, .operand = first_class },
        .{ .op = .i32_sub },
        .{ .op = .local_set, .operand = class },
        .{ .op = .local_get, .operand = size },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_sub },
        .{ .op = .local_set, .operand = size },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .i32_const, .operand = 32 },
        .{ .op = .local_get, .operand = class },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shl },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = bin },
        .{ .op = .local_get, .operand = bin },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_ne },
        .{ .op = .local_get, .operand = class },
        .{ .op = .i32_const, .operand = 32 },
        .{ .op = .i32_eq },
        .{ .op = .i32_and },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "block_size") },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_lt_u },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .local_set, .operand = head },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = bin },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "next") },
        .{ .op = .i32_store },
        .{ .op = .else_ },
        .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .local_set, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 65536 },
        .{ .op = .i32_lt_u },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 65536 },
        .{ .op = .local_set, .operand = head },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = end },
        .{ .op = .local_get, .operand = end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_lt_u },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = end },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_sub },
        .{ .op = .i32_const, .operand = 16 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = pages },
        .{ .op = .local_get, .operand = pages },
        .{ .op = .memory_size },
        .{ .op = .i32_gt_u },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = pages },
        .{ .op = .memory_size },
        .{ .op = .i32_sub },
        .{ .op = .memory_grow },
        .{ .op = .i32_const, .operand = 0xffffffff },
        .{ .op = .i32_eq },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .local_get, .operand = end },
        .{ .op = .global_set, .operand = arena.heap },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_store },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = bytes },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "requested") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "next") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "strong") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "layout") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "candidate_prev") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "candidate_next") },
        // Count reuse as well as fresh arena growth. A wrapping counter lets
        // loop safepoints compare traffic since their own previous collection.
        .{ .op = .global_get, .operand = arena.allocated },
        .{ .op = .local_get, .operand = size },
        .{ .op = .i32_add },
        .{ .op = .global_set, .operand = arena.allocated },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_add },
    };
    try module.emitSlice(arena.allocate, &code);
}
