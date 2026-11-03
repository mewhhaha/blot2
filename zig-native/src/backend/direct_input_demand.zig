//! Physical inputs of a completed helper, retaining its logical local IDs.
//! Only unpublished scoped helpers without semantic/table position catalogs
//! may use this prefix; the original instruction suffix is never rewritten.
const std = @import("std");
const ir = @import("runtime_ir.zig");
pub const Result = struct { used: []bool, omitted: usize };

/// A packed helper already reserves logical inputs 1..W. If the completed
/// body needs few enough words, retain that numbering with a direct signature;
/// parameter zero becomes the result pointer (or is removed as unread).
pub fn canPromotePacked(a: std.mem.Allocator, function: *const ir.Function, words: usize, serialization_start: usize, result_slot: bool) std.mem.Allocator.Error!bool {
    if (function.parameters.len != 1 or function.locals.items.len < words) return false;
    if (function.entry or function.parameter_roles != 0 or function.callable_layout != 0) return false;
    if (function.provider_parameter != ir.unknown_provider and function.provider_parameter != ir.no_provider) return false;
    for (function.locals.items[0..words]) |ty| if (ty != .i32) return false;
    for (function.instructions.items, 0..) |inst, index| {
        if (inst.op == .ownership or inst.op == .resource_retire or inst.table_reference or inst.table_kind != .unknown) return false;
        if ((inst.op == .local_get or inst.op == .local_set or inst.op == .local_tee) and inst.operand == 0 and (index < serialization_start or !result_slot)) return false;
    }
    const used = try a.alloc(bool, words + 1);
    defer a.free(used);
    @memset(used, false);
    for (function.instructions.items) |inst| {
        if (inst.op == .local_get and inst.operand <= words) used[inst.operand] = true;
    }
    var count: usize = 0;
    for (used) |read| if (read) {
        count += 1;
    };
    return count <= 512;
}

fn promotion(a: std.mem.Allocator) !void {
    var parameters = [_]ir.ValueType{.i32};
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendNTimes(a, .i32, 600);
    for (1..513) |index| try function.instructions.append(a, .{ .op = .local_get, .operand = @intCast(index) });
    try std.testing.expect(try canPromotePacked(a, &function, 600, 512, false));
    try function.instructions.append(a, .{ .op = .local_get, .operand = 0 });
    try std.testing.expect(!try canPromotePacked(a, &function, 600, 512, true));
    function.instructions.items[511].operand = 1;
    try std.testing.expect(try canPromotePacked(a, &function, 600, 512, true));
    // Even one packet-pointer read in the checked body prevents rebasing.
    try std.testing.expect(!try canPromotePacked(a, &function, 600, 513, true));
    try std.testing.expect(!try canPromotePacked(a, &function, 600, 512, false));
    function.instructions.items.len = 512;
    function.locals.items[0] = .f32;
    try std.testing.expect(!try canPromotePacked(a, &function, 600, 512, false));
    function.locals.items[0] = .i32;
    try function.instructions.append(a, .{ .op = .ownership });
    try std.testing.expect(!try canPromotePacked(a, &function, 600, 512, false));
}
test "packed promotion counts completed physical demand including result pointers through full OOM" {
    try promotion(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, promotion, .{});
}

pub fn materialize(a: std.mem.Allocator, function: *ir.Function) std.mem.Allocator.Error!Result {
    const unchanged: Result = .{ .used = &.{}, .omitted = 0 };
    const count = function.parameters.len;
    if (count == 0 or function.entry or function.parameter_roles != 0 or function.callable_layout != 0) return unchanged;
    if (function.provider_parameter != ir.unknown_provider and function.provider_parameter != ir.no_provider) return unchanged;
    for (function.parameters) |ty| if (ty != .i32) return unchanged;
    for (function.instructions.items) |inst| if (inst.op == .ownership or inst.op == .resource_retire or inst.table_reference or inst.table_kind != .unknown) return unchanged;
    const used = try a.alloc(bool, count);
    errdefer a.free(used);
    @memset(used, false);
    // Include result serialization and parameters written before a later read.
    for (function.instructions.items) |inst| {
        if (inst.op == .local_get and inst.operand < count) used[inst.operand] = true;
    }
    var demanded: usize = 0;
    for (used) |read| if (read) {
        demanded += 1;
    };
    if (demanded == count) {
        a.free(used);
        return unchanged;
    }
    var prefix: std.ArrayList(ir.Instruction) = .empty;
    defer prefix.deinit(a);
    var physical = demanded;
    var logical = count;
    // Destinations are >= sources. Descending moves cannot overwrite a source
    // that has not yet been moved, including overlapping parameter slots.
    while (logical != 0) {
        logical -= 1;
        if (!used[logical]) continue;
        physical -= 1;
        if (logical == physical) continue;
        try prefix.appendSlice(a, &.{
            .{ .op = .local_get, .operand = @intCast(physical) },
            .{ .op = .local_set, .operand = @intCast(logical) },
        });
    }
    // The combined parameter/local type vector keeps its complete length and
    // original tail, so every original body local retains its ID and type.
    try function.locals.insertSlice(a, 0, function.parameters[demanded..]);
    try function.instructions.insertSlice(a, 0, prefix.items);
    function.parameters = function.parameters[0..demanded];
    return .{ .used = used, .omitted = count - demanded };
}

fn overlap(a: std.mem.Allocator) !void {
    var parameters = [_]ir.ValueType{ .i32, .i32, .i32, .i32, .i32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.locals.appendSlice(a, &.{ .f32, .i32 });
    const body = [_]ir.Instruction{
        .{ .op = .local_get, .operand = 1, .origin = 42 },
        .{ .op = .local_get, .operand = 2 },
        .{ .op = .i32_add },
        .{ .op = .local_get, .operand = 4 },
        .{ .op = .i32_add },
        .{ .op = .local_set, .operand = 6 },
        .{ .op = .local_get, .operand = 6 },
    };
    try function.instructions.appendSlice(a, &body);
    const result = try materialize(a, &function);
    defer a.free(result.used);
    try std.testing.expectEqualSlices(bool, &.{ false, true, true, false, true }, result.used);
    try std.testing.expectEqual(@as(usize, 2), result.omitted);
    try std.testing.expectEqual(@as(usize, 3), function.parameters.len);
    try std.testing.expectEqualSlices(ir.ValueType, &.{ .i32, .i32, .f32, .i32 }, function.locals.items);
    try std.testing.expectEqualSlices(ir.Instruction, &body, function.instructions.items[6..]);
    var locals = [_]u32{ 11, 22, 44, 0, 0, 0, 0 };
    var value: u32 = 0;
    for (function.instructions.items[0..6]) |inst| {
        if (inst.op == .local_get) value = locals[inst.operand];
        if (inst.op == .local_set) locals[inst.operand] = value;
    }
    try std.testing.expectEqual(@as(u32, 11), locals[1]);
    try std.testing.expectEqual(@as(u32, 22), locals[2]);
    try std.testing.expectEqual(@as(u32, 44), locals[4]);
}
test "direct input demand preserves overlapping moves logical locals and body suffix through full OOM" {
    try overlap(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, overlap, .{});
}
test "direct input demand keeps written then read parameters and removes all unread parameters" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{ .i32, .i32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    try function.instructions.appendSlice(a, &.{
        .{ .op = .i32_const, .operand = 7 },
        .{ .op = .local_set, .operand = 1 },
        .{ .op = .local_get, .operand = 1 },
    });
    const result = try materialize(a, &function);
    defer a.free(result.used);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, result.used);
    try std.testing.expectEqual(@as(usize, 1), function.parameters.len);
    function.instructions.clearRetainingCapacity();
    try function.instructions.append(a, .{ .op = .i32_const });
    const empty = try materialize(a, &function);
    defer a.free(empty.used);
    try std.testing.expectEqualSlices(bool, &.{false}, empty.used);
    try std.testing.expectEqual(@as(usize, 0), function.parameters.len);
    try std.testing.expectEqual(@as(usize, 2), function.locals.items.len);
}
test "direct input demand declines hidden operands and retains fully demanded signatures" {
    const a = std.testing.allocator;
    var parameters = [_]ir.ValueType{ .i32, .i32 };
    var function: ir.Function = .{ .parameters = &parameters, .result = .i32, .signature = 0 };
    defer function.deinit(a);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    for ([_]ir.Instruction{ .{ .op = .ownership }, .{ .op = .resource_retire }, .{ .op = .i32_const, .table_reference = true }, .{ .op = .i32_const, .table_kind = .callable } }) |inst| {
        function.instructions.clearRetainingCapacity();
        try function.instructions.append(a, inst);
        try std.testing.expectEqual(@as(usize, 0), (try materialize(failing.allocator(), &function)).used.len);
        try std.testing.expectEqual(@as(usize, 2), function.parameters.len);
    }
    function.instructions.clearRetainingCapacity();
    try function.instructions.appendSlice(a, &.{ .{ .op = .local_get, .operand = 0 }, .{ .op = .local_get, .operand = 1 }, .{ .op = .i32_add } });
    const result = try materialize(a, &function);
    defer a.free(result.used);
    try std.testing.expectEqual(@as(usize, 0), result.used.len);
    try std.testing.expectEqual(@as(usize, 2), function.parameters.len);
}
