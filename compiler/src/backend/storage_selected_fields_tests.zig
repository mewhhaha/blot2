const std = @import("std");
const lexer = @import("../parse/lexer.zig");
const parser = @import("../parse/parser.zig");
const symbols = @import("../parse/symbols.zig");
const check = @import("../check/check.zig");
const core = @import("../check/core.zig");
const scoped = @import("scoped_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var lexed = try lexer.lex(allocator, source);
    defer lexed.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, lexed.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModule(allocator, &tree, &names, &.{}, &.{}, 1);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn wideModule(width: usize, accesses: usize, nominal: bool) !core.Module {
    var fields: std.ArrayList(u8) = .empty;
    defer fields.deinit(a);
    var values: std.ArrayList(u8) = .empty;
    defer values.deinit(a);
    for (0..width) |index| {
        const field = try a.print("f{d}: U32,", .{index});
        defer a.free(field);
        try fields.appendSlice(a, field);
        const value = try a.print("f{d}: input,", .{index});
        defer a.free(value);
        try values.appendSlice(a, value);
    }
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(a);
    var row_type: []const u8 = fields.items;
    if (nominal) {
        const declaration = try a.print("type Row is data = $Row {{{s}}}\n", .{fields.items});
        defer a.free(declaration);
        try source.appendSlice(a, declaration);
        row_type = "Row";
    }
    var opening: []u8 = undefined;
    if (nominal) opening = try a.print("entry const answer = func (input: U32) => return do:\n  let rows: GrowArray {s} = #[$Row {{{s}}}]\n  let total: U32 = 0\n", .{ row_type, values.items }) else opening = try a.print("entry const answer = func (input: U32) => return do:\n  let rows: GrowArray {{{s}}} = #[{{{s}}}]\n  let total: U32 = 0\n", .{ row_type, values.items });
    defer a.free(opening);
    try source.appendSlice(a, opening);
    for (0..accesses) |_| try source.appendSlice(a, "  rows[0].f0 := @u32.add self 1\n  total := @u32.add total rows[0].f0\n");
    try source.appendSlice(a, "  return total\n");
    return lower(a, source.items);
}

fn emittedBytes(width: usize, accesses: usize, nominal: bool) !usize {
    var module = try wideModule(width, accesses, nominal);
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    return result.bytes.len;
}

test "selected stored field access cost stays bounded as plain row width grows" {
    for ([_]bool{ false, true }) |nominal| {
        const narrow_once = try emittedBytes(8, 1, nominal);
        const narrow_many = try emittedBytes(8, 8, nominal);
        const wide_once = try emittedBytes(64, 1, nominal);
        const wide_many = try emittedBytes(64, 8, nominal);
        // Subtraction removes each layout's one-time row construction cost.
        const narrow_delta = narrow_many - narrow_once;
        const wide_delta = wide_many - wide_once;
        try std.testing.expect(narrow_delta > 0);
        try std.testing.expect(wide_delta < narrow_delta * 2 + 128);
    }
}

fn publish(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
}

test "selected stored field publication survives allocation failures" {
    var module = try wideModule(3, 1, true);
    defer module.deinit(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publish, .{@as([]const core.Module, &.{module})});
}
