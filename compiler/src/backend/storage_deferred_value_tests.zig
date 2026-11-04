const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower(source: []const u8) !core.Module {
    var lexed = try lexer.lex(a, source);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, source, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("deferred join source: {s} at {d}:{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    return module;
}
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("deferred joins: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_join_words_shared > 0);
}
test "deferred aggregate joins retain complete control and variant checking through OOM" {
    var module = try lower(@import("fixtures").source("deferred_join.blot"));
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "deferred aggregate joins retain scalar address fallback and borrowed escape rejection" {
    var addressed = try lower(@import("fixtures").source("identity_join_address.blot"));
    defer addressed.deinit(a);
    var fallback = try scoped.compile(a, &.{addressed}, 1);
    defer fallback.deinit(a);
    try std.testing.expect(fallback.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), fallback.counters.scoped_join_words_shared);
    var escaping = try lower(
        \\const capture = func (saved: &[U32]) => return func (argument: U32): U32 => return @u32.add saved[0] argument
        \\const escape = func (input: U32) => return do:
        \\  let rows: Array U32 = #[input]
        \\  let access = {rows: rows, hook: capture (&rows[0..1])}
        \\  if @u32.eq input 0:
        \\    access.rows[0] := @u32.add self 10
        \\  else:
        \\    access.rows[0] := @u32.add self 20
        \\  return access.hook
        \\entry const answer = func (input: U32): U32 => return (escape input) 7
    );
    defer escaping.deinit(a);
    var rejected = try scoped.compile(a, &.{escaping}, 1);
    defer rejected.deinit(a);
    try std.testing.expect(rejected.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, rejected.diagnostic.?.code);
}
