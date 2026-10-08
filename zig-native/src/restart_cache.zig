//! Best-effort storage for validated backend checkpoint candidates. Files never
//! replace source checking, and an incomplete write never replaces a checkpoint.
const std = @import("std");
const builtin = @import("builtin");
const checkpoint = @import("backend_checkpoint.zig");
const A = std.mem.Allocator;
const Io = std.Io;
pub const maximum_bytes = 64 * 1024 * 1024;

/// The explicit override is the complete cache root; an empty value disables
/// persistence. Relative or missing platform directories are unavailable.
pub fn root(a: A, env: *const std.process.Environ.Map) A.Error!?[]u8 {
    if (env.get("BLOT_CACHE_DIR")) |value| return absolute(a, value);
    if (builtin.os.tag == .windows) {
        const base = env.get("LOCALAPPDATA") orelse return null;
        return beneath(a, base, "Blot");
    }
    if (env.get("XDG_CACHE_HOME")) |base| if (std.Io.Dir.path.isAbsolute(base)) return beneath(a, base, "blot");
    const home = env.get("HOME") orelse return null;
    return beneath(a, home, if (builtin.os.tag == .macos) "Library/Caches/blot" else ".cache/blot");
}

fn absolute(a: A, path: []const u8) A.Error!?[]u8 {
    if (!Io.Dir.path.isAbsolute(path) or std.mem.findScalar(u8, path, 0) != null) return null;
    return try a.dupe(u8, path);
}
fn beneath(a: A, base: []const u8, suffix: []const u8) A.Error!?[]u8 {
    if (!Io.Dir.path.isAbsolute(base)) return null;
    return try Io.Dir.path.join(a, &.{ base, suffix });
}

pub const File = struct {
    allocator: A,
    compiler: [32]u8,
    directory: []u8,
    path: []u8,

    pub fn init(a: A, directory: []const u8, compiler: [32]u8, entry: []const u8) A.Error!File {
        const version = std.fmt.bytesToHex(compiler, .lower);
        const digest = std.fmt.bytesToHex(@import("dependency_format.zig").digest(entry), .lower);
        const folder = try Io.Dir.path.join(a, &.{ directory, "v1", &version });
        errdefer a.free(folder);
        const filename = try a.print("{s}.blotcache", .{digest});
        defer a.free(filename);
        return .{ .allocator = a, .compiler = compiler, .directory = folder, .path = try Io.Dir.path.join(a, &.{ folder, filename }) };
    }
    pub fn deinit(self: *File) void {
        self.allocator.free(self.directory);
        self.allocator.free(self.path);
        self.* = undefined;
    }
    pub fn load(self: *const File, io: Io) ?checkpoint.Checkpoint {
        const bytes = Io.Dir.cwd().readFileAlloc(io, self.path, self.allocator, .limited(maximum_bytes)) catch return null;
        defer self.allocator.free(bytes);
        return checkpoint.decode(self.allocator, self.compiler, bytes) catch null;
    }
    pub fn save(self: *const File, io: Io, bytes: []const u8) bool {
        if (bytes.len == 0 or bytes.len > maximum_bytes) return false;
        Io.Dir.cwd().createDirPath(io, self.directory) catch return false;
        @import("dependency_cli.zig").publish(io, self.path, bytes) catch return false;
        return true;
    }
    pub fn capture(self: *const File, io: Io, artifacts: *const @import("artifact_capture.zig").Capture) bool {
        const bytes = checkpoint.encode(self.allocator, self.compiler, artifacts) catch return false;
        defer self.allocator.free(bytes);
        return self.save(io, bytes);
    }
};

test "restart cache roots require absolute platform paths and honor disabling" {
    const a = std.testing.allocator;
    var env = std.process.Environ.Map.init(a);
    defer env.deinit();
    try std.testing.expectEqual(@as(?[]u8, null), try root(a, &env));
    try env.put("BLOT_CACHE_DIR", "relative");
    try std.testing.expectEqual(@as(?[]u8, null), try root(a, &env));
    try env.put("BLOT_CACHE_DIR", "");
    try env.put("HOME", "/fallback");
    try std.testing.expectEqual(@as(?[]u8, null), try root(a, &env));
    try env.put("BLOT_CACHE_DIR", "/explicit");
    const chosen = (try root(a, &env)).?;
    defer a.free(chosen);
    try std.testing.expectEqualStrings("/explicit", chosen);
}

fn keyOwnership(a: A) !void {
    var first = try File.init(a, "/cache", @splat(1), "/project/main.blot");
    defer first.deinit();
    var other_compiler = try File.init(a, "/cache", @splat(2), "/project/main.blot");
    defer other_compiler.deinit();
    var other_entry = try File.init(a, "/cache", @splat(1), "/other/main.blot");
    defer other_entry.deinit();
    try std.testing.expect(!std.mem.eql(u8, first.directory, other_compiler.directory));
    try std.testing.expect(!std.mem.eql(u8, first.path, other_entry.path));
}

test "restart cache keys own compiler and entry separation under allocation failure" {
    try keyOwnership(std.testing.allocator);
    try @import("allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, keyOwnership, .{});
}
