//! Reuse dead scalar temporaries after all ownership/safepoint lowering.
//! Only single-definition i32 locals confined to one straight-line segment
//! share slots. Parameters, zero-initialized reads and cross-control values
//! keep dedicated slots; instruction order and packed metadata are unchanged.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(usize);
const Use = struct {
    segment: usize = absent,
    last: usize = 0,
    definitions: u8 = 0,
    pinned: bool = false,
};
fn boundary(op: ir.Op) bool {
    return switch (op) {
        .block, .loop, .if_, .else_, .end, .br, .br_if, .return_, .unreachable_ => true,
        else => false,
    };
}
fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
pub fn run(a: A, source: *const ir.Function) A.Error!?ir.Body {
    if (source.locals.items.len < 2) return null;
    const parameters = source.parameters.len;
    const total = std.math.add(usize, parameters, source.locals.items.len) catch return null;
    if (total > std.math.maxInt(u32) or source.instructions.items.len >= std.math.maxInt(u32)) return null;
    const uses = try a.alloc(Use, source.locals.items.len);
    defer a.free(uses);
    for (uses, source.locals.items) |*use, ty| use.* = .{ .pinned = ty != .i32 };
    var segment: usize = 0;
    for (source.instructions.items, 0..) |inst, at| {
        // These pseudo-instructions can encode local IDs outside ordinary
        // local operands. Decline rather than rewriting hidden identities.
        if (inst.op == .ownership or inst.op == .resource_retire) return null;
        if (local(inst.op)) {
            if (inst.operand >= total) return null;
            if (inst.operand >= parameters) {
                const use = &uses[inst.operand - parameters];
                if (use.segment == absent) use.segment = segment;
                if (use.segment != segment) use.pinned = true;
                use.last = at;
                if (inst.op == .local_get) {
                    if (use.definitions == 0) use.pinned = true;
                } else use.definitions +|= 1;
            }
        }
        if (boundary(inst.op)) segment += 1;
    }
    var candidates: usize = 0;
    for (uses) |*use| {
        if (use.definitions != 1) use.pinned = true;
        if (!use.pinned) candidates += 1;
    }
    if (candidates < 2) return null;
    var graph = try @import("wasm_control_flow.zig").Graph.init(a, source.instructions.items);
    defer graph.deinit(a);
    if (!graph.valid) return null;
    const slots = try a.alloc(u32, uses.len);
    defer a.free(slots);
    @memset(slots, std.math.maxInt(u32));
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    for (uses, source.locals.items, 0..) |use, ty, index| {
        if (!use.pinned) continue;
        slots[index] = @intCast(parameters + result.locals.items.len);
        try result.locals.append(a, ty);
    }
    var free: std.ArrayList(u32) = .empty;
    defer free.deinit(a);
    try result.instructions.ensureTotalCapacity(a, source.instructions.items.len);
    for (source.instructions.items, 0..) |inst, at| {
        var output = inst;
        if (local(inst.op) and inst.operand >= parameters) {
            const index = inst.operand - parameters;
            const use = uses[index];
            if (slots[index] == std.math.maxInt(u32)) {
                slots[index] = free.pop() orelse next: {
                    const slot: u32 = @intCast(parameters + result.locals.items.len);
                    try result.locals.append(a, .i32);
                    break :next slot;
                };
            }
            output.operand = slots[index];
            if (!use.pinned and use.last == at) try free.append(a, slots[index]);
        }
        result.instructions.appendAssumeCapacity(output);
    }
    if (result.locals.items.len >= source.locals.items.len) {
        result.deinit(a);
        return null;
    }
    return result;
}

test {
    _ = @import("wasm_local_compact_tests.zig");
}
