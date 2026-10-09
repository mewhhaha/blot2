const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const eval = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const layout = @import("layout.zig");
const types = @import("types.zig");

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

const path_source =
    \\const position = make (fn value => value.position)
    \\  (fn replacement => fn value => @record.merge value { position: replacement })
    \\const x = make (fn value => value.x)
    \\  (fn replacement => fn value => @record.merge value { x: replacement })
    \\const position_x = compose position x
    \\const original = { position: { x: 40, y: 7 }, kept: 2, callback: fn value => @u32.add value 40 }
    \\const changed = set position_x 2.5 original
    \\entry const answer = @u32.add original.position.x changed.kept
    \\entry const runtime = fn (value: U32) => get identity value
    \\entry const composed = fn (value: U32) => do:
    \\  let initial = { position: { x: value, y: 7 }, kept: 2, callback: fn argument => @u32.add argument value }
    \\  let changed = set position_x 2.5 initial
    \\  return get position_x changed
    \\entry const effects = fn (send: U32 -> U32 ! {Foreign}) => do:
    \\  let initial = { position: { x: 40, y: 7 }, callback: fn value => send value }
    \\  let changed = set position_x 2.5 initial
    \\  let focus = get position_x changed
    \\  return @f32.add focus (@u32.to_f32 (changed.callback 2))
    \\entry const callback = fn () => changed.callback 2
    \\const inner = make (fn source => source.inner)
    \\  (fn replacement => fn source => @record.merge source { inner: replacement })
    \\const deep_x = compose inner (compose inner (compose inner (compose inner x)))
    \\entry const deep = fn (value: U32) => do:
    \\  let callback = fn argument => @u32.add argument value
    \\  let initial = { inner: { inner: { inner: { inner: { x: value, callback }, callback }, callback }, callback }, callback }
    \\  let changed = set deep_x 2.5 initial
    \\  return get deep_x changed
    \\entry const deep_effects = fn (send: U32 -> U32 ! {Foreign}) => do:
    \\  let callback = fn argument => send argument
    \\  let initial = { inner: { inner: { inner: { inner: { x: 40, callback }, callback }, callback }, callback }, callback }
    \\  let changed = set deep_x 2.5 initial
    \\  return @f32.add (get deep_x changed) (@u32.to_f32 (changed.callback 2))
    \\entry const deep_closed = fn (value: U32) => get deep_x { inner: { inner: { inner: { inner: { x: value, callback: #False }, callback: #False }, callback: #False }, callback: #False }, callback: #False }
;

fn pathFrontend(allocator: std.mem.Allocator, input: []const u8) !void {
    var module = try lowerInput(allocator, input);
    defer module.deinit(allocator);
}

test "typed paths keep unobserved generic accessors staged through allocation failure" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const library = std.Io.Dir.cwd().readFileAlloc(io, "std/path.blot", allocator, .limited(65536)) catch |err| switch (err) {
        error.FileNotFound => try std.Io.Dir.cwd().readFileAlloc(io, "../std/path.blot", allocator, .limited(65536)),
        else => return err,
    };
    defer allocator.free(library);
    const input = try allocator.print("{s}\n{s}", .{ library, path_source });
    defer allocator.free(input);
    var module = try lowerInput(allocator, input);
    defer module.deinit(allocator);
    const saved = try allocator.dupe(types.Node, module.types.nodes);
    defer allocator.free(saved);
    try evaluate(allocator, &module);
    try emit(allocator, &module);
    const failures = @import("allocation_failures.zig");
    try failures.checkAllAllocationFailures(allocator, pathFrontend, .{input});
    try failures.checkAllAllocationFailures(allocator, evaluate, .{&module});
    try failures.checkAllAllocationFailures(allocator, emit, .{&module});
    try std.testing.expectEqualDeep(saved, module.types.nodes);
}
