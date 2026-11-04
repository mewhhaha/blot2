//! Native layout pilot, not production Blot code generation or a wire ABI.
//! Run with Zig 0.17: zig test -fno-llvm -Osafe <this file>, or build-exe -Ofast.
const std = @import("std");
const Error = error{ Capacity, Frozen, InvalidImage, Overflow };
const Point = struct { x: u32, y: f32 };
const Samples = struct { channel: u32, words: []const u32 };
const Element = union(enum) { empty, point: Point, samples: Samples };
const Tail = struct { channel: u32, count: u32, bytes: []const u8 };
const Decoded = union(enum) { empty, point: Point, samples: Tail };

fn word(bytes: []const u8, offset: usize) u32 {
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}
fn put(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}
fn extent(bytes: []const u8, position: usize, length: usize) Error!usize {
    if (position > bytes.len or length > bytes.len - position) return error.InvalidImage;
    return position + length;
}
const Cursor = struct {
    bytes: []const u8,
    position: usize = 0,
    remaining: u32,

    fn next(self: *Cursor) Error!?Decoded {
        if (self.remaining == 0) {
            if (self.position != self.bytes.len) return error.InvalidImage;
            return null;
        }
        var at = try extent(self.bytes, self.position, 1);
        const tag = self.bytes[self.position];
        const value: Decoded = switch (tag) {
            0 => .empty,
            1 => point: {
                const end = try extent(self.bytes, at, 8);
                const result: Point = .{ .x = word(self.bytes, at), .y = @bitCast(word(self.bytes, at + 4)) };
                at = end;
                break :point .{ .point = result };
            },
            2 => samples: {
                _ = try extent(self.bytes, at, 12);
                const channel = word(self.bytes, at);
                const count = word(self.bytes, at + 4);
                const length = word(self.bytes, at + 8);
                const expected = std.math.mul(u32, count, 4) catch return error.InvalidImage;
                if (length != expected) return error.InvalidImage;
                at += 12;
                const end = try extent(self.bytes, at, length);
                const result: Tail = .{ .channel = channel, .count = count, .bytes = self.bytes[at..end] };
                at = end;
                break :samples .{ .samples = result };
            },
            else => return error.InvalidImage,
        };
        self.position = at;
        self.remaining -= 1;
        return value;
    }
};
const Sequence = struct {
    bytes: []const u8,
    count: u32,
    fn cursor(self: Sequence) Cursor {
        return .{ .bytes = self.bytes, .remaining = self.count };
    }
};
const Builder = struct {
    storage: []u8,
    used: usize = 0,
    count: u32 = 0,
    frozen: bool = false,

    fn room(self: *Builder, bytes: usize, elements: u32) Error!void {
        if (self.frozen) return error.Frozen;
        if (bytes > self.storage.len - self.used) return error.Capacity;
        _ = try std.math.add(u32, self.count, elements);
    }
    fn append(self: *Builder, value: Element) Error!void {
        var length: usize = 1;
        switch (value) {
            .empty => {},
            .point => length = 9,
            .samples => |tail| {
                if (tail.words.len > std.math.maxInt(u32) / 4) return error.Overflow;
                length = try std.math.add(usize, 13, try std.math.mul(usize, tail.words.len, 4));
            },
        }
        try self.room(length, 1);
        const out = self.storage[self.used..][0..length];
        switch (value) {
            .empty => out[0] = 0,
            .point => |point| {
                out[0] = 1;
                put(out, 1, point.x);
                put(out, 5, @bitCast(point.y));
            },
            .samples => |tail| {
                out[0] = 2;
                put(out, 1, tail.channel);
                put(out, 5, @intCast(tail.words.len));
                put(out, 9, @intCast(tail.words.len * 4));
                for (tail.words, 0..) |value_, index| put(out, 13 + index * 4, value_);
            },
        }
        self.used += length;
        self.count += 1;
    }
    fn extend(self: *Builder, source: Sequence) Error!void {
        try self.room(source.bytes.len, source.count);
        var check = source.cursor();
        while (try check.next()) |_| {}
        const out = self.storage[self.used..][0..source.bytes.len];
        // The real owner checker must forbid overlapping live builder storage.
        @memcpy(out, source.bytes);
        self.used += source.bytes.len;
        self.count += source.count;
    }
    fn freeze(self: *Builder) Sequence {
        self.frozen = true;
        return .{ .bytes = self.storage[0..self.used], .count = self.count };
    }
};

test "active alternatives preserve exact F32 bits and independent cursors" {
    var storage: [64]u8 = undefined;
    var builder: Builder = .{ .storage = &storage };
    try builder.append(.empty);
    try builder.append(.{ .point = .{ .x = 42, .y = @bitCast(@as(u32, 0x80000000)) } });
    try builder.append(.{ .point = .{ .x = 7, .y = @bitCast(@as(u32, 0x7fc01234)) } });
    const sequence = builder.freeze();
    try std.testing.expectEqual(@as(usize, 19), sequence.bytes.len);
    var cursor = sequence.cursor();
    _ = try cursor.next();
    var independent = cursor;
    const point = (try cursor.next()).?.point;
    try std.testing.expectEqual(@as(u32, 42), point.x);
    try std.testing.expectEqual(@as(u32, 0x80000000), @as(u32, @bitCast(point.y)));
    try std.testing.expectEqual(@as(u32, 42), (try independent.next()).?.point.x);
    try std.testing.expectEqual(@as(u32, 0x7fc01234), @as(u32, @bitCast((try cursor.next()).?.point.y)));
    try std.testing.expect(try cursor.next() == null);
}
test "runtime-sized scalar tails copy bytes and retain a compact borrowed view" {
    var storage: [64]u8 = undefined;
    var words = [_]u32{ 10, 20, 30 };
    var builder: Builder = .{ .storage = &storage };
    try builder.append(.{ .samples = .{ .channel = 9, .words = &words } });
    words[0] = 99;
    const sequence = builder.freeze();
    try std.testing.expectEqual(@as(usize, 25), sequence.bytes.len);
    var cursor = sequence.cursor();
    const tail = (try cursor.next()).?.samples;
    try std.testing.expectEqual(@as(u32, 9), tail.channel);
    try std.testing.expectEqual(@as(u32, 3), tail.count);
    try std.testing.expectEqual(@as(u32, 10), word(tail.bytes, 0));
    try std.testing.expectEqual(@as(u32, 30), word(tail.bytes, 8));
    try std.testing.expect(try cursor.next() == null);
}
test "capacity failure preserves the complete prefix and freeze closes the builder" {
    var storage: [9]u8 = undefined;
    var builder: Builder = .{ .storage = &storage };
    try builder.append(.empty);
    try std.testing.expectError(error.Capacity, builder.append(.{ .point = .{ .x = 1, .y = 2 } }));
    try std.testing.expectEqual(@as(usize, 1), builder.used);
    try std.testing.expectEqual(@as(u32, 1), builder.count);
    const sequence = builder.freeze();
    try std.testing.expectEqualSlices(u8, &.{0}, sequence.bytes);
    try std.testing.expectError(error.Frozen, builder.append(.empty));
}
test "concatenation preserves order without changing either frozen input" {
    var left_bytes: [16]u8 = undefined;
    var right_bytes: [16]u8 = undefined;
    var output: [32]u8 = undefined;
    var left: Builder = .{ .storage = &left_bytes };
    var right: Builder = .{ .storage = &right_bytes };
    var joined: Builder = .{ .storage = &output };
    try left.append(.empty);
    try right.append(.{ .point = .{ .x = 42, .y = 1.5 } });
    const first = left.freeze();
    const second = right.freeze();
    try joined.extend(first);
    try joined.extend(second);
    const sequence = joined.freeze();
    try std.testing.expectEqual(@as(usize, 10), sequence.bytes.len);
    try std.testing.expectEqual(@as(u32, 2), sequence.count);
    var cursor = sequence.cursor();
    try std.testing.expect((try cursor.next()).? == .empty);
    try std.testing.expectEqual(@as(u32, 42), (try cursor.next()).?.point.x);
    try std.testing.expect(try cursor.next() == null);
    try std.testing.expectEqual(@as(usize, 1), first.bytes.len);
    try std.testing.expectEqual(@as(usize, 9), second.bytes.len);
}
test "decoding rejects invalid tags truncated extents and inconsistent tail counts" {
    var invalid_tag = (Sequence{ .bytes = &.{9}, .count = 1 }).cursor();
    try std.testing.expectError(error.InvalidImage, invalid_tag.next());
    try std.testing.expectEqual(@as(usize, 0), invalid_tag.position);
    var short = (Sequence{ .bytes = &.{ 1, 0 }, .count = 1 }).cursor();
    try std.testing.expectError(error.InvalidImage, short.next());
    var malformed: [13]u8 = @splat(0);
    malformed[0] = 2;
    put(&malformed, 5, 1);
    var tail = (Sequence{ .bytes = &malformed, .count = 1 }).cursor();
    try std.testing.expectError(error.InvalidImage, tail.next());
    var trailing = (Sequence{ .bytes = &.{0}, .count = 0 }).cursor();
    try std.testing.expectError(error.InvalidImage, trailing.next());
}
pub fn main(init: std.process.Init) !void {
    const count = 100_000;
    const storage = try init.arena.allocator().alloc(u8, count * 9);
    var builder: Builder = .{ .storage = storage };
    for (0..count) |index| {
        if (index % 5 == 0) try builder.append(.{ .point = .{ .x = @intCast(index), .y = 1.5 } }) else try builder.append(.empty);
    }
    const sequence = builder.freeze();
    var cursor = sequence.cursor();
    var decoded: usize = 0;
    var checksum: u64 = 0;
    while (try cursor.next()) |element| {
        decoded += 1;
        if (element == .point) checksum += element.point.x;
    }
    if (decoded != count or checksum != 999_950_000) return error.IncorrectWitness;
    std.debug.print("{{\"elements\":{d},\"packed_bytes\":{d},\"reserved_bytes\":{d},\"modeled_fixed_union_bytes\":{d},\"decoded_elements\":{d},\"checksum\":{d}}}\n", .{ count, sequence.bytes.len, storage.len, count * (4 + 8), decoded, checksum });
}
