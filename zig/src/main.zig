//! Framed native compiler protocol. Stdout contains protocol bytes only.
const std = @import("std");
const builtin = @import("builtin");
const r = @import("runtime.zig");
const core = @import("generated/functions.zig");
const max_words: u32 = 16 * 1024 * 1024;
const magic: u32 = 0x424c4f54;
const version = @import("generated/protocol.zig").version;
const Failure = error{ ReadFailed, WriteFailed, TruncatedFrame, FrameTooLarge, InvalidPacket, InvalidArgument };

fn readExact(bytes: []u8, allow_eof: bool) Failure!bool {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = std.c.read(0, bytes[offset..].ptr, bytes.len - offset);
        if (count < 0) {
            if (std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
            return error.ReadFailed;
        }
        if (count == 0) {
            if (allow_eof and offset == 0) return false;
            return error.TruncatedFrame;
        }
        offset += @intCast(count);
    }
    return true;
}
fn writeExact(bytes: []const u8) Failure!void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const count = std.c.write(1, bytes[offset..].ptr, bytes.len - offset);
        if (count < 0 and std.c._errno().* == @intFromEnum(std.c.E.INTR)) continue;
        if (count <= 0) return error.WriteFailed;
        offset += @intCast(count);
    }
}
fn readFrame(ctx: *r.Context) !?r.Value {
    var prefix: [4]u8 = undefined;
    if (!try readExact(&prefix, true)) return null;
    const count = std.mem.readInt(u32, &prefix, .little);
    if (count > max_words) return error.FrameTooLarge;
    const byte_count = std.math.mul(usize, count, 4) catch return error.FrameTooLarge;
    const bytes = try ctx.allocator().alloc(u8, byte_count);
    _ = try readExact(bytes, false);
    const words = try ctx.allocator().alloc(u32, count);
    for (words, 0..) |*word, i| word.* = std.mem.readInt(u32, bytes[i * 4 ..][0..4], .little);
    return ctx.node(.native_io_Frame, &.{ ctx.arrayWords(words), r.word(count) });
}
fn packetBytes(ctx: *r.Context, packet: r.Value) ![]const u8 {
    if (r.tag(packet) != .native_output_Packet) return error.InvalidPacket;
    const count = r.toWord(r.field(packet, 0));
    if (count > max_words) return error.FrameTooLarge;
    const payload_size = std.math.mul(usize, count, 4) catch return error.FrameTooLarge;
    const frame_size = std.math.add(usize, payload_size, 4) catch return error.FrameTooLarge;
    const bytes = try ctx.allocator().alloc(u8, frame_size);
    @memset(bytes, 0);
    std.mem.writeInt(u32, bytes[0..4], count, .little);
    var offset: usize = 4;
    var header = r.field(packet, 1);
    while (r.tag(header) == .Cons) : (header = r.field(header, 1)) {
        if (bytes.len - offset < 4) return error.InvalidPacket;
        std.mem.writeInt(u32, bytes[offset..][0..4], r.toWord(r.field(header, 0)), .little);
        offset += 4;
    }
    if (r.tag(header) != .Nil) return error.InvalidPacket;
    var blocks = r.field(packet, 2);
    while (r.tag(blocks) == .Cons) : (blocks = r.field(blocks, 1)) {
        const block = r.field(blocks, 0);
        if (r.tag(block) != .native_output_Block) return error.InvalidPacket;
        var remaining = r.toNat(r.field(block, 0));
        var words = r.field(block, 1);
        if (remaining > bytes.len - offset) return error.InvalidPacket;
        while (r.tag(words) == .Cons) : (words = r.field(words, 1)) {
            if (remaining == 0) return error.InvalidPacket;
            var value = r.toWord(r.field(words, 0));
            const n = @min(remaining, 4);
            var i: u64 = 0;
            while (i < n) : (i += 1) {
                bytes[offset] = @truncate(value);
                offset += 1;
                value >>= 8;
            }
            if (value != 0) return error.InvalidPacket;
            remaining -= n;
        }
        if (remaining != 0 or r.tag(words) != .Nil) return error.InvalidPacket;
    }
    if (r.tag(blocks) != .Nil or bytes.len - offset >= 4) return error.InvalidPacket;
    return bytes;
}

fn restorePriority() void {
    if (builtin.os.tag != .linux) return;
    const linux = std.os.linux;
    const raw = linux.sched_getscheduler(0);
    if (raw >= @as(usize, @bitCast(@as(isize, -4095)))) return;
    const policy = raw & ~@as(usize, 0x40000000);
    // Linux getpriority's raw result is 20 minus the nice level.
    const niceness = linux.syscall2(.getpriority, 0, 0);
    const cpu = policy == 5 or ((policy == 0 or policy == 3) and niceness < @as(usize, @bitCast(@as(isize, -4095))) and niceness < 20);
    const io = linux.syscall2(.ioprio_get, 1, 0);
    const idle_io = io < @as(usize, @bitCast(@as(isize, -4095))) and io >> 13 == 3;
    if (cpu) {
        var parameter: i32 = 0;
        _ = linux.syscall3(.sched_setscheduler, 0, 0, @intFromPtr(&parameter));
        _ = linux.syscall3(.setpriority, 0, 0, 0);
    }
    if (cpu or idle_io) _ = linux.syscall3(.ioprio_set, 1, 0, (2 << 13) | 4);
}
fn serve(init: std.process.Init.Minimal) !void {
    var args = init.args.iterate();
    _ = args.next();
    var inherit = false;
    var thread_count: usize = 1;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--inherit-priority")) {
            inherit = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--threads")) {
            const value = args.next() orelse return error.InvalidArgument;
            const threads = std.fmt.parseInt(u8, value, 10) catch return error.InvalidArgument;
            if (threads == 0 or threads > 64) return error.InvalidArgument;
            thread_count = threads;
            continue;
        }
        if (std.mem.eql(u8, arg, "--version")) {
            try writeExact(std.fmt.comptimePrint("blotc-zig 0.1.0 (protocol {d})\n", .{version}));
            return;
        }
        return error.InvalidArgument;
    }
    if (!inherit) restorePriority();
    // Spawn after adjusting priorities; workers inherit the selected policy.
    var pool: r.Context.Pool = .{};
    try pool.start(thread_count);
    defer pool.deinit();
    var hello: [12]u8 = undefined;
    std.mem.writeInt(u32, hello[0..4], 2, .little);
    std.mem.writeInt(u32, hello[4..8], magic, .little);
    std.mem.writeInt(u32, hello[8..12], version, .little);
    try writeExact(&hello);
    var retained = r.Context.init(std.heap.page_allocator);
    defer retained.deinit();
    var state = r.empty(.None);
    while (true) {
        var request = r.Context.init(std.heap.page_allocator);
        request.pool = &pool;
        defer request.deinit();
        const frame = (try readFrame(&request)) orelse break;
        const parsed = request.call(core.native_request_decode, &.{frame});
        const reply = request.call(core.native_main_respond, &.{ state, parsed });
        try writeExact(try packetBytes(&request, r.field(reply, 1)));
        var next = r.Context.init(std.heap.page_allocator);
        state = next.retain(r.field(reply, 0));
        retained.deinit();
        retained = next;
    }
}
pub fn main(init: std.process.Init.Minimal) void {
    serve(init) catch |err| {
        switch (err) {
            error.TruncatedFrame => std.debug.print("native protocol: truncated frame\n", .{}),
            error.FrameTooLarge => std.debug.print("native protocol: frame exceeds {d} words\n", .{max_words}),
            else => std.debug.print("blotc-zig: {s}\n", .{@errorName(err)}),
        }
        std.process.exit(1);
    };
}
test "blocks concatenate their exact byte lengths, not intermediate padding" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const x = ctx.node(.native_output_Block, &.{ r.nat(1), ctx.node(.Cons, &.{ r.word(0xaa), r.empty(.Nil) }) });
    const y = ctx.node(.native_output_Block, &.{ r.nat(2), ctx.node(.Cons, &.{ r.word(0xccbb), r.empty(.Nil) }) });
    const blocks = ctx.node(.Cons, &.{ x, ctx.node(.Cons, &.{ y, r.empty(.Nil) }) });
    const packet = ctx.node(.native_output_Packet, &.{ r.word(1), r.empty(.Nil), blocks });
    try std.testing.expectEqualSlices(u8, &.{ 1, 0, 0, 0, 0xaa, 0xbb, 0xcc, 0 }, try packetBytes(&ctx, packet));
}
test "malformed complete input returns a compiler diagnostic" {
    var ctx = r.Context.init(std.testing.allocator);
    defer ctx.deinit();
    const frame = ctx.node(.native_io_Frame, &.{ ctx.arrayWords(&.{}), r.word(0) });
    const parsed = ctx.call(core.native_request_decode, &.{frame});
    try std.testing.expectEqual(r.Tag.Fail, r.tag(parsed));
    const reply = ctx.call(core.native_main_respond, &.{ r.empty(.None), parsed });
    try std.testing.expectEqual(r.Tag.native_main_Reply, r.tag(reply));
    _ = try packetBytes(&ctx, r.field(reply, 1));
}
