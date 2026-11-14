//! One candidate's owned project settings, raw source bytes and import decisions.
//! Filesystem reads are memoized here and the loader consumes these same facts.
//! This owner is not an evaluated-value or semantic cache certificate.
const std = @import("std");
const project = @import("project.zig");
const D = @import("frozen_dependency.zig");
const Allocator = std.mem.Allocator;
pub const overlays = @import("source_overlays.zig");
const Outcome = union(enum) {
    bytes: []u8,
    failure: anyerror,

    fn deinit(self: Outcome, a: Allocator) void {
        switch (self) {
            .bytes => |bytes| a.free(bytes),
            .failure => {},
        }
    }
};
const Entry = struct {
    key: []u8,
    result: Outcome,

    fn deinit(self: Entry, a: Allocator) void {
        a.free(self.key);
        self.result.deinit(a);
    }
};
const Resolution = struct {
    source: []u8,
    request: []u8,
    result: Outcome,

    fn deinit(self: Resolution, a: Allocator) void {
        a.free(self.source);
        a.free(self.request);
        self.result.deinit(a);
    }
};
pub const Counts = struct { canonical_reads: usize = 0, source_reads: usize = 0, resolutions: usize = 0 };

fn freeOptions(a: Allocator, options: project.Options) void {
    if (options.prelude_path) |path| a.free(path);
    if (options.std_root) |root| a.free(root);
    for (options.aliases) |alias| {
        a.free(alias.prefix);
        a.free(alias.root);
    }
    a.free(options.aliases);
}

/// An import observation's key: the importing file and its request text.
const ImportKey = struct {
    source: []const u8,
    request: []const u8,
    const Context = struct {
        pub fn hash(_: Context, key: ImportKey) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&key.source.len));
            hasher.update(key.source);
            hasher.update(key.request);
            return hasher.final();
        }
        pub fn eql(_: Context, left: ImportKey, right: ImportKey) bool {
            return std.mem.eql(u8, left.source, right.source) and std.mem.eql(u8, left.request, right.request);
        }
    };
};

pub const Snapshot = struct {
    allocator: Allocator,
    options: project.Options,
    paths: std.ArrayList(Entry) = .empty,
    files: std.ArrayList(Entry) = .empty,
    imports: std.ArrayList(Resolution) = .empty,
    counts: Counts = .{},
    sources: ?overlays.Set = null,
    /// Positions in `paths`, `files` and `imports`, keyed by the entries' own
    /// key bytes. They answer exactly what a scan of the lists would.
    path_index: std.StringHashMapUnmanaged(u32) = .empty,
    file_index: std.StringHashMapUnmanaged(u32) = .empty,
    import_index: std.HashMapUnmanaged(ImportKey, u32, ImportKey.Context, std.hash_map.default_max_load_percentage) = .empty,
    /// Digests of successful reads by `files` position, each computed once.
    digests: std.AutoHashMapUnmanaged(u32, [32]u8) = .empty,

    /// The complete overlay set is copied before any admission or compilation.
    /// Published revisions never borrow the request or caller's source buffers.
    pub fn initWithSources(a: Allocator, io: std.Io, options: project.Options, sources: []const overlays.Source) !Snapshot {
        var result = try init(a, options);
        errdefer result.deinit();
        if (sources.len != 0) result.sources = try overlays.Set.init(a, io, sources, options);
        return result;
    }

    pub fn init(a: Allocator, options: project.Options) Allocator.Error!Snapshot {
        var result: Snapshot = .{ .allocator = a, .options = options };
        result.options.prelude_path = null;
        result.options.std_root = null;
        result.options.aliases = &.{};
        errdefer result.deinit();
        if (options.prelude_path) |path| result.options.prelude_path = try a.dupe(u8, path);
        if (options.std_root) |root| result.options.std_root = try a.dupe(u8, root);
        const aliases = try a.alloc(project.Alias, options.aliases.len);
        var initialized: usize = 0;
        errdefer {
            for (aliases[0..initialized]) |alias| {
                a.free(alias.prefix);
                a.free(alias.root);
            }
            a.free(aliases);
        }
        for (options.aliases, aliases) |alias, *copy| {
            const prefix = try a.dupe(u8, alias.prefix);
            errdefer a.free(prefix);
            const root = try a.dupe(u8, alias.root);
            copy.* = .{ .prefix = prefix, .root = root };
            initialized += 1;
        }
        result.options.aliases = aliases;
        return result;
    }
    pub fn deinit(self: *Snapshot) void {
        const a = self.allocator;
        if (self.sources) |*sources| sources.deinit();
        freeOptions(a, self.options);
        for (self.paths.items) |entry| entry.deinit(a);
        self.paths.deinit(a);
        for (self.files.items) |entry| entry.deinit(a);
        self.files.deinit(a);
        for (self.imports.items) |entry| entry.deinit(a);
        self.imports.deinit(a);
        self.deinitIndexes();
        self.* = undefined;
    }
    fn deinitIndexes(self: *Snapshot) void {
        const a = self.allocator;
        self.path_index.deinit(a);
        self.file_index.deinit(a);
        self.import_index.deinit(a);
        self.digests.deinit(a);
    }
    fn lookup(entries: []const Entry, index: *const std.StringHashMapUnmanaged(u32), key: []const u8) ?Outcome {
        const position = index.get(key) orelse return null;
        return entries[position].result;
    }
    fn value(result: Outcome) anyerror![]const u8 {
        if (result == .failure) return result.failure;
        return result.bytes;
    }
    fn publish(self: *Snapshot, entries: *std.ArrayList(Entry), index: *std.StringHashMapUnmanaged(u32), key: []const u8, result: Outcome) Allocator.Error!Outcome {
        errdefer result.deinit(self.allocator);
        if (entries.items.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        try entries.ensureUnusedCapacity(self.allocator, 1);
        try index.ensureUnusedCapacity(self.allocator, 1);
        const owned = try self.allocator.dupe(u8, key);
        entries.appendAssumeCapacity(.{ .key = owned, .result = result });
        index.putAssumeCapacityNoClobber(owned, @intCast(entries.items.len - 1));
        return result;
    }
    /// The digest of a source this snapshot read successfully, computed once.
    pub fn sourceDigest(self: *Snapshot, canonical_path: []const u8, bytes: []const u8) Allocator.Error![32]u8 {
        const position = self.file_index.get(canonical_path) orelse return @import("dependency_format.zig").digest(bytes);
        std.debug.assert(self.files.items[position].result == .bytes and self.files.items[position].result.bytes.ptr == bytes.ptr);
        const entry = try self.digests.getOrPut(self.allocator, position);
        if (!entry.found_existing) entry.value_ptr.* = @import("dependency_format.zig").digest(bytes);
        return entry.value_ptr.*;
    }
    pub fn canonical(self: *Snapshot, io: std.Io, path: []const u8) anyerror![]const u8 {
        if (lookup(self.paths.items, &self.path_index, path)) |old| return value(old);
        self.counts.canonical_reads += 1;
        const result: Outcome = blk: {
            if (self.sources) |*sources| {
                const name = overlays.canonicalPath(self.allocator, io, path) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    break :blk .{ .failure = err };
                };
                if (sources.files.contains(name)) break :blk .{ .bytes = name };
                self.allocator.free(name);
            }
            const raw = std.Io.Dir.cwd().realPathFileAlloc(io, path, self.allocator) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                break :blk .{ .failure = err };
            };
            defer self.allocator.free(raw);
            break :blk .{ .bytes = try self.allocator.dupe(u8, raw) };
        };
        return value(try self.publish(&self.paths, &self.path_index, path, result));
    }
    pub fn read(self: *Snapshot, io: std.Io, canonical_path: []const u8) anyerror![]const u8 {
        if (lookup(self.files.items, &self.file_index, canonical_path)) |old| return value(old);
        self.counts.source_reads += 1;
        const cap = @min(self.options.max_source_bytes, std.math.maxInt(u32)) +| 1;
        const result: Outcome = blk: {
            if (self.sources) |*sources| if (sources.files.getPtr(canonical_path)) |entry| {
                break :blk if (entry.*) |bytes| .{ .bytes = try self.allocator.dupe(u8, bytes) } else .{ .failure = error.FileNotFound };
            };
            const bytes = std.Io.Dir.cwd().readFileAlloc(io, canonical_path, self.allocator, .limited(cap)) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                break :blk .{ .failure = err };
            };
            break :blk .{ .bytes = bytes };
        };
        return value(try self.publish(&self.files, &self.file_index, canonical_path, result));
    }
    pub fn resolve(self: *Snapshot, source: []const u8, request: []const u8) (Allocator.Error || error{InvalidPath})![]const u8 {
        if (self.import_index.get(.{ .source = source, .request = request })) |position| {
            return switch (self.imports.items[position].result) {
                .bytes => |bytes| bytes,
                .failure => error.InvalidPath,
            };
        }
        self.counts.resolutions += 1;
        const result: Outcome = blk: {
            const bytes = project.resolveImportPath(self.allocator, source, request, self.options) catch |err| switch (err) {
                error.OutOfMemory => return err,
                error.InvalidPath => break :blk .{ .failure = err },
            };
            break :blk .{ .bytes = bytes };
        };
        var published = false;
        errdefer if (!published) result.deinit(self.allocator);
        if (self.imports.items.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        try self.imports.ensureUnusedCapacity(self.allocator, 1);
        try self.import_index.ensureUnusedCapacity(self.allocator, 1);
        const owned_source = try self.allocator.dupe(u8, source);
        errdefer if (!published) self.allocator.free(owned_source);
        const owned_request = try self.allocator.dupe(u8, request);
        self.imports.appendAssumeCapacity(.{ .source = owned_source, .request = owned_request, .result = result });
        self.import_index.putAssumeCapacityNoClobber(.{ .source = owned_source, .request = owned_request }, @intCast(self.imports.items.len - 1));
        published = true;
        return switch (result) {
            .bytes => |bytes| bytes,
            .failure => error.InvalidPath,
        };
    }
    fn context(raw: *anyopaque) *Snapshot {
        return @ptrCast(@alignCast(raw));
    }
    fn canonicalInput(raw: *anyopaque, a: Allocator, io: std.Io, path: []const u8) anyerror![:0]u8 {
        return a.dupeSentinel(u8, try context(raw).canonical(io, path), 0);
    }
    fn readInput(raw: *anyopaque, a: Allocator, io: std.Io, path: []const u8, limit: usize) anyerror![]u8 {
        const bytes = try context(raw).read(io, path);
        if (bytes.len > limit) return error.StreamTooLong;
        return a.dupe(u8, bytes);
    }
    fn resolveInput(raw: *anyopaque, a: Allocator, source: []const u8, request: []const u8, _: project.Options) (Allocator.Error || error{InvalidPath})![]u8 {
        return a.dupe(u8, try context(raw).resolve(source, request));
    }
    pub fn provider(self: *Snapshot) project.InputProvider {
        return .{ .context = self, .canonical = canonicalInput, .read = readInput, .resolve = resolveInput };
    }

    /// Borrow a successful source read already owned by this immutable snapshot.
    pub fn capturedSource(self: *const Snapshot, canonical_path: []const u8) ?[]const u8 {
        return switch (lookup(self.files.items, &self.file_index, canonical_path) orelse return null) {
            .bytes => |bytes| bytes,
            .failure => null,
        };
    }
    /// Exact raw-input admission plus transitive import invalidation: which
    /// of the seed's modules are unchanged. The returned mask belongs to the
    /// caller; null means the seed cannot be used at all.
    pub fn reusableModules(self: *Snapshot, io: std.Io, seed: *const D.FrozenDependency) Allocator.Error!?[]bool {
        const a = self.allocator;
        if (self.options.input_mode != .project or seed.modules.len == 0 or seed.modules.len >= self.options.max_files) return null;
        const reuse = try a.alloc(bool, seed.modules.len);
        var transferred = false;
        defer if (!transferred) a.free(reuse);
        var total: usize = 0;
        var prelude: ?usize = null;
        for (seed.modules, reuse, 0..) |module, *same, i| {
            const canonical_path = self.canonical(io, module.identity.normalized_path) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return null;
            };
            if (!std.mem.eql(u8, canonical_path, module.identity.normalized_path)) return null;
            const bytes = self.read(io, canonical_path) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return null;
            };
            if (bytes.len > self.options.max_source_bytes or bytes.len > self.options.max_total_source_bytes -| total) return null;
            total += bytes.len;
            same.* = bytes.len == module.identity.source_bytes and std.mem.eql(u8, &try self.sourceDigest(canonical_path, bytes), &module.identity.source_digest);
            if (module.identity.prelude) {
                if (prelude != null) return null;
                const raw = self.options.prelude_path orelse return null;
                const actual = self.canonical(io, raw) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return null;
                };
                if (!std.mem.eql(u8, actual, canonical_path)) return null;
                prelude = i;
            }
            if (same.*) for (module.source_imports) |request| {
                if (request.target == 0 or request.target > seed.modules.len) return null;
                const resolved = self.resolve(canonical_path, request.path) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return null;
                };
                const target = self.canonical(io, resolved) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return null;
                };
                if (!std.mem.eql(u8, target, seed.modules[request.target - 1].identity.normalized_path)) return null;
            };
        }
        // Stable IDs retain old spellings. Bound their accumulation by the
        // current source size; a full frontend rebuild compacts the dictionary.
        // This also handles a large producer shrinking to a small one.
        var dictionary_budget = @max(@as(usize, 64 * 1024), total *| 2);
        for (seed.symbols) |symbol| {
            if (symbol.text.len > dictionary_budget) return null;
            dictionary_budget -= symbol.text.len;
        }
        if ((prelude != null) != (self.options.prelude_path != null)) return null;
        var changed = true;
        while (changed) {
            changed = false;
            for (seed.modules, reuse) |module, *same| {
                if (!same.*) continue;
                for (module.imports) |target| {
                    if (target == 0 or target > reuse.len) return null;
                    if (!reuse[target - 1]) {
                        same.* = false;
                        changed = true;
                        break;
                    }
                }
            }
        }
        if (prelude) |id| if (!reuse[id]) return null;
        transferred = true;
        return reuse;
    }
};
