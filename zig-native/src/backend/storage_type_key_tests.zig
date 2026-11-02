const std = @import("std");
const K = @import("storage_type_key.zig");
const calls = @import("storage_calls.zig");
const a = std.testing.allocator;
const Term = struct { reference: K.Reference, head: []const u32, children: []const usize = &.{}, tail: []const u32 = &.{} };

fn visit(builder: *K.Builder, terms: []const Term, ordinal: usize, depth: usize) K.Error!K.Result {
    const term = terms[ordinal];
    if (try builder.enter(term.reference, depth)) |result| return result;
    var words: std.ArrayList(u32) = .empty;
    defer words.deinit(builder.allocator);
    try builder.addWords(&words, term.head);
    var height: usize = 0;
    for (term.children) |child| {
        const result = try visit(builder, terms, child, depth + 1);
        height = @max(height, result.height + 1);
        try builder.addWord(&words, result.id);
    }
    try builder.addWords(&words, term.tail);
    return builder.complete(term.reference, words.items, height);
}
fn key(allocator: std.mem.Allocator, terms: []const Term, roots: []const usize, options: K.Options) ![]u32 {
    var work: usize = 4096;
    var builder = K.Builder.init(allocator, &work, options);
    defer builder.deinit();
    var output: std.ArrayList(u32) = .empty;
    errdefer output.deinit(allocator);
    for (roots) |root| try builder.root(&output, try visit(&builder, terms, root, 0));
    try builder.finish(&output);
    return output.toOwnedSlice(allocator);
}
fn expanded(allocator: std.mem.Allocator, terms: []const Term, root: usize, output: *std.ArrayList(u32)) !void {
    try output.appendSlice(allocator, terms[root].head);
    for (terms[root].children) |child| try expanded(allocator, terms, child, output);
    try output.appendSlice(allocator, terms[root].tail);
}

fn inlineMemoScenario(allocator: std.mem.Allocator) !void {
    const terms = [_]Term{
        .{ .reference = .{ .unit = 0, .ty = 1 }, .head = &.{4} },
        .{ .reference = .{ .unit = 0, .ty = 2 }, .head = &.{ 9, 2 }, .children = &.{ 0, 0 } },
        .{ .reference = .{ .unit = 9, .ty = 2 }, .head = &.{ 9, 2 }, .children = &.{ 0, 0 } },
        .{ .reference = .{ .unit = 0, .ty = 2, .environment = 7, .captured = true }, .head = &.{ 9, 2 }, .children = &.{ 0, 0 } },
        .{ .reference = .{ .unit = 0, .ty = 3, .captured = true }, .head = &.{ 9, 1 }, .children = &.{0} },
        .{ .reference = .{ .unit = 0, .ty = 5 }, .head = &.{ 9, 2 }, .children = &.{ 1, 2 } },
        .{ .reference = .{ .unit = 0, .ty = 6 }, .head = &.{4} },
    };
    var ordinary = terms;
    for (&ordinary) |*term| term.reference.unit += 100;
    const roots = [_]usize{ 5, 3, 4, 6, 5 };
    const direct = try key(allocator, &terms, &roots, .{ .hash_mask = 0 });
    defer allocator.free(direct);
    const hashed = try key(allocator, &ordinary, &roots, .{ .hash_mask = 0 });
    defer allocator.free(hashed);
    try std.testing.expectEqualSlices(u32, hashed, direct);
}

test "selected structural inline memo preserves arbitrary descriptors captured references collisions and OOM" {
    try inlineMemoScenario(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, inlineMemoScenario, .{});
}

test "selected structural inline memo retains active depth completion and work bounds" {
    const reference: K.Reference = .{ .unit = 0, .ty = 3 };
    var work: usize = 2;
    var builder = K.Builder.init(a, &work, .{});
    defer builder.deinit();
    try std.testing.expectEqual(@as(?K.Result, null), try builder.enter(reference, 0));
    const result = try builder.complete(reference, &.{4}, 0);
    try std.testing.expectEqual(@as(usize, 0), builder.memo.count());
    var output: std.ArrayList(u32) = .empty;
    defer output.deinit(a);
    try builder.root(&output, result);
    try builder.finish(&output);
    try std.testing.expectEqual(@as(usize, 0), work);

    var active_work: usize = 8;
    var active = K.Builder.init(a, &active_work, .{});
    defer active.deinit();
    _ = try active.enter(reference, 0);
    try std.testing.expectError(error.Cycle, active.enter(reference, 0));
    try std.testing.expectError(error.Limit, active.finish(&output));

    var depth_work: usize = 8;
    var depth = K.Builder.init(a, &depth_work, .{});
    defer depth.deinit();
    _ = try depth.enter(reference, 128);
    try std.testing.expectError(error.Limit, depth.complete(reference, &.{4}, 1));

    var pending_work: usize = 8;
    var pending = K.Builder.init(a, &pending_work, .{});
    defer pending.deinit();
    _ = try pending.enter(reference, 0);
    try std.testing.expectError(error.Cycle, pending.finish(&output));

    var exhausted_work: usize = 1;
    var exhausted = K.Builder.init(a, &exhausted_work, .{});
    defer exhausted.deinit();
    _ = try exhausted.enter(reference, 0);
    _ = try exhausted.complete(reference, &.{4}, 0);
    try std.testing.expectError(error.Limit, exhausted.finish(&output));
}

test "selected structural keys preserve tree equality independently of sharing and source ids" {
    const shared = [_]Term{
        .{ .reference = .{ .unit = 1, .ty = 1 }, .head = &.{3} },
        .{ .reference = .{ .unit = 1, .ty = 2 }, .head = &.{ 9, 2 }, .children = &.{ 0, 0 } },
    };
    const copied = [_]Term{
        .{ .reference = .{ .unit = 3, .ty = 99 }, .head = &.{3} },
        .{ .reference = .{ .unit = 4, .ty = 6 }, .head = &.{3} },
        .{ .reference = .{ .unit = 8, .ty = 52 }, .head = &.{ 9, 2 }, .children = &.{ 0, 1 } },
    };
    var left_tree: std.ArrayList(u32) = .empty;
    defer left_tree.deinit(a);
    var right_tree: std.ArrayList(u32) = .empty;
    defer right_tree.deinit(a);
    try expanded(a, &shared, 1, &left_tree);
    try expanded(a, &copied, 2, &right_tree);
    try std.testing.expectEqualSlices(u32, left_tree.items, right_tree.items);
    const left = try key(a, &shared, &.{ 1, 0, 1 }, .{});
    defer a.free(left);
    const right = try key(a, &copied, &.{ 2, 1, 2 }, .{});
    defer a.free(right);
    try std.testing.expectEqualSlices(u32, left, right);
    const collisions = try key(a, &copied, &.{ 2, 1, 2 }, .{ .hash_mask = 0 });
    defer a.free(collisions);
    try std.testing.expectEqualSlices(u32, left, collisions);
    var active: calls.ActiveCalls = .{ .allocator = a };
    defer active.deinit();
    const target: calls.ActiveCalls.Target = .{ .unit = 1, .id = 4, .kind = .named };
    try std.testing.expect(try active.enter(target, left));
    try std.testing.expect(!try active.enter(target, right));
    active.leave();
}

test "selected structural keys retain ordered roles correlations and captured environments" {
    var terms = [_]Term{
        .{ .reference = .{ .unit = 1, .ty = 1, .environment = 100, .captured = true }, .head = &.{ 7, 1, 55 } },
        .{ .reference = .{ .unit = 1, .ty = 1, .environment = 200, .captured = true }, .head = &.{ 7, 1, 56 } },
        .{ .reference = .{ .unit = 1, .ty = 3 }, .head = &.{ 9, 2 }, .children = &.{ 0, 0 } },
        .{ .reference = .{ .unit = 1, .ty = 4 }, .head = &.{ 9, 2 }, .children = &.{ 0, 1 } },
    };
    const correlated = try key(a, &terms, &.{2}, .{});
    defer a.free(correlated);
    const independent = try key(a, &terms, &.{3}, .{});
    defer a.free(independent);
    try std.testing.expect(!std.mem.eql(u32, correlated, independent));
    terms[1].head = terms[0].head;
    const equivalent = try key(a, &terms, &.{3}, .{});
    defer a.free(equivalent);
    try std.testing.expectEqualSlices(u32, correlated, equivalent);
    // Different nominal/field/primitive/row/usage/abstract role words stay exact.
    for ([_][]const u32{ &.{ 7, 2, 55 }, &.{ 7, 1, 54 }, &.{ 8, 1, 55 }, &.{ 7, 1, 55, 1 } }) |changed| {
        terms[1].head = changed;
        const different = try key(a, &terms, &.{3}, .{ .hash_mask = 0 });
        defer a.free(different);
        try std.testing.expect(!std.mem.eql(u32, correlated, different));
    }
    terms[1].head = &.{4};
    const forward = try key(a, &terms, &.{ 0, 1 }, .{});
    defer a.free(forward);
    const backward = try key(a, &terms, &.{ 1, 0 }, .{});
    defer a.free(backward);
    try std.testing.expect(!std.mem.eql(u32, forward, backward));
}

test "selected structural keys bound broad forests cycles memo depth and output" {
    var fields: [166]usize = @splat(0);
    const terms = [_]Term{
        .{ .reference = .{ .unit = 1, .ty = 3 }, .head = &.{3} },
        .{ .reference = .{ .unit = 1, .ty = 6 }, .head = &.{ 11, 166 }, .children = &fields },
        .{ .reference = .{ .unit = 1, .ty = 7 }, .head = &.{12}, .children = &.{ 1, 1 }, .tail = &.{ 0, 0 } },
    };
    const roots: [13]usize = @splat(2);
    const broad = try key(a, &terms, &roots, .{});
    defer a.free(broad);
    try std.testing.expect(broad.len < 256);
    try std.testing.expectError(error.Limit, key(a, &terms, &roots, .{ .encoded_words = 32 }));
    try std.testing.expectError(error.Limit, key(a, &terms, &roots, .{ .word_work = 3 }));
    const cycle = [_]Term{.{ .reference = .{ .unit = 1, .ty = 1 }, .head = &.{9}, .children = &.{0} }};
    try std.testing.expectError(error.Cycle, key(a, &cycle, &.{0}, .{}));
    var work: usize = 4096;
    var builder = K.Builder.init(a, &work, .{});
    defer builder.deinit();
    _ = try visit(&builder, &terms, 2, 0);
    try std.testing.expectError(error.Limit, visit(&builder, &terms, 2, 127));
}

fn atomicScenario(allocator: std.mem.Allocator) !void {
    const terms = [_]Term{
        .{ .reference = .{ .unit = 1, .ty = 1 }, .head = &.{3} },
        .{ .reference = .{ .unit = 1, .ty = 2 }, .head = &.{9}, .children = &.{ 0, 0 } },
    };
    var work: usize = 4096;
    var builder = K.Builder.init(allocator, &work, .{});
    defer builder.deinit();
    const result = try visit(&builder, &terms, 1, 0);
    var output: std.ArrayList(u32) = .empty;
    defer output.deinit(allocator);
    try builder.root(&output, result);
    const prefix_len = output.items.len;
    builder.finish(&output) catch |err| {
        try std.testing.expectEqual(prefix_len, output.items.len);
        try std.testing.expectEqual(result.id, output.items[0]);
        return err;
    };
}
test "selected structural key construction and table publication are atomic through allocation failure" {
    try atomicScenario(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, atomicScenario, .{});
}

fn visitScratch(builder: *K.Builder, terms: []const Term, ordinal: usize, depth: usize) K.Error!K.Result {
    const term = terms[ordinal];
    if (try builder.enter(term.reference, depth)) |result| return result;
    const start = builder.beginDescriptor();
    defer builder.endDescriptor(start);
    try builder.descriptorWords(start, term.head);
    var height: usize = 0;
    for (term.children) |child| {
        const result = try visitScratch(builder, terms, child, depth + 1);
        height = @max(height, result.height + 1);
        try builder.descriptorWord(start, result.id);
    }
    try builder.descriptorWords(start, term.tail);
    return builder.completeDescriptor(term.reference, start, height);
}
fn scratchScenario(allocator: std.mem.Allocator) !void {
    const names: [129]u32 = @splat(0x12345678);
    const terms = [_]Term{
        .{ .reference = .{ .unit = 1, .ty = 1 }, .head = &names },
        .{ .reference = .{ .unit = 1, .ty = 2 }, .head = &names, .children = &.{ 0, 0 }, .tail = &.{ 7, 8 } },
        .{ .reference = .{ .unit = 2, .ty = 3, .environment = 42, .captured = true }, .head = &names, .children = &.{ 1, 0, 1 } },
    };
    for ([_]K.Options{ .{}, .{ .hash_mask = 0 }, .{ .encoded_words = 400 }, .{ .word_work = 800 } }) |options| {
        var old_work: usize = 4096;
        var new_work: usize = old_work;
        var old = K.Builder.init(allocator, &old_work, options);
        defer old.deinit();
        var new = K.Builder.init(allocator, &new_work, options);
        defer new.deinit();
        var expected: std.ArrayList(u32) = .empty;
        defer expected.deinit(allocator);
        var actual: std.ArrayList(u32) = .empty;
        defer actual.deinit(allocator);
        for ([_]usize{ 2, 1, 2, 0 }) |root| {
            const before = visit(&old, &terms, root, 0) catch |err| {
                if (err == error.OutOfMemory) return err;
                if (visitScratch(&new, &terms, root, 0)) |_| {
                    return error.TestExpectedError;
                } else |actual_error| {
                    if (actual_error == error.OutOfMemory) return actual_error;
                    try std.testing.expectEqual(err, actual_error);
                }
                try std.testing.expectEqual(@as(usize, 0), new.scratch.items.len);
                try std.testing.expect(new.poisoned);
                try std.testing.expectEqual(old_work, new_work);
                try std.testing.expectEqual(old.word_work, new.word_work);
                break;
            };
            const after = try visitScratch(&new, &terms, root, 0);
            try std.testing.expectEqual(before, after);
            try std.testing.expectEqual(@as(usize, 0), new.scratch.items.len);
            try old.root(&expected, before);
            try new.root(&actual, after);
        }
        if (old.poisoned) continue;
        try old.finish(&expected);
        try new.finish(&actual);
        try std.testing.expectEqualSlices(u32, expected.items, actual.items);
        try std.testing.expectEqual(old_work, new_work);
        try std.testing.expectEqual(old.word_work, new.word_work);
    }
}
test "selected structural scratch descriptors preserve nested growth exact keys budgets and unwind through OOM" {
    try scratchScenario(a);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scratchScenario, .{});
}
