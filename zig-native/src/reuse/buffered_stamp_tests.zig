const std = @import("std");
const artifacts = @import("code_artifacts.zig");
fn same(value: anytype) !void {
    const before = artifacts.stampReference(value);
    const after = artifacts.stampBuffered(value);
    try std.testing.expectEqualSlices(u8, &before, &after);
}
const Tag = enum(u16) { empty = 7, scalar = 190, nested = 9000 };
const Choice = union(Tag) { empty: void, scalar: u64, nested: struct { maybe: ?f32, values: []const u16 } };
test "buffered structural stamp preserves diverse primitive bits nested tagged optional and ordered slice streams" {
    const words: [4]u16 = .{ 0, 1, 65535, 1000 };
    for ([_]bool{ false, true }) |value| try same(value);
    try same(@as(u8, 255));
    try same(@as(i16, -32000));
    try same(@as(u128, 0xffffffffffffffffffffffffffffff00));
    for ([_]u32{ 0, 0x80000000, 0x7f800000, 0xff800000, 0x7fc00001, 0x7fa00123 }) |bits| try same(@as(f32, @bitCast(bits)));
    for ([_]u64{ 0, 0x8000000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000042 }) |bits| try same(@as(f64, @bitCast(bits)));
    try same(@as(?u32, null));
    try same(@as(?u32, 42));
    try same(@as(??u16, @as(?u16, null)));
    try same(@as(??u16, @as(?u16, 42)));
    try same(Choice{ .empty = {} });
    try same(Choice{ .scalar = 0xffffffffffffffff });
    try same(Choice{ .nested = .{ .maybe = @bitCast(@as(u32, 0x80000000)), .values = &words } });
    try same(.{ .flag = true, .small = @as(u8, 7), .wide = @as(u64, 99), .choice = Choice{ .nested = .{ .maybe = null, .values = &.{} } }, .slices = @as([]const []const u16, &.{ &words, &.{}, &words }), .array = words });
    try same(@as([]const u8, ""));
    try same(@as([]const u32, &.{}));
    const positive = artifacts.stampBuffered(@as(f32, @bitCast(@as(u32, 0))));
    const negative = artifacts.stampBuffered(@as(f32, @bitCast(@as(u32, 0x80000000))));
    try std.testing.expect(!std.mem.eql(u8, &positive, &negative));
    const left = artifacts.stampBuffered(@as([]const u16, &.{ 1, 2 }));
    const right = artifacts.stampBuffered(@as([]const u16, &.{ 2, 1 }));
    try std.testing.expect(!std.mem.eql(u8, &left, &right));
}
test "buffered structural stamp preserves byte chunks and primitive writes at every flush boundary" {
    var bytes: [20000]u8 = undefined;
    for (&bytes, 0..) |*byte, index| byte.* = @truncate(index *% 97);
    for ([_]usize{ 0, 1, 4066, 4067, 4068, 4095, 4096, 4097, 8191, 8192, 8193, 16383, 16384, 16385, bytes.len }) |len| {
        try same(@as([]const u8, bytes[0..len]));
        try same(.{ @as(u8, 3), @as([]const u8, bytes[0..len]), @as(u128, 0xdeadbeef), @as(?u16, 900) });
        try same(@as([]const []const u8, &.{ bytes[0..len], bytes[len..], &.{}, bytes[0..@min(len, 29)] }));
    }
    // Arrays retain their original per-element stream (no slice length).
    try same(bytes);
    var numbers: [2051]u64 = undefined;
    for (&numbers, 0..) |*word, index| word.* = @as(u64, index) *% 0x0102030405060708;
    try same(numbers);
    try same(@as([]const u64, &numbers));
}
test "buffered structural stamp counters preserve input stream and remove tiny Blake3 update calls without allocations" {
    var words: [8193]u32 = undefined;
    for (&words, 0..) |*word, index| word.* = @intCast(index);
    var original: artifacts.StampCounts = .{};
    var counts: artifacts.StampCounts = .{};
    const reference = (artifacts.Stamping{ .algorithm = .reference, .counts = &original }).stamp(@as([]const u32, &words));
    const buffered = (artifacts.Stamping{ .counts = &counts }).stamp(@as([]const u32, &words));
    try std.testing.expectEqualSlices(u8, &reference, &buffered);
    try std.testing.expectEqual(original.bytes, counts.bytes);
    try std.testing.expectEqual(original.input_updates, counts.input_updates);
    try std.testing.expectEqual(@as(usize, 8195), original.hash_updates);
    try std.testing.expectEqual(@as(usize, 9), counts.hash_updates);
    try std.testing.expectEqual(counts.hash_updates, counts.buffer_flushes);
    try std.testing.expectEqual(@as(usize, 0), counts.direct_chunks);
    const saved = counts;
    try same(@as([]const u32, &words));
    _ = artifacts.stamp(words);
    try std.testing.expectEqual(saved, counts);
}
