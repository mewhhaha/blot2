//! Put frequently encoded locals below Wasm's ULEB index thresholds.
//! This is a type-preserving permutation after semantic lowering: parameters,
//! instruction order, zero initialization and every packed flag remain intact.
const std = @import("std");
const ir = @import("runtime_ir.zig");
const A = std.mem.Allocator;

fn local(op: ir.Op) bool {
    return op == .local_get or op == .local_set or op == .local_tee;
}
fn uleb(value: usize) u64 {
    var rest = value;
    var bytes: u64 = 1;
    while (rest >= 128) : (rest >>= 7) bytes += 1;
    return bytes;
}
fn declarationBytes(types: []const ir.ValueType, order: ?[]const u32) u64 {
    var groups: usize = 0;
    var bytes: u64 = 0;
    var start: usize = 0;
    while (start < types.len) {
        var first = start;
        if (order) |indices| first = indices[start];
        var end = start + 1;
        while (end < types.len) : (end += 1) {
            var next = end;
            if (order) |indices| next = indices[end];
            if (types[next] != types[first]) break;
        }
        groups += 1;
        bytes += uleb(end - start) + 1;
        start = end;
    }
    return uleb(groups) + bytes;
}

pub fn run(a: A, source: *const ir.Function) A.Error!?ir.Body {
    const parameters = source.parameters.len;
    const count = source.locals.items.len;
    if (count < 2) return null;
    const total = std.math.add(usize, parameters, count) catch return null;
    if (total > std.math.maxInt(u32) or source.instructions.items.len > std.math.maxInt(u32)) return null;
    // No operand can get shorter inside a single encoding-width bucket.
    if (uleb(parameters) == uleb(total - 1)) return null;
    for (source.instructions.items) |inst| switch (inst.op) {
        // These markers may hide local identities outside ordinary operands.
        .ownership, .resource_retire, .wide_layouts => return null,
        .local_get, .local_set, .local_tee => if (inst.operand >= total) return null,
        else => {},
    };
    const weights = try a.alloc(u32, count);
    defer a.free(weights);
    @memset(weights, 0);
    for (source.instructions.items) |inst| if (local(inst.op) and inst.operand >= parameters) {
        weights[inst.operand - parameters] += 1;
    };
    const order = try a.alloc(u32, count);
    defer a.free(order);
    for (order, 0..) |*index, original| index.* = @intCast(original);
    std.mem.sort(u32, order, weights, struct {
        fn less(references: []const u32, left: u32, right: u32) bool {
            if (references[left] != references[right]) return references[left] > references[right];
            return left < right;
        }
    }.less);
    var before = declarationBytes(source.locals.items, null);
    var after = declarationBytes(source.locals.items, order);
    for (order, 0..) |original, next| {
        before += @as(u64, weights[original]) * uleb(parameters + original);
        after += @as(u64, weights[original]) * uleb(parameters + next);
    }
    // Reordering mixed types can split declaration runs. Charge their exact
    // encoding too; unchanged instruction bytes and body prefixes cannot grow.
    if (after >= before) return null;
    const mapping = try a.alloc(u32, count);
    defer a.free(mapping);
    var result: ir.Body = .{};
    errdefer result.deinit(a);
    try result.locals.ensureTotalCapacityPrecise(a, count);
    for (order, 0..) |original, next| {
        mapping[original] = @intCast(parameters + next);
        result.locals.appendAssumeCapacity(source.locals.items[original]);
    }
    try result.instructions.ensureTotalCapacityPrecise(a, source.instructions.items.len);
    for (source.instructions.items) |inst| {
        var output = inst;
        if (local(inst.op) and inst.operand >= parameters) output.operand = mapping[inst.operand - parameters];
        result.instructions.appendAssumeCapacity(output);
    }
    return result;
}

test {
    _ = @import("wasm_local_order_tests.zig");
}
