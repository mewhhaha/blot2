//! Native implementations of measured semantic hot paths. The generator enables
//! these only for matching source-module hashes; changed algorithms use the
//! source-derived implementation until their native counterpart is revalidated.
const std = @import("std");
const r = @import("runtime.zig");
const V = r.Value;
const variables = @import("variables.zig");
pub const variableContains = variables.has;
pub const variablePut = variables.put;
pub const variableWide = variables.isWide;
pub const variableUnion = variables.merge;
pub const variableDifference = variables.difference;

pub fn decode(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    return @import("wire.zig").decode(ctx, args[0]);
}

pub fn nameEqual(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    return r.boolean(r.stringEqual(args[0], args[1]));
}
pub fn typeIdEqual(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    r.assert(r.tag(args[0]) == .model_TypeId and r.tag(args[1]) == .model_TypeId);
    return r.boolean(r.stringEqual(r.field(args[0], 0), r.field(args[1], 0)) and
        r.stringEqual(r.field(args[0], 1), r.field(args[1], 1)));
}

// Track the already-reached suffix: several Patricia branches often inspect
// different bits of the same character. No closures or reconstructed maps.
fn stringLookup(root: V, key: V) ?V {
    var node = root;
    var suffix = key;
    var character: u64 = 0;
    while (r.tag(node) == .MNode) {
        const position = r.toNat(r.field(node, 0));
        const next_character = position / 33;
        var distance = next_character -| character;
        while (distance != 0 and r.tag(suffix) == .SCon) : (distance -= 1) suffix = r.field(suffix, 1);
        character = next_character;
        const offset = position % 33;
        const high = r.tag(suffix) == .SCon and (offset == 0 or
            (r.toWord(r.field(r.field(suffix, 0), 0)) >> @as(u5, @intCast(32 - offset))) & 1 != 0);
        node = r.field(node, if (high) 2 else 1);
    }
    if (r.tag(node) == .MLeaf and r.stringEqual(key, r.field(node, 0))) return r.field(node, 1);
    return null;
}
pub fn stringFind(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 3);
    return if (stringLookup(args[1], args[2])) |value| ctx.node(.Some, &.{value}) else r.empty(.None);
}
pub fn stringGet(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 4);
    return stringLookup(args[1], args[2]) orelse args[3];
}

fn within(key: u64, sample: u64, mask: u64) bool {
    r.assert(mask != 0 and std.math.isPowerOfTwo(mask));
    return ((key ^ sample) & ~((mask << 1) - 1)) == 0;
}
fn natLookup(root: V, key: u64) ?V {
    var node = root;
    // The source entry point has 49 steps: at most 48 branches and one leaf.
    var remaining: usize = 49;
    while (remaining != 0) : (remaining -= 1) {
        switch (r.tag(node)) {
            .nat_index_Empty => return null,
            .nat_index_Leaf => return if (r.toNat(r.field(node, 0)) == key) r.field(node, 1) else null,
            .nat_index_Branch => {
                const mask = r.toNat(r.field(node, 1));
                if (!within(key, r.toNat(r.field(node, 0)), mask)) return null;
                node = r.field(node, if (key & mask == 0) 2 else 3);
            },
            else => @panic("invalid native Nat index"),
        }
    }
    return null;
}
pub fn natFind(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 3);
    return if (natLookup(args[1], r.toNat(args[2]))) |value| ctx.node(.Some, &.{value}) else r.empty(.None);
}
pub fn natGet(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 4);
    return natLookup(args[1], r.toNat(args[2])) orelse args[3];
}
fn link(ctx: *r.Context, key: u64, leaf: V, sample: u64, other: V) V {
    const difference = key ^ sample;
    r.assert(difference != 0);
    const mask = @as(u64, 1) << @as(u6, @intCast(63 - @clz(difference)));
    return ctx.node(.nat_index_Branch, &.{ r.nat(key), r.nat(mask), if (key & mask == 0) leaf else other, if (key & mask == 0) other else leaf });
}
pub fn natSet(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 4);
    const Frame = struct { node: V, high: bool };
    var path: [48]Frame = undefined;
    var depth: usize = 0;
    var node = args[1];
    const key = r.toNat(args[2]);
    // Build one leaf, then copy only the search path. All other nodes stay
    // immutable and shared with previous snapshots.
    var result = ctx.node(.nat_index_Leaf, &.{ args[2], args[3] });
    walk: while (true) {
        switch (r.tag(node)) {
            .nat_index_Empty => break :walk,
            .nat_index_Leaf => {
                const old = r.toNat(r.field(node, 0));
                if (old != key) result = link(ctx, key, result, old, node);
                break :walk;
            },
            .nat_index_Branch => {
                const sample = r.toNat(r.field(node, 0));
                const mask = r.toNat(r.field(node, 1));
                if (!within(key, sample, mask)) {
                    result = link(ctx, key, result, sample, node);
                    break :walk;
                }
                r.assert(depth < path.len);
                const high = key & mask != 0;
                path[depth] = .{ .node = node, .high = high };
                depth += 1;
                node = r.field(node, if (high) 3 else 2);
            },
            else => @panic("invalid native Nat index"),
        }
    }
    while (depth != 0) {
        depth -= 1;
        const frame = path[depth];
        result = ctx.node(.nat_index_Branch, &.{
            r.field(frame.node, 0),                             r.field(frame.node, 1),
            if (frame.high) r.field(frame.node, 2) else result, if (frame.high) result else r.field(frame.node, 3),
        });
    }
    return result;
}

pub inline fn childrenOf(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    r.assert(r.tag(args[0]) == .cst_Cst);
    return r.field(args[0], 4);
}
pub inline fn kindOf(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    r.assert(r.tag(args[0]) == .cst_Cst);
    return r.field(args[0], 0);
}
pub inline fn textOf(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    r.assert(r.tag(args[0]) == .cst_Cst);
    return r.field(args[0], 2);
}
pub inline fn offsetOf(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    r.assert(r.tag(args[0]) == .cst_Cst);
    return r.field(args[0], 3);
}
fn selectFields(ctx: *r.Context, nodes: V, label: V, initial: V) V {
    var cursor = nodes;
    var reversed = initial;
    while (r.tag(cursor) == .Cons) : (cursor = r.field(cursor, 1)) {
        const node = r.field(cursor, 0);
        r.assert(r.tag(node) == .cst_Cst);
        if (r.stringEqual(r.field(node, 1), label)) reversed = ctx.node(.Cons, &.{ node, reversed });
    }
    return ctx.reverse(reversed, r.empty(.Nil), .Cons);
}
pub fn fields(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    return selectFields(ctx, args[0], args[1], r.empty(.Nil));
}
pub fn fieldsReversed(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 3);
    return selectFields(ctx, args[0], args[1], args[2]);
}
pub fn fieldValues(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 2);
    r.assert(r.tag(args[0]) == .cst_Cst);
    return selectFields(ctx, r.field(args[0], 4), args[1], r.empty(.Nil));
}

test "native names and string indexes preserve Unicode, prefixes and snapshots" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const keys = [_]V{ r.literal(""), r.literal("a"), r.literal("aa"), r.literal("a😀"), r.literal("😀"), r.literal("é"), r.literal("e\u{301}"), r.literal("\x00") };
    var index = r.empty(.MTip);
    for (keys, 0..) |key, i| index = ctx.mapSet(index, key, r.nat(i));
    for (keys, 0..) |left, i| {
        for (keys, 0..) |right, j| try std.testing.expectEqual(r.boolean(i == j), nameEqual(&ctx, &.{ left, right }));
        try std.testing.expectEqual(r.nat(i), stringGet(&ctx, &.{ r.erased, index, left, r.erased }));
    }
    try std.testing.expectEqual(r.empty(.None), stringFind(&ctx, &.{ r.erased, index, r.literal("missing") }));
    const changed = ctx.mapSet(index, keys[0], r.word(99));
    try std.testing.expectEqual(r.nat(0), stringGet(&ctx, &.{ r.erased, index, keys[0], r.erased }));
    try std.testing.expectEqual(r.word(99), stringGet(&ctx, &.{ r.erased, changed, keys[0], r.erased }));
    // Also compare the linked-string and contiguous-string representations.
    const linked = ctx.node(.SCon, &.{ r.character('a'), ctx.node(.SCon, &.{ r.character(0x1f600), r.empty(.SNil) }) });
    try std.testing.expectEqual(r.boolean(true), nameEqual(&ctx, &.{ keys[3], linked }));
    try std.testing.expectEqual(r.nat(3), stringGet(&ctx, &.{ r.erased, index, linked, r.erased }));
}

test "native Nat indexes cover every branching bit and retain old roots" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var root = r.empty(.nat_index_Empty);
    var snapshots: [49]V = undefined;
    const keys = blk: {
        var values: [49]u64 = undefined;
        values[0] = 0;
        for (values[1..], 0..) |*key, i| key.* = @as(u64, 1) << @as(u6, @intCast(i));
        break :blk values;
    };
    for (keys, 0..) |key, i| {
        root = natSet(&ctx, &.{ r.erased, root, r.nat(key), r.word(@intCast(i)) });
        snapshots[i] = root;
    }
    for (snapshots, 0..) |snapshot, i| {
        for (keys, 0..) |key, j| {
            const found = natFind(&ctx, &.{ r.erased, snapshot, r.nat(key) });
            if (j <= i) {
                try std.testing.expectEqual(r.Tag.Some, r.tag(found));
                try std.testing.expectEqual(r.word(@intCast(j)), r.field(found, 0));
            } else try std.testing.expectEqual(r.empty(.None), found);
        }
    }
    const replacement = natSet(&ctx, &.{ r.erased, root, r.nat(0), r.word(999) });
    try std.testing.expectEqual(r.word(0), natGet(&ctx, &.{ r.erased, root, r.nat(0), r.erased }));
    try std.testing.expectEqual(r.word(999), natGet(&ctx, &.{ r.erased, replacement, r.nat(0), r.erased }));
    root = natSet(&ctx, &.{ r.erased, root, r.nat(r.mask), r.word(42) });
    try std.testing.expectEqual(r.word(42), natGet(&ctx, &.{ r.erased, root, r.nat(r.mask), r.erased }));
}

test "native Nat indexes match an independent hash map on mixed updates" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    var expected = std.AutoHashMap(u64, V).init(std.testing.allocator);
    defer expected.deinit();
    var random = std.Random.DefaultPrng.init(20260928);
    const rng = random.random();
    var root = r.empty(.nat_index_Empty);
    for (0..4096) |i| {
        const key: u64 = if (i % 3 == 0) rng.int(u64) & r.mask else rng.int(u8);
        const value = r.word(@intCast(i));
        root = natSet(&ctx, &.{ r.erased, root, r.nat(key), value });
        try expected.put(key, value);
        try std.testing.expectEqual(value, natGet(&ctx, &.{ r.erased, root, r.nat(key), r.erased }));
    }
    var iterator = expected.iterator();
    while (iterator.next()) |entry| try std.testing.expectEqual(entry.value_ptr.*, natGet(&ctx, &.{ r.erased, root, r.nat(entry.key_ptr.*), r.erased }));
}

test "native CST field scans preserve order and the reversed prefix" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const a = ctx.node(.cst_Cst, &.{ r.literal("IDENT"), r.literal("name"), r.literal("a"), r.nat(0), r.empty(.Nil) });
    const b = ctx.node(.cst_Cst, &.{ r.literal("IDENT"), r.literal("other"), r.literal("b"), r.nat(1), r.empty(.Nil) });
    const c = ctx.node(.cst_Cst, &.{ r.literal("IDENT"), r.literal("name"), r.literal("c"), r.nat(2), r.empty(.Nil) });
    const nodes = ctx.node(.Cons, &.{ a, ctx.node(.Cons, &.{ b, ctx.node(.Cons, &.{ c, r.empty(.Nil) }) }) });
    const filtered = fields(&ctx, &.{ nodes, r.literal("name") });
    try std.testing.expectEqual(a, r.field(filtered, 0));
    try std.testing.expectEqual(c, r.field(r.field(filtered, 1), 0));
    try std.testing.expectEqual(r.empty(.Nil), r.field(r.field(filtered, 1), 1));
    const prefix = ctx.node(.Cons, &.{ b, r.empty(.Nil) });
    const extended = fieldsReversed(&ctx, &.{ nodes, r.literal("name"), prefix });
    try std.testing.expectEqual(b, r.field(extended, 0));
    try std.testing.expectEqual(a, r.field(r.field(extended, 1), 0));
    try std.testing.expectEqual(r.empty(.Nil), fields(&ctx, &.{ nodes, r.literal("absent") }));
}

pub inline fn substitutionCount(_: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    r.assert(r.tag(args[0]) == .types_Substitutions);
    return r.field(args[0], 3);
}
pub fn firstType(ctx: *r.Context, args: []const V) V {
    std.debug.assert(args.len >= 1);
    const values = args[0];
    if (r.tag(values) == .Cons and r.tag(r.field(values, 1)) == .Nil) return ctx.node(.Done, &.{r.field(values, 0)});
    return ctx.node(.Fail, &.{ctx.node(.model_Diagnostic, &.{ r.literal("internal_error"), r.literal("inference"), r.literal("type rewrite did not produce exactly one type") })});
}
// Native typed-IR entry points. No generated compound-type fallback.
const type_bridge = @import("type_bridge.zig");
pub const resolveType = type_bridge.resolveType;
pub const resolveTypes = type_bridge.resolveWork;
pub const resolveRowAt = type_bridge.resolveRowAt;
pub const rewriteTypes = type_bridge.rewrite;
pub const renameTypes = type_bridge.rename;

test "type leaf fast paths retain identities and exact first-type diagnostics" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const empty = ctx.node(.types_Substitutions, &.{ r.empty(.Nil), r.empty(.nat_index_Empty), r.empty(.nat_index_Empty), r.nat(0) });
    const nonempty = ctx.node(.types_Substitutions, &.{ r.empty(.Nil), r.empty(.nat_index_Empty), r.empty(.nat_index_Empty), r.nat(1) });
    const compound = ctx.node(.model_ArrayTy, &.{r.empty(.model_U32Ty)});
    const resolved = resolveType(&ctx, &.{ empty, compound });
    try std.testing.expectEqual(r.Tag.Done, r.tag(resolved));
    try std.testing.expectEqual(compound, r.field(resolved, 0));
    const leaf = r.empty(.model_F32Ty);
    try std.testing.expectEqual(leaf, r.field(resolveType(&ctx, &.{ nonempty, leaf }), 0));
    const via_reference = resolveType(&ctx, &.{ nonempty, compound });
    try std.testing.expectEqual(r.Tag.Done, r.tag(via_reference));
    try std.testing.expectEqual(r.Tag.model_ArrayTy, r.tag(r.field(via_reference, 0)));
    try std.testing.expectEqual(r.empty(.model_U32Ty), r.field(r.field(via_reference, 0), 0));
    try std.testing.expectEqual(r.Tag.Fail, r.tag(firstType(&ctx, &.{r.empty(.Nil)})));
    const one = ctx.node(.Cons, &.{ leaf, r.empty(.Nil) });
    try std.testing.expectEqual(leaf, r.field(firstType(&ctx, &.{one}), 0));
    try std.testing.expectEqual(r.Tag.Fail, r.tag(firstType(&ctx, &.{ctx.node(.Cons, &.{ leaf, one })})));
}
