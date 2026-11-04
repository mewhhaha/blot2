//! Explicit reference scanner for executable test fixtures only. Production
//! assembly does not import this module or reserve its helper identities.
const std = @import("std");
const wasm = @import("../backend/wasm.zig");
const heap = @import("runtime_layout.zig");
const Error = std.mem.Allocator.Error;

fn mark(module: *wasm.Module, arena: wasm.Arena, tracing: Tracing) Error!void {
    const value = 0;
    const index = 1;
    const start = 2;
    const head = try module.addLocal(tracing.mark, .i32);
    const code = [_]wasm.Instruction{
        .{ .op = .local_get, .operand = value },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .i32_and },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .return_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = value },
        .{ .op = .local_get, .operand = start },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_add },
        .{ .op = .i32_lt_u },
        .{ .op = .local_get, .operand = value },
        .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .i32_ge_u },
        .{ .op = .i32_or },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .return_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = value },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_sub },
        .{ .op = .local_set, .operand = head },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shl },
        .{ .op = .i32_add },
        .{ .op = .i32_load },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 31 },
        .{ .op = .i32_and },
        .{ .op = .i32_shl },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .return_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "requested") },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_ne },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .i32_and },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_or },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "flags") },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_and },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .i32_load },
        .{ .op = .i32_store, .operand = heap.offset(heap.ArenaHeader, "next") },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_store },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .i32_const, .operand = 0 },
    };
    try module.emitSlice(tracing.mark, &code);
}

fn collect(module: *wasm.Module, arena: wasm.Arena, tracing: Tracing) Error!void {
    const root = 0;
    const floor = 1;
    const head = try module.addLocal(tracing.collect, .i32);
    const count = try module.addLocal(tracing.collect, .i32);
    const index = try module.addLocal(tracing.collect, .i32);
    const end = try module.addLocal(tracing.collect, .i32);
    const scratch_end = try module.addLocal(tracing.collect, .i32);
    const pages = try module.addLocal(tracing.collect, .i32);
    const slot = try module.addLocal(tracing.collect, .i32);
    const limit = try module.addLocal(tracing.collect, .i32);
    const size = try module.addLocal(tracing.collect, .i32);
    const clamp_floor = [_]wasm.Instruction{
        .{ .op = .local_get, .operand = floor },
        .{ .op = .global_get, .operand = arena.base },
        .{ .op = .i32_lt_u },
        .{ .op = .if_ },
        .{ .op = .global_get, .operand = arena.base },
        .{ .op = .local_set, .operand = floor },
        .{ .op = .end },
    };
    const prefix = [_]wasm.Instruction{
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_eqz },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = root },
        .{ .op = .return_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_set, .operand = count },
        .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .local_set, .operand = end },
        .{ .op = .local_get, .operand = end },
        .{ .op = .local_set, .operand = index },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = end },
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .i32_add },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shl },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = scratch_end },
        .{ .op = .local_get, .operand = scratch_end },
        .{ .op = .local_get, .operand = index },
        .{ .op = .i32_lt_u },
        .{ .op = .if_ },
        .{ .op = .unreachable_ },
        .{ .op = .end },
        .{ .op = .local_get, .operand = scratch_end },
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
        .{ .op = .i32_const, .operand = 12 },
        .{ .op = .i32_load },
        .{ .op = .local_get, .operand = end },
        .{ .op = .i32_ne },
        .{ .op = .if_ },
        .{ .op = .local_get, .operand = index },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .local_get, .operand = scratch_end },
        .{ .op = .local_get, .operand = index },
        .{ .op = .i32_sub },
        .{ .op = .memory_fill },
        .{ .op = .block },
        .{ .op = .loop },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = end },
        .{ .op = .i32_ge_u },
        .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shl },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = slot },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_load },
        .{ .op = .i32_const, .operand = 1 },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = 2 },
        .{ .op = .i32_shr_u },
        .{ .op = .i32_const, .operand = 31 },
        .{ .op = .i32_and },
        .{ .op = .i32_shl },
        .{ .op = .i32_or },
        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "block_size") },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = head },
        .{ .op = .br, .operand = 0 },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .i32_const, .operand = 12 },
        .{ .op = .local_get, .operand = end },
        .{ .op = .i32_store },
        .{ .op = .end },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .i32_const, .operand = 0 },
        .{ .op = .i32_store },
    };
    const static_mark = [_]wasm.Instruction{
        .{ .op = .i32_const, .operand = @import("arena_runtime.zig").metadata_bytes },
        .{ .op = .local_set, .operand = slot },
        .{ .op = .block },
        .{ .op = .loop },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .global_get, .operand = arena.static_end },
        .{ .op = .i32_ge_u },
        .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_load },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = count },
        .{ .op = .call, .operand = tracing.mark },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = slot },
        .{ .op = .br, .operand = 0 },
        .{ .op = .end },
        .{ .op = .end },
    };
    const suffix = [_]wasm.Instruction{
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = head },
        .{ .op = .block },
        .{ .op = .loop },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = floor },
        .{ .op = .i32_ge_u },
        .{ .op = .br_if, .operand = 1 },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = count },
        .{ .op = .call, .operand = tracing.mark },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "block_size") },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = head },
        .{ .op = .br, .operand = 0 },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .local_get, .operand = root },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = count },
        .{ .op = .call, .operand = tracing.mark },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = count },
        .{ .op = .call, .operand = tracing.root_mark },
        .{ .op = .block },
        .{ .op = .loop },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = head },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_eqz },
        .{ .op = .br_if, .operand = 1 },
        .{ .op = .i32_const, .operand = 8 },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "next") },
        .{ .op = .i32_store },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_const, .operand = @sizeOf(heap.ArenaHeader) },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = slot },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .local_get, .operand = head },
        .{ .op = .i32_load, .operand = heap.offset(heap.ArenaHeader, "requested") },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = limit },
        .{ .op = .block },
        .{ .op = .loop },
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_const, .operand = 3 },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = limit },
        .{ .op = .i32_ge_u },
        .{ .op = .br_if, .operand = 1 },
    };
    try module.emitSlice(tracing.collect, &.{
        .{ .op = .global_get, .operand = arena.root_enabled },
        .{ .op = .if_ },
        .{ .op = .global_get, .operand = arena.static_end },
        .{ .op = .local_set, .operand = floor },
        .{ .op = .else_ },
    });
    try module.emitSlice(tracing.collect, &clamp_floor);
    try module.emit(tracing.collect, .{ .op = .end });
    try module.emitSlice(tracing.collect, &prefix);
    try module.emitSlice(tracing.collect, &.{ .{ .op = .global_get, .operand = arena.root_enabled }, .{ .op = .i32_eqz }, .{ .op = .if_ } });
    try module.emitSlice(tracing.collect, &static_mark);
    try module.emit(tracing.collect, .{ .op = .end });
    try module.emitSlice(tracing.collect, &suffix);
    const trace_code: @import("../backend/runtime_code.zig").Code = .{ .module = module, .function = tracing.collect };
    try trace_code.value(.{ .i32_and, .{ .load, @import("../backend/runtime_code.zig").Local{ .id = head }, heap.offset(heap.ArenaHeader, "flags") }, @import("shared_rc.zig").counted });
    try trace_code.op(.if_, 0x7f);
    try @import("shared_rc.zig").referenceSlot(trace_code, .{ .id = head }, .{ .i32_sub, .{ .i32_sub, @import("../backend/runtime_code.zig").Local{ .id = slot }, @import("../backend/runtime_code.zig").Local{ .id = head } }, @sizeOf(heap.ArenaHeader) });
    try trace_code.op(.else_, 0);
    try trace_code.value(1);
    try trace_code.end();
    try trace_code.op(.if_, 0);
    try module.emitSlice(tracing.collect, &.{
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_load },
        .{ .op = .local_get, .operand = index },
        .{ .op = .local_get, .operand = count },
        .{ .op = .call, .operand = tracing.mark },
        .{ .op = .drop },
    });
    try trace_code.end();
    try module.emitSlice(tracing.collect, &.{
        .{ .op = .local_get, .operand = slot },
        .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = slot },
        .{ .op = .br, .operand = 0 },
        .{ .op = .end },
        .{ .op = .end },
        .{ .op = .br, .operand = 0 },
        .{ .op = .end },
        .{ .op = .end },
    });
    const gen = @import("../backend/runtime_code.zig");
    const c: gen.Code = .{ .module = module, .function = tracing.collect };
    const block: gen.Local = .{ .id = head };
    const stop: gen.Local = .{ .id = end };
    const block_size: gen.Local = .{ .id = size };
    // Complete the dead set before removing any counted edge. Physical sizes
    // remain available even after retirement; allocator links are never roots.
    try c.set(block, .{ .load, 4, 0 });
    try c.loop(.{ .i32_lt_u, block, stop });
    try c.when(.{ .i32_and, .{ .i32_ge_u, block, gen.Local{ .id = floor } }, .{ .i32_and, .{ .i32_ne, .{ .load, block, heap.offset(heap.ArenaHeader, "requested") }, 0 }, .{ .i32_eqz, .{ .i32_and, .{ .load, block, heap.offset(heap.ArenaHeader, "flags") }, 1 } } } });
    try c.store(block, heap.offset(heap.ArenaHeader, "flags"), .{ .i32_or, .{ .load, block, heap.offset(heap.ArenaHeader, "flags") }, @import("shared_rc.zig").dead });
    try c.end();
    try c.set(block, .{ .i32_add, block, .{ .load, block, heap.offset(heap.ArenaHeader, "block_size") } });
    try c.again();
    try c.set(block, .{ .load, 4, 0 });
    try c.loop(.{ .i32_lt_u, block, stop });
    try c.set(block_size, .{ .load, block, heap.offset(heap.ArenaHeader, "block_size") });
    try c.when(.{ .i32_and, .{ .load, block, heap.offset(heap.ArenaHeader, "flags") }, @import("shared_rc.zig").dead });
    try c.when(.{ .i32_and, .{ .load, block, heap.offset(heap.ArenaHeader, "flags") }, @import("shared_rc.zig").counted });
    try c.value(.{ .call, arena.retire, .{ .i32_add, block, @sizeOf(heap.ArenaHeader) } });
    try c.op(.else_, 0);
    try c.value(.{ .call, arena.free, .{ .i32_add, block, @sizeOf(heap.ArenaHeader) } });
    try c.end();
    try c.op(.else_, 0);
    try c.store(block, heap.offset(heap.ArenaHeader, "flags"), .{ .i32_and, .{ .load, block, heap.offset(heap.ArenaHeader, "flags") }, ~@as(u32, 1) });
    try c.end();
    try c.set(block, .{ .i32_add, block, block_size });
    try c.again();
    try c.value(.{ .call, arena.release, 0 });
    try c.value(gen.Local{ .id = root });
}

fn rootMark(c: @import("../backend/runtime_code.zig").Code, a: wasm.Arena, tracing: Tracing) Error!void {
    const index: @import("../backend/runtime_code.zig").Local = .{ .id = 0 };
    const start: @import("../backend/runtime_code.zig").Local = .{ .id = 1 };
    const page = try c.temp();
    const top = try c.temp();
    const slot = try c.temp();
    const journal = @import("root_runtime.zig");
    try c.set(page, .{ .global, a.root_page });
    try c.set(top, .{ .global, a.root_top });
    try c.loop(page);
    try c.value(.{ .call, tracing.mark, page, index, start });
    try c.op(.drop, 0);
    try c.set(slot, journal.first_slot);
    try c.loop(.{ .i32_lt_u, slot, top });
    try c.value(.{ .call, tracing.mark, .{ .load, .{ .i32_add, page, slot }, 0 }, index, start });
    try c.op(.drop, 0);
    try c.set(slot, .{ .i32_add, slot, journal.slot_bytes });
    try c.again();
    try c.set(page, .{ .load, page, 0 });
    try c.set(top, journal.page_bytes);
    try c.again();
}

pub const Tracing = struct { mark: u32, collect: u32, root_mark: u32 };
pub fn install(module: *wasm.Module) !Tracing {
    if (module.artifacts != null or module.fixture_helpers != null) return error.InvalidFixture;
    const arena = try module.ensureArena();
    const tracing: Tracing = .{ .mark = try module.addFunction(&.{ .i32, .i32, .i32 }, .i32), .collect = try module.addFunction(&.{ .i32, .i32, .i32 }, .i32), .root_mark = try module.addFunction(&.{ .i32, .i32 }, .none) };
    module.fixture_helpers = .{ tracing.mark, tracing.collect, tracing.root_mark };
    try mark(module, arena, tracing);
    try collect(module, arena, tracing);
    try rootMark(.{ .module = module, .function = tracing.root_mark }, arena, tracing);
    // The reference allocator owns its scanner chain and invalidation boundary.
    const function = &module.functions.items[arena.allocate];
    var insertion: ?usize = null;
    for (function.instructions.items, 0..) |inst, at| if (inst.op == .global_set and inst.operand == arena.heap) {
        insertion = at - 1;
        break;
    };
    const at = insertion orelse return error.InvalidFixture;
    var allocation_head: ?u32 = null;
    for (function.instructions.items, 0..) |inst, pc| {
        if (pc < 2 or inst.op != .i32_store or inst.operand != heap.offset(heap.ArenaHeader, "requested")) continue;
        const address = function.instructions.items[pc - 2];
        const value = function.instructions.items[pc - 1];
        if (address.op != .local_get or value.op != .local_get or value.operand != 0) return error.InvalidFixture;
        allocation_head = address.operand;
        break;
    }
    const head = allocation_head orelse return error.InvalidFixture;
    try function.instructions.insertSlice(module.allocator, at, &.{
        .{ .op = .i32_const, .operand = 4 },  .{ .op = .i32_load },                   .{ .op = .i32_eqz },   .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 4 },  .{ .op = .local_get, .operand = head }, .{ .op = .i32_store }, .{ .op = .end },
        .{ .op = .i32_const, .operand = 12 }, .{ .op = .i32_const },                  .{ .op = .i32_store },
    });
    module.functions.items[arena.reset].instructions.clearRetainingCapacity();
    try module.emitSlice(arena.reset, &.{
        // Complete journal admission retires every temporary owner through
        // leave/scopes. Reset preserves allocator storage and strong roots;
        // trial deletion alone handles any newly unreachable cycle.
        .{ .op = .global_get, .operand = arena.root_enabled }, .{ .op = .i32_const, .operand = @import("root_runtime.zig").complete },
        .{ .op = .i32_and },                                   .{ .op = .if_ },
        .{ .op = .global_get, .operand = arena.cycle_head },   .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 1 },                   .{ .op = .call, .operand = arena.cycle_safe },
        .{ .op = .end },                                       .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .return_ },                                   .{ .op = .end },
        .{ .op = .global_get, .operand = arena.root_enabled }, .{ .op = .if_ },
        .{ .op = .i32_const },                                 .{ .op = .global_get, .operand = arena.static_end },
        .{ .op = .i32_const },                                 .{ .op = .call, .operand = tracing.collect },
        .{ .op = .drop },                                      .{ .op = .global_get, .operand = arena.heap },
        .{ .op = .return_ },                                   .{ .op = .end },
        // Counted tracer leases retire through the same dead-set path.
        .{ .op = .global_get, .operand = arena.rc_enabled },   .{ .op = .if_ },
        .{ .op = .i32_const },                                 .{ .op = .global_get, .operand = arena.base },
        .{ .op = .i32_const },                                 .{ .op = .call, .operand = tracing.collect },
        .{ .op = .drop },                                      .{ .op = .end },
        .{ .op = .global_get, .operand = arena.base },         .{ .op = .global_set, .operand = arena.heap },
        .{ .op = .i32_const, .operand = 32 },                  .{ .op = .i32_const },
        .{ .op = .i32_const, .operand = 132 },                 .{ .op = .memory_fill },
        .{ .op = .i32_const, .operand = 12 },                  .{ .op = .i32_const },
        .{ .op = .i32_store },                                 .{ .op = .i32_const, .operand = 4 },
        .{ .op = .i32_load },                                  .{ .op = .global_get, .operand = arena.base },
        .{ .op = .i32_ge_u },                                  .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 4 },                   .{ .op = .i32_const },
        .{ .op = .i32_store },                                 .{ .op = .end },
        .{ .op = .i32_const, .operand = 16 },                  .{ .op = .i32_const },
        .{ .op = .i32_store },                                 .{ .op = .i32_const },
    });

    return tracing;
}
