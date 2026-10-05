const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const evaluator = @import("core_eval.zig");
const scalar_ops = @import("scalar_ops.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const code_expectation = @import("code_expectation.zig");
const types = @import("types.zig");
const type_evidence = @import("type_evidence.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    return lowerWithOptions(source, .{});
}

fn lowerWithOptions(source: []const u8, options: checker.ModuleOptions) !core.Module {
    var tokens = try lexer.lex(a, source);
    defer tokens.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tokens.diagnostics.items.len);
    var pool: symbols.Pool = .{};
    defer pool.deinit(a);
    var syntax = try parser.parse(a, source, tokens.tokens.items, &pool);
    defer syntax.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(a, &syntax, &pool, &.{}, &.{}, 1, options);
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("check:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &syntax, &pool, &checked);
    errdefer module.deinit(a);
    for (module.diagnostics) |diagnostic| std.debug.print("core:{d}: {s}\n", .{ diagnostic.span.start, diagnostic.message() });
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn target(module: *const core.Module, name: []const u8) core.BindingRef {
    for (module.bodies) |body| if (body.exported and std.mem.eql(u8, module.name(body.export_name), name)) return .{ .unit = if (module.unit == 0) 1 else module.unit, .binding = body.binding };
    unreachable;
}

const pattern_source =
    \\type Pair is data = #Pair (U32,U32)
    \\type Fields is data = #Fields { first: U32, second: U32 }
    \\const first = fn actual => do:
    \\  let expected = 7
    \\  return case actual of
    \\    #Pair (expected,^expected) => expected
    \\    _ => 0
    \\const second = fn actual => do:
    \\  let expected = 7
    \\  return case actual of
    \\    #Pair (^expected,expected) => expected
    \\    _ => 0
    \\const fields = fn actual => do:
    \\  let expected = 7
    \\  return case actual of
    \\    #Fields { first: expected, second: ^expected } => expected
    \\    _ => 0
    \\entry const first_hit = first (#Pair (42,7))
    \\entry const first_miss = first (#Pair (7,42))
    \\entry const second_hit = second (#Pair (7,42))
    \\entry const second_miss = second (#Pair (42,7))
    \\entry const fields_hit = fields (#Fields { first: 42, second: 7 })
    \\entry const fields_miss = fields (#Fields { first: 7, second: 42 })
;
fn patternScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var session = try evaluator.Session.init(allocator, &.{module.*});
    defer session.deinit();
    for ([_][]const u8{ "first_hit", "first_miss", "second_hit", "second_miss", "fields_hit", "fields_miss" }, [_]u32{ 42, 0, 42, 0, 42, 0 }) |name, expected| {
        try std.testing.expectEqual(expected, (try session.value(target(module, name))).bits);
    }
}
test "value patterns capture enclosing bindings before tuple and record sibling binders" {
    var module = try lower(pattern_source);
    defer module.deinit(a);
    const nodes = try a.dupe(core.Node, module.nodes);
    defer a.free(nodes);
    const bindings = try a.dupe(core.Binding, module.bindings);
    defer a.free(bindings);
    try patternScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, patternScenario, .{&module});
    try std.testing.expectEqualDeep(nodes, module.nodes);
    try std.testing.expectEqualDeep(bindings, module.bindings);
}
