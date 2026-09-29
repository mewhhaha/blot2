//! Ordered free-variable operations. Lists remain immutable; only temporary
//! membership tables and unpublished result links are mutable.
const std = @import("std");
const r = @import("runtime.zig");
const V = r.Value;
const Set = std.AutoHashMapUnmanaged(V, void);

fn contains(values: V, needle: V) bool {
    var cursor = values;
    while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
        if (r.field(cursor, 0) == needle) return true;
    }
    return false;
}
fn wide(values: V) bool {
    var cursor = values;
    for (0..16) |_| {
        if (r.tag(cursor) == .Nil) return false;
        cursor = r.field(cursor, 1);
    }
    return true;
}
fn seed(ctx: *r.Context, set: *Set, values: V) void {
    var cursor = values;
    while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
        set.put(ctx.allocator(), r.field(cursor, 0), {}) catch @panic("out of memory");
    }
}
pub fn has(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    return r.boolean(contains(args[0], args[1]));
}
pub fn put(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    return if (contains(args[0], args[1])) args[0] else ctx.node(.Cons, &.{ args[1], args[0] });
}
pub fn isWide(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    return r.boolean(wide(args[0]));
}
pub fn merge(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    var left = args[0];
    var result = args[1];
    if (!wide(left)) {
        // Most free-variable unions add zero or one ID. Do not allocate a
        // hash table on that path, even when the right-hand list is large.
        while (r.tag(left) == .Cons) : (left = r.field(left, 1)) {
            const value = r.field(left, 0);
            if (!contains(result, value)) result = ctx.node(.Cons, &.{ value, result });
        }
        return result;
    }
    var seen: Set = .empty;
    defer seen.deinit(ctx.allocator());
    seed(ctx, &seen, result);
    while (r.tag(left) == .Cons) : (left = r.field(left, 1)) {
        const value = r.field(left, 0);
        const entry = seen.getOrPut(ctx.allocator(), value) catch @panic("out of memory");
        if (!entry.found_existing) result = ctx.node(.Cons, &.{ value, result });
    }
    // The right-hand list is retained verbatim, including its duplicates.
    return result;
}
pub fn difference(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    var cursor = args[0];
    const excluded = args[1];
    if (r.tag(excluded) == .Nil) return cursor;
    var reversed = r.empty(.Nil);
    if (!wide(cursor) or !wide(excluded)) {
        while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
            const value = r.field(cursor, 0);
            if (!contains(excluded, value)) reversed = ctx.node(.Cons, &.{ value, reversed });
        }
    } else {
        var seen: Set = .empty;
        defer seen.deinit(ctx.allocator());
        seed(ctx, &seen, excluded);
        while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
            const value = r.field(cursor, 0);
            if (!seen.contains(value)) reversed = ctx.node(.Cons, &.{ value, reversed });
        }
    }
    return r.Context.reverseOwnedList(reversed);
}

fn list(ctx: *r.Context, values: []const u64) V {
    var out = r.empty(.Nil);
    var i = values.len;
    while (i != 0) {
        i -= 1;
        out = ctx.node(.Cons, &.{ r.nat(values[i]), out });
    }
    return out;
}
fn expectList(expected: []const u64, actual: V) !void {
    var cursor = actual;
    for (expected) |value| {
        try std.testing.expectEqual(r.Tag.Cons, r.tag(cursor));
        try std.testing.expectEqual(value, r.toNat(r.field(cursor, 0)));
        cursor = r.field(cursor, 1);
    }
    try std.testing.expectEqual(r.Tag.Nil, r.tag(cursor));
}
test "variable union preserves right duplicates and reverses new left IDs" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const left = list(&ctx, &.{ 5, 3, 5, 1, 4, r.mask });
    const right = list(&ctx, &.{ 3, 3, 2 });
    try expectList(&.{ r.mask, 4, 1, 5, 3, 3, 2 }, merge(&ctx, &.{ left, right }));
    try expectList(&.{ 5, 1, 5, 4, r.mask }, difference(&ctx, &.{ list(&ctx, &.{ 5, 3, 1, 5, 4, r.mask }), right }));
    try expectList(&.{ 5, 3, 5, 1, 4, r.mask }, left);
    try expectList(&.{ 3, 3, 2 }, right);
    try std.testing.expectEqual(right, merge(&ctx, &.{ r.empty(.Nil), right }));
    try std.testing.expectEqual(right, put(&ctx, &.{ right, r.nat(3) }));
}
test "wide variable operations match independent ordered array operations" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var a: [512]u64 = undefined;
    var b: [512]u64 = undefined;
    for (&a, &b, 0..) |*x, *y, i| {
        x.* = (i * 7) % 127;
        y.* = (i * 3) % 67;
    }
    var expected: std.ArrayList(u64) = .empty;
    defer expected.deinit(std.testing.allocator);
    try expected.appendSlice(std.testing.allocator, &b);
    for (a) |value| {
        if (std.mem.indexOfScalar(u64, expected.items, value) == null) try expected.insert(std.testing.allocator, 0, value);
    }
    const left = list(&ctx, &a);
    const right = list(&ctx, &b);
    try expectList(expected.items, merge(&ctx, &.{ left, right }));
    expected.clearRetainingCapacity();
    for (a) |value| {
        if (std.mem.indexOfScalar(u64, &b, value) == null) try expected.append(std.testing.allocator, value);
    }
    try expectList(expected.items, difference(&ctx, &.{ left, right }));
    try expectList(&a, left);
    try expectList(&b, right);
    try std.testing.expect(r.truth(isWide(&ctx, &.{left})));
    try std.testing.expect(!r.truth(isWide(&ctx, &.{list(&ctx, a[0..15])})));
}
