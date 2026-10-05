//! Portable owned dependency payloads. No pointers, padding, allocator state,
//! solver caches or native hash-table layouts enter the file.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Hash = std.crypto.hash.Blake3;
const magic = "BLOTDEP1";
const version: u32 = 1;
const header_size = 212;

pub const Digest = [32]u8;
pub const Key = struct {
    compiler: Digest,
    settings: Digest,
    source: Digest,
    dependencies: Digest,
};
pub const Limits = struct {
    payload_bytes: usize = 64 * 1024 * 1024,
    elements: usize = 4 * 1024 * 1024,
    depth: usize = 64,
};
pub const Error = Allocator.Error || error{ InvalidArtifact, StaleArtifact, UnsupportedVersion, SchemaMismatch, ArtifactLimit };

/// Discover explicitly untrusted provenance keys without allocating or decoding
/// an owner. Only header length, magic and version are checked here. Call decode
/// for schema, payload bounds and integrity; independently recompute all source
/// and dependency keys before publishing a decoded candidate. Returned arrays
/// own their bytes and retain no pointer into the input.
pub fn inspectKey(bytes: []const u8) Error!Key {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..8], magic)) return error.InvalidArtifact;
    if (std.mem.readInt(u32, bytes[8..12], .little) != version) return error.UnsupportedVersion;
    var result: Key = undefined;
    var at: usize = magic.len + @sizeOf(u32) + @sizeOf(Digest);
    inline for (@typeInfo(Key).@"struct".field_names) |name| {
        if (@FieldType(Key, name) != Digest) @compileError("Version-one header keys must remain fixed-size digests");
        @memcpy(&@field(result, name), bytes[at..][0..@sizeOf(Digest)]);
        at += @sizeOf(Digest);
    }
    return result;
}

pub fn digest(bytes: []const u8) Digest {
    var result: Digest = undefined;
    Hash.hash(bytes, &result, .{});
    return result;
}

pub fn encode(allocator: Allocator, key: Key, value: anytype) Error![]u8 {
    return encodeWithLimits(allocator, key, value, .{});
}
pub fn encodeWithLimits(allocator: Allocator, key: Key, value: anytype, limits: Limits) Error![]u8 {
    var body: Encoder = .{ .allocator = allocator, .limits = limits, .remaining = limits.elements };
    defer body.bytes.deinit(allocator);
    try body.value(value, 0);
    var header: Encoder = .{ .allocator = allocator, .limits = .{ .payload_bytes = header_size }, .remaining = 1024 };
    defer header.bytes.deinit(allocator);
    try header.bytes.appendSlice(allocator, magic);
    try header.integer(u32, version);
    try header.value(schema(@TypeOf(value)), 0);
    try header.value(key, 0);
    try header.integer(u64, @intCast(body.bytes.items.len));
    try header.value(digest(body.bytes.items), 0);
    std.debug.assert(header.bytes.items.len == header_size);
    const output = try allocator.alloc(u8, header_size + body.bytes.items.len);
    @memcpy(output[0..header_size], header.bytes.items);
    @memcpy(output[header_size..], body.bytes.items);
    return output;
}

pub fn decode(comptime T: type, allocator: Allocator, bytes: []const u8, expected: Key) Error!T {
    return decodeWithLimits(T, allocator, bytes, expected, .{});
}
pub fn decodeWithLimits(comptime T: type, allocator: Allocator, bytes: []const u8, expected: Key, limits: Limits) Error!T {
    if (bytes.len < header_size or !std.mem.eql(u8, bytes[0..8], magic)) return error.InvalidArtifact;
    var reader: Decoder = .{ .allocator = allocator, .bytes = bytes, .limits = limits, .remaining = limits.elements, .at = 8 };
    if (try reader.integer(u32) != version) return error.UnsupportedVersion;
    const stored_schema = try reader.value(Digest, 0);
    if (!std.mem.eql(u8, &stored_schema, &schema(T))) return error.SchemaMismatch;
    const stored = try reader.value(Key, 0);
    inline for (@typeInfo(Key).@"struct".field_names) |name| {
        if (!std.mem.eql(u8, &@field(stored, name), &@field(expected, name))) return error.StaleArtifact;
    }
    const size = try reader.integer(u64);
    const checksum = try reader.value(Digest, 0);
    if (size > limits.payload_bytes) return error.ArtifactLimit;
    if (size != bytes.len - header_size) return error.InvalidArtifact;
    if (!std.mem.eql(u8, &checksum, &digest(bytes[header_size..]))) return error.InvalidArtifact;
    reader.remaining = limits.elements;
    var result = try reader.value(T, 0);
    errdefer deinit(allocator, &result);
    if (reader.at != bytes.len) return error.InvalidArtifact;
    return result;
}

/// Releases only decoded owners. The encoder always borrows its input.
pub fn deinit(allocator: Allocator, value: anytype) void {
    const T = @TypeOf(value.*);
    switch (@typeInfo(T)) {
        .pointer => |pointer| {
            if (pointer.size != .slice) @compileError("Dependency payload pointers must be owned slices");
            for (value.*) |*item| deinit(allocator, @constCast(item));
            allocator.free(value.*);
        },
        .array => for (value) |*item| deinit(allocator, item),
        .@"struct" => |structure| inline for (structure.field_names) |name| deinit(allocator, &@field(value.*, name)),
        .optional => if (value.*) |*item| deinit(allocator, item),
        .@"union" => |union_| {
            if (union_.tag_type == null) @compileError("Dependency payload unions require a tag");
            switch (value.*) {
                inline else => |*item| deinit(allocator, item),
            }
        },
        .int, .float, .bool, .@"enum", .void => {},
        else => @compileError("Unsupported dependency payload type " ++ @typeName(T)),
    }
}

const Encoder = struct {
    allocator: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    limits: Limits,
    remaining: usize,
    fn integer(self: *Encoder, comptime T: type, number: T) Error!void {
        var data: [@sizeOf(T)]u8 = undefined;
        std.mem.writeInt(T, &data, number, .little);
        try self.append(&data);
    }
    fn append(self: *Encoder, bytes: []const u8) Error!void {
        if (self.bytes.items.len > self.limits.payload_bytes or bytes.len > self.limits.payload_bytes - self.bytes.items.len) return error.ArtifactLimit;
        try self.bytes.appendSlice(self.allocator, bytes);
    }
    fn value(self: *Encoder, item: anytype, depth: usize) Error!void {
        if (depth > self.limits.depth) return error.ArtifactLimit;
        const T = @TypeOf(item);
        if (T == @import("types.zig").Node) {
            // Solver certificates are temporary owned proofs. Persist only
            // semantic type fields, independently of their owned cache state.
            try self.value(item.tag, depth + 1);
            try self.value(item.a, depth + 1);
            try self.value(item.b, depth + 1);
            try self.value(item.c, depth + 1);
            return;
        }
        switch (@typeInfo(T)) {
            .int => {
                if (T == usize) try self.integer(u64, item) else if (T == isize) try self.integer(i64, item) else try self.integer(T, item);
            },
            .float => |number| {
                const Bits = @Int(.unsigned, number.bits);
                try self.integer(Bits, @bitCast(item));
            },
            .bool => try self.integer(u8, @intFromBool(item)),
            .@"enum" => try self.integer(u32, @intCast(@backingInt(item))),
            .void => {},
            .array => for (item) |child| try self.value(child, depth + 1),
            .@"struct" => |structure| inline for (structure.field_names) |name| try self.value(@field(item, name), depth + 1),
            .optional => {
                try self.integer(u8, @intFromBool(item != null));
                if (item) |child| try self.value(child, depth + 1);
            },
            .@"union" => |union_| {
                if (union_.tag_type == null) @compileError("Dependency payload unions require a tag");
                try self.value(std.meta.activeTag(item), depth + 1);
                switch (item) {
                    inline else => |child| try self.value(child, depth + 1),
                }
            },
            .pointer => |pointer| {
                if (pointer.size != .slice or pointer.sentinel_ptr != null) @compileError("Dependency payload pointers must be nonsentinel slices");
                if (item.len > self.remaining or item.len > std.math.maxInt(u32)) return error.ArtifactLimit;
                self.remaining -= item.len;
                try self.integer(u32, @intCast(item.len));
                if (pointer.child == u8) try self.append(item) else for (item) |child| try self.value(child, depth + 1);
            },
            else => @compileError("Unsupported dependency payload type " ++ @typeName(T)),
        }
    }
};

const Decoder = struct {
    allocator: Allocator,
    bytes: []const u8,
    limits: Limits,
    remaining: usize,
    at: usize = 0,
    fn take(self: *Decoder, len: usize) Error![]const u8 {
        if (len > self.bytes.len - self.at) return error.InvalidArtifact;
        const result = self.bytes[self.at..][0..len];
        self.at += len;
        return result;
    }
    fn integer(self: *Decoder, comptime T: type) Error!T {
        const data = try self.take(@sizeOf(T));
        return std.mem.readInt(T, data[0..@sizeOf(T)], .little);
    }
    fn value(self: *Decoder, comptime T: type, depth: usize) Error!T {
        @setEvalBranchQuota(20_000);
        if (depth > self.limits.depth) return error.ArtifactLimit;
        if (T == @import("types.zig").Node) return .{
            .tag = try self.value(@import("types.zig").Tag, depth + 1),
            .a = try self.value(u32, depth + 1),
            .b = try self.value(u32, depth + 1),
            .c = try self.value(u32, depth + 1),
        };
        return switch (@typeInfo(T)) {
            .int => if (T == usize) std.math.cast(usize, try self.integer(u64)) orelse return error.ArtifactLimit else if (T == isize) std.math.cast(isize, try self.integer(i64)) orelse return error.ArtifactLimit else self.integer(T),
            .float => |number| @bitCast(try self.integer(@Int(.unsigned, number.bits))),
            .bool => switch (try self.integer(u8)) {
                0 => false,
                1 => true,
                else => return error.InvalidArtifact,
            },
            .@"enum" => |enumeration| enumeration: {
                const raw = try self.integer(u32);
                inline for (enumeration.field_values) |raw_value| {
                    if (raw == raw_value) break :enumeration @fromBackingInt(@intCast(raw_value));
                }
                return error.InvalidArtifact;
            },
            .void => {},
            .array => |array| array: {
                var result: T = undefined;
                var initialized: usize = 0;
                errdefer for (result[0..initialized]) |*item| deinit(self.allocator, item);
                for (0..array.len) |i| {
                    result[i] = try self.value(array.child, depth + 1);
                    initialized += 1;
                }
                break :array result;
            },
            .@"struct" => |structure| structure: {
                var result: T = undefined;
                var initialized: usize = 0;
                errdefer inline for (structure.field_names, 0..) |name, i| {
                    if (i < initialized) deinit(self.allocator, &@field(result, name));
                };
                inline for (structure.field_names, structure.field_types) |name, Field| {
                    @field(result, name) = try self.value(Field, depth + 1);
                    initialized += 1;
                }
                break :structure result;
            },
            .optional => |optional| switch (try self.integer(u8)) {
                0 => null,
                1 => try self.value(optional.child, depth + 1),
                else => return error.InvalidArtifact,
            },
            .@"union" => |union_| tagged: {
                const Tag = union_.tag_type orelse @compileError("Dependency payload unions require a tag");
                const tag = try self.value(Tag, depth + 1);
                inline for (union_.field_names, union_.field_types) |name, Field| {
                    if (std.mem.eql(u8, @tagName(tag), name)) break :tagged @unionInit(T, name, try self.value(Field, depth + 1));
                }
                return error.InvalidArtifact;
            },
            .pointer => |pointer| slice: {
                if (pointer.size != .slice or pointer.sentinel_ptr != null) @compileError("Dependency payload pointers must be nonsentinel slices");
                const count = try self.integer(u32);
                if (count > self.remaining) return error.ArtifactLimit;
                self.remaining -= count;
                const minimum = comptime minimumSize(pointer.child);
                if (minimum != 0 and count > (self.bytes.len - self.at) / minimum) return error.InvalidArtifact;
                if (pointer.child == u8) break :slice try self.allocator.dupe(u8, try self.take(count));
                const result = try self.allocator.alloc(pointer.child, count);
                var initialized: usize = 0;
                errdefer {
                    for (result[0..initialized]) |*item| deinit(self.allocator, item);
                    self.allocator.free(result);
                }
                for (result) |*item| {
                    item.* = try self.value(pointer.child, depth + 1);
                    initialized += 1;
                }
                break :slice result;
            },
            else => @compileError("Unsupported dependency payload type " ++ @typeName(T)),
        };
    }
};

fn minimumSize(comptime T: type) usize {
    if (T == @import("types.zig").Node) return 4 * @sizeOf(u32);
    return switch (@typeInfo(T)) {
        .int => if (T == usize or T == isize) 8 else @sizeOf(T),
        .float => @sizeOf(T),
        .bool, .optional => 1,
        .@"enum", .pointer, .@"union" => 4,
        .void => 0,
        .array => |array| array.len * minimumSize(array.child),
        .@"struct" => |structure| size: {
            var size: usize = 0;
            for (structure.field_types) |Field| size += minimumSize(Field);
            break :size size;
        },
        else => @compileError("Unsupported dependency payload type " ++ @typeName(T)),
    };
}

fn schema(comptime T: type) Digest {
    var hasher = Hash.init(.{});
    describe(T, &hasher);
    var result: Digest = undefined;
    hasher.final(&result);
    return result;
}
fn describe(comptime T: type, hasher: *Hash) void {
    hasher.update(@typeName(T));
    hasher.update("\x00");
    if (T == @import("types.zig").Node) {
        inline for (.{ "tag", "a", "b", "c" }) |name| {
            hasher.update(name);
            hasher.update("\x00");
            describe(@FieldType(T, name), hasher);
        }
        return;
    }
    switch (@typeInfo(T)) {
        .@"struct" => |structure| inline for (structure.field_names, structure.field_types) |name, Field| {
            hasher.update(name);
            hasher.update("\x00");
            describe(Field, hasher);
        },
        .@"enum" => |enumeration| inline for (enumeration.field_names, enumeration.field_values) |name, value| {
            hasher.update(name);
            var bytes: [8]u8 = undefined;
            std.mem.writeInt(u64, &bytes, value, .little);
            hasher.update(&bytes);
        },
        .@"union" => |union_| {
            describe(union_.tag_type orelse @compileError("Dependency payload unions require a tag"), hasher);
            inline for (union_.field_names, union_.field_types) |name, Field| {
                hasher.update(name);
                hasher.update("\x00");
                describe(Field, hasher);
            }
        },
        .pointer => |pointer| describe(pointer.child, hasher),
        .array => |array| describe(array.child, hasher),
        .optional => |optional| describe(optional.child, hasher),
        .int, .float, .bool, .void => {},
        else => @compileError("Unsupported dependency payload type " ++ @typeName(T)),
    }
}
