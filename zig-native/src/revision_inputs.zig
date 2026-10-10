//! One candidate's owned project settings, raw source bytes and import decisions.
//! Filesystem reads are memoized here and the loader consumes these same facts.
//! This owner is not an evaluated-value or semantic cache certificate.
const std = @import("std");
const project = @import("project.zig");
const D = @import("frozen_dependency.zig");
const closure = @import("dependency_closure.zig");
const queries = @import("semantic_query_table.zig");
const Allocator = std.mem.Allocator;
pub const overlays = @import("source_overlays.zig");
comptime {
    if (@typeInfo(project.Options).@"struct".field_names.len != 7 or @typeInfo(project.Alias).@"struct".field_names.len != 2) @compileError("Extend exact unchanged-input option comparison before adding project options or alias fields");
}
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

/// Successful source acquisition has a different owner from the mutable
/// provider. These records describe inputs only; no semantic or emitted result
/// can be obtained from their validation claim.
const Settings = struct {
    options: project.Options,
    pub fn deinit(self: *Settings, a: Allocator) void {
        freeOptions(a, self.options);
    }
};
const Observations = struct {
    paths: std.ArrayList(Entry),
    files: std.ArrayList(Entry),
    imports: std.ArrayList(Resolution),
    pub fn deinit(self: *Observations, a: Allocator) void {
        for (self.paths.items) |entry| entry.deinit(a);
        self.paths.deinit(a);
        for (self.files.items) |entry| entry.deinit(a);
        self.files.deinit(a);
        for (self.imports.items) |entry| entry.deinit(a);
        self.imports.deinit(a);
    }
};
const Acquired = struct {
    counts: Counts,
    pub fn deinit(_: *Acquired, _: Allocator) void {}
};
pub const Record = queries.OwnedRecord(.source_validation, Settings, Observations, Acquired);

/// A single revision owns exactly one input record, so it needs no bucket or
/// optional cache capacity. Freezing moves the original buffers without copying
/// bytes or allocating. Auxiliary failed observations remain explicit and make
/// unchanged-input admission decline, just as they do on the mutable provider.
pub const Frozen = struct {
    allocator: Allocator,
    record: Record,
    sources: ?overlays.Set,

    pub fn deinit(self: *Frozen) void {
        self.record.deinit(self.allocator);
        if (self.sources) |*sources| sources.deinit();
        self.* = undefined;
    }
    pub fn view(self: *const Frozen) View {
        return .{ .options = self.record.key.options, .paths = self.record.dependencies.paths.items, .files = self.record.dependencies.files.items, .imports = self.record.dependencies.imports.items, .counts = self.record.value.counts };
    }
    pub fn capturedSource(self: *const Frozen, canonical_path: []const u8) ?[]const u8 {
        return self.view().capturedSource(canonical_path);
    }
};

/// Borrowed exact input projection shared by acquisition and frozen records.
/// It deliberately exposes no mutable provider or filesystem operations.
pub const View = struct {
    options: project.Options,
    paths: []const Entry,
    files: []const Entry,
    imports: []const Resolution,
    counts: Counts,
    pub fn capturedSource(self: View, canonical_path: []const u8) ?[]const u8 {
        return switch (Snapshot.get(self.files, canonical_path) orelse return null) {
            .bytes => |bytes| bytes,
            .failure => null,
        };
    }
};

fn freeOptions(a: Allocator, options: project.Options) void {
    if (options.prelude_path) |path| a.free(path);
    if (options.std_root) |root| a.free(root);
    for (options.aliases) |alias| {
        a.free(alias.prefix);
        a.free(alias.root);
    }
    a.free(options.aliases);
}

pub const Snapshot = struct {
    allocator: Allocator,
    options: project.Options,
    paths: std.ArrayList(Entry) = .empty,
    files: std.ArrayList(Entry) = .empty,
    imports: std.ArrayList(Resolution) = .empty,
    counts: Counts = .{},
    sources: ?overlays.Set = null,

    pub fn view(self: *const Snapshot) View {
        return .{ .options = self.options, .paths = self.paths.items, .files = self.files.items, .imports = self.imports.items, .counts = self.counts };
    }
    /// Call only after successful compilation. The provider is invalid after
    /// this ownership transfer; rejected attempts retain their Snapshot.
    pub fn freeze(self: *Snapshot) Frozen {
        const frozen: Frozen = .{ .allocator = self.allocator, .record = .{ .key = .{ .options = self.options }, .dependencies = .{ .paths = self.paths, .files = self.files, .imports = self.imports }, .value = .{ .counts = self.counts } }, .sources = self.sources };
        self.* = undefined;
        return frozen;
    }

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
        self.* = undefined;
    }
    fn get(entries: []const Entry, key: []const u8) ?Outcome {
        for (entries) |entry| if (std.mem.eql(u8, entry.key, key)) return entry.result;
        return null;
    }
    fn value(result: Outcome) anyerror![]const u8 {
        if (result == .failure) return result.failure;
        return result.bytes;
    }
    fn publish(self: *Snapshot, entries: *std.ArrayList(Entry), key: []const u8, result: Outcome) Allocator.Error!Outcome {
        errdefer result.deinit(self.allocator);
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
        errdefer if (!published) result.deinit(self.allocator);
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
    pub fn entryEqualsPrevious(self: *Snapshot, io: std.Io, requested: []const u8, old_canonical: []const u8, previous: View) Allocator.Error!bool {
        const actual_path = self.canonical(io, requested) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        if (!std.mem.eql(u8, actual_path, old_canonical)) return false;
        const expected = switch (get(previous.files, old_canonical) orelse return false) {
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
    pub fn equalsPrevious(self: *Snapshot, io: std.Io, previous: View) Allocator.Error!bool {
        const left = self.options;
        const right = previous.options;
        if (left.input_mode != right.input_mode or left.max_source_bytes != right.max_source_bytes or left.max_total_source_bytes != right.max_total_source_bytes or left.max_files != right.max_files or !optionalTextEqual(left.prelude_path, right.prelude_path) or !optionalTextEqual(left.std_root, right.std_root) or left.aliases.len != right.aliases.len) return false;
        for (left.aliases, right.aliases) |actual, old| {
            if (!std.mem.eql(u8, actual.prefix, old.prefix) or !std.mem.eql(u8, actual.root, old.root)) return false;
        }
        if (previous.files.len == 0) return false;
        for (previous.paths) |entry| {
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
        for (previous.files) |entry| {
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
        for (previous.imports) |entry| {
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
