const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;
test {
    _ = @import("packed_input_demand.zig");
}
fn source() ![]u8 {
    var fields: std.ArrayList(u8) = .empty;
    defer fields.deinit(a);
    for (0..600) |index| {
        const field = try a.print("f{d}: @u32.add input {d},", .{ index, index });
        defer a.free(field);
        try fields.appendSlice(a, field);
    }
    const template = @import("fixtures").source("packed_input.blot.in");
    const at = std.mem.find(u8, template, "__FIELDS__").?;
    return std.mem.concat(a, u8, &.{ template[0..at], fields.items, template[at + 10 ..] });
}
fn lower(text: []const u8) !core.Module {
    var lexed = try lexer.lex(a, text);
    defer lexed.deinit(a);
    var names: symbols.Pool = .{};
    defer names.deinit(a);
    var tree = try parser.parse(a, text, lexed.tokens.items, &names);
    defer tree.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(a, &tree, &names, &.{}, &.{}, 1, .{ .builtin_catalog = false });
    defer checked.deinit(a);
    for (checked.diagnostics) |diagnostic| std.debug.print("packed source: {s}\n", .{@tagName(diagnostic.code)});
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    return module;
}
test "packed input demand composes through wide forwarding while retaining owner effects" {
    const text = try source();
    defer a.free(text);
    var module = try lower(text);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |diagnostic| std.debug.print("packed backend: {s}\n", .{diagnostic.message()});
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_owned_packed_calls > 0);
    try std.testing.expect(result.counters.scoped_packed_input_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_packed_argument_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_function_plan_read_events > 0);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
}
fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.counters.scoped_owned_packed_calls > 0);
    try std.testing.expect(result.counters.scoped_packed_input_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_packed_argument_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
}
test "packed input demand publishes repeated wide plans through full OOM" {
    var module = try lower(@import("fixtures").source("packed_input_oom.blot"));
    defer module.deinit(a);
    try publish(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
