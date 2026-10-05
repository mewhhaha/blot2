const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &pool, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
    return result;
}
const fixture =
    \\data Cell value = #Cell value
    \\type Increment is data = #Increment U32
    \\const Increment.add = fn left => fn right => do:
    \\  let #Increment a = left
    \\  let #Increment b = right
    \\  return #Increment (@u32.add a b)
    \\const twice: a -> a where { associated "add" a a a } = fn value => @type.call "add" value value
    \\entry const answer = fn () => do:
    \\  let unused: a -> a where { associated "missing" a a a } = fn value => value
    \\  let read_local = fn witness => @state.get witness
    \\  let (_, #Cell count) = @state.run (#Cell 40) (fn () => read_local (fn ignored -> Cell U32 => @panic "unused"))
    \\  let local = twice
    \\  let #Increment delta = local (#Increment 1)
    \\  return @u32.add count delta
;
fn backendScenario(allocator: std.mem.Allocator, module: *const core.Module) !void {
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |item| std.debug.print("{s}:{}\n", .{ @tagName(item.code), item.span.start });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}
test "qualified body evidence and captured generic local functions survive frontend teardown and all backend allocations" {
    const a = std.testing.allocator;
    var module = try lower(a, fixture);
    defer module.deinit(a);
    try backendScenario(a, &module);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, backendScenario, .{&module});
}
test "explicit closed extras and independent rows require proof while unused callable schemes remain suspended" {
    const cases = [_]struct { source: []const u8, code: ?backend.Code }{
        .{ .source = "entry const answer: U32 where { associated \"missing\" Bool Bool Bool } = 42\n", .code = .missing_associated },
        .{ .source = "entry let answer: U32 where { associated \"missing\" Bool Bool Bool } = 42\n", .code = .missing_associated },
        .{ .source = "const identity: a -> a where { effect_rep ! {| e} } = fn value => value\nentry const answer = fn () => identity 42\n", .code = .ambiguous_qualified },
        .{ .source = "entry const answer: U32 where { type_rep a } = 42\n", .code = .ambiguous_qualified },
        .{ .source = "entry const answer: U32 where { effect_rep ! {| e} } = 42\n", .code = .ambiguous_qualified },
        .{ .source = "entry const answer = fn () => do:\n  let unused: U32 where { effect_rep ! {| e} } = 42\n  return 42\n", .code = .ambiguous_qualified },
        .{ .source = "const unused: a -> a where { associated \"missing\" a a a } = fn value => value\nentry const answer = 42\n", .code = null },
        .{ .source = "entry const answer = fn () => do:\n  let unused: U32 -> U32 where { associated \"missing\" Bool Bool Bool } = fn value => value\n  return 42\n", .code = null },
        .{ .source = "entry const answer = fn () => do:\n  let unused: U32 where { associated \"missing\" Bool Bool Bool } = 42\n  return 42\n", .code = .missing_associated },
    };
    const a = std.testing.allocator;
    for (cases) |case| {
        var module = try lower(a, case.source);
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        if (case.code) |expected| {
            try std.testing.expect(result.diagnostic != null);
            try std.testing.expectEqual(expected, result.diagnostic.?.code);
            try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
            if (expected == .ambiguous_qualified) try std.testing.expectEqual(@as(u32, @intCast(std.mem.indexOf(u8, case.source, "where").?)), result.diagnostic.?.span.start);
        } else try std.testing.expect(result.diagnostic == null);
    }
}
