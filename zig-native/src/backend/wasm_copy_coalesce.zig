//! Coalesce adjacent numeric copies in one root's logical-local call tree.
//! Only copies whose every original read forwards safely disappear. Helpers
//! share root locals; ordinary calls cannot mutate this nonreentrant adapter.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;
const absent = std.math.maxInt(usize);
pub const Body = struct { function: u32, instructions: []const ir.Instruction };
pub const Result = struct {
    bodies: []Body,
    aliases: []u32,
    removed_copies: usize = 0,
    forwarded_reads: usize = 0,
    pub fn deinit(self: *Result, a: A) void {
        for (self.bodies) |body| a.free(body.instructions);
        a.free(self.bodies);
        a.free(self.aliases);
    }
};
const Alias = struct { source: u32, version: usize, segment: usize };
const Use = struct {
    writes: u8 = 0,
    reads: usize = 0,
    forwarded: usize = 0,
    pair: usize = absent,
    body: usize = 0,
    copy_source: u32 = 0,
    version: usize = 0,
    alias: ?Alias = null,
    accepted: bool = false,
};
const Frame = struct { body: usize, next: usize = 0 };
fn neutral(inst: ir.Instruction) bool {
    return !inst.table_reference and inst.table_kind == .unknown;
}
fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
fn boundary(op: ir.Op) bool {
    return switch (op) {
        .block, .loop, .if_, .else_, .end, .br, .br_if, .return_, .unreachable_ => true,
        else => false,
    };
}
fn numeric(source: *const ir.Function, id: u32) bool {
    if (id < source.parameters.len) return source.parameters[id] == .i32;
    return source.locals.items[id - source.parameters.len] == .i32;
}
fn canonical(uses: []const Use, id: u32, segment: usize) u32 {
    if (uses[id].alias) |alias| {
        if (alias.segment == segment and uses[alias.source].version == alias.version) return alias.source;
    }
    return id;
}
pub fn run(a: A, source: *const ir.Function, bodies: []const Body) A.Error!?Result {
    if (bodies.len == 0 or source.locals.items.len == 0) return null;
    const parameters = source.parameters.len;
    const total = std.math.add(usize, parameters, source.locals.items.len) catch return null;
    if (total > std.math.maxInt(u32) or bodies.len > std.math.maxInt(u32)) return null;
    var ids: std.AutoHashMapUnmanaged(u32, usize) = .empty;
    defer ids.deinit(a);
    const offsets = try a.alloc(usize, bodies.len);
    defer a.free(offsets);
    const counts = try a.alloc(usize, bodies.len);
    defer a.free(counts);
    @memset(counts, 0);
    var length: usize = 0;
    for (bodies, 0..) |body, index| {
        const entry = try ids.getOrPut(a, body.function);
        if (entry.found_existing) return null;
        entry.value_ptr.* = index;
        offsets[index] = length;
        length = std.math.add(usize, length, body.instructions.len) catch return null;
        if (length >= std.math.maxInt(u32)) return null;
    }
    const uses = try a.alloc(Use, total);
    defer a.free(uses);
    @memset(uses, .{});
    for (bodies, 0..) |body, index| for (body.instructions, 0..) |inst, at| {
        if (inst.op == .ownership or inst.op == .resource_retire or inst.op == .wide_layouts) return null;
        if (inst.op == .call) if (ids.get(inst.operand)) |callee| {
            if (!neutral(inst) or callee == 0 or counts[callee] != 0) return null;
            counts[callee] = 1;
        };
        if (!local(inst.op)) continue;
        if (inst.operand >= total or !neutral(inst)) return null;
        const use = &uses[inst.operand];
        if (inst.op == .local_get) {
            use.reads += 1;
            continue;
        }
        use.writes +|= 1;
        if (inst.op != .local_set or inst.operand < parameters or at == 0 or !numeric(source, inst.operand)) continue;
        const previous = body.instructions[at - 1];
        if (previous.op != .local_get or previous.operand >= total or !neutral(previous)) continue;
        if (previous.operand == inst.operand or !numeric(source, previous.operand)) continue;
        use.pair = offsets[index] + at;
        use.body = index;
        use.copy_source = previous.operand;
    };
    for (counts[1..]) |count| if (count != 1) return null;
    var candidates: usize = 0;
    for (uses) |use| if (use.writes == 1 and use.pair != absent) {
        candidates += 1;
    };
    if (candidates == 0) return null;
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(a);
    try frames.append(a, .{ .body = 0 });
    var visited: usize = 1;
    var segment: usize = 0;
    while (frames.items.len != 0) {
        const frame = &frames.items[frames.items.len - 1];
        const code = bodies[frame.body].instructions;
        if (frame.next == code.len) {
            _ = frames.pop();
            continue;
        }
        const at = frame.next;
        frame.next += 1;
        const flat = offsets[frame.body] + at;
        const inst = code[at];
        if (inst.op == .call) if (ids.get(inst.operand)) |callee| {
            try frames.append(a, .{ .body = callee });
            visited += 1;
            continue;
        };
        if (inst.op == .local_get) {
            if (canonical(uses, inst.operand, segment) != inst.operand) uses[inst.operand].forwarded += 1;
        } else if (local(inst.op)) {
            const use = &uses[inst.operand];
            // Even a rejected candidate advances its original write version.
            use.version += 1;
            use.alias = null;
            if (use.writes == 1 and use.pair == flat) {
                const src = canonical(uses, code[at - 1].operand, segment);
                use.alias = .{ .source = src, .version = uses[src].version, .segment = segment };
            }
        }
        if (boundary(inst.op)) segment += 1;
    }
    // A disconnected cycle has one incoming call per helper but is not a tree.
    if (visited != bodies.len) return null;
    var removed: usize = 0;
    for (bodies, counts) |body, *count| count.* = body.instructions.len;
    for (uses) |*use| {
        use.accepted = use.writes == 1 and use.pair != absent and use.reads == use.forwarded;
        if (!use.accepted) continue;
        removed += 1;
        counts[use.body] -= 2;
    }
    if (removed == 0) return null;
    var result: Result = .{
        .bodies = try a.alloc(Body, bodies.len),
        .aliases = &.{},
        .removed_copies = removed,
    };
    for (result.bodies, bodies) |*output, input| output.* = .{ .function = input.function, .instructions = &.{} };
    errdefer result.deinit(a);
    result.aliases = try a.alloc(u32, total);
    for (uses, result.aliases, 0..) |use, *alias, id| {
        alias.* = @intCast(id);
        if (use.accepted) alias.* = use.copy_source;
    }
    // Publish only through removed copies. A retained intermediate still owns
    // its captured value and avoids introducing a new root-bank dependency.
    for (0..total) |id| {
        var target = result.aliases[id];
        while (result.aliases[target] != target) target = result.aliases[target];
        var current: u32 = @intCast(id);
        while (result.aliases[current] != target) {
            const next = result.aliases[current];
            result.aliases[current] = target;
            current = next;
        }
    }
    for (bodies, result.bodies, counts, offsets) |body, *output, count, offset| {
        const instructions = try a.alloc(ir.Instruction, count);
        output.instructions = instructions;
        var at: usize = 0;
        var written: usize = 0;
        while (at < body.instructions.len) {
            var inst = body.instructions[at];
            if (inst.op == .local_get and at + 1 < body.instructions.len) {
                const next = body.instructions[at + 1];
                if (next.op == .local_set and uses[next.operand].accepted and uses[next.operand].pair == offset + at + 1) {
                    at += 2;
                    continue;
                }
            }
            if (inst.op == .local_get and uses[inst.operand].accepted) {
                inst.operand = result.aliases[inst.operand];
                result.forwarded_reads += 1;
            }
            instructions[written] = inst;
            written += 1;
            at += 1;
        }
        std.debug.assert(written == count);
    }
    return result;
}

/// Ordinary completed bodies have no shared outlined-local interface. Remove
/// only the eliminated copy destinations, preserving parameters and other slots.
pub fn runSingle(a: A, source: *const ir.Function) A.Error!?ir.Body {
    var result = (try run(a, source, &.{.{ .function = std.math.maxInt(u32), .instructions = source.instructions.items }})) orelse return null;
    defer result.deinit(a);
    var output: ir.Body = .{ .instructions = .fromOwnedSlice(@constCast(result.bodies[0].instructions)) };
    result.bodies[0].instructions = &.{};
    errdefer output.deinit(a);
    for (source.locals.items, 0..) |ty, index| {
        const id = source.parameters.len + index;
        if (result.aliases[id] != id) continue;
        result.aliases[id] = @intCast(source.parameters.len + output.locals.items.len);
        try output.locals.append(a, ty);
    }
    for (output.instructions.items) |*inst| if (local(inst.op)) {
        inst.operand = result.aliases[inst.operand];
    };
    return output;
}

test {
    _ = @import("wasm_copy_coalesce_tests.zig");
}
