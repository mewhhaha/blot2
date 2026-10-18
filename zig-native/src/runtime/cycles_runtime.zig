//! Local trial deletion. Journal leases are counted outside boundaries; all
//! other scratch links are weak and phase-exclusive. No phase allocates memory.
const std = @import("std");
const w = @import("../backend/wasm.zig");
const h = @import("runtime_layout.zig");
const rc = @import("shared_rc.zig");
const gen = @import("../backend/runtime_code.zig");
const Code = gen.Code;
const Local = gen.Local;
const Error = std.mem.Allocator.Error;
pub const queued: u32 = 32;
pub const gray: u32 = 64;
pub const black: u32 = 128;
pub const deferred: u32 = 256;
pub const no_cycle: u32 = 512;
/// Flags that make enqueue and visit return early. Cohort extensions widen
/// these exact constants.
pub const enqueue_guard: u32 = rc.lease | rc.dead | no_cycle;
pub const visit_guard: u32 = rc.lease | gray | no_cycle;
/// Traffic that triggers a pass grows with the vertices the previous pass
/// discovered and kept, so rescanning live temporaries stays proportional to
/// allocation traffic. Reclaimed vertices do not raise it, so uncollected
/// cyclic garbage stays bounded by live scan size plus the minimum.
pub const minimum_traffic: u32 = 65536;
const traffic_per_vertex_shift = 6;
const traffic_vertex_cap: u32 = 1 << 18;
const header = @sizeOf(h.ArenaHeader);
const f = struct {
    const flags = h.offset(h.ArenaHeader, "flags");
    const next = h.offset(h.ArenaHeader, "next");
    const trial = h.offset(h.ArenaHeader, "candidate_prev");
    const member = h.offset(h.ArenaHeader, "candidate_next");
    const strong = h.offset(h.ArenaHeader, "strong");
    const layout = h.offset(h.ArenaHeader, "layout");
    const requested = h.offset(h.ArenaHeader, "requested");
};
fn set(c: Code, global: u32, value: anytype) Error!void {
    try c.value(value);
    try c.op(.global_set, global);
}
fn add(c: Code, global: u32, value: anytype) Error!void {
    try set(c, global, .{ .i32_add, .{ .global, global }, value });
}
fn head(c: Code, value: Local) Error!Local {
    const result = try c.temp();
    try c.set(result, .{ .i32_sub, value, header });
    return result;
}
pub fn emit(m: *w.Module, a: w.Arena) Error!void {
    try unlink(.{ .module = m, .function = a.cycle_unlink }, a);
    try enqueue(.{ .module = m, .function = a.cycle_enqueue }, a);
    try visit(.{ .module = m, .function = a.cycle_visit }, a);
    try collect(.{ .module = m, .function = a.cycle_collect }, a);
    try safe(.{ .module = m, .function = a.cycle_safe }, a);
}
fn unlink(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    const b = try head(c, p);
    const prev = try c.temp();
    const next = try c.temp();
    try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, b, f.flags }, queued } });
    try c.op(.return_, 0);
    try c.end();
    try c.set(prev, .{ .load, b, f.trial });
    try c.set(next, .{ .load, b, f.member });
    try c.when(prev);
    try c.store(.{ .i32_sub, prev, header }, f.member, next);
    try c.op(.else_, 0);
    try set(c, a.cycle_head, next);
    try c.end();
    try c.when(next);
    try c.store(.{ .i32_sub, next, header }, f.trial, prev);
    try c.end();
    try c.store(b, f.trial, 0);
    try c.store(b, f.member, 0);
    try c.store(b, f.flags, .{ .i32_and, .{ .load, b, f.flags }, ~queued });
}
fn enqueue(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    const b = try head(c, p);
    try c.when(.{ .i32_or, .{ .i32_eqz, .{ .load, b, f.layout } }, .{ .i32_and, .{ .load, b, f.flags }, enqueue_guard } });
    try c.op(.return_, 0);
    try c.end();
    // A queued candidate's later releases add no removal traffic.
    try c.when(.{ .i32_and, .{ .load, b, f.flags }, queued });
    try c.op(.return_, 0);
    try c.end();
    // Saturate removal traffic so a large destruction batch cannot wrap and
    // suppress the next safe point. Membership remains independent of traffic.
    try c.when(.{ .i32_lt_u, .{ .global, a.cycle_removed }, .{ .global, a.cycle_threshold } });
    try c.when(.{ .i32_ge_u, .{ .load, b, f.requested }, .{ .i32_sub, .{ .global, a.cycle_threshold }, .{ .global, a.cycle_removed } } });
    try set(c, a.cycle_removed, .{ .global, a.cycle_threshold });
    try c.op(.else_, 0);
    try add(c, a.cycle_removed, .{ .load, b, f.requested });
    try c.end();
    try c.end();
    try c.when(.{ .i32_and, .{ .load, b, f.flags }, gray });
    try c.store(b, f.flags, .{ .i32_or, .{ .load, b, f.flags }, deferred });
    try c.op(.return_, 0);
    try c.end();
    try c.store(b, f.trial, 0);
    try c.store(b, f.member, .{ .global, a.cycle_head });
    try c.when(.{ .global, a.cycle_head });
    try c.store(.{ .i32_sub, .{ .global, a.cycle_head }, header }, f.trial, p);
    try c.end();
    try set(c, a.cycle_head, p);
    try c.store(b, f.flags, .{ .i32_or, .{ .load, b, f.flags }, queued });
}
fn visit(c: Code, a: w.Arena) Error!void {
    const p: Local = .{ .id = 0 };
    try c.when(.{ .i32_lt_u, p, .{ .global, a.static_end } });
    try c.op(.return_, 0);
    try c.end();
    const b = try head(c, p);
    // Leased boundaries and their outgoing edges stay outside subtraction. An
    // exact no_cycle proof covers the object's whole reachable structure, so no
    // cycle passes through it; leaving it outside only keeps its children live.
    try c.when(.{ .i32_and, .{ .load, b, f.flags }, visit_guard });
    try c.op(.return_, 0);
    try c.end();
    try c.trap(.{ .i32_eqz, .{ .load, b, f.requested } });
    try c.trap(.{ .i32_eqz, .{ .i32_and, .{ .load, b, f.flags }, rc.counted } });
    try c.value(.{ .call, a.cycle_unlink, p });
    try c.store(b, f.flags, .{ .i32_or, .{ .load, b, f.flags }, gray });
    try c.store(b, f.trial, .{ .load, b, f.strong });
    try c.store(b, f.member, .{ .global, a.cycle_members });
    try set(c, a.cycle_members, p);
    try c.store(b, f.next, .{ .global, a.cycle_work });
    try set(c, a.cycle_work, p);
    try add(c, a.cycle_vertices, 1);
}
// Every physically retained reference slot is visited, including unused List
// capacity whose writer has not cleared an old edge. Scalar bits never enter.
fn edges(c: Code, a: w.Arena, p: Local, comptime phase: enum { discover, live }) Error!void {
    const b = try head(c, p);
    const offset = try c.temp();
    const child = try c.temp();
    const cb = try c.temp();
    try c.set(offset, 0);
    try c.when(.{ .load, b, f.layout });
    const end = try rc.referenceEnd(c, b);
    try c.loop(.{ .i32_lt_u, offset, end });
    try rc.referenceSlot(c, b, offset);
    try c.op(.if_, 0);
    try c.set(child, .{ .load, .{ .i32_add, p, offset }, 0 });
    try c.when(.{ .i32_ge_u, child, .{ .global, a.static_end } });
    if (phase == .discover) {
        try add(c, a.cycle_edges, 1);
        try c.value(.{ .call, a.cycle_visit, child });
    }
    try c.set(cb, .{ .i32_sub, child, header });
    try c.when(.{ .i32_and, .{ .load, cb, f.flags }, gray });
    if (phase == .discover) {
        try c.trap(.{ .i32_eqz, .{ .load, cb, f.trial } });
        try c.store(cb, f.trial, .{ .i32_sub, .{ .load, cb, f.trial }, 1 });
    } else {
        try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, cb, f.flags }, black } });
        try c.store(cb, f.flags, .{ .i32_or, .{ .load, cb, f.flags }, black });
        try c.store(cb, f.next, .{ .global, a.cycle_work });
        try set(c, a.cycle_work, child);
        try c.end();
    }
    try c.end();
    try c.end();
    try c.end();
    try c.set(offset, .{ .i32_add, offset, 4 });
    try c.again();
    try c.end();
}
fn work(c: Code, a: w.Arena, p: Local, comptime phase: enum { discover, live }) Error!void {
    try c.loop(.{ .global, a.cycle_work });
    try c.set(p, .{ .global, a.cycle_work });
    try set(c, a.cycle_work, .{ .load, .{ .i32_sub, p, header }, f.next });
    try c.store(.{ .i32_sub, p, header }, f.next, 0);
    if (phase == .discover) try edges(c, a, p, .discover) else try edges(c, a, p, .live);
    try c.again();
}
fn collect(c: Code, a: w.Arena) Error!void {
    const p = try c.temp();
    const b = try c.temp();
    const next = try c.temp();
    const pending = try c.temp();
    const scanned = try c.temp();
    try c.when(.{ .i32_or, .{ .global, a.cycle_phase }, .{ .i32_eqz, .{ .global, a.cycle_head } } });
    try c.op(.return_, 0);
    try c.end();
    try set(c, a.cycle_phase, 1);
    try set(c, a.cycle_removed, 0);
    try set(c, a.cycle_cadence, .{ .global, a.allocated });
    try add(c, a.cycle_passes, 1);
    try c.set(scanned, .{ .global, a.cycle_vertices });
    try c.loop(.{ .global, a.cycle_head });
    try c.value(.{ .call, a.cycle_visit, .{ .global, a.cycle_head } });
    try work(c, a, p, .discover);
    try c.again();
    try c.set(scanned, .{ .i32_sub, .{ .global, a.cycle_vertices }, scanned });
    try c.set(p, .{ .global, a.cycle_members });
    try c.loop(p);
    try c.set(b, .{ .i32_sub, p, header });
    try c.when(.{ .load, b, f.trial });
    try c.store(b, f.flags, .{ .i32_or, .{ .load, b, f.flags }, black });
    try c.store(b, f.next, .{ .global, a.cycle_work });
    try set(c, a.cycle_work, p);
    try c.end();
    try c.set(p, .{ .load, b, f.member });
    try c.again();
    try work(c, a, p, .live);
    // Classify the entire dead set before removing any owning edge.
    try c.set(p, .{ .global, a.cycle_members });
    try c.loop(p);
    try c.set(b, .{ .i32_sub, p, header });
    try c.when(.{ .i32_eqz, .{ .i32_and, .{ .load, b, f.flags }, black } });
    try c.store(b, f.flags, .{ .i32_or, .{ .load, b, f.flags }, rc.dead });
    try c.end();
    try c.set(p, .{ .load, b, f.member });
    try c.again();
    // Splice live members out before retirement can enqueue them again.
    // Keep the dead member chain in the global, with no live scratch remaining.
    try c.set(p, .{ .global, a.cycle_members });
    try set(c, a.cycle_members, 0);
    try c.loop(p);
    try c.set(b, .{ .i32_sub, p, header });
    try c.set(next, .{ .load, b, f.member });
    try c.when(.{ .i32_and, .{ .load, b, f.flags }, black });
    try c.set(pending, .{ .i32_and, .{ .load, b, f.flags }, deferred });
    try c.store(b, f.trial, 0);
    try c.store(b, f.member, 0);
    try c.store(b, f.flags, .{ .i32_and, .{ .load, b, f.flags }, ~(gray | black | deferred) });
    try c.when(pending);
    try c.value(.{ .call, a.cycle_enqueue, p });
    try c.end();
    try c.op(.else_, 0);
    try c.store(b, f.member, .{ .global, a.cycle_members });
    try set(c, a.cycle_members, p);
    try c.end();
    try c.set(p, next);
    try c.again();
    try c.loop(.{ .global, a.cycle_members });
    try c.set(p, .{ .global, a.cycle_members });
    try c.set(b, .{ .i32_sub, p, header });
    try set(c, a.cycle_members, .{ .load, b, f.member });
    try add(c, a.cycle_bytes, .{ .load, b, f.requested });
    try c.set(scanned, .{ .i32_sub, scanned, 1 });
    try c.value(.{ .call, a.retire, p });
    try c.again();
    try c.when(.{ .i32_gt_u, scanned, traffic_vertex_cap });
    try c.set(scanned, traffic_vertex_cap);
    try c.end();
    try set(c, a.cycle_threshold, .{ .i32_add, minimum_traffic, .{ .i32_shl, scanned, traffic_per_vertex_shift } });
    try set(c, a.cycle_phase, 0);
    try rc.drain(c, a);
}
fn safe(c: Code, a: w.Arena) Error!void {
    try c.when(.{ .i32_eqz, .{ .global, a.cycle_head } });
    try c.op(.return_, 0);
    try c.end();
    try c.when(.{ .i32_or, Local{ .id = 0 }, .{ .i32_or, .{ .i32_ge_u, .{ .global, a.cycle_removed }, .{ .global, a.cycle_threshold } }, .{ .i32_ge_u, .{ .i32_sub, .{ .global, a.allocated }, .{ .global, a.cycle_cadence } }, .{ .global, a.cycle_threshold } } } });
    try c.value(.{ .call, a.cycle_collect });
    try c.end();
}

test "cycle phases emit no allocation, host call or recursive traversal" {
    var module = w.Module.init(std.testing.allocator);
    defer module.deinit();
    const arena = try module.ensureArena();
    inline for (.{ "cycle_enqueue", "cycle_unlink", "cycle_visit", "cycle_collect", "cycle_safe" }) |field| {
        for (module.functions.items[@field(arena, field)].instructions.items) |inst| {
            try std.testing.expect(inst.op != .memory_grow and inst.op != .call_import and inst.op != .call_indirect);
            if (inst.op != .call) continue;
            try std.testing.expect(inst.operand == arena.cycle_enqueue or inst.operand == arena.cycle_unlink or inst.operand == arena.cycle_visit or inst.operand == arena.cycle_collect or inst.operand == arena.retire);
        }
    }
    try std.testing.expectEqual(@as(usize, 32), header);
    var summaries = try @import("../backend/wasm_lifetimes.zig").Summaries.init(std.testing.allocator, &module);
    defer summaries.deinit();
    try summaries.prepare();
    try std.testing.expect(summaries.functions[arena.cycle_collect].invalidates);
    try std.testing.expect(summaries.functions[arena.cycle_safe].invalidates);
}

fn demandScenario(allocator: std.mem.Allocator, table: bool) !void {
    var module = w.Module.init(allocator);
    defer module.deinit();
    module.defer_cycles = true;
    const arena = try module.ensureArena();
    const lists = try module.ensureLists();
    const function = try module.addFunction(&.{}, .none);
    if (table) {
        try module.emit(function, .{ .op = .i32_const, .operand = lists.new, .table_reference = true });
    } else {
        const constructor = &module.functions.items[lists.new];
        try std.testing.expectEqualSlices(w.ValueType, &.{ .i32, .i32, .i32 }, constructor.parameters);
        try std.testing.expectEqual(w.ValueType.i32, constructor.result);
        try module.emitSlice(function, &.{ .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_const }, .{ .op = .i32_const, .operand = @import("list_runtime.zig").capacity }, .{ .op = .call, .operand = lists.new } });
    }
    try module.emit(function, .{ .op = .drop });
    const count = module.functions.items.len;
    try module.prepareCycles();
    try std.testing.expectEqual(count, module.functions.items.len);
    try std.testing.expect(module.functions.items[arena.cycle_collect].instructions.items.len != 0);
    const bytes = try module.assemble();
    defer allocator.free(bytes);
}
test "cycle helper demand follows checked direct and table references through collection constructors" {
    try demandScenario(std.testing.allocator, false);
    try demandScenario(std.testing.allocator, true);
}
test "cycle helper demand and late emission own every allocation failure" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, demandScenario, .{false});
}
