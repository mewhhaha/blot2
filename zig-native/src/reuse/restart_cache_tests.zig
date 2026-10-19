//! Laws for restart-cache publication: detached writers, the key lock loaders
//! wait on, killed writers and concurrent loaders.
const std = @import("std");
const builtin = @import("builtin");
const cache = @import("restart_cache.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const linux = std.os.linux;

const Fixture = struct {
    dir: std.testing.TmpDir,
    root: [:0]u8,
    file: cache.File,

    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        const root = try dir.dir.realPathFileAlloc(io, ".", a);
        errdefer a.free(root);
        return .{ .dir = dir, .root = root, .file = try cache.File.init(a, root, @splat(7), "/project/main.blot") };
    }
    fn deinit(self: *Fixture) void {
        self.file.deinit();
        a.free(self.root);
        self.dir.cleanup();
    }
    fn published(self: *const Fixture) ?[]u8 {
        return std.Io.Dir.cwd().readFileAlloc(io, self.file.path, a, .limited(cache.maximum_bytes)) catch null;
    }
    fn exists(path: []const u8) bool {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
        return true;
    }
};

/// A producer whose checkpoint part reports its process ID, then returns
/// `payload` once the test writes a nonzero byte (zero, or a closed pipe, makes
/// it fail). Its output part, when `output` is set, is the checkpoint it
/// received followed by `output`; otherwise it is omitted.
const Gate = struct {
    ready: [2]linux.fd_t,
    release: [2]linux.fd_t,
    payload: []const u8,
    output: ?[]const u8 = null,
    /// Reported as a semantic owner left out for size.
    semantic_over_limit: bool = false,

    fn init(payload: []const u8) !Gate {
        var gate: Gate = .{ .ready = undefined, .release = undefined, .payload = payload };
        if (linux.errno(linux.pipe2(&gate.ready, .{ .CLOEXEC = true })) != .SUCCESS) return error.Pipe;
        if (linux.errno(linux.pipe2(&gate.release, .{ .CLOEXEC = true })) != .SUCCESS) return error.Pipe;
        return gate;
    }
    fn deinit(self: *Gate) void {
        for ([_]linux.fd_t{ self.ready[0], self.ready[1], self.release[0], self.release[1] }) |fd| _ = linux.close(fd);
    }
    fn producer(self: *const Gate) cache.Producer {
        return .{ .context = self, .encode = encode };
    }
    fn encode(context: *const anyopaque, allocator: std.mem.Allocator, part: cache.Part, checkpoint: ?[]const u8, report: *cache.Report) ?[]u8 {
        const self: *const Gate = @ptrCast(@alignCast(context));
        report.semantic_over_limit = report.semantic_over_limit or self.semantic_over_limit;
        if (part == .output) {
            const suffix = self.output orelse return null;
            return std.mem.concat(allocator, u8, &.{ checkpoint orelse "", suffix }) catch null;
        }
        const pid = linux.getpid();
        if (linux.write(self.ready[1], std.mem.asBytes(&pid), @sizeOf(linux.pid_t)) != @sizeOf(linux.pid_t)) return null;
        var byte: [1]u8 = undefined;
        if (linux.read(self.release[0], &byte, 1) != 1 or byte[0] == 0) return null;
        return allocator.dupe(u8, self.payload) catch null;
    }
    /// The writer's process ID, once it is encoding.
    fn writer(self: *const Gate) !linux.pid_t {
        var pid: linux.pid_t = 0;
        if (linux.read(self.ready[0], std.mem.asBytes(&pid), @sizeOf(linux.pid_t)) != @sizeOf(linux.pid_t)) return error.NoWriter;
        return pid;
    }
    fn open(self: *const Gate, value: u8) !void {
        if (linux.write(self.release[1], &[_]u8{value}, 1) != 1) return error.Pipe;
    }
};

var unreported: cache.Report = .{};

fn settled(file: *const cache.File) bool {
    // Generous: a scheduled writer finishes in milliseconds.
    return file.settleWithin(io, 5_000);
}

test "restart cache: a detached writer publishes after persist returns, and loaders wait for it" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var gate = try Gate.init("second");
    defer gate.deinit();
    try std.testing.expect(fixture.file.save(io, "first", &unreported));
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    _ = try gate.writer();
    // The writer holds the lock from before persist returned until it renames.
    try std.testing.expect(!fixture.file.settleWithin(io, 30));
    const before = fixture.published().?;
    defer a.free(before);
    try std.testing.expectEqualStrings("first", before);
    try gate.open(1);
    try std.testing.expect(settled(&fixture.file));
    const after = fixture.published().?;
    defer a.free(after);
    try std.testing.expectEqualStrings("second", after);
    try std.testing.expect(!Fixture.exists(fixture.file.partial_paths[0]));
}

test "restart cache: a killed writer frees the lock and never publishes, so loaders fall back to the last whole file" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try std.testing.expect(fixture.file.save(io, "whole", &unreported));
    // What a writer killed mid-write leaves: a partial file nobody reads.
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = fixture.file.partial_paths[0], .data = "trunc" });
    var gate = try Gate.init("never");
    defer gate.deinit();
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    const pid = try gate.writer();
    try std.testing.expect(!fixture.file.settleWithin(io, 30));
    // The lock file names the writer.
    try std.testing.expectEqual(pid, fixture.file.readReport(io).?.writer);
    if (linux.errno(linux.kill(pid, .KILL)) != .SUCCESS) return error.Kill;
    try std.testing.expect(settled(&fixture.file));
    const kept = fixture.published().?;
    defer a.free(kept);
    try std.testing.expectEqualStrings("whole", kept);
    // The next writer overwrites the dead writer's partial file.
    var next = try Gate.init("replaced");
    defer next.deinit();
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, next.producer()));
    _ = try next.writer();
    try next.open(1);
    try std.testing.expect(settled(&fixture.file));
    const replaced = fixture.published().?;
    defer a.free(replaced);
    try std.testing.expectEqualStrings("replaced", replaced);
    try std.testing.expect(!Fixture.exists(fixture.file.partial_paths[0]));
}

test "restart cache: one writer publishes both parts, and an omitted output removes the published one" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var both = try Gate.init("ck");
    defer both.deinit();
    both.output = "+out";
    try both.open(1);
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, both.producer()));
    _ = try both.writer();
    try std.testing.expect(settled(&fixture.file));
    const output = fixture.file.read(io, .output).?;
    defer a.free(output);
    try std.testing.expectEqualStrings("ck+out", output);
    var alone = try Gate.init("ck2");
    defer alone.deinit();
    try alone.open(1);
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, alone.producer()));
    _ = try alone.writer();
    try std.testing.expect(settled(&fixture.file));
    try std.testing.expect(fixture.file.read(io, .output) == null);
    const checkpoint = fixture.published().?;
    defer a.free(checkpoint);
    try std.testing.expectEqualStrings("ck2", checkpoint);
    for (fixture.file.partial_paths) |partial| try std.testing.expect(!Fixture.exists(partial));
}

test "restart cache: a writer whose encoding fails publishes nothing and releases the lock" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var gate = try Gate.init("unused");
    defer gate.deinit();
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    _ = try gate.writer();
    try gate.open(0);
    try std.testing.expect(settled(&fixture.file));
    try std.testing.expect(fixture.published() == null);
    try std.testing.expect(!Fixture.exists(fixture.file.partial_paths[0]));
    try std.testing.expect(fixture.file.load(io) == null);
}

test "restart cache: a writer that finds the lock taken waits for it before writing" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try std.Io.Dir.cwd().createDirPath(io, fixture.file.directory);
    const holder = try std.Io.Dir.cwd().createFile(io, fixture.file.lock_path, .{ .truncate = false });
    defer holder.close(io);
    try std.testing.expect(try holder.tryLock(io, .exclusive));
    var gate = try Gate.init("late");
    defer gate.deinit();
    try gate.open(1);
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    // Encoding waits for the lock, so the writer has not reported yet.
    try std.testing.expect(!fixture.file.settleWithin(io, 30));
    try std.testing.expect(fixture.published() == null);
    holder.unlock(io);
    _ = try gate.writer();
    try std.testing.expect(settled(&fixture.file));
    const late = fixture.published().?;
    defer a.free(late);
    try std.testing.expectEqualStrings("late", late);
}

test "restart cache: concurrent loaders all wait for a write in flight and read the same file" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var gate = try Gate.init("shared");
    defer gate.deinit();
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    _ = try gate.writer();
    const Loader = struct {
        fn run(file: *const cache.File, out: *?[]u8) void {
            out.* = if (settled(file)) std.Io.Dir.cwd().readFileAlloc(io, file.path, a, .limited(64)) catch null else null;
        }
    };
    var results: [3]?[]u8 = @splat(null);
    var threads: [3]std.Thread = undefined;
    for (&threads, &results) |*thread, *result| thread.* = try std.Thread.spawn(.{}, Loader.run, .{ &fixture.file, result });
    try gate.open(1);
    for (threads) |thread| thread.join();
    for (results) |result| {
        const bytes = result orelse return error.MissingLoad;
        defer a.free(bytes);
        try std.testing.expectEqualStrings("shared", bytes);
    }
}

test "restart cache: synchronous saves publish whole files and decline oversized or empty bytes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try std.testing.expect(!fixture.file.save(io, "", &unreported));
    try std.testing.expect(fixture.published() == null);
    try std.testing.expect(fixture.file.save(io, "one", &unreported));
    try std.testing.expect(fixture.file.save(io, "two", &unreported));
    const bytes = fixture.published().?;
    defer a.free(bytes);
    try std.testing.expectEqualStrings("two", bytes);
    try std.testing.expect(!Fixture.exists(fixture.file.partial_paths[0]));
    // Bytes that do not decode for this compiler never load.
    try std.testing.expect(fixture.file.load(io) == null);
}

test "restart cache: a part over the limit is reported in the lock file and the old file stays" {
    if (!cache.detached_writes) return error.SkipZigTest;
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.file.limit = 4;
    var report: cache.Report = .{};
    try std.testing.expect(fixture.file.save(io, "old", &report));
    var gate = try Gate.init("too large");
    defer gate.deinit();
    gate.semantic_over_limit = true;
    try gate.open(1);
    try std.testing.expectEqual(cache.Persisted.detached, fixture.file.persist(io, gate.producer()));
    const pid = try gate.writer();
    try std.testing.expect(settled(&fixture.file));
    const kept = fixture.published().?;
    defer a.free(kept);
    try std.testing.expectEqualStrings("old", kept);
    const written = fixture.file.readReport(io).?;
    try std.testing.expectEqual(pid, written.writer);
    try std.testing.expectEqual(@as(usize, 9), written.checkpoint_bytes);
    try std.testing.expect(written.over_limit and written.semantic_over_limit);
    try std.testing.expectEqual(@as(usize, 0), written.output_bytes);
}

test "restart cache: a synchronous save over the limit is reported too" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    fixture.file.limit = 4;
    var report: cache.Report = .{};
    try std.testing.expect(!fixture.file.save(io, "too large", &report));
    try std.testing.expect(report.over_limit and report.checkpoint_bytes == 9);
    try std.testing.expect(fixture.published() == null);
    try std.testing.expect(fixture.file.readReport(io).?.over_limit);
    var empty: cache.Report = .{};
    try std.testing.expect(!fixture.file.save(io, null, &empty));
    try std.testing.expect(!fixture.file.readReport(io).?.over_limit);
}
