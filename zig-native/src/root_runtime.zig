//! Private typed ownership roots. Journal pages are allocator storage, not
//! source objects. Every published slot owns one counted reference.
const std = @import("std");
const w = @import("wasm.zig");
const h = @import("runtime_layout.zig");
const gen = @import("runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
const Error = std.mem.Allocator.Error;
const page_bytes = 4096;
const first_slot = 8;
const slot_bytes = 8;
pub const slots_per_page = (page_bytes - first_slot) / slot_bytes;
pub const enabled: u32 = 1;
pub const complete: u32 = 2;
const head_bytes = @sizeOf(h.ArenaHeader);
const owner_slot = h.offset(h.ArenaHeader, "candidate_prev");
fn code(m: *w.Module, id: u32) Code {
    return .{ .module = m, .function = id };
}
fn setGlobal(c: Code, id: u32, value: anytype) Error!void {
    try c.value(value);
    try c.op(.global_set, id);
}
fn count(c: Code, a: w.Arena, comptime op: w.Op) Error!void {
    if (op == .i32_add) {
        try setGlobal(c, a.root_count, .{ .i32_add, .{ .global, a.root_count }, 1 });
    } else {
        try setGlobal(c, a.root_count, .{ .i32_sub, .{ .global, a.root_count }, 1 });
    }
}
pub fn emit(m: *w.Module, a: w.Arena) Error!void {
    try reserve(code(m, a.root_reserve), a);
    try allocate(code(m, a.root_allocate), a);
    try pop(code(m, a.root_pop), a);
    try open(code(m, a.root_open), a);
    try close(code(m, a.root_close), a);
    try mark(code(m, a.root_mark), a);
    try enter(code(m, a.root_enter), a);
    try leave(code(m, a.root_leave), a);
    if (m.host_references != null) try hostCleanup(m, a);
    try store(code(m, a.root_store), a);
    try publicAllocate(code(m, a.root_public_allocate), a);
    try publicReset(code(m, a.root_public_reset), a);
    try force(code(m, a.root_force), a);
    try authority(code(m, a.root_authority), a);
}
fn reserve(c: Code, a: w.Arena) Error!void {
    const page = try c.temp();
    const slot = try c.temp();
    try c.when(.{ .i32_or, .{ .i32_eqz, .{ .global, a.root_page } }, .{ .i32_eq, .{ .global, a.root_top }, page_bytes } });
    // A failed growth leaves all earlier owners recorded in the old pages.
    try c.set(page, .{ .call, a.allocate, page_bytes });
    try c.store(page, 0, .{ .global, a.root_page });
    try c.store(.{ .i32_sub, page, head_bytes }, h.offset(h.ArenaHeader, "flags"), 2);
    try setGlobal(c, a.root_page, page);
    try setGlobal(c, a.root_top, first_slot);
    try c.end();
    try c.set(slot, .{ .i32_add, .{ .global, a.root_page }, .{ .global, a.root_top } });
    try c.zero(slot, slot_bytes);
    try c.store(slot, 4, .{ .global, a.root_frame });
    try setGlobal(c, a.root_top, .{ .i32_add, .{ .global, a.root_top }, slot_bytes });
    try c.value(slot);
}
fn allocate(c: Code, a: w.Arena) Error!void {
    const bytes: Local = .{ .id = 0 };
    const mask: Local = .{ .id = 1 };
    const slot = try c.temp();
    const value = try c.temp();
    try c.when(.{ .i32_eqz, .{ .global, a.root_enabled } });
    try c.ret(.{ .call, a.allocate_typed, bytes, mask });
    try c.end();
    try c.set(slot, .{ .call, a.root_reserve });
    try c.set(value, .{ .call, a.allocate_typed, bytes, mask });
    try c.when(value);
    try c.store(slot, 0, value);
    try c.store(.{ .i32_sub, value, head_bytes }, owner_slot, slot);
    try count(c, a, .i32_add);
    try c.end();
    try c.value(value);
}
fn pop(c: Code, a: w.Arena) Error!void {
    const page = try c.temp();
    const slot = try c.temp();
    const value = try c.temp();
    try c.trap(.{ .i32_eqz, .{ .global, a.root_page } });
    try c.when(.{ .i32_eq, .{ .global, a.root_top }, first_slot });
    try c.set(page, .{ .global, a.root_page });
    try setGlobal(c, a.root_page, .{ .load, page, 0 });
    try setGlobal(c, a.root_top, page_bytes);
    try c.value(.{ .call, a.free, page });
    try c.trap(.{ .i32_eqz, .{ .global, a.root_page } });
    // Let the caller inspect its marker after an empty page is removed.
    try c.ret(0);
    try c.end();
    try setGlobal(c, a.root_top, .{ .i32_sub, .{ .global, a.root_top }, slot_bytes });
    try c.set(slot, .{ .i32_add, .{ .global, a.root_page }, .{ .global, a.root_top } });
    try c.set(value, .{ .load, slot, 0 });
    // Interrupted forces become terminal before any of their owners retire.
    // Language cancellation already reset its selected force to pending.
    try c.when(value);
    try c.when(.{ .i32_and, .{ .load, slot, 4 }, 1 });
    try c.when(.{ .i32_and, .{ .global, a.root_active }, 1 });
    try c.when(.{ .i32_eq, .{ .load, value, h.offset(h.Demand, "status") }, @backingInt(h.DemandStatus.evaluating) });
    try c.store(value, h.offset(h.Demand, "status"), @backingInt(h.DemandStatus.terminal));
    try c.end();
    try c.end();
    try c.end();
    try c.end();
    // Detach before destruction. Nested releases cannot consume this root twice.
    try c.store(slot, 0, 0);
    try c.when(.{ .i32_ge_u, value, .{ .global, a.static_end } });
    try count(c, a, .i32_sub);
    const rc = @import("shared_rc.zig");
    const head = try rc.checkedHead(c, value);
    try c.when(.{ .i32_and, .{ .i32_ne, .{ .i32_and, .{ .load, head, h.offset(h.ArenaHeader, "flags") }, @import("shared_rc.zig").lease }, 0 }, .{ .i32_eq, .{ .load, head, owner_slot }, slot } });
    try c.store(head, owner_slot, 0);
    try rc.consumeLease(c, a, value, head);
    try c.op(.else_, 0);
    try rc.decrementKnown(c, a, value, head);
    try c.end();
    try rc.drain(c, a);
    try c.end();
    try c.value(slot);
}
fn open(c: Code, a: w.Arena) Error!void {
    const frame = try c.temp();
    // The marker precedes every callee owner. At close it can become the
    // caller result slot without another reservation or an ownership gap.
    try c.set(frame, .{ .call, a.root_reserve });
    try setGlobal(c, a.root_frame, frame);
    try c.value(frame);
}
fn close(c: Code, a: w.Arena) Error!void {
    const value: Local = .{ .id = 0 };
    const frame = try c.temp();
    const parent = try c.temp();
    const owner = try c.temp();
    const slot = try c.temp();
    try c.set(frame, .{ .global, a.root_frame });
    try c.trap(.{ .i32_eqz, frame });
    try c.set(parent, .{ .load, frame, 4 });
    try c.when(.{ .i32_ge_u, value, .{ .global, a.static_end } });
    try c.when(.{ .i32_and, .{ .load, .{ .i32_sub, value, head_bytes }, h.offset(h.ArenaHeader, "flags") }, @import("shared_rc.zig").lease });
    try c.set(owner, .{ .load, .{ .i32_sub, value, head_bytes }, owner_slot });
    try c.end();
    // A fresh owner in this frame moves into the caller slot. Borrowed values
    // retain before the frame closes, including shared children and aliases.
    try c.when(owner);
    try c.set(slot, .{ .load, owner, 4 });
    try c.end();
    try c.when(.{ .i32_eq, slot, frame });
    try c.store(owner, 0, 0);
    try c.store(.{ .i32_sub, value, head_bytes }, owner_slot, frame);
    try c.op(.else_, 0);
    try c.value(.{ .call, a.retain, value });
    try count(c, a, .i32_add);
    try c.end();
    try c.store(frame, 0, value);
    try c.end();
    try c.loop(1);
    try c.when(.{ .i32_eq, .{ .i32_sub, .{ .i32_add, .{ .global, a.root_page }, .{ .global, a.root_top } }, slot_bytes }, frame });
    try c.when(.{ .i32_eqz, .{ .load, frame, 0 } });
    try c.value(.{ .call, a.root_pop });
    try c.op(.drop, 0);
    try c.end();
    try c.op(.br, 2);
    try c.end();
    try c.value(.{ .call, a.root_pop });
    try c.op(.drop, 0);
    try c.again();
    try setGlobal(c, a.root_frame, parent);
    try c.when(.{ .global, a.cycle_head });
    try c.value(.{ .call, a.cycle_safe, 0 });
    try c.end();
}
fn mark(c: Code, a: w.Arena) Error!void {
    const index: Local = .{ .id = 0 };
    const start: Local = .{ .id = 1 };
    const page = try c.temp();
    const top = try c.temp();
    const slot = try c.temp();
    try c.set(page, .{ .global, a.root_page });
    try c.set(top, .{ .global, a.root_top });
    try c.loop(page);
    try c.value(.{ .call, a.mark, page, index, start });
    try c.op(.drop, 0);
    try c.set(slot, first_slot);
    try c.loop(.{ .i32_lt_u, slot, top });
    try c.value(.{ .call, a.mark, .{ .load, .{ .i32_add, page, slot }, 0 }, index, start });
    try c.op(.drop, 0);
    try c.set(slot, .{ .i32_add, slot, slot_bytes });
    try c.again();
    try c.set(page, .{ .load, page, 0 });
    try c.set(top, page_bytes);
    try c.again();
}
fn enter(c: Code, a: w.Arena) Error!void {
    try c.trap(.{ .i32_or, .{ .global, a.root_active }, .{ .global, a.root_frame } });
    // A failed frame reservation remains an invocation failure that leave(1)
    // can discharge without changing earlier persistent owners.
    try setGlobal(c, a.root_active, 1);
    try setGlobal(c, a.root_active, .{ .call, a.root_open });
    try setGlobal(c, a.root_external, 1);
    try setGlobal(c, a.root_started, 0);
}
fn leave(c: Code, a: w.Arena) Error!void {
    const outcome: Local = .{ .id = 0 };
    try c.trap(.{ .i32_gt_u, outcome, 2 });
    try c.when(.{ .i32_eq, outcome, 2 });
    try c.trap(.{ .i32_or, .{ .global, a.root_active }, .{ .global, a.root_frame } });
    const page = try c.temp();
    try c.loop(.{ .global, a.root_page });
    try c.when(.{ .i32_eq, .{ .global, a.root_top }, first_slot });
    try c.set(page, .{ .global, a.root_page });
    try setGlobal(c, a.root_page, .{ .load, page, 0 });
    try setGlobal(c, a.root_top, page_bytes);
    try c.value(.{ .call, a.free, page });
    try c.op(.else_, 0);
    try c.value(.{ .call, a.root_pop });
    try c.op(.drop, 0);
    try c.end();
    try c.again();
    try setGlobal(c, a.root_top, 0);
    try setGlobal(c, a.root_globals, 0);
    try c.op(.else_, 0);
    try c.trap(.{ .i32_eqz, .{ .global, a.root_active } });
    try c.when(.{ .i32_eq, outcome, 1 });
    try setGlobal(c, a.root_active, .{ .i32_or, .{ .global, a.root_active }, 1 });
    try c.end();
    try c.when(.{ .i32_and, .{ .global, a.root_active }, 2 });
    try revokeAuthorities(c, a);
    try c.end();
    try c.loop(.{ .global, a.root_frame });
    try c.value(.{ .call, a.root_close, 0 });
    try c.again();
    // Empty suffix slots own nothing; persistent module slots below them
    // retain their values, including when enter() failed to reserve its marker.
    const last = try c.temp();
    try c.loop(.{ .i32_and, .{ .i32_ne, .{ .global, a.root_page }, 0 }, .{ .i32_gt_u, .{ .global, a.root_top }, first_slot } });
    try c.set(last, .{ .i32_sub, .{ .i32_add, .{ .global, a.root_page }, .{ .global, a.root_top } }, slot_bytes });
    try c.when(.{ .load, last, 0 });
    try c.op(.br, 2);
    try c.end();
    try c.value(.{ .call, a.root_pop });
    try c.op(.drop, 0);
    try c.again();
    try setGlobal(c, a.root_active, 0);
    try setGlobal(c, a.root_external, 0);
    try setGlobal(c, a.root_started, 0);
    try c.end();
    try c.when(.{ .global, a.cycle_head });
    try c.value(.{ .call, a.cycle_safe, 1 });
    try c.end();
}

/// Consume an allocation's original journal owner before its lease releases.
/// Popping/moving a root clears this link first; field owners have no slot.
pub fn detach(c: Code, a: w.Arena, head: Local) Error!void {
    const slot = try c.temp();
    try c.when(.{ .global, a.root_enabled });
    try c.set(slot, .{ .load, head, owner_slot });
    try c.when(slot);
    try c.store(slot, 0, 0);
    try c.store(head, owner_slot, 0);
    try count(c, a, .i32_sub);
    try c.end();
    try c.end();
}

/// Mutating a parent edge can remove the last owner of a borrowed child.
/// Keep that borrow in the caller frame until its replacement is published.
pub fn retainBorrow(c: Code, a: w.Arena, value: Local) Error!void {
    try c.when(.{ .global, a.root_enabled });
    try c.when(.{ .i32_ge_u, value, .{ .global, a.static_end } });
    try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, .{ .i32_sub, value, head_bytes }, h.offset(h.ArenaHeader, "flags") }, @import("shared_rc.zig").lease } });
    try c.value(.{ .call, a.root_reserve });
    try c.value(value);
    try c.op(.call, a.root_store);
    try c.end();
    try c.end();
    try c.end();
}

// Stable carry slots own aliases independently of the allocation's original
// slot. Publish a replacement before releasing the old edge.
fn store(c: Code, a: w.Arena) Error!void {
    const slot: Local = .{ .id = 0 };
    const value: Local = .{ .id = 1 };
    const old = try c.temp();
    try c.set(old, .{ .load, slot, 0 });
    try c.when(.{ .i32_ge_u, value, .{ .global, a.static_end } });
    try c.when(.{ .i32_eq, old, value });
    try c.op(.return_, 0);
    try c.end();
    try c.value(.{ .call, a.retain, value });
    try c.store(slot, 0, value);
    try count(c, a, .i32_add);
    try c.op(.else_, 0);
    try c.store(slot, 0, 0);
    try c.end();
    try c.when(old);
    try count(c, a, .i32_sub);
    try c.value(.{ .call, a.release, old });
    try c.end();
}

fn publicAllocate(c: Code, a: w.Arena) Error!void {
    const bytes: Local = .{ .id = 0 };
    try c.when(.{ .global, a.root_enabled });
    try c.when(.{ .i32_eqz, .{ .global, a.root_active } });
    try c.value(.{ .call, a.root_enter });
    try setGlobal(c, a.root_external, 0);
    try c.end();
    try c.ret(.{ .call, a.root_allocate, bytes, 0 });
    try c.end();
    try c.value(.{ .call, a.allocate, bytes });
}
fn publicReset(c: Code, a: w.Arena) Error!void {
    try c.when(.{ .i32_and, .{ .global, a.root_enabled }, .{ .i32_eqz, .{ .global, a.root_external } } });
    try c.when(.{ .global, a.root_active });
    try c.value(.{ .call, a.root_leave, 1 });
    try c.end();
    try c.end();
    try c.value(.{ .call, a.reset, 0 });
}

/// The same leave boundary clears the externref cursor on success, failure and
/// idle teardown. Guest finally must not leave stale capabilities after a trap.
pub fn hostCleanup(m: *w.Module, a: w.Arena) Error!void {
    const references = m.host_references.?;
    try code(m, a.root_leave).value(.{ .call, references.release, 0 });
}

// The low frame bit marks an active-force record. Static demand cells are
// immortal references and need a record, but consume no dynamic strong count.
// Scope records own their owner edge. Bit two is separate from active demands.
fn authority(c: Code, a: w.Arena) Error!void {
    const value: Local = .{ .id = 0 };
    const slot = try c.temp();
    try c.when(.{ .i32_eqz, .{ .global, a.root_enabled } });
    try c.op(.return_, 0);
    try c.end();
    try c.set(slot, .{ .call, a.root_reserve });
    try c.value(.{ .call, a.root_store, slot, value });
    try c.store(slot, 4, .{ .i32_or, .{ .load, slot, 4 }, 2 });
    try setGlobal(c, a.root_active, .{ .i32_or, .{ .global, a.root_active }, 2 });
}
// Revoke the complete invocation before closing any frame. In particular a
// JSPI rejection/trap cannot leave a cycle-retained operation active.
fn revokeAuthorities(c: Code, a: w.Arena) Error!void {
    const page = try c.temp();
    const top = try c.temp();
    const slot = try c.temp();
    const owner = try c.temp();
    try c.set(page, .{ .global, a.root_page });
    try c.set(top, .{ .global, a.root_top });
    try c.loop(page);
    try c.loop(.{ .i32_gt_u, top, first_slot });
    try c.set(top, .{ .i32_sub, top, slot_bytes });
    try c.set(slot, .{ .i32_add, page, top });
    try c.set(owner, .{ .load, slot, 0 });
    try c.when(.{ .i32_and, .{ .i32_ne, owner, 0 }, .{ .i32_ne, .{ .i32_and, .{ .load, slot, 4 }, 2 }, 0 } });
    try c.store(owner, h.offset(h.EffectAuthority, "active"), 0);
    try c.end();
    try c.again();
    try c.set(page, .{ .load, page, 0 });
    try c.set(top, page_bytes);
    try c.again();
}
fn force(c: Code, a: w.Arena) Error!void {
    const value: Local = .{ .id = 0 };
    const slot = try c.temp();
    try c.set(slot, .{ .call, a.root_reserve });
    try c.value(.{ .call, a.root_store, slot, value });
    try c.when(.{ .i32_lt_u, value, .{ .global, a.static_end } });
    try c.store(slot, 0, value);
    try c.end();
    try c.store(slot, 4, .{ .i32_or, .{ .load, slot, 4 }, 1 });
}
