//! One candidate's owned project settings, raw source bytes and import decisions.
//! Filesystem reads are memoized here and the loader consumes these same facts.
//! This owner is not an evaluated-value or semantic cache certificate.
const std = @import("std");
const project = @import("project.zig");
const D = @import("frozen_dependency.zig");
const closure = @import("dependency_closure.zig");
const Allocator = std.mem.Allocator;
pub const overlays = @import("source_overlays.zig");
comptime {
    if (@typeInfo(project.Options).@"struct".field_names.len != 7 or @typeInfo(project.Alias).@"struct".field_names.len != 2) @compileError("Extend exact unchanged-input option comparison before adding project options or alias fields");
}
const Outcome = union(enum) { bytes: []u8, failure: anyerror };
const Entry = struct { key: []u8, result: Outcome };
const Resolution = struct { source: []u8, request: []u8, result: Outcome };
pub const Counts = struct { canonical_reads: usize = 0, source_reads: usize = 0, resolutions: usize = 0 };

pub const Snapshot = struct {
    allocator: Allocator,
    options: project.Options,
    paths: std.ArrayList(Entry) = .empty,
    files: std.ArrayList(Entry) = .empty,
    imports: std.ArrayList(Resolution) = .empty,
    counts: Counts = .{},
    sources: ?overlays.Set = null,

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
    fn release(a: Allocator, result: Outcome) void {
        switch (result) {
            .bytes => |bytes| a.free(bytes),
            .failure => {},
        }
    }
    pub fn deinit(self: *Snapshot) void {
        const a = self.allocator;
        if (self.sources) |*sources| sources.deinit();
        if (self.options.prelude_path) |path| a.free(path);
        if (self.options.std_root) |root| a.free(root);
        for (self.options.aliases) |alias| {
            a.free(alias.prefix);
            a.free(alias.root);
        }
        a.free(self.options.aliases);
        for (self.paths.items) |entry| {
            a.free(entry.key);
            release(a, entry.result);
        }
        self.paths.deinit(a);
        for (self.files.items) |entry| {
            a.free(entry.key);
            release(a, entry.result);
        }
        self.files.deinit(a);
        for (self.imports.items) |entry| {
            a.free(entry.source);
            a.free(entry.request);
            release(a, entry.result);
        }
        self.imports.deinit(a);
        self.* = undefined;
    }
    fn get(entries: []const Entry, key: []const u8) ?Outcome {
        for (entries) |entry| if (std.mem.eql(u8, entry.key, key)) return entry.result;
        return null;
    }
    fn value(result: Outcome) anyerror![]const u8 {
        return switch (result) {
            .bytes => |bytes| bytes,
            .failure => |err| err,
        };
    }
    fn publish(self: *Snapshot, entries: *std.ArrayList(Entry), key: []const u8, result: Outcome) Allocator.Error!Outcome {
        errdefer release(self.allocator, result);
        const owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(owned);
        try entries.append(self.allocator, .{ .key = owned, .result = result });
        return result;
    }
    pub fn canonical(self: *Snapshot, io: std.Io, path: []const u8) anyerror![]const u8 {
        if (get(self.paths.items, path)) |old| return value(old);
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
        return value(try self.publish(&self.paths, path, result));
    }
    pub fn read(self: *Snapshot, io: std.Io, canonical_path: []const u8) anyerror![]const u8 {
        if (get(self.files.items, canonical_path)) |old| return value(old);
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
        return value(try self.publish(&self.files, canonical_path, result));
    }
    pub fn resolve(self: *Snapshot, source: []const u8, request: []const u8) (Allocator.Error || error{InvalidPath})![]const u8 {
        for (self.imports.items) |entry| if (std.mem.eql(u8, entry.source, source) and std.mem.eql(u8, entry.request, request)) {
            return switch (entry.result) {
                .bytes => |bytes| bytes,
                .failure => error.InvalidPath,
            };
        };
        self.counts.resolutions += 1;
        const result: Outcome = blk: {
            const bytes = project.resolveImportPath(self.allocator, source, request, self.options) catch |err| switch (err) {
                error.OutOfMemory => return err,
                error.InvalidPath => break :blk .{ .failure = err },
            };
            break :blk .{ .bytes = bytes };
        };
        var published = false;
        errdefer if (!published) release(self.allocator, result);
        const owned_source = try self.allocator.dupe(u8, source);
        errdefer if (!published) self.allocator.free(owned_source);
        const owned_request = try self.allocator.dupe(u8, request);
        errdefer if (!published) self.allocator.free(owned_request);
        try self.imports.append(self.allocator, .{ .source = owned_source, .request = owned_request, .result = result });
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

    fn optionalTextEqual(left: ?[]const u8, right: ?[]const u8) bool {
        if (left) |text| return if (right) |other| std.mem.eql(u8, text, other) else false;
        return right == null;
    }

    /// Borrow a successful source read already owned by this immutable snapshot.
    pub fn capturedSource(self: *const Snapshot, canonical_path: []const u8) ?[]const u8 {
        return switch (get(self.files.items, canonical_path) orelse return null) {
            .bytes => |bytes| bytes,
            .failure => null,
        };
    }
    pub fn entryEqualsPrevious(self: *Snapshot, io: std.Io, requested: []const u8, old_canonical: []const u8, previous: *const Snapshot) Allocator.Error!bool {
        const actual_path = self.canonical(io, requested) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        if (!std.mem.eql(u8, actual_path, old_canonical)) return false;
        const expected = switch (get(previous.files.items, old_canonical) orelse return false) {
            .bytes => |bytes| bytes,
            .failure => return false,
        };
        const actual = self.read(io, actual_path) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        return std.mem.eql(u8, expected, actual);
    }

    /// Validate all facts consumed by a successful revision against current
    /// reads. Exact source bytes and resolution outcomes are required. Unknown
    /// or failed old observations decline; this is not timestamp admission.
    pub fn equalsPrevious(self: *Snapshot, io: std.Io, previous: *const Snapshot) Allocator.Error!bool {
        const left = self.options;
        const right = previous.options;
        if (left.input_mode != right.input_mode or left.max_source_bytes != right.max_source_bytes or left.max_total_source_bytes != right.max_total_source_bytes or left.max_files != right.max_files or !optionalTextEqual(left.prelude_path, right.prelude_path) or !optionalTextEqual(left.std_root, right.std_root) or left.aliases.len != right.aliases.len) return false;
        for (left.aliases, right.aliases) |actual, old| {
            if (!std.mem.eql(u8, actual.prefix, old.prefix) or !std.mem.eql(u8, actual.root, old.root)) return false;
        }
        if (previous.files.items.len == 0) return false;
        for (previous.paths.items) |entry| {
            const expected = switch (entry.result) {
                .bytes => |bytes| bytes,
                .failure => return false,
            };
            const actual = self.canonical(io, entry.key) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            if (!std.mem.eql(u8, expected, actual)) return false;
        }
        for (previous.files.items) |entry| {
            const expected = switch (entry.result) {
                .bytes => |bytes| bytes,
                .failure => return false,
            };
            const actual = self.read(io, entry.key) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            if (!std.mem.eql(u8, expected, actual)) return false;
        }
        for (previous.imports.items) |entry| {
            const expected = switch (entry.result) {
                .bytes => |bytes| bytes,
                .failure => return false,
            };
            const actual = self.resolve(entry.source, entry.request) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            if (!std.mem.eql(u8, expected, actual)) return false;
        }
        return true;
    }

    /// Exact raw-input admission plus transitive import invalidation. The
    /// returned mask is private to this candidate; no prior owner is changed.
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
            same.* = bytes.len == module.identity.source_bytes and std.mem.eql(u8, &@import("dependency_format.zig").digest(bytes), &module.identity.source_digest);
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
        var count: usize = 0;
        for (reuse) |same| count += @intFromBool(same);
        if (count == 0 or count == reuse.len) return null;
        transferred = true;
        return reuse;
    }

    /// This validation consumes exactly the facts later given to the loader.
    /// Missing/invalid changed inputs select fresh loading for its ordinary
    /// diagnostics. Allocation failure aborts; no changed seed is published.
    pub fn admits(self: *Snapshot, io: std.Io, seed: *const D.FrozenDependency) Allocator.Error!bool {
        if (self.options.input_mode != .project) return false;
        if (seed.modules.len >= self.options.max_files) return false;
        var total: usize = 0;
        var found_prelude = false;
        for (seed.modules) |*module| {
            const canonical_path = self.canonical(io, module.identity.normalized_path) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            const bytes = self.read(io, canonical_path) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                return false;
            };
            closure.validateProducer(module, canonical_path, bytes) catch return false;
            if (bytes.len > self.options.max_source_bytes or bytes.len > self.options.max_total_source_bytes -| total) return false;
            total += bytes.len;
            if (module.identity.prelude) {
                const raw_prelude = self.options.prelude_path orelse return false;
                const prelude = self.canonical(io, raw_prelude) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return false;
                };
                if (!std.mem.eql(u8, prelude, canonical_path)) return false;
                found_prelude = true;
            }
            for (module.source_imports) |request| {
                if (request.target == 0 or request.target > seed.modules.len) return false;
                const resolved = self.resolve(canonical_path, request.path) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidPath => return false,
                };
                const target = self.canonical(io, resolved) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    return false;
                };
                if (!std.mem.eql(u8, target, seed.modules[request.target - 1].identity.normalized_path)) return false;
            }
        }
        return found_prelude == (self.options.prelude_path != null);
    }
};
