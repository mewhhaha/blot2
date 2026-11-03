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
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(a, &tree, &names, &checked);
    errdefer module.deinit(a);
    module.unit = 1;
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn publishPartition(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_input_alias_words_avoided > 0);
    // Both scalar equality partitions need plans; later locals reuse them.
    try std.testing.expect(result.counters.scoped_completed_plan_definitions >= 2);
    try std.testing.expect(result.counters.scoped_function_plan_hits >= 2);
    try std.testing.expectEqual(@as(u64, 0), result.counters.scoped_completed_plan_rollbacks);
    try std.testing.expect(result.counters.scoped_direct_input_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_direct_argument_words_avoided > 0);
}

test "exact input aliases partition scalar plan keys and publish transactionally through OOM" {
    var module = try lower(@import("fixtures").source("input_alias_partition.blot"));
    defer module.deinit(a);
    try publishPartition(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishPartition, .{@as([]const core.Module, &.{module})});
}

test "exact input aliases retain mixed origins inactive variants view snapshots and grower events" {
    var module = try lower(@import("fixtures").source("input_alias_descriptors.blot"));
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_input_alias_words_avoided > 0);
    try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
    try std.testing.expect(result.counters.scoped_function_plan_read_events > 0);
    try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
}

fn callbackSource(width: usize, distinct: bool) ![]u8 {
    var types: std.ArrayList(u8) = .empty;
    defer types.deinit(a);
    var original: std.ArrayList(u8) = .empty;
    defer original.deinit(a);
    var later: std.ArrayList(u8) = .empty;
    defer later.deinit(a);
    var reads: std.ArrayList(u8) = .empty;
    defer reads.deinit(a);
    for (0..width) |index| {
        const ty = try a.print("f{d}: Array U32,", .{index});
        defer a.free(ty);
        try types.appendSlice(a, ty);
        var first = try a.print("f{d}: original,", .{index});
        if (distinct) {
            a.free(first);
            var owner = index;
            if (index % 4 == 3) owner -= 1;
            first = try a.print("f{d}: original_{d},", .{ index, owner });
        }
        defer a.free(first);
        try original.appendSlice(a, first);
        var second = try a.print("f{d}: later,", .{index});
        if (distinct) {
            a.free(second);
            var owner = index;
            if (index % 4 == 3) owner -= 1;
            second = try a.print("f{d}: later_{d},", .{ index, owner });
        }
        defer a.free(second);
        try later.appendSlice(a, second);
        const read = try a.print("  result := @u32.add self bundle.f{d}[0]\n", .{index});
        defer a.free(read);
        try reads.appendSlice(a, read);
    }
    var declarations: std.ArrayList(u8) = .empty;
    defer declarations.deinit(a);
    if (distinct) {
        for (0..width) |index| {
            if (index % 4 == 3) continue;
            const declaration = try a.print("  let original_{d}: Array U32 = #[@u32.add input {d}]\n  let later_{d}: Array U32 = #[@u32.add input {d}]\n", .{ index, index, index, index + 7 });
            defer a.free(declaration);
            try declarations.appendSlice(a, declaration);
        }
    }
    var source = try a.dupe(u8, @import("fixtures").source("input_alias_callbacks.blot.in"));
    errdefer a.free(source);
    var second_bundle: []const u8 = "bundle";
    if (distinct) second_bundle = "next";
    inline for (.{ "__TYPES__", "__ORIGINAL__", "__LATER__", "__READS__", "__SECOND_BUNDLE__", "__DECLARATIONS__" }, .{ types.items, original.items, later.items, reads.items, second_bundle, declarations.items }) |placeholder, replacement| {
        const next = try std.mem.replaceOwned(u8, a, source, placeholder, replacement);
        a.free(source);
        source = next;
    }
    return source;
}

test "exact input aliases share wide bundle callback words in direct and buffered plans" {
    const Case = struct { width: usize, distinct: bool };
    for ([_]Case{ .{ .width = 32, .distinct = false }, .{ .width = 128, .distinct = false }, .{ .width = 256, .distinct = true } }) |case| {
        const source = try callbackSource(case.width, case.distinct);
        defer a.free(source);
        var module = try lower(source);
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expect(result.bytes.len > 8);
        try std.testing.expect(result.counters.scoped_input_alias_words_avoided >= case.width);
        try std.testing.expect(result.counters.scoped_function_plan_hits > 0);
        if (!case.distinct) {
            try std.testing.expect(result.counters.scoped_owned_word_calls > 0);
            try std.testing.expect(result.counters.scoped_direct_argument_words_avoided > 0);
        } else {
            try std.testing.expect(result.counters.scoped_owned_packed_calls > 0);
            try std.testing.expect(result.counters.scoped_packed_input_words_avoided > 0);
            try std.testing.expect(result.counters.scoped_packed_argument_words_avoided > 0);
        }
    }
}

test "exact input aliases do not authorize borrowed owner escape" {
    var module = try lower(@import("fixtures").source("input_alias_borrow_escape.blot"));
    defer module.deinit(a);
    var result = try scoped.compile(a, &.{module}, 1);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic != null);
    try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
}
