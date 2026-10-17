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
            if (comptime plainBytes(pointer.child)) break :blk std.mem.eql(u8, std.mem.sliceAsBytes(a), std.mem.sliceAsBytes(b));
            for (a, b) |left, right| if (!equal(left, right)) break :blk false;
            break :blk true;
        },
        .array => blk: {
            if (comptime plainBytes(T)) break :blk std.mem.eql(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
            for (a, b) |left, right| if (!equal(left, right)) break :blk false;
            break :blk true;
        },
        .@"struct" => |structure| blk: {
            if (comptime plainBytes(T)) break :blk std.mem.eql(u8, std.mem.asBytes(&a), std.mem.asBytes(&b));
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
/// their tag, so unequal values never share a stream prefix. Fixed-size parts
/// reach the sink in larger pieces; the stream itself never changes, so a sink
/// must not depend on how it is split.
pub fn hash(sink: anytype, value: anytype) void {
    const T = @TypeOf(value);
    if (comptime fixedStream(T) == 0) return;
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("Structural hashes cannot contain borrowed pointers");
            hash(sink, value.len);
            if (comptime memoryStream(pointer.child)) {
                sink.update(std.mem.sliceAsBytes(value));
            } else if (comptime fixedStream(pointer.child) != null) {
                hashFixedItems(sink, pointer.child, value);
            } else for (value) |item| hash(sink, item);
        },
        .array => |array| if (comptime memoryStream(T)) {
            sink.update(std.mem.asBytes(&value));
        } else if (comptime fixedStream(array.child) != null) {
            hashFixedItems(sink, array.child, &value);
        } else for (value) |item| hash(sink, item),
        .@"struct" => |structure| if (comptime memoryStream(T)) {
            sink.update(std.mem.asBytes(&value));
        } else if (comptime (fixedStream(T) orelse max_fixed_chunk + 1) <= max_fixed_chunk) {
            var bytes: [fixedStream(T).?]u8 = undefined;
            putFixed(T, value, &bytes);
            sink.update(&bytes);
        } else inline for (structure.field_names) |name| hash(sink, @field(value, name)),
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

/// Types compared by `equal` exactly when their bytes match: no padding,
/// unused bits, floats, pointers or unions.
fn plainBytes(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => std.meta.hasUniqueRepresentation(T),
        .array => |array| plainBytes(array.child),
        .@"struct" => |structure| blk: {
            if (structure.layout == .@"packed") break :blk false;
            var size: usize = 0;
            for (structure.field_names, structure.field_attrs) |name, attrs| {
                if (attrs.@"comptime" or !plainBytes(@FieldType(T, name))) break :blk false;
                size += @sizeOf(@FieldType(T, name));
            }
            break :blk size == @sizeOf(T);
        },
        else => false,
    };
}
/// Types whose memory is byte for byte their `hash` stream: scalars without
/// padding bytes, and arrays and structs of them laid out in declaration
/// order with no gaps.
fn memoryStream(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .int, .@"enum" => std.meta.hasUniqueRepresentation(T),
        .float => @bitSizeOf(T) == @sizeOf(T) * 8,
        .bool => true,
        .array => |array| memoryStream(array.child),
        .@"struct" => |structure| blk: {
            if (structure.layout == .@"packed") break :blk false;
            var offset: usize = 0;
            for (structure.field_names, structure.field_attrs) |name, attrs| {
                if (attrs.@"comptime" or !memoryStream(@FieldType(T, name)) or @offsetOf(T, name) != offset) break :blk false;
                offset += @sizeOf(@FieldType(T, name));
            }
            break :blk offset == @sizeOf(T);
        },
        else => false,
    };
}
/// Length of the `hash` stream when it is the same for every value of `T`.
fn fixedStream(comptime T: type) ?usize {
    return switch (@typeInfo(T)) {
        .int, .float, .bool => @sizeOf(T),
        .@"enum" => |info| @sizeOf(info.tag_type),
        .void => 0,
        .array => |array| if (fixedStream(array.child)) |item| item * array.len else null,
        .@"struct" => |structure| blk: {
            var size: usize = 0;
            for (structure.field_names) |name| size += fixedStream(@FieldType(T, name)) orelse break :blk null;
            break :blk size;
        },
        else => null,
    };
}
const max_fixed_chunk = 1024;
/// Writes the `hash` stream of a fixed-stream value without calling a sink.
fn putFixed(comptime T: type, value: T, out: *[fixedStream(T).?]u8) void {
    switch (@typeInfo(T)) {
        .int, .float, .bool => out.* = std.mem.toBytes(value),
        .@"enum" => |info| putFixed(info.tag_type, @backingInt(value), out),
        .void => {},
        .array => |array| {
            const width = comptime fixedStream(array.child).?;
            for (value, 0..) |item, index| putFixed(array.child, item, out[index * width ..][0..width]);
        },
        .@"struct" => |structure| {
            comptime var offset: usize = 0;
            inline for (structure.field_names) |name| {
                const Field = @FieldType(T, name);
                const width = comptime fixedStream(Field).?;
                putFixed(Field, @field(value, name), out[offset..][0..width]);
                offset += width;
            }
        },
        else => comptime unreachable,
    }
}
fn hashFixedItems(sink: anytype, comptime Item: type, items: []const Item) void {
    const width = comptime fixedStream(Item).?;
    if (width == 0) return;
    if (width > max_fixed_chunk) {
        for (items) |item| hash(sink, item);
        return;
    }
    const per_chunk = max_fixed_chunk / width;
    var bytes: [per_chunk * width]u8 = undefined;
    var start: usize = 0;
    while (start < items.len) {
        const count = @min(per_chunk, items.len - start);
        for (items[start..][0..count], 0..) |item, index| putFixed(Item, item, bytes[index * width ..][0..width]);
        sink.update(bytes[0 .. count * width]);
        start += count;
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

/// The element-by-element stream every fast path must reproduce exactly.
fn walk(sink: anytype, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => {
            walk(sink, value.len);
            for (value) |item| walk(sink, item);
        },
        .array => for (value) |item| walk(sink, item),
        .@"struct" => |structure| inline for (structure.field_names) |name| walk(sink, @field(value, name)),
        .optional => {
            walk(sink, value != null);
            if (value) |item| walk(sink, item);
        },
        .@"union" => {
            walk(sink, std.meta.activeTag(value));
            switch (value) {
                inline else => |item| walk(sink, item),
            }
        },
        .@"enum" => walk(sink, @backingInt(value)),
        .int, .float, .bool => sink.update(std.mem.asBytes(&value)),
        .void => {},
        else => comptime unreachable,
    }
}
fn expectSameStream(value: anytype) !void {
    var fast: Collector = .{};
    defer fast.bytes.deinit(std.testing.allocator);
    var reference: Collector = .{};
    defer reference.bytes.deinit(std.testing.allocator);
    hash(&fast, value);
    walk(&reference, value);
    try std.testing.expectEqualSlices(u8, reference.bytes.items, fast.bytes.items);
}
const Plain = struct { a: u32, b: u32 };
const Padded = struct { tag: enum(u8) { none, some, many = 200 }, op: enum(u8) { none, add }, ty: u32, a: u32 = 0, b: u32 = 0, c: u32 = 0 };
const Reordered = struct { small: u8, wide: u64, mid: u16, flag: bool, empty: void = {}, ratio: f32 };

test "byte fast paths reproduce the field-by-field stream exactly" {
    comptime std.debug.assert(memoryStream(Plain) and !memoryStream(Padded) and !memoryStream(Reordered));
    comptime std.debug.assert(fixedStream(Padded).? == 18 and fixedStream(Reordered).? == 16);
    const per_chunk = max_fixed_chunk / 18;
    var items: [3 * per_chunk + 7]Padded = undefined;
    for (&items, 0..) |*item, index| item.* = .{ .tag = if (index % 3 == 0) .many else .some, .op = if (index % 2 == 0) .add else .none, .ty = @intCast(index), .a = @intCast(index * 7), .c = 0xdead0000 + @as(u32, @intCast(index)) };
    for ([_]usize{ 0, 1, per_chunk - 1, per_chunk, per_chunk + 1, items.len }) |len| try expectSameStream(@as([]const Padded, items[0..len]));
    try expectSameStream(items);
    try expectSameStream(items[5]);
    try expectSameStream(Reordered{ .small = 9, .wide = 0x0102030405060708, .mid = 0xbeef, .flag = true, .ratio = -0.0 });
    try expectSameStream([_]Reordered{ .{ .small = 1, .wide = 2, .mid = 3, .flag = false, .ratio = 1.5 }, .{ .small = 4, .wide = 5, .mid = 6, .flag = true, .ratio = std.math.nan(f32) } });
    try expectSameStream(@as([]const Plain, &.{ .{ .a = 1, .b = 2 }, .{ .a = 0xffffffff, .b = 0 } }));
    try expectSameStream([_]u16{ 1, 2, 65535, 0, 7 });
    try expectSameStream(.{ .name = @as([]const u8, "core"), .items = @as([]const Padded, items[0..40]), .plain = @as([4]Plain, @splat(.{ .a = 3, .b = 4 })), .missing = @as(?u32, null), .present = @as(?Padded, items[2]), .floats = @as([]const f64, &.{ 0.5, -0.0 }) });
    try expectSameStream(.{ .nothing = {}, .empty = @as([]const void, &.{ {}, {} }), .after = @as(u32, 5) });
}

test "byte equality agrees with field equality" {
    comptime std.debug.assert(plainBytes(Plain) and plainBytes([4]Plain) and !plainBytes(Padded) and !plainBytes(Reordered));
    const left = [_]Plain{ .{ .a = 1, .b = 2 }, .{ .a = 3, .b = 4 } };
    var right = left;
    try std.testing.expect(equal(@as([]const Plain, &left), &right));
    try std.testing.expect(equal(left, right));
    right[1].b = 5;
    try std.testing.expect(!equal(@as([]const Plain, &left), &right));
    try std.testing.expect(!equal(left, right));
    try std.testing.expect(!equal(left[0], right[1]));
    try std.testing.expect(!equal(@as([]const Plain, &left), left[0..1]));
    const padded: Padded = .{ .tag = .some, .op = .add, .ty = 3 };
    var other = padded;
    try std.testing.expect(equal(padded, other));
    other.op = .none;
    try std.testing.expect(!equal(padded, other));
    try std.testing.expect(equal(@as(f32, 0.0), @as(f32, -0.0)));
}
