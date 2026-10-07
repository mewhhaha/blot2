const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const layout = @import("layout.zig");

const source =
    \\type Point = { x: U32, y: F32 }
    \\type Box a is data = #Box a
    \\const identity = fn (point: Point) => point
    \\const merge = fn left => fn right => @record.merge left right
    \\const source = merge { y: 2.0, x: #False } { x: 40 }
    \\entry const answer = do:
    \\  let #Box point = #Box (identity source)
    \\  point.x := @u32.add self 2
    \\  let { x } = point
    \\  return x
    \\entry const runtime = fn (value: U32) => do:
    \\  let point = identity { y: 2.0, x: value }
    \\  point.x := #True
    \\  let { y, x } = point
    \\  return if x then y else 0.0
;

fn lower(allocator: std.mem.Allocator) !core.Module {
    return lowerInput(allocator, source);
}
fn lowerInput(allocator: std.mem.Allocator, input: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, input);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, input, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
fn evaluate(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try eval.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for (module.bodies) |body| if (body.exported and !body.is_function) {
        const value = try session.value(.{ .unit = 1, .binding = body.binding });
        try std.testing.expectEqual(@as(u32, 42), value.bits);
    };
}
fn emit(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(?backend.Diagnostic, null), result.diagnostic);
    try std.testing.expect(result.bytes.len > 8);
}
fn frontend(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator);
    defer module.deinit(allocator);
}
test "structural records preserve field identities through evaluation, emission and allocation failures" {
    const allocator = std.testing.allocator;
    var module = try lower(allocator);
    defer module.deinit(allocator);
    try evaluate(allocator, &module);
    try emit(allocator, &module);
    const failures = @import("allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, frontend, .{});
    try failures.checkAllAllocationFailures(allocator, evaluate, .{&module});
    try failures.checkAllAllocationFailures(allocator, emit, .{&module});
}
test "executable record layouts have one identity for every field permutation" {
    var store = try layout.Store.init(std.testing.allocator);
    defer store.deinit();
    const first = try store.internRecord(&.{ 41, 3, 12, 4, 73, 2 });
    for ([_][6]u32{
        .{ 12, 4, 41, 3, 73, 2 }, .{ 73, 2, 12, 4, 41, 3 }, .{ 41, 3, 73, 2, 12, 4 },
    }) |words| try std.testing.expectEqual(first, try store.internRecord(&words));
    try std.testing.expectEqualSlices(u32, &.{ 12, 4, 41, 3, 73, 2 }, store.children(first));
    try std.testing.expectError(error.TypeMismatch, store.internRecord(&.{ 12, 3, 12, 4 }));
}

test "constant record merge interns shapes across repeated updates" {
    const allocator = std.testing.allocator;
    var module = try lowerInput(allocator,
        \\entry const answer = do:
        \\  let record = { x: 0, kept: 42 }
        \\  for index in 0 .. 1024:
        \\    record := @record.merge record { x: @u32.add record.x 1 }
        \\  return record.kept
    );
    defer module.deinit(allocator);
    var session = try eval.Session.init(allocator, &.{module});
    defer session.deinit();
    const value = try session.value(.{ .unit = 1, .binding = module.bodies[1].binding });
    try std.testing.expectEqual(@as(u32, 42), value.bits);
    // Empty shape, the input/result shape, and the replacement shape.
    try std.testing.expectEqual(@as(usize, 3), session.record_layouts.items.len);
}
