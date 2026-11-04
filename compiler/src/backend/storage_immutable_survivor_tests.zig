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
    for (checked.diagnostics) |diagnostic| std.debug.print("survivor source: {s} at {d}:{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start, diagnostic.span.end });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    return module;
}
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    if (result.diagnostic) |diagnostic| std.debug.print("survivor backend: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_immutable_survivor_bindings > 0);
}
test "immutable single row survivors preserve live aggregate metadata through full OOM" {
    var module = try lower(@import("fixtures").source("immutable_survivor.blot"));
    defer module.deinit(a);
    var alternatives = false;
    for (module.matches) |match| {
        for (module.match_arms[match.arms.start..][0..match.arms.len]) |arm| {
            if (arm.rows.len > 1) alternatives = true;
        }
    }
    try std.testing.expect(alternatives);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
test "immutable survivors keep scalar address carrier fallback" {
    const source = @import("fixtures").source("immutable_survivor.blot");
    const start = std.mem.find(u8, source, "type Pick").?;
    var alternatives = try lower(source[start..]);
    defer alternatives.deinit(a);
    var carried = try scoped.compile(a, &.{alternatives}, 1);
    defer carried.deinit(a);
    try std.testing.expect(carried.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), carried.counters.scoped_immutable_survivor_bindings);
    var module = try lower(@import("fixtures").source("identity_join_address.blot"));
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_immutable_survivor_bindings);
}
