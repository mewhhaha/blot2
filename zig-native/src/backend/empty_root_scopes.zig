//! Empty lexical frames are proved from the current executable instructions.
//! Calls, publications, memory writes and reference exits retain their frame.
//! Function/entry frames are outside this proof, including public allocation.
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
        else => false,
    };
}

fn marker(inst: ir.Instruction, chunk: u4) bool {
    if (inst.op != .ownership) return false;
    const fact: ir.Ownership = @bitCast(inst.operand);
    return fact.kind == .scope and fact.chunk == chunk and fact.roles == 0;
}

pub fn prove(a: A, module: *const wasm.Module, source: *const ir.Function) A.Error!?[]Action {
    // A close also drains resource cleanup. Keep that exact boundary until a
    // separate proof can transport its drain, rather than delaying a callback.
    if (source.result_role != .scalar or module.resourceDrainImport() != null) return null;
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
    var work: usize = 65536;
    var found = false;
    for (code, 0..) |inst, start| {
        if (!marker(inst, 0)) continue;
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
            if (marker(code[at], 1)) {
                closed = true;
                continue;
            }
            if (!scalar(code[at], module)) {
                valid = false;
                break;
            }
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
                if (marks[previous.from] != stamp) valid = false;
                edge = previous.next;
            }
        }
        if (!valid) continue;
        actions[start] = .open;
        for (pending.items) |at| if (marker(code[at], 1)) {
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
        .{ .op = .unreachable_ },
        scope(5),
        scope(2),
    }) |bad| {
        source.instructions.items[3] = bad;
        try std.testing.expect(try prove(a, &module, source) == null);
    }
    source.instructions.items[3] = original[3];
    try std.testing.expectEqualSlices(ir.Instruction, original, source.instructions.items);
    const shared = try module.addTypedFunction(&.{.i32}, .i32, .scalar);
    try module.emitSlice(shared, &.{
        .{ .op = .local_get },                .{ .op = .if_ }, scope(0), .{ .op = .end },
        .{ .op = .i32_const, .operand = 42 }, scope(1),
    });
    // The false edge reaches the same close without entering this frame.
    try std.testing.expect(try prove(a, &module, &module.functions.items[shared]) == null);
}

test "empty lexical scalar root frames require every executable path and preserve source through OOM" {
    try boundaries(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, boundaries, .{});
}
