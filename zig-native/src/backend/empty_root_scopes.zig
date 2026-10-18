//! Empty lexical frames are proved from the current executable instructions.
//! Allocating or unknown calls, publications, unchecked memory writes and
//! reference exits retain their frame. Function/entry frames are outside this
//! proof, including public allocation.
//!
//! A lexical frame owns exactly the slots reserved while it is the current
//! frame, and its close never carries the function result (a reference exit
//! closes with chunk 2, which retains the frame). So the proof is independent
//! of the function's checked result role. Besides scalar arithmetic, a frame
//! stays empty across: checked scalar stores (`ir.scalarStore`), which write a
//! word whose checked layout has no edge; traps, which abandon the whole
//! invocation to failure cleanup, where an unopened empty frame has nothing to
//! close; calls to journal-neutral leaf functions (`neutralCall`); lane loads
//! and v128 arithmetic; and nested frames this pass has already proved empty.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const wasm = @import("wasm.zig");
const flow = @import("wasm_control_flow.zig");
const A = std.mem.Allocator;

pub const Action = enum(u2) { keep, open, close };

fn scalar(inst: ir.Instruction, module: *const wasm.Module) bool {
    return switch (inst.op) {
        .local_get,
        .local_set,
        .local_tee,
        .drop,
        .nop,
        .i32_const,
        .f32_const,
        .i32_load,
        .f32_load,
        .block,
        .loop,
        .if_,
        .else_,
        .end,
        .br,
        .br_if,
        .i32_eqz,
        .i32_eq,
        .i32_ne,
        .i32_lt_u,
        .i32_gt_u,
        .i32_le_u,
        .i32_ge_u,
        .i32_add,
        .i32_sub,
        .i32_mul,
        .i32_div_u,
        .i32_rem_u,
        .i32_and,
        .i32_or,
        .i32_xor,
        .i32_shl,
        .i32_shr_u,
        .i32_clz,
        .i32_ctz,
        .f32_eq,
        .f32_ne,
        .f32_lt,
        .f32_gt,
        .f32_le,
        .f32_ge,
        .f32_abs,
        .f32_neg,
        .f32_ceil,
        .f32_floor,
        .f32_trunc,
        .f32_sqrt,
        .f32_add,
        .f32_sub,
        .f32_mul,
        .f32_div,
        .f32_min,
        .f32_max,
        .i32_trunc_sat_f32_u,
        .f32_convert_i32_u,
        .i32_reinterpret_f32,
        .f32_reinterpret_i32,
        => true,
        .global_get => inst.operand < module.globals.items.len and module.globals.items[inst.operand].scalar.role() == .scalar,
        // Lane loads and arithmetic never call, allocate or publish; a vector
        // store still needs its checked scalar fact below.
        .v128_store => false,
        else => @import("wasm_simd_ops.zig").code(inst.op) != null,
    };
}

fn marker(inst: ir.Instruction, chunk: u4) bool {
    if (inst.op != .ownership) return false;
    const fact: ir.Ownership = @bitCast(inst.operand);
    return fact.kind == .scope and fact.chunk == chunk and fact.roles == 0;
}

/// A direct callee that cannot reach the root journal: a non-entry source
/// function with a scalar result whose body calls nothing, allocates nothing
/// and writes only checked scalar words. Any lexical frame of its own opens
/// and closes above the caller's (or erases, for a borrowing scalar body), so
/// the caller's current frame keeps exactly the owners it had.
pub fn neutralCall(module: *const wasm.Module, id: u32) bool {
    if (id >= module.functions.items.len or module.runtimeHelper(id)) return false;
    const callee = &module.functions.items[id];
    if (callee.entry or callee.result_role != .scalar) return false;
    if (module.start != null and module.start.? == id) return false;
    const body = callee.instructions.items;
    for (body, 0..) |inst, at| switch (inst.op) {
        .call, .call_import, .call_indirect, .global_set, .memory_copy, .memory_fill, .memory_grow, .resource_retire, .wide_layouts, .host_ref_get, .host_ref_set, .host_ref_size, .host_ref_grow => return false,
        .i32_store, .f32_store, .v128_store => if (!ir.hasScalarStore(body, at)) return false,
        .ownership => {
            const fact: ir.Ownership = @bitCast(inst.operand);
            if (fact.kind == .call_result) return false;
            if (fact.kind == .scope and fact.chunk != 14 and (fact.chunk > 1 or fact.roles != 0)) return false;
        },
        else => {},
    };
    return true;
}

/// Executable instructions that leave the current frame's owners unchanged.
fn empty(code: []const ir.Instruction, at: usize, module: *const wasm.Module, actions: []const Action) bool {
    const inst = code[at];
    if (scalar(inst, module)) return true;
    return switch (inst.op) {
        .unreachable_ => true,
        .i32_store, .f32_store, .v128_store => ir.hasScalarStore(code, at),
        .call => neutralCall(module, inst.operand),
        // Exact read/write facts are bookkeeping for the next instruction.
        .ownership => actions[at] != .keep or ir.hasScalarStore(code, at + 1) or ir.hasNonzeroRead(code, at + 1),
        else => false,
    };
}

pub fn prove(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?[]Action {
    // A close also drains resource cleanup. Keep that exact boundary until a
    // separate proof can transport its drain, rather than delaying a callback.
    if (module.resourceDrainImport() != null) return null;
    const code = source.instructions.items;
    if (code.len > 16384) return null;
    var any_open = false;
    for (code) |inst| if (marker(inst, 0)) {
        any_open = true;
        break;
    };
    if (!any_open) return null;
    var graph = try flow.Graph.init(a, code);
    defer graph.deinit(a);
    if (!graph.valid) return null;
    const marks = try a.alloc(u32, graph.nodes.len);
    defer a.free(marks);
    @memset(marks, 0);
    const actions = try a.alloc(Action, code.len);
    errdefer a.free(actions);
    @memset(actions, .keep);
    var pending: std.ArrayList(u32) = .empty;
    defer pending.deinit(a);
    // Dead code after a trap still has structured edges; it cannot enter.
    const reachable = try a.alloc(bool, graph.nodes.len);
    defer a.free(reachable);
    @memset(reachable, false);
    reachable[0] = true;
    try pending.append(a, 0);
    var reach_cursor: usize = 0;
    while (reach_cursor < pending.items.len) : (reach_cursor += 1) {
        for (graph.nodes[pending.items[reach_cursor]].next) |next| {
            if (next == flow.absent or reachable[next]) continue;
            reachable[next] = true;
            try pending.append(a, next);
        }
    }
    var work: usize = 1 << 20;
    var found = false;
    // Inner frames come later in the code. Proving them first lets an
    // enclosing frame pass through their removed open/close pair.
    var start = code.len;
    while (start != 0) {
        start -= 1;
        if (!marker(code[start], 0)) continue;
        const stamp: u32 = @intCast(start + 1);
        pending.clearRetainingCapacity();
        marks[start] = stamp;
        try pending.append(a, @intCast(start + 1));
        marks[start + 1] = stamp;
        var cursor: usize = 0;
        var valid = true;
        var closed = false;
        while (cursor < pending.items.len) : (cursor += 1) {
            if (work == 0) {
                valid = false;
                break;
            }
            work -= 1;
            const at = pending.items[cursor];
            if (at == code.len) {
                valid = false;
                break;
            }
            if (marker(code[at], 1) and actions[at] == .keep) {
                closed = true;
                continue;
            }
            if (!empty(code, at, module, actions)) {
                valid = false;
                break;
            }
            // A trap ends the invocation; it is not a normal frame exit.
            if (code[at].op == .unreachable_) continue;
            for (graph.nodes[at].next) |next| {
                if (next == flow.absent or marks[next] == stamp) continue;
                marks[next] = stamp;
                try pending.append(a, next);
            }
        }
        if (!valid or !closed) continue;
        // A close reached from another opening cannot be rewritten using this
        // path's proof. Require the whole region to have this sole entry.
        for (pending.items) |at| {
            var edge = graph.nodes[at].first;
            while (edge != flow.absent) {
                const previous = graph.predecessors.items[edge];
                if (reachable[previous.from] and marks[previous.from] != stamp) {
                    valid = false;
                }
                edge = previous.next;
            }
        }
        if (!valid) continue;
        actions[start] = .open;
        for (pending.items) |at| if (marker(code[at], 1) and actions[at] == .keep) {
            actions[at] = .close;
        };
        found = true;
    }
    if (found) return actions;
    a.free(actions);
    return null;
}

fn scope(chunk: u4) ir.Instruction {
    return .{ .op = .ownership, .operand = @bitCast(ir.Ownership{ .kind = .scope, .chunk = chunk }) };
}

fn boundaries(a: A) !void {
    var module = wasm.Module.init(a);
    defer module.deinit();
    const arena = try module.ensureArena();
    const function = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(function, &.{
        scope(0),                             .{ .op = .local_get },                .{ .op = .if_ },
        .{ .op = .i32_const, .operand = 41 }, .{ .op = .local_set },                scope(1),
        .{ .op = .else_ },                    .{ .op = .i32_const, .operand = 42 }, .{ .op = .local_set },
        scope(1),                             .{ .op = .end },                      .{ .op = .local_get },
    });
    const source = &module.functions.items[function];
    const original = try a.dupe(ir.Instruction, source.instructions.items);
    defer a.free(original);
    const actions = (try prove(a, &module, source)).?;
    defer a.free(actions);
    try std.testing.expectEqual(Action.open, actions[0]);
    try std.testing.expectEqual(Action.close, actions[5]);
    try std.testing.expectEqual(Action.close, actions[9]);
    // Physical scalar results never authorize an allocating, importing,
    // unknown, publishing, trapping or reference-returning operation.
    for ([_]ir.Instruction{
        .{ .op = .call, .operand = arena.allocate_typed },
        .{ .op = .call, .operand = arena.root_public_allocate },
        .{ .op = .call, .operand = arena.cycle_safe },
        .{ .op = .call_import },
        .{ .op = .call_indirect },
        .{ .op = .i32_store },
        .{ .op = .global_set },
        .{ .op = .return_ },
        ir.scalarStore(4),
        scope(5),
        scope(2),
    }) |bad| {
        source.instructions.items[3] = bad;
        try std.testing.expect(try prove(a, &module, source) == null);
    }
    // A trap abandons the whole invocation to failure cleanup, where an
    // unopened empty frame has nothing to close.
    source.instructions.items[3] = .{ .op = .unreachable_ };
    const trapped = (try prove(a, &module, source)).?;
    defer a.free(trapped);
    try std.testing.expectEqual(Action.open, trapped[0]);
    try std.testing.expectEqual(Action.close, trapped[9]);
    source.instructions.items[3] = original[3];
    try std.testing.expectEqualSlices(ir.Instruction, original, source.instructions.items);
    const shared = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(shared, &.{
        .{ .op = .local_get },                .{ .op = .if_ }, scope(0), .{ .op = .end },
        .{ .op = .i32_const, .operand = 42 }, scope(1),
    });
    // The false edge reaches the same close without entering this frame.
    try std.testing.expect(try prove(a, &module, &module.functions.items[shared]) == null);
    try nested(a, &module);
}

/// A reference-returning body: an outer frame around a loop whose iteration
/// frame holds a bounds trap, a checked numeric word and a leaf call.
fn nested(a: A, module: *wasm.Module) !void {
    const arena = module.arena.?;
    const leaf = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(leaf, &.{ .{ .op = .local_get }, .{ .op = .i32_const, .operand = 1 }, .{ .op = .i32_add } });
    const allocating = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(allocating, &.{ .{ .op = .local_get }, .{ .op = .i32_const }, .{ .op = .call, .operand = arena.allocate_typed } });
    const writes = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(writes, &.{ .{ .op = .local_get }, .{ .op = .local_get }, .{ .op = .i32_store }, .{ .op = .i32_const } });
    const borrowed = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    try module.emitSlice(borrowed, &.{.{ .op = .local_get }});
    const function = try module.addTypedFunction(&.{.i32}, .i32, .reference);
    const code = [_]ir.Instruction{
        scope(0),                          .{ .op = .block },                   .{ .op = .loop },
        scope(0),                          .{ .op = .local_get },               .{ .op = .local_get },
        ir.scalarStore(4),                 .{ .op = .i32_store, .operand = 4 }, .{ .op = .local_get },
        .{ .op = .call, .operand = leaf }, .{ .op = .drop },                    .{ .op = .local_get },
        .{ .op = .if_ },                   .{ .op = .unreachable_ },            .{ .op = .end },
        scope(1),                          .{ .op = .local_get },               .{ .op = .br_if },
        .{ .op = .end },                   .{ .op = .end },                     scope(1),
        .{ .op = .local_get },
    };
    try module.emitSlice(function, &code);
    const source = &module.functions.items[function];
    const actions = (try prove(a, module, source)).?;
    defer a.free(actions);
    // The inner frame is proved first; the outer frame then passes through
    // its removed pair. The checked result role plays no part.
    for ([_]usize{ 0, 3 }) |at| try std.testing.expectEqual(Action.open, actions[at]);
    for ([_]usize{ 15, 20 }) |at| try std.testing.expectEqual(Action.close, actions[at]);
    // Allocating, writing or reference-returning callees and an unchecked
    // word keep both frames.
    for ([_]ir.Instruction{
        .{ .op = .call, .operand = allocating },
        .{ .op = .call, .operand = writes },
        .{ .op = .call, .operand = borrowed },
        .{ .op = .call, .operand = arena.store_word },
    }) |bad| {
        source.instructions.items[9] = bad;
        try std.testing.expect(try prove(a, module, source) == null);
    }
    source.instructions.items[9] = code[9];
    source.instructions.items[6] = .{ .op = .nop };
    try std.testing.expect(try prove(a, module, source) == null);
    source.instructions.items[6] = code[6];
    try std.testing.expectEqualSlices(ir.Instruction, &code, source.instructions.items);
}

test "empty lexical root frames require every executable path, nest, and preserve source through OOM" {
    try boundaries(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, boundaries, .{});
}
