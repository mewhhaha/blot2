const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const backend = @import("core_backend.zig");

const iterator =
    \\type Maybe a is data = $Some a | $Nothing
    \\const Array.iter = func values => return @array.cursor values
    \\const Cursor.next = func cursor => return
    \\  if @cursor.has cursor then $Some (@cursor.value cursor, @cursor.advance cursor) else $Nothing
    \\const count = func xs => return do:
    \\  let n = 0
    \\  for x in xs:
    \\    n := @u32.add self 1
    \\  break n
    \\
;
const cases = [_][]const u8{
    iterator ++ "entry const create = func () => return count #[]\n",
    iterator ++ "type Box [a, b] is data = $A a | $B b\nentry const create = func () => return @u32.add (count #[]) (@u32.mul (count #[$A 1, $A 2]) 10)\n",
    iterator ++ "const empty = #[]\nentry const create = func () => return @u32.add (count #[...empty, 1]) (count #[...empty, 2.0])\n",
};

fn compile(allocator: std.mem.Allocator, source: []const u8) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    for (tree.diagnostics.items) |diagnostic| std.debug.print("parse {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.start });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &pool, &.{}, &.{}, 1, .{ .builtin_catalog = true, .prelude_unit = 1 });
    defer checked.deinit(allocator);
    for (checked.diagnostics) |diagnostic| std.debug.print("check {s} at {d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &pool, &checked);
    defer module.deinit(allocator);
    module.unit = 1;
    var result = try backend.compile(allocator, &.{module}, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("{s}: {s}\n", .{ @tagName(diagnostic.code), diagnostic.message() });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "unconstrained collection elements emit through generic cursors without closing reusable schemes" {
    for (cases) |source| try compile(std.testing.allocator, source);
}

test "partial collection projection releases every failed allocation" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, compile, .{cases[1]});
}
