const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const symbols = @import("symbols.zig");
const check = @import("check.zig");
const T = @import("types.zig");

fn requestEvidence(allocator: std.mem.Allocator, source: []const u8, expected_carries: []const u32) !void {
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), tree.diagnostics.items.len);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.request_loops.len != 0);
    for (checked.computations) |computation| {
        const node = checked.types.node(try checked.types.resolve(computation.ty, 0));
        try std.testing.expectEqual(T.Tag.nominal, node.tag);
        try std.testing.expectEqual(std.math.maxInt(u32), node.a);
        try std.testing.expectEqual(@as(u32, 5), node.b);
        const action = checked.types.node(try checked.types.resolve(computation.action_type, 0));
        try std.testing.expectEqual(T.Tag.function, action.tag);
        try std.testing.expectEqual(T.unit, action.a);
    }
    try std.testing.expectEqual(expected_carries.len, checked.request_loops.len);
    for (checked.request_loops, expected_carries) |loop, carry_count| {
        try std.testing.expectEqual(carry_count, loop.carried.len);
        try std.testing.expectEqual(@as(u32, 0), checked.resolver_block_ids[loop.return_scope]);
        try std.testing.expectEqual(@import("ast.zig").Tag.block, tree.node(loop.return_scope).tag);
        try std.testing.expectEqual(@import("ast.zig").Tag.request_arm, tree.node(loop.completion).tag);
        try std.testing.expectEqual(loop.complete_pattern, tree.node(loop.completion).b);
        try std.testing.expectEqual(loop.complete_suite, tree.node(loop.completion).c);
        try std.testing.expectEqual(loop.carried.len, loop.complete_state_bindings.len);
        for (checked.types.list(loop.arms)) |arm_id| {
            const arm = checked.request_arms[arm_id];
            try std.testing.expectEqual(loop.node, arm.loop);
            try std.testing.expectEqual(loop.carried.len, arm.state_bindings.len);
            const signature = checked.types.node(try checked.types.resolve(arm.signature, 0));
            try std.testing.expectEqual(T.Tag.function, signature.tag);
            const decision = checked.types.node(try checked.types.resolve(signature.b, 0));
            try std.testing.expectEqual(T.Tag.nominal, decision.tag);
            try std.testing.expectEqual(std.math.maxInt(u32), decision.a);
            try std.testing.expectEqual(@as(u32, 6), decision.b);
            const arguments = checked.types.nominalArguments(decision);
            try std.testing.expectEqual(try checked.types.resolve(arm.reply_type, 0), try checked.types.resolve(arguments[0], 0));
            try std.testing.expectEqual(try checked.types.resolve(loop.state_type, 0), try checked.types.resolve(arguments[1], 0));
            try std.testing.expectEqual(try checked.types.resolve(loop.result_type, 0), try checked.types.resolve(arguments[2], 0));
            for (checked.types.list(arm.state_bindings)) |binding| try std.testing.expectEqual(arm.node, checked.bindings[binding].owner);
        }
    }
    for (checked.request_controls) |control| switch (control.kind) {
        .reply => try std.testing.expectEqual(@import("ast.zig").Tag.request_arm, tree.node(control.target_scope).tag),
        .cancel => try std.testing.expectEqual(@import("ast.zig").Tag.block, tree.node(control.target_scope).tag),
        .break_ => try std.testing.expectEqual(control.loop, control.target_scope),
    };
}

test "request source graphs own lazy captures callback headers control destinations and state snapshots" {
    const sources = [_][]const u8{
        @embedFile("checker-positive_0.blot"),
        @embedFile("checker-positive_5.blot"),
        @embedFile("checker-positive_8.blot"),
        @embedFile("checker-positive_14.blot"),
        @embedFile("checker-positive_16.blot"),
        @embedFile("checker-positive_18.blot"),
        @embedFile("checker-positive_22.blot"),
    };
    const counts = [_]u32{ 0, 1, 0, 0, 2, 1, 0 };
    for (sources, counts) |source, count| try requestEvidence(std.testing.allocator, source, &.{count});
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, requestEvidence, .{ sources[4], &[_]u32{2} });
}

test "request row subtraction shares the ambient tail and retains the operation prefix" {
    const allocator = std.testing.allocator;
    const source = @embedFile("checker-positive_0.blot");
    var tokens = try lexer.lex(allocator, source);
    defer tokens.deinit(allocator);
    var pool: symbols.Pool = .{};
    defer pool.deinit(allocator);
    var tree = try parser.parse(allocator, source, tokens.tokens.items, &pool);
    defer tree.deinit(allocator);
    var checked = try check.check(allocator, &tree, &pool);
    defer checked.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    for (checked.bindings) |binding| if (std.mem.eql(u8, pool.get(binding.name), "checked")) {
        const header = checked.types.node(try checked.types.resolve(binding.scheme.root, 0));
        const input = checked.types.node(try checked.types.resolve(header.a, 0));
        const action = checked.types.node(checked.types.nominalArguments(input)[0]);
        const action_row = checked.types.row(try checked.types.resolveEffects(action.c, 0));
        const ambient = checked.types.row(try checked.types.resolveEffects(header.c, 0));
        try std.testing.expectEqual(@as(u32, 1), action_row.labels.len);
        try std.testing.expectEqual(@as(u32, 0), ambient.labels.len);
        try std.testing.expect(action_row.tail == .variable and ambient.tail == .variable);
        try std.testing.expectEqual(action_row.tail.variable, ambient.tail.variable);
        try std.testing.expectEqual(try checked.types.resolve(action.b, 0), try checked.types.resolve(header.b, 0));
    };
}

fn monadBoundary(allocator: std.mem.Allocator) !void {
    const cases = [_]struct { source: []const u8, code: check.Code, start: u32 }{
        .{ .source = @embedFile("monad_cancel.blot"), .code = .invalid_return, .start = 463 },
        .{ .source = @embedFile("monad_mixed_cancel.blot"), .code = .type_mismatch, .start = 421 },
        .{ .source = @embedFile("monad_break.blot"), .code = .invalid_return, .start = 269 },
    };
    for (cases) |item| {
        var tokens = try lexer.lex(allocator, item.source);
        defer tokens.deinit(allocator);
        var pool: symbols.Pool = .{};
        defer pool.deinit(allocator);
        var tree = try parser.parse(allocator, item.source, tokens.tokens.items, &pool);
        defer tree.deinit(allocator);
        var checked = try check.check(allocator, &tree, &pool);
        defer checked.deinit(allocator);
        try std.testing.expect(checked.diagnostics.len != 0);
        try std.testing.expectEqual(item.code, checked.diagnostics[0].code);
        try std.testing.expectEqual(item.start, checked.diagnostics[0].span.start);
    }
    try requestEvidence(allocator, @embedFile("monad_nested_plain.blot"), &.{0});
}

test "request callbacks keep plain cancellation types and monad composition requires an ordinary do boundary" {
    try monadBoundary(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, monadBoundary, .{});
}

test "request clauses discover outer writes before local shadowing and carry lexical reply and break snapshots" {
    const cases = [_]struct { source: []const u8, carries: u32 }{
        .{ .source = @embedFile("checker-shadow-payload_shadow_carried_elsewhere.blot"), .carries = 1 },
        .{ .source = @embedFile("checker-shadow-local_shadow_after_outer_update.blot"), .carries = 1 },
        .{ .source = @embedFile("checker-shadow-payload_shadows_all_updates.blot"), .carries = 0 },
        .{ .source = @embedFile("checker-shadow-completion_payload_shadow.blot"), .carries = 1 },
    };
    for (cases) |item| try requestEvidence(std.testing.allocator, item.source, &.{item.carries});
}
