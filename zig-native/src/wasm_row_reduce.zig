//! Combine bounded, scalar-only wrapping sums over adjacent words. The proof
//! sees instructions and local uses, never source names. Every removed local
//! has exactly one definition and one read; no effect or control edge moves.
//! Run after lifetime lowering: scalar pointer provenance must be consumed
//! before vector lanes erase it. Inserted cleanup calls are hard boundaries.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const Uses = struct { reads: u8 = 0, writes: u8 = 0 };
const Plan = struct {
    end: usize,
    accumulator: u32,
    base: u32,
    result: u32,
    offset: u32,
    words: u32,
};
fn is(inst: ir.Instruction, op: ir.Op, operand: u32) bool {
    return inst.op == op and inst.operand == operand;
}
fn privateLocal(uses: []const Uses, id: u32) bool {
    return id < uses.len and uses[id].reads == 1 and uses[id].writes == 1;
}
fn match(source: []const ir.Instruction, at: usize, uses: []const Uses) ?Plan {
    if (at > source.len or source.len - at < 13 or source[at].op != .local_get or source[at + 1].op != .local_set) return null;
    const accumulator = source[at].operand;
    var carry = source[at + 1].operand;
    const base = source[at + 2].operand;
    var cursor = at + 2;
    var offsets: [16]u32 = undefined;
    var count: usize = 0;
    while (count < offsets.len and cursor <= source.len and source.len - cursor >= 11) {
        const part = source[cursor..][0..11];
        if (!is(part[0], .local_get, base) or part[1].op != .i32_load or part[2].op != .local_set or
            !is(part[3], .local_get, carry) or part[4].op != .local_set or
            !is(part[5], .local_get, part[2].operand) or part[6].op != .local_set or
            !is(part[7], .local_get, part[4].operand) or !is(part[8], .local_get, part[6].operand) or
            part[9].op != .i32_add or part[10].op != .local_set) break;
        if (!privateLocal(uses, carry) or !privateLocal(uses, part[2].operand) or
            !privateLocal(uses, part[4].operand) or !privateLocal(uses, part[6].operand)) break;
        offsets[count] = part[1].operand;
        count += 1;
        cursor += 11;
        carry = part[10].operand;
    }
    if (count < 8) return null;
    const first = std.mem.min(u32, offsets[0..count]);
    var seen: u16 = 0;
    for (offsets[0..count]) |offset| {
        const difference = offset - first;
        if (difference % 4 != 0 or difference / 4 >= count) return null;
        const bit = @as(u16, 1) << @intCast(difference / 4);
        if (seen & bit != 0) return null;
        seen |= bit;
    }
    return .{ .end = cursor, .accumulator = accumulator, .base = base, .result = carry, .offset = first, .words = @intCast(count) };
}
fn emit(out: *ir.Body, a: A, plan: Plan, vector: u32) A.Error!void {
    try out.emit(a, .local_get, plan.accumulator);
    const groups = plan.words / 4;
    for (0..groups) |group| {
        try out.emit(a, .local_get, plan.base);
        try out.emit(a, .v128_load, plan.offset + @as(u32, @intCast(group)) * 16);
        if (group != 0) try out.emit(a, .i32x4_add, 0);
    }
    try out.emit(a, .local_set, vector);
    for (0..4) |lane| {
        try out.emit(a, .local_get, vector);
        try out.emit(a, .i32x4_extract_lane, @intCast(lane));
        try out.emit(a, .i32_add, 0);
    }
    for (groups * 4..plan.words) |word| {
        try out.emit(a, .local_get, plan.base);
        try out.emit(a, .i32_load, plan.offset + @as(u32, @intCast(word)) * 4);
        try out.emit(a, .i32_add, 0);
    }
    try out.emit(a, .local_set, plan.result);
}
pub fn run(a: A, function: *const ir.Function) A.Error!?ir.Body {
    const source = function.instructions.items;
    if (source.len < 90) return null;
    // Most bodies contain no eligible row. Avoid allocating use tables there.
    var possible = false;
    for (0..source.len - 3) |at| {
        if (source[at].op == .local_get and source[at + 1].op == .local_set and
            source[at + 2].op == .local_get and source[at + 3].op == .i32_load)
        {
            possible = true;
            break;
        }
    }
    if (!possible) return null;
    const count = std.math.add(usize, function.parameters.len, function.locals.items.len) catch return null;
    if (count > 65536) return null;
    const uses = try a.alloc(Uses, count);
    defer a.free(uses);
    @memset(uses, .{});
    for (source) |inst| switch (inst.op) {
        .local_get => uses[inst.operand].reads +|= 1,
        .local_set => uses[inst.operand].writes +|= 1,
        .local_tee => uses[inst.operand].writes +|= 1,
        else => {},
    };
    var out: ir.Body = .{};
    errdefer out.deinit(a);
    var changed = false;
    var copied: usize = 0;
    var at: usize = 0;
    while (at <= source.len and source.len - at >= 90) : (at += 1) {
        const plan = match(source, at, uses) orelse continue;
        if (!changed) {
            try out.locals.appendSlice(a, function.locals.items);
            try out.locals.append(a, .v128);
            changed = true;
        }
        try out.instructions.appendSlice(a, source[copied..at]);
        try emit(&out, a, plan, @intCast(count));
        copied = plan.end;
        at = plan.end - 1;
    }
    if (!changed) return null;
    try out.instructions.appendSlice(a, source[copied..]);
    return out;
}

const Fixture = struct { function: u32, first_carry: u32 };
fn fixture(module: *@import("wasm.zig").Module, words: u32) !Fixture {
    const function = try module.addFunction(&.{ .i32, .i32 }, .i32);
    var carry = try module.addLocal(function, .i32);
    const first_carry = carry;
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = 1 }, .{ .op = .local_set, .operand = carry } });
    for (0..words) |word| {
        const value = try module.addLocal(function, .i32);
        const left = try module.addLocal(function, .i32);
        const right = try module.addLocal(function, .i32);
        const next = try module.addLocal(function, .i32);
        try module.emitSlice(function, &.{
            .{ .op = .local_get },
            .{ .op = .i32_load, .operand = (words - 1 - @as(u32, @intCast(word))) * 4 },
            .{ .op = .local_set, .operand = value },
            .{ .op = .local_get, .operand = carry },
            .{ .op = .local_set, .operand = left },
            .{ .op = .local_get, .operand = value },
            .{ .op = .local_set, .operand = right },
            .{ .op = .local_get, .operand = left },
            .{ .op = .local_get, .operand = right },
            .{ .op = .i32_add },
            .{ .op = .local_set, .operand = next },
        });
        carry = next;
    }
    try module.emitSlice(function, &.{ .{ .op = .local_get, .operand = carry }, .{ .op = .return_ } });
    return .{ .function = function, .first_carry = first_carry };
}
fn ownership(a: A) !void {
    var module = @import("wasm.zig").Module.init(a);
    defer module.deinit();
    const made = try fixture(&module, 14);
    const source = &module.functions.items[made.function];
    const before = try a.dupe(ir.Instruction, source.instructions.items);
    defer a.free(before);
    var out = (try run(a, source)).?;
    defer out.deinit(a);
    var vectors: usize = 0;
    var tails: usize = 0;
    for (out.instructions.items) |inst| {
        if (inst.op == .v128_load) vectors += 1;
        if (inst.op == .i32_load) tails += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), vectors);
    try std.testing.expectEqual(@as(usize, 2), tails);
    try std.testing.expectEqualSlices(ir.Instruction, before, source.instructions.items);
}
test "wrapping row reductions preserve immutable bodies through allocation failure" {
    try ownership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, ownership, .{});
}
test "wrapping row reductions use exact byte ranges for every admitted width" {
    const a = std.testing.allocator;
    for (1..17) |words| {
        var module = @import("wasm.zig").Module.init(a);
        defer module.deinit();
        const made = try fixture(&module, @intCast(words));
        if (try run(a, &module.functions.items[made.function])) |body| {
            var out = body;
            defer out.deinit(a);
            try std.testing.expect(words >= 8);
            var loaded: usize = 0;
            for (out.instructions.items) |inst| {
                const bytes: u32 = if (inst.op == .v128_load) 16 else if (inst.op == .i32_load) 4 else continue;
                try std.testing.expect(inst.operand + bytes <= words * 4);
                loaded += bytes;
            }
            try std.testing.expectEqual(words * 4, loaded);
        } else try std.testing.expect(words < 8);
    }
}
test "wrapping row reductions retain observed temporaries and decline traps gaps floating sums and cleanup calls" {
    const a = std.testing.allocator;
    for (0..5) |variant| {
        var module = @import("wasm.zig").Module.init(a);
        defer module.deinit();
        const cleanup = try module.addFunction(&.{}, .none);
        const made = try fixture(&module, 8);
        const source = &module.functions.items[made.function];
        switch (variant) {
            0 => try module.emitSlice(made.function, &.{ .{ .op = .local_get, .operand = made.first_carry }, .{ .op = .drop } }),
            1 => source.instructions.items[11].op = .i32_div_u,
            2 => source.instructions.items[3].operand = 64,
            3 => {
                source.parameters[1] = .f32;
                source.result = .f32;
                @memset(source.locals.items, .f32);
                for (source.instructions.items) |*inst| switch (inst.op) {
                    .i32_load => inst.op = .f32_load,
                    .i32_add => inst.op = .f32_add,
                    else => {},
                };
            },
            4 => try source.instructions.insert(a, 46, .{ .op = .call, .operand = cleanup }),
            else => unreachable,
        }
        try std.testing.expect(try run(a, source) == null);
    }
}
