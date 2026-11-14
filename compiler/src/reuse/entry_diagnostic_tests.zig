const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("../check/check.zig");
const core = @import("../check/core.zig");
const project = @import("project.zig");
const project_check = @import("project_check.zig");
const types = @import("../check/types.zig");
const type_evidence = @import("../check/type_evidence.zig");
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

const generic_source =
    \\const identity = func value => return value
    \\entry const direct = func value => return value
    \\entry const alias = identity
    \\entry const update = func value => return do:
    \\  value.lower := 42
    \\  break value
    \\const maker = func captured => return func (value: U32) => return @u32.add captured value
    \\entry const selected = maker 21
    \\entry const closed = func (value: U32) => return value
    \\const hidden = func captured => return func value => return captured
    \\entry const unclosed_capture = hidden (func value => return value)
    \\entry const unresolved_body = func value => return do:
    \\  let deferred = func owner => return owner.missing
    \\  break (deferred value, value)
;
fn anonymousRecordScenario(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{
        "entry const x = { lower: 0 }\n",
        "const lower = 0\nentry const x = { lower }\n",
        "entry const x = ({ lower: missing }).lower\n",
        "entry const answer = ({ lower: 42 }).lower\n",
        "entry const x = $Missing { lower: 0 }\n",
        "type Box is data = $Box { lower: U32 }\nentry const x = ($Box { lower: 42 }).lower\n",
    }, 0..) |source, index| {
        var tokens = try lexer.lex(allocator, source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var syntax = try parser.parse(allocator, source, tokens.tokens.items, &pool);
        defer syntax.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
        var checked = try checker.check(allocator, &syntax, &pool);
        defer checked.deinit(allocator);
        if (index != 2 and index != 4) {
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        } else {
            try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
            try std.testing.expectEqual(if (index == 4) checker.Code.unknown_constructor else checker.Code.unknown_value, checked.diagnostics[0].code);
        }
    }
}
test "structural records validate children and preserve named constructor checks" {
    try anonymousRecordScenario(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, anonymousRecordScenario, .{});
}
