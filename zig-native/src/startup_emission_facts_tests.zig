const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const a = std.testing.allocator;

fn lower(allocator: std.mem.Allocator, source: []const u8) !core.Module {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var names: symbols.Pool = .{};
    defer names.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &names);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.checkModuleWithOptions(allocator, &tree, &names, &.{}, &.{}, 1, .{});
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var result = try core.lower(allocator, &tree, &names, &checked);
    errdefer result.deinit(allocator);
    result.unit = 1;
    return result;
}

fn observeOwned(allocator: std.mem.Allocator) !void {
    const source = "const read: Unit -> U32 = fn () => do:\n  for i in 0..1:\n    return second\n  return second\nlet first = read ()\nlet second: U32 = 42\nentry const answer: Unit -> U32 = fn () => @u32.add first (read ())\n";
    var ordinary, var observed = blk: {
        var module = try lower(allocator, source);
        defer module.deinit(allocator);
        var plain = try backend.compile(allocator, &.{module}, 1);
        errdefer plain.deinit(allocator);
        break :blk .{ plain, try backend.compileWithOptions(allocator, &.{module}, 1, .{ .observe_startup = true }) };
    };
    defer ordinary.deinit(allocator);
    defer observed.deinit(allocator);
    try std.testing.expect(ordinary.diagnostic == null and observed.diagnostic == null);
    try std.testing.expectEqualSlices(u8, ordinary.bytes, observed.bytes);
    try std.testing.expectEqual(ordinary.constant_steps, observed.constant_steps);
    const snapshot = observed.startup_observation orelse return error.MissingObservation;
    var hits: usize = 0;
    var reads: usize = 0;
    var complete: usize = 0;
    for (snapshot.headers) |header| if (header.complete) {
        complete += 1;
    };
    for (snapshot.events) |event| switch (event.kind) {
        .request => if (event.flag) {
            hits += 1;
        },
        .runtime_global_request => reads += 1,
        else => {},
    };
    try std.testing.expect(hits != 0 and reads != 0 and complete != 0);
}

test "startup emission observations preserve bytes and survive all source and evaluator owners" {
    try observeOwned(a);
}

test "startup emission observation owners clean up every allocation failure" {
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, observeOwned, .{});
}
