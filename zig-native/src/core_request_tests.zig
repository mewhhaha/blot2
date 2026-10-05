const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const types = @import("types.zig");
const a = std.testing.allocator;
fn lower(source: []const u8) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);

    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    for (checked.diagnostics) |d| std.debug.print("check:{d}: {s}\n", .{ d.span.start, d.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    for (module.diagnostics) |d| std.debug.print("core:{d}: {s}\n", .{ d.span.start, d.message() });
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}
fn target(module: *const core.Module) core.BindingRef {
    for (module.bodies) |body| if (std.mem.eql(u8, module.name(body.export_name), "checked_answer")) return .{ .unit = module.unit, .binding = body.binding };
    unreachable;
}
fn scenario(allocator: std.mem.Allocator, module: *const core.Module, expected: u32) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    session.options.max_steps = 1000000;
    const value = session.value(target(module)) catch |err| {
        if (session.diagnostic) |d| std.debug.print("eval:{d}: {s}\n", .{ d.span.start, d.message() });
        return err;
    };
    try std.testing.expectEqual(@as(u32, expected), value.bits);
    try std.testing.expect(session.diagnostic == null);
}
test "Requests: replies resume the computation and completion sees its result" {
    var module = try lower(@embedFile("request-fixtures/0.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: return cancels helper calls, later loop iterations and the suffix" {
    var module = try lower(@embedFile("request-fixtures/1.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: cancellation skips array allocation and generator construction" {
    var module = try lower(@embedFile("request-fixtures/2.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: cancelled demand forcing remains suspended for a later handler" {
    var module = try lower(@embedFile("request-fixtures/3.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 82);
}
test "Requests: first-class operation values keep their identity through helper calls" {
    var module = try lower(@embedFile("request-fixtures/4.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: break cancels the computation and exposes successor state to the suffix" {
    var module = try lower(@embedFile("request-fixtures/5.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: successive replies and completion share the handler's carried state" {
    var module = try lower(@embedFile("request-fixtures/6.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 45);
}
test "Requests: a completion clause can break and retain its final state update" {
    var module = try lower(@embedFile("request-fixtures/7.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: reply, computation result and early handler result have independent types" {
    var module = try lower(@embedFile("request-fixtures/8.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: a lazy captured computation can be reused with fresh handler state" {
    var module = try lower(@embedFile("request-fixtures/9.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 80);
}
test "Requests: operation identities distinguish clauses with identical signatures" {
    var module = try lower(@embedFile("request-fixtures/10.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: effect clauses run outside the entire installation and can forward their operation" {
    var module = try lower(@embedFile("request-fixtures/11.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: unrelated computation effects reach the surrounding provider" {
    var module = try lower(@embedFile("request-fixtures/12.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: an outer cancellation unwinds an inner handler and its invoking clause" {
    var module = try lower(@embedFile("request-fixtures/13.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: a nested plain do return stays local to that block" {
    var module = try lower(@embedFile("request-fixtures/14.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: break in an ordinary loop inside a clause exits that nearest loop" {
    var module = try lower(@embedFile("request-fixtures/15.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: multiple carried locals survive conditional and nested loop updates" {
    var module = try lower(@embedFile("request-fixtures/16.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 30);
}
test "Requests: nested do cannot intercept an ordinary loop break at colliding offsets" {
    var module = try lower(@embedFile("request-fixtures/17.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: nested do cannot intercept a completion break at colliding offsets" {
    var module = try lower(@embedFile("request-fixtures/18.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: unused operation clauses can handle a pure computation" {
    var module = try lower(@embedFile("request-fixtures/19.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: a request loop may contain only its completion clause" {
    var module = try lower(@embedFile("request-fixtures/20.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: grouping the entire request input preserves its request-loop meaning" {
    var module = try lower(@embedFile("request-fixtures/21.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: explicit generic operation clauses retain their specialized identity" {
    var module = try lower(@embedFile("request-fixtures/22.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: many requests in a loop use bounded call stack and fresh carried state" {
    var module = try lower(@embedFile("request-fixtures/23.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 1000);
}

test "Requests: updated captured callable survives completion" {
    var module = try lower(@embedFile("request-fixtures/carried-function.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 82);
}
test "Requests: cancellation and carried state release every allocation without mutating frozen Core" {
    for ([_][]const u8{ @embedFile("request-fixtures/3.blot"), @embedFile("request-fixtures/13.blot"), @embedFile("request-fixtures/16.blot") }, [_]u32{ 82, 42, 30 }) |source, expected| {
        var module = try lower(source);
        defer module.deinit(a);
        const nodes = try a.dupe(core.Node, module.nodes);
        defer a.free(nodes);
        const types_ = try a.dupe(types.Node, module.types.nodes);
        defer a.free(types_);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ &module, expected });
        try std.testing.expectEqualDeep(nodes, module.nodes);
        try std.testing.expectEqualDeep(types_, module.types.nodes);
    }
}
test "Requests: shadow payload_shadow_carried_elsewhere" {
    var module = try lower(@embedFile("request-fixtures/shadow-payload_shadow_carried_elsewhere.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 7);
}
test "Requests: shadow local_shadow_after_outer_update" {
    var module = try lower(@embedFile("request-fixtures/shadow-local_shadow_after_outer_update.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 2);
}
test "Requests: shadow payload_shadows_all_updates" {
    var module = try lower(@embedFile("request-fixtures/shadow-payload_shadows_all_updates.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
test "Requests: shadow completion_payload_shadow" {
    var module = try lower(@embedFile("request-fixtures/shadow-completion_payload_shadow.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 3);
}
test "Requests: plain handler cancellation retains its own boundary inside a monadic block" {
    var module = try lower(@embedFile("request-fixtures/monad-nested-plain.blot"));
    defer module.deinit(a);
    try scenario(a, &module, 42);
}
fn publicationScenario(allocator: std.mem.Allocator, tree: *const @import("ast.zig").Tree, pool: *const symbols.Pool, checked: *const checker.Checked) !void {
    var module = try core.lower(allocator, tree, pool, checked);
    defer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), module.request_loops.len);
    try std.testing.expectEqual(@as(usize, 1), module.request_arms.len);
    try std.testing.expectEqual(@as(u32, 2), module.request_loops[0].carries.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
}
test "Requests: typed publication owns generated callbacks and releases every failed allocation" {
    const source = @embedFile("request-fixtures/16.blot");
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true });
    defer checked.deinit(a);
    const nodes = try a.dupe(types.Node, checked.types.nodes.items);
    defer a.free(nodes);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, publicationScenario, .{ &syntax, &pool, &checked });
    try std.testing.expectEqualDeep(nodes, checked.types.nodes.items);
}
