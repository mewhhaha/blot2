const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const backend = @import("core_backend.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
const source =
    \\effect Read: Unit -> U32
    \\effect Other: Unit -> U32
    \\const read: Unit -> U32 ! {Read,Read} = fn () => @panic "reflection must never invoke a function"
    \\const count = fn effects => @effect.count effects
    \\const contains = fn effects => fn operation => @effect.has effects operation
    \\const same = fn left => fn right => @effect.same left right
    \\const requirements = @effect.of read
    \\const reader = @effect.descriptor Read
    \\entry const total = count requirements
    \\entry const present = contains requirements reader
    \\entry const absent = contains requirements (@effect.descriptor Other)
    \\entry const same_reader = same reader (@effect.descriptor Read)
    \\entry const different_reader = same reader (@effect.descriptor Other)
    \\entry const foreign = @effect.same (@effect.descriptor Foreign) (@effect.descriptor Foreign)
    \\entry const answer = fn () => total
;
fn lower(allocator: std.mem.Allocator) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &syntax, &pool, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn evalScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for (module.bodies) |body| {
        if (!body.exported or body.is_function) continue;
        const selected = try session.richValue(.{ .unit = 1, .binding = body.binding });
        const scalar = session.valueScalar(selected).?;
        const name = module.name(body.export_name);
        const absent = std.mem.eql(u8, name, "absent") or std.mem.eql(u8, name, "different_reader");
        try std.testing.expectEqual(@as(u32, @intFromBool(!absent)), scalar.bits);
        try std.testing.expectEqual(if (std.mem.eql(u8, name, "total")) @as(@TypeOf(scalar.scalar), .u32) else .bool, scalar.scalar);
    }
    try std.testing.expect(session.diagnostic == null);
}
fn emitScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(usize, 1), result.code_instances);
}
test "reflection owns exact compile-time sets without invoking functions or leaking failed allocations" {
    var module = try lower(a);
    defer module.deinit(a);
    const original = try a.dupe(core.Node, module.nodes);
    defer a.free(original);
    const original_types = try a.dupe(types.Node, module.types.nodes);
    defer a.free(original_types);
    try evalScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, evalScenario, .{&module});
    try emitScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, emitScenario, .{&module});
    try std.testing.expectEqualDeep(original, module.nodes);
    try std.testing.expectEqualDeep(original_types, module.types.nodes);
}
fn frontScenario(allocator: std.mem.Allocator) !void {
    var module = try lower(allocator);
    defer module.deinit(allocator);
}
test "reflection frontend owns sparse metadata on every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, frontScenario, .{});
}
