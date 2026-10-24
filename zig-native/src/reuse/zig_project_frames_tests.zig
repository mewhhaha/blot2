const std = @import("std");
const production = @import("zig_project_frames.zig");
const readRequest = production.readRequest;
const readRequestFrame = production.readRequestFrame;
const checkLengths = production.checkLengths;
const write = production.write;
const max_frame_bytes = production.max_frame_bytes;
const max_metadata_bytes = production.max_metadata_bytes;

test "Zig project framing owns requests and distinguishes boundary EOF from truncation" {
    const a = std.testing.allocator;
    var input = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 0, 0, 0, 0, '{', '}' });
    const bytes = (try readRequest(a, &input)).?;
    defer a.free(bytes);
    try std.testing.expectEqualStrings("{}", bytes);
    try std.testing.expect((try readRequest(a, &input)) == null);
    var header = std.Io.Reader.fixed(&.{ 2, 0, 0 });
    try std.testing.expectError(error.TruncatedFrame, readRequest(a, &header));
    var body = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 0, 0, 0, 0, '{' });
    try std.testing.expectError(error.TruncatedFrame, readRequest(a, &body));
}

test "Zig project frame limits count both payload and header before allocation" {
    try checkLengths(max_metadata_bytes, max_frame_bytes - 8 - max_metadata_bytes);
    try std.testing.expectError(error.FrameTooLarge, checkLengths(max_metadata_bytes, max_frame_bytes - 7 - max_metadata_bytes));
    try std.testing.expectError(error.FrameTooLarge, checkLengths(max_metadata_bytes + 1, 0));
    try std.testing.expectError(error.FrameTooLarge, checkLengths(0, 0));
    var over_header: [8]u8 = @splat(0);
    std.mem.writeInt(u32, over_header[0..4], @intCast(max_metadata_bytes + 1), .little);
    var over = std.Io.Reader.fixed(&over_header);
    try std.testing.expectError(error.FrameTooLarge, readRequest(std.testing.failing_allocator, &over));
    var payload = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 1, 0, 0, 0 });
    try std.testing.expectError(error.RequestPayloadUnsupported, readRequest(std.testing.failing_allocator, &payload));
}

test "Zig project response framing carries literal binary bytes" {
    var buffer: [14]u8 = undefined;
    var output = std.Io.Writer.fixed(&buffer);
    try write(&output, "{}", &.{ 0, 97, 115, 109 });
    try std.testing.expectEqualSlices(u8, &.{ 2, 0, 0, 0, 4, 0, 0, 0, '{', '}', 0, 97, 115, 109 }, output.buffered());
}

fn requestFrameFailure(a: std.mem.Allocator) !void {
    var input = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 4, 0, 0, 0, '{', '}', 0, 97, 115, 109 });
    var frame = (try readRequestFrame(a, &input)).?;
    defer frame.deinit(a);
    try std.testing.expectEqualStrings("{}", frame.metadata());
    try std.testing.expectEqualSlices(u8, &.{ 0, 97, 115, 109 }, frame.payload());
    try std.testing.expect((try readRequestFrame(a, &input)) == null);
}
test "source overlay framing owns metadata and payload and rejects truncated binary data" {
    const a = std.testing.allocator;
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, requestFrameFailure, .{});
    var input = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 4, 0, 0, 0, '{', '}', 0, 97, 115 });
    try std.testing.expectError(error.TruncatedFrame, readRequestFrame(a, &input));
}
