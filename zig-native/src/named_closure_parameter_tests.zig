const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const checker = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const artifacts = @import("core_snapshot_tests.zig");
const types = @import("types.zig");
const a = std.testing.allocator;

fn source(comptime name: []const u8) []const u8 {
    return @embedFile("named-closure-parameter-fixtures/" ++ name ++ ".blot");
}

fn lower(allocator: std.mem.Allocator, text: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, text);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, text, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    for (tree.diagnostics.items) |issue| std.debug.print("closure fixture parse {s}:{d}\n", .{ @tagName(issue.code), issue.start });
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try checker.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("closure fixture check {s}:{d} {s}\n", .{ @tagName(issue.code), issue.span.start, issue.message() });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var module = try core.lower(allocator, &tree, &names, &checked);
    errdefer module.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.len);
    return module;
}

fn compileSuccessful(allocator: std.mem.Allocator, module: *const core.Module) !void {
    const before = artifacts.stamp(module.*);
    var result = try backend.compile(allocator, &.{module.*}, 1);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expect(result.bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(module.*));
}

fn successful(comptime name: []const u8) !void {
    // Every source, syntax, symbol and inference owner has died on return.
    var module = try lower(a, source(name));
    defer module.deinit(a);
    const before = artifacts.stamp(module);
    var result = try backend.compile(a, &.{module}, 1);
    defer result.deinit(a);
    if (result.diagnostic) |issue| std.debug.print("{s}: {s} {s}\n", .{ name, @tagName(issue.code), issue.message() });
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(module));
}

test "named closure applied Unit uses declared parameter type without a lexical binding" {
    var module = try lower(a, source("unit-applied-export"));
    defer module.deinit(a);
    const parameter = module.bodyParameters(&module.bodies[1])[0];
    try std.testing.expectEqual(@as(u32, 0), parameter.binding);
    try std.testing.expectEqual(types.unit, parameter.ty);
    try successful("unit-applied-export");
}

test "named closure nonUnit applied arguments retain their declared layout" {
    try successful("nonunit-applied-export");
}

test "named closure independent generic captures keep Unit U32 and F32 mappings" {
    try successful("generic-unit-captures");
}

test "named closure returning an anonymous closure keeps lexical capture lookup" {
    try successful("lexical-generic-capture");
}

test "named closure Unit application preserves closed operation rows and provider scope" {
    try successful("unit-applied-effect-row");
    try successful("applied-provider-capture");
}

test "named closure applied Unit and planned runtime storage retain legal returned closure and reject real cycle" {
    inline for (.{ "returned-closure-cycle", "direct-cell-cycle" }) |name| {
        var module = try lower(a, source(name));
        defer module.deinit(a);
        var result = try backend.compile(a, &.{module}, 1);
        defer result.deinit(a);
        if (std.mem.eql(u8, name, "direct-cell-cycle")) {
            try std.testing.expectEqual(backend.Code.initialization_cycle, result.diagnostic.?.code);
            try std.testing.expectEqual(@as(usize, 0), result.bytes.len);
        } else {
            try std.testing.expect(result.diagnostic == null);
            try std.testing.expect(result.bytes.len > 8);
        }
    }
}

test "named closure applied Unit and provider captures release every failed backend allocation" {
    inline for (.{ "unit-applied-export", "applied-provider-capture" }) |name| {
        var module = try lower(a, source(name));
        defer module.deinit(a);
        const before = artifacts.stamp(module);
        try @import("allocation_failures.zig").checkAllAllocationFailures(a, compileSuccessful, .{&module});
        try std.testing.expectEqualSlices(u8, &before, &artifacts.stamp(module));
    }
}
