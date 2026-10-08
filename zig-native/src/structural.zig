//! Reflection-driven structural equality and hashing over owned data. Slices
//! compare and hash by content; borrowed pointers, untagged unions and types
//! without a stable value representation are rejected at compile time so no
//! address or padding byte ever reaches a comparison or a digest.
const std = @import("std");

/// True when `a` and `b` hold the same values field by field. Unions compare
/// their active tag and payload.
pub fn equal(a: anytype, b: @TypeOf(a)) bool {
    const T = @TypeOf(a);
    return switch (@typeInfo(T)) {
        .pointer => |pointer| blk: {
            if (pointer.size != .slice) @compileError("Structural equality requires owned slices");
            if (a.len != b.len) break :blk false;
            for (a, b) |left, right| if (!equal(left, right)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            for (a, b) |left, right| if (!equal(left, right)) break :blk false;
            break :blk true;
        },
        .@"struct" => |structure| blk: {
            inline for (structure.field_names) |name| if (!equal(@field(a, name), @field(b, name))) break :blk false;
            break :blk true;
        },
        .optional => if (a) |left| if (b) |right| equal(left, right) else false else b == null,
        .@"union" => if (std.meta.activeTag(a) != std.meta.activeTag(b)) false else switch (a) {
            inline else => |left, tag| equal(left, @field(b, @tagName(tag))),
        },
        .int, .float, .bool, .@"enum" => a == b,
        .void => true,
        else => @compileError("Unsupported structural equality type " ++ @typeName(T)),
    };
}

/// Feeds the canonical byte stream of `value` to `sink.update(bytes)`. Slice
/// lengths are framed, optionals are preceded by a presence flag and unions by
/// their tag, so unequal values never share a stream prefix.
pub fn hash(sink: anytype, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("Structural hashes cannot contain borrowed pointers");
            hash(sink, value.len);
            if (pointer.child == u8) sink.update(value) else for (value) |item| hash(sink, item);
        },
        .array => for (value) |item| hash(sink, item),
        .@"struct" => |structure| inline for (structure.field_names) |name| hash(sink, @field(value, name)),
        .optional => {
            hash(sink, value != null);
            if (value) |item| hash(sink, item);
        },
        .@"union" => |union_| {
            if (union_.tag_type == null) @compileError("Structural hashes require tagged unions");
            hash(sink, std.meta.activeTag(value));
            switch (value) {
                inline else => |item| hash(sink, item),
            }
        },
        .@"enum" => hash(sink, @backingInt(value)),
        .int, .float, .bool => sink.update(std.mem.asBytes(&value)),
        .void => {},
        else => @compileError("Unsupported structural hash type " ++ @typeName(T)),
    }
}

const Sample = struct {
    name: []const u8,
    counts: [2]u32,
    parent: ?u32,
    shape: union(enum) { none, size: u16, pair: struct { a: bool, b: f32 } },
};

const Collector = struct {
    bytes: std.ArrayList(u8) = .empty,

    fn update(self: *Collector, source: []const u8) void {
        self.bytes.appendSlice(std.testing.allocator, source) catch @panic("out of memory");
    }
};

fn sample(name: []const u8, shape: @FieldType(Sample, "shape")) Sample {
    return .{ .name = name, .counts = .{ 1, 2 }, .parent = null, .shape = shape };
}

test "equality compares slices by content and unions by active payload" {
    const left = [_]Sample{ sample("a", .none), sample("b", .{ .size = 3 }) };
    const copy = [_]Sample{ sample("a", .none), sample("b", .{ .size = 3 }) };
    try std.testing.expect(equal(@as([]const Sample, &left), &copy));
    try std.testing.expect(!equal(@as([]const Sample, &left), left[0..1]));
    var different = copy;
    different[1].shape = .{ .size = 4 };
    try std.testing.expect(!equal(@as([]const Sample, &left), &different));
    different[1].shape = .none;
    try std.testing.expect(!equal(@as([]const Sample, &left), &different));
    different = copy;
    different[0].parent = 0;
    try std.testing.expect(!equal(@as([]const Sample, &left), &different));
    different = copy;
    different[0].name = "other";
    try std.testing.expect(!equal(@as([]const Sample, &left), &different));
}

test "hash streams are framed and independent of addresses" {
    var first: Collector = .{};
    defer first.bytes.deinit(std.testing.allocator);
    var second: Collector = .{};
    defer second.bytes.deinit(std.testing.allocator);
    const name = try std.testing.allocator.dupe(u8, "name");
    defer std.testing.allocator.free(name);
    hash(&first, sample("name", .{ .size = 7 }));
    hash(&second, sample(name, .{ .size = 7 }));
    try std.testing.expectEqualSlices(u8, first.bytes.items, second.bytes.items);

    var other: Collector = .{};
    defer other.bytes.deinit(std.testing.allocator);
    hash(&other, sample("name", .{ .size = 8 }));
    try std.testing.expect(!std.mem.eql(u8, first.bytes.items, other.bytes.items));

    var split: Collector = .{};
    defer split.bytes.deinit(std.testing.allocator);
    var joined: Collector = .{};
    defer joined.bytes.deinit(std.testing.allocator);
    hash(&split, [_][]const u8{ "ab", "c" });
    hash(&joined, [_][]const u8{ "a", "bc" });
    try std.testing.expect(!std.mem.eql(u8, split.bytes.items, joined.bytes.items));
}
