//! A native completion peer keeps process startup outside the behavior under
//! test: held replies are released by cancellation, never by a timed sleep.
const std = @import("std");
const A = std.mem.Allocator;
const Io = std.Io;

fn frame(a: A, io: Io, value: anytype) !void {
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    defer a.free(bytes);
    var header: [8]u8 = @splat(0);
    std.mem.writeInt(u32, header[0..4], @intCast(bytes.len), .little);
    try Io.File.stdout().writeStreamingAll(io, &header);
    try Io.File.stdout().writeStreamingAll(io, bytes);
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 4) return error.InvalidArguments;
    const mode = args[1];
    const restart = std.mem.eql(u8, mode, "completion-restart");
    if (!restart and !std.mem.eql(u8, mode, "completion-hold") and !std.mem.eql(u8, mode, "completion-stall")) return error.InvalidMode;
    var first = false;
    if (restart) {
        const path = try std.fmt.allocPrint(a, "{s}.started", .{args[2]});
        if (Io.Dir.cwd().createFile(io, path, .{ .exclusive = true })) |file| {
            file.close(io);
            first = true;
        } else |err| if (err != error.PathAlreadyExists) return err;
    }
    const log = try Io.Dir.cwd().createFile(io, args[2], .{});
    defer log.close(io);
    const pid = if (@import("builtin").os.tag == .windows) std.os.windows.GetCurrentProcessId() else std.c.getpid();
    const started = try std.json.Stringify.valueAlloc(a, .{ .pid = pid, .command = args[3] }, .{});
    try log.writeStreamingAll(io, started);
    try log.writeStreamingAll(io, "\n");
    try frame(a, io, .{
        .kind = "hello",
        .protocol = "blot-zig-project",
        .version = 1,
        .compilerIdentity = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        .capabilities = [_][]const u8{ "project-build", "utf8_bytes", "abort-disposes-process", "source-buffers-v1", "editor-completion-v1" },
        .maxFrameBytes = 67108864,
    });
    var buffer: [4096]u8 = undefined;
    var input = Io.File.stdin().readerStreaming(io, &buffer);
    while (true) {
        var header: [8]u8 = undefined;
        const count = try input.interface.readSliceShort(&header);
        if (count == 0) return;
        if (count != header.len) return error.TruncatedFrame;
        const length = std.mem.readInt(u32, header[0..4], .little);
        const payload = std.mem.readInt(u32, header[4..8], .little);
        if (length == 0 or length > 1048576 or payload > 67108864 - 8 - length) return error.InvalidFrame;
        const bytes = try a.alloc(u8, length + payload);
        defer a.free(bytes);
        try input.interface.readSliceAll(bytes);
        var parsed = try std.json.parseFromSlice(std.json.Value, a, bytes[0..length], .{});
        defer parsed.deinit();
        try log.writeStreamingAll(io, bytes[0..length]);
        try log.writeStreamingAll(io, "\n");
        const request = parsed.value.object;
        const kind = request.get("kind").?.string;
        const id = request.get("id").?;
        if (std.mem.eql(u8, kind, "open") or std.mem.eql(u8, kind, "close")) {
            try frame(a, io, .{ .kind = kind, .id = id, .epoch = "epoch", .revision = 0 });
            if (std.mem.eql(u8, kind, "close")) return;
            continue;
        }
        if (!std.mem.eql(u8, kind, "complete")) return error.InvalidRequest;
        if (!restart or first) while (true) try Io.sleep(io, .fromSeconds(60), .awake);
        const position = request.get("position").?;
        try frame(a, io, .{
            .kind = "complete",
            .id = id,
            .epoch = "epoch",
            .revision = 0,
            .snapshot = request.get("snapshot").?,
            .filename = request.get("filename").?,
            .position = position,
            .success = true,
            .replace = .{ .start = position, .end = position },
            .context = null,
            .items = .{.{ .label = "value", .insertText = "value", .kind = "value", .detail = "U32", .match = "exact" }},
            .truncated = false,
            .diagnostics = [_]std.json.Value{},
        });
    }
}
