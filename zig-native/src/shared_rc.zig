//! Checked field ownership with explicit counted tracer leases during tasks
//! 031–034. Zero-count destruction uses the header as an allocation-free queue;
//! tracing retires its complete dead set through the same destructor.
const std = @import("std");
const w = @import("wasm.zig");
const h = @import("runtime_layout.zig");
const gen = @import("runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
const Error = std.mem.Allocator.Error;
pub const counted: u32 = 4;
pub const lease: u32 = 8;
pub const dead: u32 = 16;
const queue: u32 = 16;
const header = @sizeOf(h.ArenaHeader);
const f = struct {
    const strong = h.offset(h.ArenaHeader, "strong");
    const flags = h.offset(h.ArenaHeader, "flags");
    const layout = h.offset(h.ArenaHeader, "layout");
    const next = h.offset(h.ArenaHeader, "next");
    const requested = h.offset(h.ArenaHeader, "requested");
};
fn code(m: *w.Module, id: u32) Code {
    return .{ .module = m, .function = id };
}
fn bump(c: Code, global: u32) Error!void {
    try c.value(.{ .i32_add, .{ .global, global }, 1 });
    try c.op(.global_set, global);
}
fn dynamic(c: Code, a: w.Arena) Error!Local {
    const p: Local = .{ .id = 0 };
    try c.when(.{ .i32_lt_u, p, .{ .global, a.static_end } });
    try c.op(.return_, 0);
    try c.end();
    const head = try c.temp();
    try c.set(head, .{ .i32_sub, p, header });
    try c.trap(.{ .i32_or, .{ .i32_and, p, 3 }, .{ .i32_eqz, .{ .load, head, f.requested } } });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, counted } });
    return head;
}
pub fn referenceSlot(c: Code, head: Local, offset: anytype) Error!void {
    try c.value(.{ .i32_div_u, offset, 4 });
    const word = try c.temp();
    try c.op(.local_set, word.id);
    try c.when(.{ .i32_gt_u, word, 31 });
    try c.set(word, 31);
    try c.end();
    try c.value(.{ .i32_and, .{ .i32_shr_u, .{ .load, head, f.layout }, word }, 1 });
}
// Bit 31 describes every tail word; finite masks stop at their last edge.
pub fn referenceEnd(c: Code, head: Local) Error!Local {
    const end = try c.temp();
    const mask = try c.temp();
    try c.set(end, .{ .load, head, f.requested });
    try c.set(mask, .{ .load, head, f.layout });
    try c.when(.{ .i32_eqz, .{ .i32_and, mask, 0x80000000 } });
    try c.set(mask, .{ .i32_mul, .{ .i32_sub, 32, .{ .i32_clz, mask } }, 4 });
    try c.when(.{ .i32_lt_u, mask, end });
    try c.set(end, mask);
    try c.end();
    try c.end();
    return end;
}
pub fn emit(m: *w.Module, a: w.Arena) Error!void {
    try allocate(code(m, a.allocate_typed), a);
    try retain(code(m, a.retain), a);
    try decrement(code(m, a.decrement), a);
    try release(code(m, a.release), a);
    try releaseLease(code(m, a.release_lease), a);
    try retire(code(m, a.retire), a);
    try store(code(m, a.store_word), a);
    try copy(code(m, a.copy_words), a);
    const c = code(m, a.recycle);
    const p: Local = .{ .id = 0 };
    try c.when(.{ .i32_and, .{ .load, .{ .i32_sub, p, header }, f.flags }, counted });
    try c.value(.{ .call, a.release_lease, p });
    try c.op(.else_, 0);
    try c.value(.{ .call, a.free, p });
    try c.end();
}
fn allocate(c: Code, a: w.Arena) Error!void {
    const bytes: Local = .{ .id = 0 };
    const mask: Local = .{ .id = 1 };
    const p = try c.temp();
    const head = try c.temp();
    try c.when(.{ .i32_eqz, bytes });
    try c.value(0);
    try c.op(.return_, 0);
    try c.end();
    try c.when(.{ .global, a.rc_enabled });
    try c.trap(.{ .i32_and, bytes, 3 });
    try c.end();
    try c.set(p, .{ .call, a.allocate, bytes });
    try c.set(head, .{ .i32_sub, p, header });
    try c.when(.{ .i32_eqz, mask });
    try c.store(head, f.flags, 2);
    try c.end();
    try c.when(.{ .global, a.rc_enabled });
    try c.store(head, f.flags, .{ .i32_or, .{ .load, head, f.flags }, counted | lease });
    try c.store(head, f.layout, mask);
    try c.store(head, f.strong, 1);
    // Reused storage must contain null reference fields before publication.
    try c.when(mask);
    try c.zero(p, bytes);
    try c.end();
    try bump(c, a.rc_leases);
    try c.end();
    try c.value(p);
}
fn retain(c: Code, a: w.Arena) Error!void {
    const head = try dynamic(c, a);
    try c.trap(.{ .i32_eqz, .{ .load, head, f.strong } });
    try c.trap(.{ .i32_eq, .{ .load, head, f.strong }, std.math.maxInt(u32) });
    try c.store(head, f.strong, .{ .i32_add, .{ .load, head, f.strong }, 1 });
    try bump(c, a.rc_retains);
}
fn decrement(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    const head = try dynamic(c, a);
    try c.trap(.{ .i32_eqz, .{ .load, head, f.strong } });
    try c.store(head, f.strong, .{ .i32_sub, .{ .load, head, f.strong }, 1 });
    try bump(c, a.rc_releases);
    try c.when(.{ .i32_eqz, .{ .load, head, f.strong } });
    try c.when(.{ .i32_and, .{ .load, head, f.flags }, @import("cycles_runtime.zig").queued });
    try c.value(.{ .call, a.cycle_unlink, p });
    try c.end();
    try c.store(head, f.next, .{ .load, queue, 0 });
    try c.store(queue, 0, p);
    try c.op(.else_, 0);
    try c.when(.{ .load, head, f.layout });
    try c.value(.{ .call, a.cycle_enqueue, p });
    try c.end();
    try c.end();
}
fn release(c: Code, a: w.Arena) Error!void {
    try c.value(.{ .call, a.decrement, Local{ .id = 0 } });
    try drain(c, a);
}
pub fn drain(c: Code, a: w.Arena) Error!void {
    const p = try c.temp();
    try c.loop(.{ .load, queue, 0 });
    try c.set(p, .{ .load, queue, 0 });
    try c.store(queue, 0, .{ .load, .{ .i32_sub, p, header }, f.next });
    try c.store(.{ .i32_sub, p, header }, f.next, 0);
    try c.value(.{ .call, a.retire, p });
    try c.again();
}
fn releaseLease(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    const head = try dynamic(c, a);
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, lease } });
    try @import("root_runtime.zig").detach(c, a, head);
    try c.store(head, f.flags, .{ .i32_and, .{ .load, head, f.flags }, ~lease });
    try c.value(.{ .i32_sub, .{ .global, a.rc_leases }, 1 });
    try c.op(.global_set, a.rc_leases);
    try c.value(.{ .call, a.release, p });
}
fn retire(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    const head = try dynamic(c, a);
    const is_dead = try c.temp();
    const offset = try c.temp();
    const child = try c.temp();
    try c.set(is_dead, .{ .i32_and, .{ .load, head, f.flags }, dead });
    try c.trap(.{ .i32_and, .{ .i32_eqz, is_dead }, .{ .load, head, f.strong } });
    try c.when(.{ .i32_and, .{ .load, head, f.flags }, @import("cycles_runtime.zig").queued });
    try c.value(.{ .call, a.cycle_unlink, p });
    try c.end();
    // The tracer owns the full white set before calling this destructor.
    // Internal white edges disappear with that set, live outgoing edges drop.
    try c.when(.{ .i32_and, .{ .load, head, f.flags }, lease });
    try c.trap(.{ .i32_eqz, is_dead });
    try c.value(.{ .i32_sub, .{ .global, a.rc_leases }, 1 });
    try c.op(.global_set, a.rc_leases);
    try c.end();
    try c.store(head, f.strong, 0);
    // Zero-child layouts retire without scanning their scalar payload.
    try c.when(.{ .load, head, f.layout });
    const end = try referenceEnd(c, head);
    try c.loop(.{ .i32_lt_u, offset, end });
    try referenceSlot(c, head, offset);
    try c.op(.if_, 0);
    try c.set(child, .{ .load, .{ .i32_add, p, offset }, 0 });
    try c.store(.{ .i32_add, p, offset }, 0, 0);
    try c.when(.{ .i32_ge_u, child, .{ .global, a.static_end } });
    try c.when(is_dead);
    try c.when(.{ .i32_and, .{ .i32_ne, .{ .load, .{ .i32_sub, child, header }, f.requested }, 0 }, .{ .i32_eqz, .{ .i32_and, .{ .load, .{ .i32_sub, child, header }, f.flags }, dead } } });
    try c.value(.{ .call, a.decrement, child });
    try c.end();
    try c.op(.else_, 0);
    try c.value(.{ .call, a.decrement, child });
    try c.end();
    try c.end();
    try c.end();
    try c.set(offset, .{ .i32_add, offset, 4 });
    try c.again();
    try c.end();
    try bump(c, a.rc_destroyed);
    try c.value(.{ .call, a.free, p });
}
fn store(c: Code, a: w.Arena) Error!void {
    const parent: Local = .{ .id = 0 };
    const address: Local = .{ .id = 1 };
    const value: Local = .{ .id = 2 };
    const head = try c.temp();
    const offset = try c.temp();
    const old = try c.temp();
    try c.when(.{ .global, a.rc_enabled });
    try c.when(.{ .i32_lt_u, parent, .{ .global, a.static_end } });
    // Static mutable fields have checked roles and permanent owner-table
    // slots. All other static storage permits only idempotent writes.
    try c.when(.{ .global, a.root_enabled });
    const index = try c.temp();
    const field = try c.temp();
    const slot = try c.temp();
    try c.set(index, 0);
    try c.loop(.{ .i32_lt_u, index, .{ .global, a.root_static_count } });
    try c.set(field, .{ .load, .{ .cell, .{ .global, a.root_static_map }, index, 0 }, 0 });
    try c.when(.{ .i32_eq, .{ .i32_and, field, ~@as(u32, 3) }, address });
    try c.when(.{ .i32_eq, .{ .i32_and, field, 3 }, @backingInt(@import("runtime_ir.zig").Role.reference) });
    try c.set(slot, .{ .cell, .{ .global, a.root_globals }, .{ .i32_add, .{ .global, a.root_global_count }, index }, 0 });
    try c.value(.{ .call, a.store_word, .{ .global, a.root_globals }, slot, value });
    try c.end();
    try c.store(address, 0, value);
    try c.op(.return_, 0);
    try c.end();
    try c.set(index, .{ .i32_add, index, 1 });
    try c.again();
    try c.end();
    try c.trap(.{ .i32_ne, .{ .load, address, 0 }, value });
    try c.op(.return_, 0);
    try c.end();
    try c.set(head, .{ .i32_sub, parent, header });
    try c.set(offset, .{ .i32_sub, address, parent });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, counted } });
    try c.trap(.{ .i32_or, .{ .i32_and, offset, 3 }, .{ .i32_ge_u, offset, .{ .load, head, f.requested } } });
    try c.trap(.{ .i32_lt_u, .{ .i32_sub, .{ .load, head, f.requested }, offset }, 4 });
    try referenceSlot(c, head, offset);
    try c.op(.if_, 0);
    try c.set(old, .{ .load, address, 0 });
    try c.value(.{ .call, a.retain, value });
    try c.store(address, 0, value);
    try c.value(.{ .call, a.release, old });
    try c.op(.return_, 0);
    try c.end();
    try c.end();
    try c.store(address, 0, value);
}
// The caller has checked the full destination range once. Keep only field
// selection and edge accounting inside the copy loop.
fn copyWord(c: Code, a: w.Arena, head: Local, offset: anytype, address: anytype, source: anytype) Error!void {
    const value = try c.temp();
    const old = try c.temp();
    try c.set(value, .{ .load, source, 0 });
    try referenceSlot(c, head, offset);
    try c.op(.if_, 0);
    try c.set(old, .{ .load, address, 0 });
    try c.when(.{ .i32_ne, value, old });
    try c.value(.{ .call, a.retain, value });
    try c.store(address, 0, value);
    try c.when(.{ .i32_ge_u, old, .{ .global, a.static_end } });
    try c.value(.{ .call, a.release, old });
    try c.end();
    try c.end();
    try c.op(.else_, 0);
    try c.store(address, 0, value);
    try c.end();
}
fn copy(c: Code, a: w.Arena) Error!void {
    const parent: Local = .{ .id = 0 };
    const target: Local = .{ .id = 1 };
    const source: Local = .{ .id = 2 };
    const bytes: Local = .{ .id = 3 };
    const index = try c.temp();
    try c.when(.{ .i32_eqz, .{ .global, a.rc_enabled } });
    try c.copy(target, source, bytes);
    try c.op(.return_, 0);
    try c.end();
    try c.trap(.{ .i32_and, bytes, 3 });
    try c.when(.{ .i32_eqz, bytes });
    try c.op(.return_, 0);
    try c.end();
    const head = try c.temp();
    const offset = try c.temp();
    try c.set(head, .{ .i32_sub, parent, header });
    try c.set(offset, .{ .i32_sub, target, parent });
    try c.trap(.{ .i32_lt_u, parent, .{ .global, a.static_end } });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, head, f.flags }, counted } });
    try c.trap(.{ .i32_or, .{ .i32_and, offset, 3 }, .{ .i32_gt_u, offset, .{ .load, head, f.requested } } });
    try c.trap(.{ .i32_gt_u, bytes, .{ .i32_sub, .{ .load, head, f.requested }, offset } });
    try c.when(.{ .i32_eqz, .{ .load, head, f.layout } });
    try c.copy(target, source, bytes);
    try c.op(.return_, 0);
    try c.end();
    try c.when(.{ .i32_gt_u, target, source });
    try c.set(index, bytes);
    try c.loop(index);
    try c.set(index, .{ .i32_sub, index, 4 });
    try copyWord(c, a, head, .{ .i32_add, offset, index }, .{ .i32_add, target, index }, .{ .i32_add, source, index });
    try c.again();
    try c.op(.else_, 0);
    try c.loop(.{ .i32_lt_u, index, bytes });
    try copyWord(c, a, head, .{ .i32_add, offset, index }, .{ .i32_add, target, index }, .{ .i32_add, source, index });
    try c.set(index, .{ .i32_add, index, 4 });
    try c.again();
    try c.end();
}
