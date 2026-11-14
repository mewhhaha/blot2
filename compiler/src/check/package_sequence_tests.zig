const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const a = std.testing.allocator;

fn checkInput(allocator: std.mem.Allocator, input: []const u8, accepted: bool) !void {
    var tokens = try lexer.lex(allocator, input);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var syntax = try parser.parse(allocator, input, tokens.tokens.items, &pool);
    defer syntax.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), syntax.diagnostics.items.len);
    var checked = try checker.checkModule(allocator, &syntax, &pool, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(accepted, checked.diagnostics.len == 0);
}

fn nominalBinderSource(allocator: std.mem.Allocator) !void {
    try checkInput(allocator,
        \\type Box a is data = $Box a
        \\type Item = exists [a] => (Box a, Box a -> U32)
        \\const make: U32 -> Item = func value => return pack [U32] ($Box value, func ($Box inner) => return inner) as Item
    , true);
}

test "nominal package binders retain lexical scope and allocation failure ownership" {
    try nominalBinderSource(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, nominalBinderSource, .{});
    try checkInput(a,
        \\type Box a is data = $Box a
        \\type Item = exists [a] => Box a
        \\const wrong: Item -> Box U32 = func item => return unpack item as [a] value in value
    , false);
    try checkInput(a,
        \\type Box a is data = $Box a
        \\type Item = exists [a] => Box a
        \\const wrong: Item -> Item -> Unit = func left => return func right => return unpack left as [a] x in unpack right as [b] y in (func (other: Box a) => return ()) y
    , false);
}
