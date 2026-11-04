//! One revision's owned source buffers. Missing entries use the filesystem;
//! null entries hide a file for this revision. Nothing writes to disk.
const std = @import("std");
const project = @import("project.zig");
const Allocator = std.mem.Allocator;
pub const Source = struct { path: []const u8, contents: ?[]const u8 };

/// Canonicalize existing prefixes too, so new virtual files reached through a
/// directory symlink have the same identity as files reached by their real path.
pub fn canonicalPath(a: Allocator, io: std.Io, raw: []const u8) ![]u8 {
    if (!std.Io.Dir.path.isAbsolute(raw) or std.mem.findScalar(u8, raw, 0) != null or !std.unicode.utf8ValidateSlice(raw)) return error.InvalidSourcePath;
    const normalized = try std.Io.Dir.path.resolveAlloc(a, &.{raw});
    defer a.free(normalized);
    var end = normalized.len;
    while (true) {
        const prefix = std.Io.Dir.cwd().realPathFileAlloc(io, normalized[0..end], a) catch |err| {
            if (err != error.FileNotFound) return err;
            const parent = std.Io.Dir.path.dirname(normalized[0..end]) orelse return err;
            if (parent.len == end) return err;
            end = parent.len;
            continue;
        };
        defer a.free(prefix);
        var suffix = normalized[end..];
        while (suffix.len > 0 and std.Io.Dir.path.isSep(suffix[0])) suffix = suffix[1..];
        return std.Io.Dir.path.resolveAlloc(a, &.{ prefix, suffix });
    }
}

pub const Set = struct {
    allocator: Allocator,
    files: std.StringHashMapUnmanaged(?[]u8) = .empty,

    pub fn init(a: Allocator, io: std.Io, sources: []const Source, options: project.Options) !Set {
        var self: Set = .{ .allocator = a };
        errdefer self.deinit();
        if (sources.len > options.max_files) return error.SourceLimit;
        var total: usize = 0;
        for (sources) |source| {
            if (source.contents) |bytes| {
                if (bytes.len > options.max_source_bytes or bytes.len > options.max_total_source_bytes -| total) return error.SourceLimit;
                total += bytes.len;
            }
            const name = try canonicalPath(a, io, source.path);
            var transferred = false;
            defer if (!transferred) a.free(name);
            const entry = try self.files.getOrPut(a, name);
            if (entry.found_existing) return error.DuplicateSourcePath;
            entry.value_ptr.* = null;
            transferred = true;
            if (source.contents) |bytes| entry.value_ptr.* = try a.dupe(u8, bytes);
        }
        return self;
    }
    pub fn deinit(self: *Set) void {
        var it = self.files.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.*) |bytes| self.allocator.free(bytes);
        }
        self.files.deinit(self.allocator);
        self.* = undefined;
    }
};
