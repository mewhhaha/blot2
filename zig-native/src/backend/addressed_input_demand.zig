//! Completed private input demand for immutable addressed bundles.
const std = @import("std");
const ir = @import("runtime_ir.zig");

pub const Bundle = struct { parameter: u32, first: u32, words: usize };
pub const Result = struct { used: []bool, omitted: usize, loads: usize };

fn wordOffset(word: usize) ?u32 {
    if (word > std.math.maxInt(u32) / 4) return null;
    return @intCast(word * 4);
}

fn contains(bundle: Bundle, local: u32) bool {
    if (local < bundle.first) return false;
    return @as(usize, local - bundle.first) < bundle.words;
}

/// The caller proves snapshot storage and invocation lifetime, and excludes
/// semantic instruction coordinates before calling. Null leaves the function
/// unchanged. One/two reads load at their use; three or more retain the logical
/// local with one entry load. The caller owns `used`, in concatenated bundle-word
/// order. `loads` counts generated loads, including entry loads.
pub fn materialize(a: std.mem.Allocator, function: *ir.Function, bundles: []const Bundle) std.mem.Allocator.Error!?Result {
    const local_count = std.math.add(usize, function.parameters.len, function.locals.items.len) catch return null;
    var words: usize = 0;
    for (bundles, 0..) |bundle, index| {
        if (bundle.parameter >= function.parameters.len or function.parameters[bundle.parameter] != .i32) return null;
        if (bundle.words == 0 or wordOffset(bundle.words - 1) == null) return null;
        if (bundle.first < function.parameters.len or bundle.first > local_count) return null;
        if (bundle.words > local_count - bundle.first) return null;
        if (bundle.words - 1 > std.math.maxInt(u32) - bundle.first) return null;
        for (function.locals.items[bundle.first - function.parameters.len ..][0..bundle.words]) |ty| {
            if (ty != .i32) return null;
        }
        for (bundles[0..index]) |previous| {
            if (contains(previous, bundle.first) or contains(bundle, previous.first)) return null;
        }
        words = std.math.add(usize, words, bundle.words) catch return null;
    }
    for (function.instructions.items) |inst| {
        // These operands can carry identities outside ordinary local reads.
        if (inst.op == .ownership or inst.op == .resource_retire or inst.table_reference or inst.table_kind != .unknown) return null;
        if (inst.op != .local_get and inst.op != .local_set and inst.op != .local_tee) continue;
        if (inst.operand >= local_count) return null;
        for (bundles) |bundle| {
            if (inst.op != .local_get) {
                if (contains(bundle, inst.operand) or inst.operand == bundle.parameter) return null;
            }
        }
    }
    const used = try a.alloc(bool, words);
    errdefer a.free(used);
    @memset(used, false);
    const reads = try a.alloc(u2, words);
    defer a.free(reads);
    @memset(reads, 0);
    for (function.instructions.items) |inst| {
        if (inst.op != .local_get) continue;
        var first: usize = 0;
        for (bundles) |bundle| {
            if (contains(bundle, inst.operand)) {
                const index = first + inst.operand - bundle.first;
                used[index] = true;
                reads[index] +|= 1;
                break;
            }
            first += bundle.words;
        }
    }
    var loads: usize = 0;
    var added: usize = 0;
    var omitted: usize = 0;
    for (reads) |count| {
        if (count == 0) {
            omitted += 1;
            continue;
        }
        if (count == 3) {
            added = std.math.add(usize, added, 3) catch {
                a.free(used);
                return null;
            };
            loads = std.math.add(usize, loads, 1) catch unreachable;
        } else {
            added = std.math.add(usize, added, count) catch {
                a.free(used);
                return null;
            };
            loads = std.math.add(usize, loads, count) catch unreachable;
        }
    }
    const length = std.math.add(usize, function.instructions.items.len, added) catch {
        a.free(used);
        return null;
    };
    if (loads == 0) return .{ .used = used, .omitted = omitted, .loads = 0 };
    // Stage the complete replacement: an allocation failure cannot partially
    // rewrite a body, its signature or its logical local inventory.
    var lowered: std.ArrayList(ir.Instruction) = .empty;
    errdefer lowered.deinit(a);
    try lowered.ensureTotalCapacityPrecise(a, length);
    var first_word: usize = 0;
    for (bundles) |bundle| {
        for (reads[first_word..][0..bundle.words], 0..) |count, word| {
            if (count != 3) continue;
            lowered.appendAssumeCapacity(.{ .op = .local_get, .operand = bundle.parameter });
            lowered.appendAssumeCapacity(.{ .op = .i32_load, .operand = wordOffset(word).? });
            lowered.appendAssumeCapacity(.{ .op = .local_set, .operand = bundle.first + @as(u32, @intCast(word)) });
        }
        first_word += bundle.words;
    }
    for (function.instructions.items) |inst| {
        var first: usize = 0;
        var replaced = false;
        if (inst.op == .local_get) {
            for (bundles) |bundle| {
                if (contains(bundle, inst.operand)) {
                    const word = inst.operand - bundle.first;
                    if (reads[first + word] == 3) break;
                    lowered.appendAssumeCapacity(.{ .op = .local_get, .operand = bundle.parameter, .origin = inst.origin });
                    lowered.appendAssumeCapacity(.{ .op = .i32_load, .operand = wordOffset(word).?, .origin = inst.origin });
                    replaced = true;
                    break;
                }
                first += bundle.words;
            }
        }
        if (!replaced) lowered.appendAssumeCapacity(inst);
    }
    function.instructions.deinit(a);
    function.instructions = lowered;
    return .{ .used = used, .omitted = omitted, .loads = loads };
}

test "addressed input demand loads each exact use without moving effects or output serialization" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{ .i32, .i32, .i32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 79 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 6);
    const body = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 5, .origin = 42 },
        .{ .op = .call, .operand = 91, .origin = 9 },
        .{ .op = .local_get, .operand = 5, .origin = 43 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = 6 },
        .{ .op = .local_get, .operand = 2, .origin = 8 },
        .{ .op = .local_get, .operand = 7, .origin = 44 },
        .{ .op = .i32_store, .operand = 20 },
        .{ .op = .local_get, .operand = 6 },
    };
    try function.instructions.appendSlice(a, &body);
    const locals = function.locals.items.ptr;
    const result = (try materialize(a, &function, &.{
        .{ .parameter = 1, .first = 3, .words = 3 },
        .{ .parameter = 0, .first = 7, .words = 2 },
    })).?;
    defer a.free(result.used);
    try std.testing.expectEqualSlices(bool, &.{ false, false, true, true, false }, result.used);
    try std.testing.expectEqual(@as(usize, 3), result.omitted);
    try std.testing.expectEqual(@as(usize, 3), result.loads);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .local_get, .operand = 1, .origin = 42 },
        .{ .op = .i32_load, .operand = 8, .origin = 42 },
        body[1],
        .{ .op = .local_get, .operand = 1, .origin = 43 },
        .{ .op = .i32_load, .operand = 8, .origin = 43 },
        body[3],
        body[4],
        body[5],
        .{ .op = .local_get, .operand = 0, .origin = 44 },
        .{ .op = .i32_load, .origin = 44 },
        body[7],
        body[8],
    }, function.instructions.items);
    try std.testing.expectEqual(@as(u32, 79), function.signature);
    try std.testing.expectEqual(parameters[0..].ptr, function.parameters.ptr);
    try std.testing.expectEqual(locals, function.locals.items.ptr);
    try std.testing.expectEqual(@as(usize, 6), function.locals.items.len);
}

test "addressed input demand leaves forwarding pointer calls and unread words without loads" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .none, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 2);
    const body = [_]ir.Instruction{ .{ .op = .local_get }, .{ .op = .call, .operand = 4 } };
    try function.instructions.appendSlice(a, &body);
    const result = (try materialize(a, &function, &.{.{ .parameter = 0, .first = 1, .words = 2 }})).?;
    defer a.free(result.used);
    try std.testing.expectEqualSlices(bool, &.{ false, false }, result.used);
    try std.testing.expectEqual(@as(usize, 2), result.omitted);
    try std.testing.expectEqual(@as(usize, 0), result.loads);
    try std.testing.expectEqualSlices(ir.Instruction, &body, function.instructions.items);
}

test "addressed input demand retains frequently read logical words with one entry load" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .none, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 2);
    const body = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 1, .origin = 1 },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = 1, .origin = 2 },
        .{ .op = .call, .operand = 17 },
        .{ .op = .local_get, .operand = 1, .origin = 3 },
        .{ .op = .drop },
        .{ .op = .local_get, .operand = 1, .origin = 4 },
        .{ .op = .drop },
    };
    try function.instructions.appendSlice(a, &body);
    const result = (try materialize(a, &function, &.{.{ .parameter = 0, .first = 1, .words = 2 }})).?;
    defer a.free(result.used);
    try std.testing.expectEqual(@as(usize, 1), result.loads);
    try std.testing.expectEqual(@as(usize, 1), result.omitted);
    try std.testing.expectEqualSlices(bool, &.{ true, false }, result.used);
    try std.testing.expectEqualSlices(ir.Instruction, &.{
        .{ .op = .local_get },
        .{ .op = .i32_load },
        .{ .op = .local_set, .operand = 1 },
    }, function.instructions.items[0..3]);
    try std.testing.expectEqualSlices(ir.Instruction, &body, function.instructions.items[3..]);
}

test "addressed input demand declines written words pointers and hidden identities without mutation" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .none, .signature = 0 };
    defer function.deinit(a);
    try function.locals.append(a, .i32);
    try function.instructions.append(a, .{ .op = .nop });
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]ir.Instruction{
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_tee, .operand = 1 },
        .{ .op = .local_set },
        .{ .op = .local_tee },
        .{ .op = .ownership },
        .{ .op = .resource_retire },
        .{ .op = .i32_const, .table_reference = true },
        .{ .op = .local_get, .operand = 1, .table_kind = .callable },
        .{ .op = .local_get, .operand = 2 },
    }) |inst| {
        function.instructions.items[0] = inst;
        try std.testing.expect(try materialize(failing.allocator(), &function, &.{.{ .parameter = 0, .first = 1, .words = 1 }}) == null);
        try std.testing.expectEqual(inst, function.instructions.items[0]);
    }
}

test "addressed input demand validates disjoint typed ranges and complete word offsets" {
    const a = std.testing.allocator;
    try std.testing.expectEqual(@as(u32, 4294967292), wordOffset(1073741823).?);
    try std.testing.expect(wordOffset(1073741824) == null);
    var parameters = [_]ir.ValueType{ .i32, .f32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .none, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendSlice(a, &.{ .i32, .i32, .f32 });
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]Bundle{
        .{ .parameter = 1, .first = 2, .words = 1 },
        .{ .parameter = 2, .first = 2, .words = 1 },
        .{ .parameter = 0, .first = 0, .words = 1 },
        .{ .parameter = 0, .first = 2, .words = 0 },
        .{ .parameter = 0, .first = 4, .words = 1 },
        .{ .parameter = 0, .first = 5, .words = 1 },
        .{ .parameter = 0, .first = std.math.maxInt(u32), .words = 2 },
        .{ .parameter = 0, .first = 2, .words = 1073741825 },
    }) |bundle| {
        try std.testing.expect(try materialize(failing.allocator(), &function, &.{bundle}) == null);
    }
    try std.testing.expect(try materialize(failing.allocator(), &function, &.{
        .{ .parameter = 0, .first = 2, .words = 2 },
        .{ .parameter = 0, .first = 3, .words = 1 },
    }) == null);
}

fn allocationFailures(a: std.mem.Allocator) !void {
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 19 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 3);
    const body = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 2, .origin = 37 },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 3 },
        .{ .op = .i32_add },
    };
    try function.instructions.appendSlice(a, &body);
    const result = materialize(a, &function, &.{.{ .parameter = 0, .first = 1, .words = 3 }}) catch |err| {
        try std.testing.expectEqualSlices(ir.Instruction, &body, function.instructions.items);
        try std.testing.expectEqual(@as(u32, 19), function.signature);
        try std.testing.expectEqual(@as(usize, 3), function.locals.items.len);
        return err;
    };
    const accepted = result.?;
    defer a.free(accepted.used);
    try std.testing.expectEqualSlices(bool, &.{ false, true, true }, accepted.used);
    try std.testing.expectEqual(@as(usize, 1), accepted.omitted);
    try std.testing.expectEqual(@as(usize, 3), accepted.loads);
    try std.testing.expectEqual(@as(usize, 14), function.instructions.items.len);
}

test "addressed input demand stages all mutations through full OOM" {
    try allocationFailures(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, allocationFailures, .{});
}
