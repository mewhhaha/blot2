const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const allocator = std.testing.allocator;
const Observation = struct { name: []const u8, source: []const u8, success: bool, code: []const u8 };
fn checkSource(memory: std.mem.Allocator, source: []const u8, success: bool) !void {
    var tokens = try lexer.lex(memory, source);
    defer tokens.deinit(memory);
    var pool: symbols.Pool = .{};
    defer pool.deinit(memory);
    var tree = try parser.parse(memory, source, tokens.tokens.items, &pool);
    defer tree.deinit(memory);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(memory, &tree, &pool);
    defer checked.deinit(memory);
    if (success) {
        for (checked.diagnostics) |diagnostic| std.debug.print("Unit coverage {s} at{d}\n", .{ @tagName(diagnostic.code), diagnostic.span.start });
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    } else {
        try std.testing.expectEqual(@as(usize, 1), checked.diagnostics.len);
        try std.testing.expectEqual(check.Code.non_exhaustive_match, checked.diagnostics[0].code);
    }
}
test "Unit zero-arity variant matches sixteen actual constant runtime nested and partial coverage controls" {
    const records = try std.json.parseFromSlice([]Observation, allocator, @embedFile("unit-coverage-oracle.json"), .{ .ignore_unknown_fields = true });
    defer records.deinit();
    for (records.value) |item| {
        if (!item.success) try std.testing.expectEqualStrings("non_exhaustive_match", item.code);
        checkSource(allocator, item.source, item.success) catch |err| {
            std.debug.print("Unit coverage fixture {s}: {s}\n", .{ item.name, @errorName(err) });
            return err;
        };
    }
}
test "Unit coverage constructor field specialization releases successful and failing allocations" {
    const source = "type Pair is data = #Pair {token: Unit, value: (Unit, U32)}\nentry const answer = case #Pair {token: (), value: ((), 42)} of\n  #Pair {token: (), value: ((), result)} => result\n";
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, checkSource, .{ source, true });
    const partial = "entry const answer = case ((), ((), 42)) of\n  ((), ((), 42)) => 42\n";
    try @import("allocation_failures.zig").checkAllAllocationFailures(allocator, checkSource, .{ partial, false });
}
