// Test-only pointer-independent snapshot for Core immutability assertions.
const std = @import("std");
const structural = @import("structural.zig");
const Hash = std.crypto.hash.Blake3;
pub fn stamp(value: anytype) [32]u8 {
    var hash = Hash.init(.{});
    hash.update("BLOT-PINNED-ARTIFACT-1");
    structural.hash(&hash, value);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
