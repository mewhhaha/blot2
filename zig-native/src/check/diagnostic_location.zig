//! Public source coordinates borrow filenames only for serialization.
const core = @import("core.zig");
const std = @import("std");
const staging = @import("staging_origins.zig");
pub const Location = struct {
    filename: []const u8,
    start: u32,
    end: u32,
    offset_encoding: []const u8 = "utf8_bytes",
    pub fn init(filename: []const u8, span: core.Span) Location {
        return .{ .filename = filename, .start = span.start, .end = span.end };
    }
};

pub const Origin = struct {
    kind: staging.Kind,
    filename: []const u8,
    start: u32,
    end: u32,
    offset_encoding: []const u8 = "utf8_bytes",

    pub fn init(kind: staging.Kind, filename: []const u8, span: core.Span) Origin {
        return .{ .kind = kind, .filename = filename, .start = span.start, .end = span.end };
    }
};

pub const OwnedOrigins = struct {
    entries: []Origin = &.{},

    pub fn init(allocator: std.mem.Allocator, trace: *const staging.Trace, paths: []const []const u8) (std.mem.Allocator.Error || error{InvalidUnit})!OwnedOrigins {
        const entries = try allocator.alloc(Origin, trace.len);
        errdefer allocator.free(entries);
        var copied: usize = 0;
        errdefer for (entries[0..copied]) |entry| allocator.free(entry.filename);
        for (trace.items(), entries) |origin, *entry| {
            const unit = origin.location.unit;
            if (unit == 0 or unit > paths.len) return error.InvalidUnit;
            const filename = try allocator.dupe(u8, paths[unit - 1]);
            entry.* = Origin.init(origin.kind, filename, origin.location.span);
            copied += 1;
        }
        return .{ .entries = entries };
    }

    pub fn deinit(self: *OwnedOrigins, allocator: std.mem.Allocator) void {
        for (self.entries) |entry| allocator.free(entry.filename);
        allocator.free(self.entries);
        self.* = .{};
    }
};

pub fn WithOrigins(comptime Payload: type) type {
    return struct {
        payload: Payload,
        origins: []const Origin,

        pub fn jsonStringify(self: @This(), stream: *std.json.Stringify) std.Io.Writer.Error!void {
            try stream.beginObject();
            inline for (@typeInfo(Payload).@"struct".field_names) |name| {
                try stream.objectField(name);
                try stream.write(@field(self.payload, name));
            }
            if (self.origins.len != 0) {
                try stream.objectField("origins");
                try stream.write(self.origins);
            }
            try stream.endObject();
        }
    };
}
