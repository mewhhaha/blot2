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

fn publishRead(allocator: std.mem.Allocator, modules: []const core.Module) !void {
    var result = try scoped.compile(allocator, modules, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expect(result.counters.scoped_global_plan_definitions > 0);
    try std.testing.expect(result.counters.scoped_global_plan_definitions <= 2);
    try std.testing.expect(result.counters.scoped_global_plan_loads > 0);
    // Ten source call sites share at most one helper per exported context.
    try std.testing.expect(result.counters.scoped_function_plan_hits >= 8);
    try std.testing.expect(result.counters.scoped_function_plan_read_events > 0);
}

test "global owner plans share initialized scalar readers across repeated calls through OOM" {
    var module = try lower(@import("fixtures").source("global_call_read.blot"));
    defer module.deinit(a);
    try publishRead(a, &.{module});
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, publishRead, .{@as([]const core.Module, &.{module})});
}

test "global owner plans retain nested growth explicit aliases returned owners and initialized dependencies" {
    inline for (.{ "global_call_mutation.blot", "global_call_initialization.blot" }) |path| {
        var module = try lower(@import("fixtures").source(path));
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expect(result.bytes.len > 8);
        try std.testing.expect(result.counters.scoped_global_plan_definitions > 0);
        try std.testing.expect(result.counters.scoped_global_plan_loads > 0);
        try std.testing.expect(result.counters.scoped_function_plan_read_events > 0);
        if (comptime std.mem.eql(u8, path, "global_call_mutation.blot")) {
            try std.testing.expect(result.counters.scoped_function_plan_write_events > 0);
        }
    }
}

test "global owner plans retain freeze barriers and reject local borrowed escapes" {
    inline for (.{ "global_call_freeze.blot", "global_call_borrow_escape.blot" }) |path| {
        var module = try lower(@import("fixtures").source(path));
        defer module.deinit(a);
        var result = try scoped.compile(a, &.{module}, 1);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic != null);
        if (comptime std.mem.eql(u8, path, "global_call_freeze.blot")) {
            try std.testing.expectEqual(@import("core_backend.zig").Code.storage_borrow_conflict, result.diagnostic.?.code);
        } else {
            try std.testing.expectEqual(@import("core_backend.zig").Code.storage_escape, result.diagnostic.?.code);
        }
        try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
    }
}
