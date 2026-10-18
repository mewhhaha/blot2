//! Best-effort storage for validated backend checkpoint candidates. Files never
//! replace source checking, and an incomplete write never replaces a checkpoint.
//!
//! Writers and loaders of one key meet at `<key>.lock` beside its files. A
//! writer holds an exclusive advisory lock while it writes each part to
//! `<part>.partial` and renames it into place; a loader first waits, at most
//! `wait_limit_ms`, for a shared lock, so it never misses a write already in
//! flight. The kernel releases a dead writer's lock, and its partial files are
//! never read and are overwritten by the next writer.
//!
//! On Linux `persist` forks a detached writer (its own session, heap and
//! `/dev/null` stdio) that inherits the exclusive lock taken before the fork,
//! so the caller can reply at once: a host may kill the caller right after the
//! reply and the next process still waits for, then loads, the complete files.
//! Elsewhere `persist` writes synchronously.
const std = @import("std");
const builtin = @import("builtin");
const checkpoint = @import("../backend/backend_checkpoint.zig");
const A = std.mem.Allocator;
const Io = std.Io;
const linux = std.os.linux;
pub const maximum_bytes = 64 * 1024 * 1024;
/// How long a loader, or a writer that found the lock taken, waits for it.
pub const wait_limit_ms = 10_000;
/// Whether `persist` writes from a detached process.
pub const detached_writes = builtin.os.tag == .linux;

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

/// The files one writer publishes for a key, in this order. The checkpoint is
/// the backend checkpoint format the CLI also reads; the output part holds a
/// server revision's output and the inputs it read.
pub const Part = enum { checkpoint, output };
const parts = std.enums.values(Part);

/// Produces each part with the allocator it is given, or null to leave that
/// part out (an omitted output also removes the published one). The output
/// part receives the checkpoint bytes just produced, if any. A detached writer
/// calls it after the fork, on a private heap, over the caller's copy-on-write
/// memory; it must not take locks other threads may hold.
pub const Producer = struct {
    context: *const anyopaque,
    encode: *const fn (context: *const anyopaque, a: A, part: Part, checkpoint: ?[]const u8) ?[]u8,
};

/// How `persist` went: `detached` means a writer holding the lock is running.
pub const Persisted = enum { failed, written, detached };

pub const File = struct {
    allocator: A,
    compiler: [32]u8,
    directory: []u8,
    /// The checkpoint part.
    path: [:0]u8,
    output_path: [:0]u8,
    lock_path: [:0]u8,
    /// `<part>.partial` by part, written only by the exclusive lock's holder.
    partial_paths: [parts.len][:0]u8,

    pub fn init(a: A, directory: []const u8, compiler: [32]u8, entry: []const u8) A.Error!File {
        const version = std.fmt.bytesToHex(compiler, .lower);
        const digest = std.fmt.bytesToHex(@import("dependency_format.zig").digest(entry), .lower);
        const folder = try Io.Dir.path.join(a, &.{ directory, "v1", &version });
        errdefer a.free(folder);
        const path = try a.printSentinel("{s}/{s}.blotcache", .{ folder, digest }, 0);
        errdefer a.free(path);
        const output_path = try a.printSentinel("{s}/{s}.blotout", .{ folder, digest }, 0);
        errdefer a.free(output_path);
        const lock_path = try a.printSentinel("{s}/{s}.lock", .{ folder, digest }, 0);
        errdefer a.free(lock_path);
        const checkpoint_partial = try a.printSentinel("{s}.partial", .{path}, 0);
        errdefer a.free(checkpoint_partial);
        const output_partial = try a.printSentinel("{s}.partial", .{output_path}, 0);
        return .{ .allocator = a, .compiler = compiler, .directory = folder, .path = path, .output_path = output_path, .lock_path = lock_path, .partial_paths = .{ checkpoint_partial, output_partial } };
    }
    pub fn deinit(self: *File) void {
        self.allocator.free(self.directory);
        self.allocator.free(self.path);
        self.allocator.free(self.output_path);
        self.allocator.free(self.lock_path);
        for (self.partial_paths) |partial| self.allocator.free(partial);
        self.* = undefined;
    }
    pub fn final(self: *const File, part: Part) [:0]const u8 {
        return switch (part) {
            .checkpoint => self.path,
            .output => self.output_path,
        };
    }
    /// Waits, at most `wait_limit_ms`, until no writer holds this key's lock.
    /// Returns false on timeout; published files are still whole either way.
    pub fn settle(self: *const File, io: Io) bool {
        return self.settleWithin(io, wait_limit_ms);
    }
    pub fn settleWithin(self: *const File, io: Io, limit_ms: i64) bool {
        const lock = Io.Dir.cwd().openFile(io, self.lock_path, .{}) catch return true;
        defer lock.close(io);
        if (!acquire(io, lock, .shared, limit_ms)) return false;
        lock.unlock(io);
        return true;
    }
    /// Settles, then decodes the checkpoint part.
    pub fn load(self: *const File, io: Io) ?checkpoint.Checkpoint {
        _ = self.settle(io);
        const bytes = self.read(io, .checkpoint) orelse return null;
        defer self.allocator.free(bytes);
        return checkpoint.decode(self.allocator, self.compiler, bytes) catch null;
    }
    /// The published bytes of `part`, without settling.
    pub fn read(self: *const File, io: Io, part: Part) ?[]u8 {
        return Io.Dir.cwd().readFileAlloc(io, self.final(part), self.allocator, .limited(maximum_bytes)) catch null;
    }
    /// Writes the checkpoint part synchronously under the exclusive lock.
    pub fn save(self: *const File, io: Io, bytes: []const u8) bool {
        if (!fits(bytes)) return false;
        const lock = self.openLock(io) orelse return false;
        defer lock.close(io);
        if (!acquire(io, lock, .exclusive, wait_limit_ms)) return false;
        defer lock.unlock(io);
        return self.publish(io, .checkpoint, bytes);
    }
    pub fn capture(self: *const File, io: Io, artifacts: *const @import("artifact_capture.zig").Capture) bool {
        const bytes = checkpoint.encode(self.allocator, self.compiler, artifacts) catch return false;
        defer self.allocator.free(bytes);
        return self.save(io, bytes);
    }
    /// Persists `producer`'s parts. With `detached_writes` this returns once a
    /// detached writer holds the lock (the caller's later mutations cannot
    /// reach its copy); if no writer can be started it writes synchronously.
    pub fn persist(self: *const File, io: Io, producer: Producer) Persisted {
        const lock = self.openLock(io) orelse return .failed;
        defer lock.close(io);
        const held = (lock.tryLock(io, .exclusive) catch false);
        if (detached_writes) {
            if (self.fork(lock.handle, held, producer)) return .detached;
        }
        if (!held and !acquire(io, lock, .exclusive, wait_limit_ms)) return .failed;
        defer lock.unlock(io);
        var written = true;
        var produced: ?[]u8 = null;
        defer if (produced) |bytes| self.allocator.free(bytes);
        for (parts) |part| {
            const bytes = producer.encode(producer.context, self.allocator, part, produced) orelse {
                if (part == .output) Io.Dir.cwd().deleteFile(io, self.output_path) catch {};
                continue;
            };
            defer if (part != .checkpoint) self.allocator.free(bytes);
            if (part == .checkpoint) produced = bytes;
            written = fits(bytes) and self.publish(io, part, bytes) and written;
        }
        return if (written) .written else .failed;
    }

    fn openLock(self: *const File, io: Io) ?Io.File {
        Io.Dir.cwd().createDirPath(io, self.directory) catch return null;
        return Io.Dir.cwd().createFile(io, self.lock_path, .{ .truncate = false }) catch null;
    }
    /// Requires the exclusive lock: only its holder touches partial files.
    fn publish(self: *const File, io: Io, part: Part, bytes: []const u8) bool {
        const cwd = Io.Dir.cwd();
        const partial_path = self.partial_paths[@intFromEnum(part)];
        {
            const partial = cwd.createFile(io, partial_path, .{}) catch return false;
            defer partial.close(io);
            partial.writeStreamingAll(io, bytes) catch return false;
            partial.sync(io) catch return false;
        }
        cwd.rename(partial_path, cwd, self.final(part), io) catch return false;
        return true;
    }
    /// Starts the detached writer: the child leaves the caller's session and
    /// forks the writer, then exits, so the caller reaps it at once and the
    /// writer is reparented. Returns whether the writer started.
    fn fork(self: *const File, lock: linux.fd_t, held: bool, producer: Producer) bool {
        const pid = linux.fork();
        if (linux.errno(pid) != .SUCCESS) return false;
        if (pid == 0) {
            _ = linux.setsid();
            const writer = linux.fork();
            if (writer != 0) linux.exit_group(if (linux.errno(writer) == .SUCCESS) 0 else 1);
            linux.exit_group(if (self.writeDetached(lock, held, producer)) 0 else 1);
        }
        var status: i32 = 0;
        while (true) switch (linux.errno(linux.wait4(@intCast(pid), &status, 0, null))) {
            .SUCCESS => break,
            .INTR => continue,
            else => return false,
        };
        const word: u32 = @bitCast(status);
        return linux.W.IFEXITED(word) and linux.W.EXITSTATUS(word) == 0;
    }
    /// Runs in the detached writer only. Raw system calls: the caller's Io and
    /// allocators may have been mid-operation on another thread at the fork.
    fn writeDetached(self: *const File, lock: linux.fd_t, held: bool, producer: Producer) bool {
        // The host may wait for the caller's stdio to close; never hold it.
        const sink = linux.openat(linux.AT.FDCWD, "/dev/null", .{ .ACCMODE = .RDWR }, 0);
        if (linux.errno(sink) == .SUCCESS) {
            for (0..3) |fd| _ = linux.dup2(@intCast(sink), @intCast(fd));
            if (sink > 2) _ = linux.close(@intCast(sink));
        }
        // The lock file names its latest writer, for people and tests.
        var note: [32]u8 = undefined;
        if (std.mem.print(&note, "{{\"writer\":{d}}}\n", .{linux.getpid()})) |text| {
            _ = linux.ftruncate(lock, 0);
            _ = linux.pwrite(lock, text.ptr, text.len, 0);
        } else |_| {}
        if (!held and !acquireRaw(lock)) return false;
        var heap: @import("../runtime/session_heap.zig").Heap = .{};
        var written = true;
        var produced: ?[]u8 = null;
        for (parts) |part| {
            const bytes = producer.encode(producer.context, heap.allocator(), part, produced) orelse {
                if (part == .output) _ = linux.unlinkat(linux.AT.FDCWD, self.output_path, 0);
                continue;
            };
            if (part == .checkpoint) produced = bytes;
            written = fits(bytes) and self.publishRaw(part, bytes) and written;
        }
        return written;
    }
    fn publishRaw(self: *const File, part: Part, bytes: []const u8) bool {
        const partial_path = self.partial_paths[@intFromEnum(part)];
        const flags: linux.O = .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true, .CLOEXEC = true };
        const fd = linux.openat(linux.AT.FDCWD, partial_path, flags, 0o644);
        if (linux.errno(fd) != .SUCCESS) return false;
        var written: usize = 0;
        while (written < bytes.len) {
            const count = linux.write(@intCast(fd), bytes[written..].ptr, bytes.len - written);
            switch (linux.errno(count)) {
                .SUCCESS => written += count,
                .INTR => {},
                else => break,
            }
        }
        const synced = written == bytes.len and linux.errno(linux.fsync(@intCast(fd))) == .SUCCESS;
        _ = linux.close(@intCast(fd));
        if (!synced) return false;
        return linux.errno(linux.renameat(linux.AT.FDCWD, partial_path, linux.AT.FDCWD, self.final(part))) == .SUCCESS;
    }
};

fn fits(bytes: []const u8) bool {
    return bytes.len != 0 and bytes.len <= maximum_bytes;
}
/// Polls for `kind`, at most `limit_ms`.
fn acquire(io: Io, lock: Io.File, kind: Io.File.Lock, limit_ms: i64) bool {
    const start = Io.Clock.awake.now(io);
    var pause_ms: i64 = 1;
    while (true) {
        if (lock.tryLock(io, kind) catch return false) return true;
        if (start.durationTo(Io.Clock.awake.now(io)).toMilliseconds() >= limit_ms) return false;
        io.sleep(.fromMilliseconds(pause_ms), .awake) catch return false;
        pause_ms = @min(pause_ms * 2, 20);
    }
}
fn acquireRaw(lock: linux.fd_t) bool {
    var waited_ms: u64 = 0;
    var pause_ms: u64 = 1;
    while (waited_ms < wait_limit_ms) : (waited_ms += pause_ms) {
        switch (linux.errno(linux.flock(lock, std.posix.LOCK.EX | std.posix.LOCK.NB))) {
            .SUCCESS => return true,
            .AGAIN, .INTR => {},
            else => return false,
        }
        const pause: linux.timespec = .{ .sec = 0, .nsec = @intCast(pause_ms * std.time.ns_per_ms) };
        _ = linux.nanosleep(&pause, null);
        pause_ms = @min(pause_ms * 2, 20);
    }
    return false;
}

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
    try std.testing.expect(!std.mem.eql(u8, first.lock_path, other_entry.lock_path));
    try std.testing.expect(std.mem.startsWith(u8, first.lock_path, first.directory));
    for (parts, first.partial_paths) |part, partial| try std.testing.expect(std.mem.startsWith(u8, partial, first.final(part)));
}

test "restart cache keys own compiler and entry separation under allocation failure" {
    try keyOwnership(std.testing.allocator);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, keyOwnership, .{});
}
