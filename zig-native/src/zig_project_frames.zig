//! A separate byte protocol for the handwritten project-build server.
//! Bounds are checked before allocating or touching compiler revision state.
const std = @import("std");
pub const max_frame_bytes: usize = 64 * 1024 * 1024;
pub const max_metadata_bytes: usize = 1024 * 1024;
pub const max_revision: u64 = (1 << 53) - 1;

pub const RequestFrame = struct {
    bytes: []u8,
    metadata_length: usize,
    pub fn metadata(self: RequestFrame) []const u8 {
        return self.bytes[0..self.metadata_length];
    }
    pub fn payload(self: RequestFrame) []const u8 {
        return self.bytes[self.metadata_length..];
    }
    pub fn deinit(self: *RequestFrame, a: std.mem.Allocator) void {
        a.free(self.bytes);
        self.* = undefined;
    }
};

/// Binary request data is owned independently of the reader. Operation-specific
/// metadata must validate every source range before revision preparation.
pub fn readRequestFrame(a: std.mem.Allocator, reader: *std.Io.Reader) !?RequestFrame {
    var header: [8]u8 = undefined;
    const count = try reader.readSliceShort(&header);
    if (count == 0) return null;
    if (count != header.len) return error.TruncatedFrame;
    const metadata = std.mem.readInt(u32, header[0..4], .little);
    const payload = std.mem.readInt(u32, header[4..8], .little);
    try checkLengths(metadata, payload);
    const length = std.math.add(usize, metadata, payload) catch return error.FrameTooLarge;
    const bytes = try a.alloc(u8, length);
    errdefer a.free(bytes);
    reader.readSliceAll(bytes) catch |err| switch (err) {
        error.EndOfStream => return error.TruncatedFrame,
        else => return err,
    };
    return .{ .bytes = bytes, .metadata_length = metadata };
}

pub fn checkLengths(metadata: usize, payload: usize) !void {
    if (metadata == 0 or metadata > max_metadata_bytes or payload > max_frame_bytes - 8 - metadata) return error.FrameTooLarge;
}

/// EOF is normal only at a frame boundary. Requests have no binary payload.
/// The caller owns the returned JSON bytes, including after reader reuse.
pub fn readRequest(a: std.mem.Allocator, reader: *std.Io.Reader) !?[]u8 {
    var header: [8]u8 = undefined;
    const count = try reader.readSliceShort(&header);
    if (count == 0) return null;
    if (count != header.len) return error.TruncatedFrame;
    const metadata = std.mem.readInt(u32, header[0..4], .little);
    const payload = std.mem.readInt(u32, header[4..8], .little);
    try checkLengths(metadata, payload);
    if (payload != 0) return error.RequestPayloadUnsupported;
    const bytes = try a.alloc(u8, metadata);
    errdefer a.free(bytes);
    reader.readSliceAll(bytes) catch |err| switch (err) {
        error.EndOfStream => return error.TruncatedFrame,
        else => return err,
    };
    return bytes;
}

/// The caller checks/encodes metadata before committing a candidate. Any I/O
/// failure after commit is terminal for the owned process and its session.
pub fn write(writer: *std.Io.Writer, metadata: []const u8, payload: []const u8) !void {
    try checkLengths(metadata.len, payload.len);
    var header: [8]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], @intCast(metadata.len), .little);
    std.mem.writeInt(u32, header[4..8], @intCast(payload.len), .little);
    try writer.writeAll(&header);
    try writer.writeAll(metadata);
    try writer.writeAll(payload);
    try writer.flush();
}

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
    var over = std.Io.Reader.fixed(&.{ 1, 0, 16, 0, 0, 0, 0, 0 });
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, requestFrameFailure, .{});
    var input = std.Io.Reader.fixed(&.{ 2, 0, 0, 0, 4, 0, 0, 0, '{', '}', 0, 97, 115 });
    try std.testing.expectError(error.TruncatedFrame, readRequestFrame(a, &input));
}
