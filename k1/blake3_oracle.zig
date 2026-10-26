// Test-only oracle. Requires the pinned Zig 0.17.0 standard library, not a
// dependency of the Goose compiler or the generated programs.
const std = @import("std");
var data: [16 * 1024 * 1024]u8 = undefined;
pub fn main() void {
    const sizes = [_]usize{ 0, 1, 3, 31, 63, 64, 65, 67, 127, 255, 511, 777,
        1023, 1024, 1025, 1535, 2047, 2048, 2049, 2053, 3071, 3072, 3073,
        4095, 4097, 4099, 8193, 16383, 25001, 65537, 65539, 100000,
        131071, 1048576, 2097149, 8388611, 16777215, 16777216 };
    for (0..3) |mode| {
        var random: u32 = 0x12345678;
        for (&data, 0..) |*byte, i| {
            if (mode == 2) {
                random = random *% 1664525 +% 1013904223;
                byte.* = @truncate(random >> 24);
            } else byte.* = @intCast(if (mode == 0) i % 251 else (i * 73 + 19) % 251);
        }
        for (sizes) |size| {
            var digest: [32]u8 = undefined;
            std.crypto.hash.Blake3.hash(data[0..size], &digest, .{});
            std.debug.print("{d}:{d}:", .{ mode, size });
            for (digest) |byte| std.debug.print("{x:0>2}", .{byte});
            std.debug.print("\n", .{});
        }
    }
}
