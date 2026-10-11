//! Native asset inputs and generated imports share one transactional owner.
//! Readers see captured bytes; a rejected compiler build never updates reuse.
const std = @import("std");
const overlays = @import("source_overlays.zig");
const readers = @import("native_asset_readers.zig");
const wgsl = @import("native_asset_wgsl.zig");
const A = std.mem.Allocator;
const Io = std.Io;

pub const Kind = enum { json, catalog, text, tunables, wgsl, reference };
pub const Definition = struct {
    module: []const u8,
    path: []const u8,
    kind: Kind,
    type: ?[]const u8 = null,
    @"export": ?[]const u8 = null,
    mediaType: ?[]const u8 = null,
};
pub const Options = struct { imports: []const Definition = &.{}, roots: []const []const u8 = &.{} };
pub const Stats = struct { parsed: usize = 0, reused: usize = 0, inputBytes: usize = 0, generatedBytes: usize = 0 };
pub const Dependency = struct { path: []const u8, sha256: ?[64]u8 };
pub const Resource = struct { id: u32, path: []const u8, mediaType: []const u8, sha256: [64]u8, bytes: []const u8, key: []const u8 };
pub const Issue = struct { filename: []const u8, start: u32 = 0, end: u32 = 0, code: []const u8, message: []const u8 };
const Module = struct { module: []const u8, definition: Definition, canonical: []const u8, bytes: []const u8, source: []const u8 };
const maximum_file = 16 * 1024 * 1024;
const maximum_total = 64 * 1024 * 1024;

pub const Candidate = struct {
    arena: std.heap.ArenaAllocator,
    modules: std.ArrayList(Module) = .empty,
    sources: std.ArrayList(overlays.Source) = .empty,
    dependencies: std.ArrayList(Dependency) = .empty,
    resources: std.ArrayList(Resource) = .empty,
    stats: Stats = .{},
    issue: ?Issue = null,

    pub fn deinit(self: *Candidate, a: A) void {
        self.arena.deinit();
        a.destroy(self);
    }
    fn fail(self: *Candidate, filename: []const u8, code: []const u8, message: []const u8) void {
        self.issue = .{ .filename = filename, .code = code, .message = message };
    }
};

pub const Session = struct {
    allocator: A,
    options_arena: std.heap.ArenaAllocator,
    options: Options,
    last: ?*Candidate = null,

    pub fn init(a: A, options: Options) !Session {
        if (options.imports.len > 4096 or options.roots.len > 4096 - options.imports.len) return error.AssetLimit;
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        const owner = arena.allocator();
        const definitions = try owner.alloc(Definition, options.imports.len);
        for (options.imports, definitions) |definition, *target| {
            if (!validPath(definition.module) or !validPath(definition.path) or !std.mem.endsWith(u8, definition.module, ".blot")) return error.InvalidNativeAssets;
            if (definition.kind == .reference) {
                if (definition.type == null or definition.@"export" == null or definition.mediaType == null) return error.InvalidNativeAssets;
                if (!identifier(definition.type.?, true) or !identifier(definition.@"export".?, false) or !validMediaType(definition.mediaType.?)) return error.InvalidNativeAssets;
            } else if (definition.type != null or definition.@"export" != null or definition.mediaType != null) return error.InvalidNativeAssets;
            target.* = definition;
            target.module = try owner.dupe(u8, definition.module);
            target.path = try owner.dupe(u8, definition.path);
            if (definition.type) |value| target.type = try owner.dupe(u8, value);
            if (definition.@"export") |value| target.@"export" = try owner.dupe(u8, value);
            if (definition.mediaType) |value| target.mediaType = try owner.dupe(u8, value);
        }
        const roots = try owner.alloc([]const u8, options.roots.len);
        for (options.roots, roots) |root, *target| {
            if (!validPath(root)) return error.InvalidNativeAssets;
            target.* = try owner.dupe(u8, root);
        }
        return .{ .allocator = a, .options_arena = arena, .options = .{ .imports = definitions, .roots = roots } };
    }
    pub fn deinit(self: *Session) void {
        if (self.last) |last| last.deinit(self.allocator);
        self.options_arena.deinit();
        self.* = undefined;
    }
    pub fn commit(self: *Session, candidate: *Candidate) void {
        std.debug.assert(candidate.issue == null);
        if (self.last) |last| last.deinit(self.allocator);
        self.last = candidate;
    }
    pub fn prepare(self: *Session, io: Io, entry: []const u8, sources: []const overlays.Source, asset_sources: []const overlays.Source) !*Candidate {
        const candidate = try self.allocator.create(Candidate);
        candidate.* = .{ .arena = std.heap.ArenaAllocator.init(self.allocator) };
        errdefer candidate.deinit(self.allocator);
        const a = candidate.arena.allocator();
        var overrides = try overlays.Set.init(a, io, asset_sources, .{});
        defer overrides.deinit();
        var definitions: std.ArrayList(Definition) = .empty;
        defer definitions.deinit(a);
        try definitions.appendSlice(a, self.options.imports);
        var discovered: std.ArrayList(Definition) = .empty;
        defer discovered.deinit(a);
        for (self.options.roots) |root| try discover(a, io, root, &overrides, &discovered);
        try definitions.appendSlice(a, discovered.items);
        if (definitions.items.len > 4096) return error.AssetLimit;
        for (definitions.items) |definition| if (!validPath(definition.module) or !validPath(definition.path)) return error.InvalidNativeAssets;
        std.mem.sort(Definition, definitions.items, {}, definitionLess);
        const canonical_entry = try overlays.canonicalPath(a, io, entry);
        var source_names: std.StringHashMapUnmanaged(void) = .empty;
        defer source_names.deinit(a);
        for (sources) |source| {
            const path = try overlays.canonicalPath(a, io, source.path);
            const slot = try source_names.getOrPut(a, path);
            if (slot.found_existing) return error.DuplicateSourcePath;
        }
        var module_names: std.StringHashMapUnmanaged(void) = .empty;
        defer module_names.deinit(a);
        var loads: std.StringHashMapUnmanaged([]const u8) = .empty;
        defer loads.deinit(a);
        for (definitions.items) |definition| {
            const module_path = try overlays.canonicalPath(a, io, definition.module);
            if (!validPath(module_path)) return error.InvalidNativeAssets;
            const slot = try module_names.getOrPut(a, module_path);
            if (slot.found_existing or source_names.contains(module_path) or std.mem.eql(u8, module_path, canonical_entry)) return error.DuplicateAssetModule;
            const input_path = try overlays.canonicalPath(a, io, definition.path);
            if (!validPath(input_path)) return error.InvalidNativeAssets;
            const input = loads.get(input_path) orelse read: {
                const bytes = if (overrides.files.get(input_path)) |override| try a.dupe(u8, override orelse {
                    candidate.fail(definition.path, "asset_missing", "Asset hidden by overlay");
                    return candidate;
                }) else Io.Dir.cwd().readFileAlloc(io, input_path, a, .limited(maximum_file + 1)) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    if (err == error.StreamTooLong) {
                        candidate.fail(definition.path, "asset_limit", "Asset input exceeds 16 MiB");
                        return candidate;
                    }
                    candidate.fail(definition.path, "asset_input", try a.print("Unable to read asset: {s}", .{@errorName(err)}));
                    return candidate;
                };
                if (bytes.len > maximum_file) {
                    candidate.fail(definition.path, "asset_limit", "Asset input exceeds 16 MiB");
                    return candidate;
                }
                if (bytes.len > maximum_total -| candidate.stats.inputBytes) {
                    candidate.fail(definition.path, "asset_limit", "Asset inputs exceed 64 MiB");
                    return candidate;
                }
                candidate.stats.inputBytes += bytes.len;
                try loads.put(a, input_path, bytes);
                break :read bytes;
            };
            var hash: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(input, &hash, .{});
            const digest = std.fmt.bytesToHex(hash, .lower);
            var dependency_exists = false;
            for (candidate.dependencies.items) |dependency| if (std.mem.eql(u8, dependency.path, definition.path)) {
                dependency_exists = true;
                break;
            };
            if (!dependency_exists) try candidate.dependencies.append(a, .{ .path = definition.path, .sha256 = digest });
            var source: []const u8 = undefined;
            if (definition.kind == .reference) {
                source = ""; // Render after all content handles are assigned.
                var found = false;
                for (candidate.resources.items) |resource| if (std.mem.eql(u8, resource.path, input_path) and std.mem.eql(u8, resource.mediaType, definition.mediaType.?) and std.mem.eql(u8, &resource.sha256, &digest)) {
                    found = true;
                    break;
                };
                if (!found) try candidate.resources.append(a, .{ .id = 0, .path = input_path, .mediaType = definition.mediaType.?, .sha256 = digest, .bytes = input, .key = try std.json.Stringify.valueAlloc(a, .{ input_path, definition.mediaType.?, digest[0..] }, .{}) });
                if (self.reusable(module_path, input_path, .reference, input) != null) candidate.stats.reused += 1 else candidate.stats.parsed += 1;
            } else if (self.reusable(module_path, input_path, definition.kind, input)) |old| {
                source = try a.dupe(u8, old.source);
                candidate.stats.reused += 1;
            } else {
                if (definition.kind == .wgsl) {
                    var generated = try wgsl.generate(self.allocator, input);
                    defer wgsl.deinit(self.allocator, &generated);
                    switch (generated) {
                        .source => |bytes| source = try a.dupe(u8, bytes),
                        .issue => |issue| {
                            candidate.issue = .{ .filename = definition.path, .start = issue.start, .end = issue.end, .code = issue.code, .message = try a.dupe(u8, issue.message) };
                            return candidate;
                        },
                    }
                } else {
                    const kind: readers.Kind = switch (definition.kind) {
                        .json => .json,
                        .catalog => .catalog,
                        .text => .text,
                        .tunables => .tunables,
                        else => unreachable,
                    };
                    var generated = try readers.generate(self.allocator, kind, input);
                    defer readers.deinit(self.allocator, &generated);
                    switch (generated) {
                        .source => |bytes| source = try a.dupe(u8, bytes),
                        .issue => |issue| {
                            candidate.issue = .{ .filename = definition.path, .start = issue.start, .end = issue.end, .code = issue.code, .message = try a.dupe(u8, issue.message) };
                            return candidate;
                        },
                    }
                }
                candidate.stats.parsed += 1;
            }
            try candidate.modules.append(a, .{ .module = module_path, .definition = definition, .canonical = input_path, .bytes = input, .source = source });
        }
        std.mem.sort(Resource, candidate.resources.items, {}, resourceLess);
        for (candidate.resources.items, 1..) |*resource, id| resource.id = @intCast(id);
        for (candidate.modules.items) |*module| {
            if (module.definition.kind == .reference) {
                for (candidate.resources.items) |resource| if (std.mem.eql(u8, resource.path, module.canonical) and std.mem.eql(u8, resource.mediaType, module.definition.mediaType.?)) {
                    module.source = try a.print("type {s} is data = #{s} U32\nconst {s}: {s} = (#{s} {d})\n", .{ module.definition.type.?, module.definition.type.?, module.definition.@"export".?, module.definition.type.?, module.definition.type.?, resource.id });
                    break;
                };
            }
            if (module.source.len > maximum_file or module.source.len > maximum_total -| candidate.stats.generatedBytes) return error.AssetLimit;
            candidate.stats.generatedBytes += module.source.len;
            try candidate.sources.append(a, .{ .path = module.module, .contents = module.source });
        }
        std.mem.sort(Dependency, candidate.dependencies.items, {}, dependencyLess);
        return candidate;
    }
    fn reusable(self: *const Session, module: []const u8, input: []const u8, kind: Kind, bytes: []const u8) ?Module {
        const last = self.last orelse return null;
        for (last.modules.items) |old| {
            if (old.definition.kind == kind and std.mem.eql(u8, old.module, module) and std.mem.eql(u8, old.canonical, input) and std.mem.eql(u8, old.bytes, bytes)) return old;
        }
        return null;
    }
};

fn validPath(path: []const u8) bool {
    return path.len != 0 and Io.Dir.path.isAbsolute(path) and std.mem.findScalar(u8, path, 0) == null and std.unicode.utf8ValidateSlice(path);
}
fn validMediaType(value: []const u8) bool {
    if (value.len == 0 or value.len > 1024 or std.mem.findAny(u8, value, "\r\n\x00") != null) return false;
    const view = std.unicode.Utf8View.init(value) catch return false;
    var iterator = view.iterator();
    var units: usize = 0;
    while (iterator.nextCodepoint()) |point| {
        units += 1;
        if (point > 0xffff) units += 1;
        if (units > 256) return false;
    }
    return true;
}
fn identifier(name: []const u8, upper: bool) bool {
    if (name.len == 0 or std.mem.eql(u8, name, "_")) return false;
    if (upper) {
        if (name[0] < 'A' or name[0] > 'Z') return false;
        for ([_][]const u8{ "Unit", "Bool", "U32", "F32", "Array", "List" }) |builtin| if (std.mem.eql(u8, name, builtin)) return false;
    } else if ((name[0] < 'a' or name[0] > 'z') and name[0] != '_') return false;
    for (name[1..]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_') return false;
    var words = std.mem.tokenizeScalar(u8, "const let type data effect is fn do use return yield break for ever in case of if then else as import infix infixl infixr self where", ' ');
    while (words.next()) |word| if (std.mem.eql(u8, word, name)) return false;
    return true;
}
fn definitionLess(_: void, left: Definition, right: Definition) bool {
    return utf16Less(left.module, right.module);
}
fn dependencyLess(_: void, left: Dependency, right: Dependency) bool {
    return utf16Less(left.path, right.path);
}
fn resourceLess(_: void, left: Resource, right: Resource) bool {
    return utf16Less(left.key, right.key);
}
fn utf16Less(left: []const u8, right: []const u8) bool {
    var l = std.unicode.Utf8View.initUnchecked(left).iterator();
    var r = std.unicode.Utf8View.initUnchecked(right).iterator();
    while (true) {
        const lp = l.nextCodepoint() orelse return r.nextCodepoint() != null;
        const rp = r.nextCodepoint() orelse return false;
        var lu = lp;
        var ru = rp;
        if (lp > 0xffff) lu = 0xd800 + ((lp - 0x10000) >> 10);
        if (rp > 0xffff) ru = 0xd800 + ((rp - 0x10000) >> 10);
        if (lu != ru) return lu < ru;
        // Equal leading surrogates imply two supplementary scalars; their
        // scalar order is also their trailing UTF-16-unit order.
        if (lp != rp) return lp < rp;
    }
}
fn appendDiscovered(a: A, definitions: *std.ArrayList(Definition), path: []const u8, kind: Kind) !void {
    const module = try a.print("{s}.blot", .{path});
    for (definitions.items) |definition| if (std.mem.eql(u8, definition.module, module)) return;
    if (definitions.items.len >= 4096) return error.AssetLimit;
    try definitions.append(a, .{ .path = path, .module = module, .kind = kind });
}
fn discover(a: A, io: Io, root: []const u8, overrides: *const overlays.Set, definitions: *std.ArrayList(Definition)) !void {
    for ([_]struct { path: []const u8, kind: Kind }{ .{ .path = "assets/catalog.json", .kind = .catalog }, .{ .path = "text.json", .kind = .text }, .{ .path = "tunables.json", .kind = .tunables } }) |known| {
        const path = try Io.Dir.path.join(a, &.{ root, known.path });
        const canonical = try overlays.canonicalPath(a, io, path);
        if (overrides.files.get(canonical)) |override| {
            if (override != null) try appendDiscovered(a, definitions, path, known.kind);
            continue;
        }
        const stat = Io.Dir.cwd().statFile(io, path, .{}) catch |err| {
            if (err == error.FileNotFound) continue;
            return err;
        };
        if (stat.kind == .file) try appendDiscovered(a, definitions, path, known.kind);
    }
    const asset_path = try Io.Dir.path.join(a, &.{ root, "assets" });
    if (Io.Dir.cwd().openDir(io, asset_path, .{ .iterate = true })) |opened| {
        var dir = opened;
        defer dir.close(io);
        var iterator = dir.iterate();
        while (try iterator.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".wgsl")) continue;
            const path = try Io.Dir.path.join(a, &.{ asset_path, entry.name });
            const canonical = try overlays.canonicalPath(a, io, path);
            if (overrides.files.get(canonical)) |override| if (override == null) continue;
            try appendDiscovered(a, definitions, path, .wgsl);
        }
    } else |err| {
        if (err != error.FileNotFound) return err;
    }
    const canonical_assets = try overlays.canonicalPath(a, io, asset_path);
    var iterator = overrides.files.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* == null or !std.mem.endsWith(u8, entry.key_ptr.*, ".wgsl")) continue;
        const parent = Io.Dir.path.dirname(entry.key_ptr.*) orelse continue;
        if (!std.mem.eql(u8, parent, canonical_assets)) continue;
        const path = try Io.Dir.path.join(a, &.{ asset_path, Io.Dir.path.basename(entry.key_ptr.*) });
        try appendDiscovered(a, definitions, path, .wgsl);
    }
}

fn ownershipLaw(a: A, root: []const u8) !void {
    const io = std.testing.io;
    const entry = try Io.Dir.path.join(a, &.{ root, "main.blot" });
    defer a.free(entry);
    const module = try Io.Dir.path.join(a, &.{ root, "data.json.blot" });
    defer a.free(module);
    const input = try Io.Dir.path.join(a, &.{ root, "data.json" });
    defer a.free(input);
    var session = try Session.init(a, .{ .imports = &.{.{ .module = module, .path = input, .kind = .json }} });
    defer session.deinit();
    const first = try session.prepare(io, entry, &.{}, &.{.{ .path = input, .contents = "{\"answer\":42}" }});
    var first_owned = true;
    defer if (first_owned) first.deinit(a);
    try std.testing.expect(first.issue == null);
    try std.testing.expectEqual(@as(usize, 1), first.stats.parsed);
    session.commit(first);
    first_owned = false;
    const rejected = try session.prepare(io, entry, &.{}, &.{.{ .path = input, .contents = "{" }});
    defer rejected.deinit(a);
    try std.testing.expect(rejected.issue != null);
    try std.testing.expect(session.last.? == first);
    const recovered = try session.prepare(io, entry, &.{}, &.{.{ .path = input, .contents = "{\"answer\":42}" }});
    defer recovered.deinit(a);
    try std.testing.expect(recovered.issue == null);
    try std.testing.expectEqual(@as(usize, 1), recovered.stats.reused);
    try std.testing.expectEqualStrings(first.sources.items[0].contents.?, recovered.sources.items[0].contents.?);
    try std.testing.expectEqualStrings("{\"answer\":42}", first.modules.items[0].bytes);
}

test "native asset rejection preserves exact captured inputs and parse reuse through allocation failure" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var buffer: [Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &buffer);
    try ownershipLaw(std.testing.allocator, buffer[0..count]);
    // Arena growth can remap differently as the backing heap changes. Force
    // allocation on growth so the exhaustive failure schedule is deterministic.
    var backing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(backing.allocator(), ownershipLaw, .{buffer[0..count]});
}

test "native content media types have the same bounded wire admission as the host" {
    try std.testing.expect(validMediaType("application/octet-stream"));
    for ([_][]const u8{ "", "a\n", "a\r", "a\x00", "\xff" }) |value| try std.testing.expect(!validMediaType(value));
    try std.testing.expect(validMediaType(&(@as([256]u8, @splat('a')))));
    try std.testing.expect(!validMediaType(&(@as([257]u8, @splat('a')))));
}

test "native asset names and content handles use host UTF16 lexical order" {
    try std.testing.expect(utf16Less("/p/😀", "/p/\u{e000}"));
    try std.testing.expect(!utf16Less("/p/\u{e000}", "/p/😀"));
    try std.testing.expect(utf16Less("/p/😀", "/p/😁"));
    try std.testing.expect(utf16Less("prefix", "prefixx"));
    try std.testing.expect(!utf16Less("same", "same"));
}
