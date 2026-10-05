// Test-only pointer-independent snapshot for Core immutability assertions.
const std = @import("std");
const Hash = std.crypto.hash.Blake3;
pub fn stamp(value: anytype) [32]u8 {
    var hash = Hash.init(.{});
    hash.update("BLOT-PINNED-ARTIFACT-1");
    hashValue(&hash, value);
    var result: [32]u8 = undefined;
    hash.final(&result);
    return result;
}
fn hashValue(hash: *Hash, value: anytype) void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("Artifact stamps cannot contain borrowed pointers");
            hashValue(hash, value.len);
            if (pointer.child == u8) hash.update(value) else for (value) |item| hashValue(hash, item);
        },
        .array => for (value) |item| hashValue(hash, item),
        .@"struct" => |structure| inline for (structure.field_names) |name| hashValue(hash, @field(value, name)),
        .optional => {
            hashValue(hash, value != null);
            if (value) |item| hashValue(hash, item);
        },
        .@"union" => |union_| {
            if (union_.tag_type == null) @compileError("Artifact stamps require tagged unions");
            hashValue(hash, std.meta.activeTag(value));
            switch (value) {
                inline else => |item| hashValue(hash, item),
            }
        },
        .@"enum" => hashValue(hash, @backingInt(value)),
        .int, .float, .bool => hash.update(std.mem.asBytes(&value)),
        .void => {},
        else => @compileError("Unsupported artifact stamp type " ++ @typeName(T)),
    }
}
