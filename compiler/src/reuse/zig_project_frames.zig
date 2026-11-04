//! A separate byte protocol for the handwritten project-build server.
//! Bounds are checked before allocating or touching compiler revision state.
const std = @import("std");
pub const max_frame_bytes: usize = 64 * 1024 * 1024;
pub const max_metadata_bytes: usize = 16 * 1024 * 1024;
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
    return writeParts(writer, metadata, &.{payload});
}

/// Borrow independently owned payload segments through the final flush. The
/// wire format is unchanged, and every size is checked before writing a byte.
pub fn writeParts(writer: *std.Io.Writer, metadata: []const u8, parts: []const []const u8) !void {
    var payload: usize = 0;
    for (parts) |part| payload = std.math.add(usize, payload, part.len) catch return error.FrameTooLarge;
    try checkLengths(metadata.len, payload);
    var header: [8]u8 = undefined;
    std.mem.writeInt(u32, header[0..4], @intCast(metadata.len), .little);
    std.mem.writeInt(u32, header[4..8], @intCast(payload), .little);
    try writer.writeAll(&header);
    try writer.writeAll(metadata);
    for (parts) |part| try writer.writeAll(part);
    try writer.flush();
}
