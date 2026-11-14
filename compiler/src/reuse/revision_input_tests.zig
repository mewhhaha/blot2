//! Actual source edits exercise snapshot admission and transactional fallback.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const inputs = @import("revision_inputs.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const original = "const value:U32 = 42\nconst read:Unit->U32 = func () => return value\n";
const edited = "const value:U32 = 43\nconst read:Unit->U32 = func () => return value\n";
const main = "import * as dep from \"./dep\"\nentry const answer:Unit->U32 = func () => return dep.read ()\n";
const key: format.Key = .{ .compiler = @splat(1), .settings = @splat(2), .source = @splat(3), .dependencies = @splat(4) };

fn seed(a_: std.mem.Allocator, path: []const u8, options: project.Options) !D.FrozenDependency {
    var source = try project.load(a_, io, path, options);
    defer source.deinit(a_);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(a_, &source);
    defer checked.deinit(a_);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var value = try closure.freeze(a_, &source, &checked);
    errdefer format.deinit(a_, &value);
    try closure.validate(a_, &value);
    return value;
}
fn fresh(path: []const u8, options: project.Options) !partial.Result {
    var source = try project.load(a, io, path, options);
    defer source.deinit(a);
    const empty: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var preparation = try partial.prepareProject(a, &source, path, null, &empty);
    switch (preparation) {
        .rejected => |result| return result,
        .ready => |*prepared| {
            defer prepared.deinit(a);
            return prepared.emit(a);
        },
    }
}
fn equal(result: *const partial.Result, expected: *const partial.Result) !void {
    try std.testing.expect(result.result.diagnostic == null);
    if (result.result.compiled.diagnostic) |d| std.debug.print("backend: {s}\n", .{d.message()});
    try std.testing.expect(result.result.compiled.diagnostic == null);
    try std.testing.expect(expected.result.diagnostic == null and expected.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, result.result.compiled.bytes);
}
test "revision input invalid resolution is owned and repeated without premature cleanup" {
    var snapshot = try inputs.Snapshot.init(a, .{});
    defer snapshot.deinit();
    try std.testing.expectError(error.InvalidPath, snapshot.resolve("/tmp/main.blot", "unknown/dep"));
    try std.testing.expectError(error.InvalidPath, snapshot.resolve("/tmp/main.blot", "unknown/dep"));
    try std.testing.expectEqual(@as(usize, 1), snapshot.counts.resolutions);
}

fn freezeInputs(allocator: std.mem.Allocator, path: []const u8) !void {
    var snapshot = try inputs.Snapshot.init(allocator, .{});
    var alive = true;
    defer if (alive) snapshot.deinit();
    const canonical = try snapshot.canonical(io, path);
    const bytes = try snapshot.read(io, canonical);
    const files = snapshot.files.items.ptr;
    const source = bytes.ptr;
    const counts = snapshot.counts;
    var frozen = snapshot.freeze();
    alive = false;
    defer frozen.deinit();
    try std.testing.expect(frozen.record.dependencies.files.items.ptr == files);
    try std.testing.expect(frozen.capturedSource(canonical).?.ptr == source);
    try std.testing.expectEqualDeep(counts, frozen.view().counts);
    var next = try inputs.Snapshot.init(allocator, .{});
    defer next.deinit();
    try std.testing.expect(try next.equalsPrevious(io, frozen.view()));
    try std.testing.expect(try next.entryEqualsPrevious(io, path, canonical, frozen.view()));
}
test "source validation frozen revision record moves each source owner once and survives every acquisition allocation failure" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "entry const answer:U32=42\n" });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    try freezeInputs(a, path);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, freezeInputs, .{path});
}

test "source validation frozen inputs recheck exact bytes ordered settings and failed import observations" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    const text = "entry const answer:U32=42\n";
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = text });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    const aliases = [_]project.Alias{ .{ .prefix = "one/", .root = "/one" }, .{ .prefix = "two/", .root = "/two" } };
    var snapshot = try inputs.Snapshot.init(a, .{ .aliases = &aliases });
    const canonical = try snapshot.canonical(io, path);
    _ = try snapshot.read(io, canonical);
    var frozen = snapshot.freeze();
    defer frozen.deinit();
    var same = try inputs.Snapshot.init(a, .{ .aliases = &aliases });
    defer same.deinit();
    try std.testing.expect(try same.equalsPrevious(io, frozen.view()));
    const reversed = [_]project.Alias{ aliases[1], aliases[0] };
    var reordered = try inputs.Snapshot.init(a, .{ .aliases = &reversed });
    defer reordered.deinit();
    try std.testing.expect(!try reordered.equalsPrevious(io, frozen.view()));
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "entry const answer:U32=43\n" });
    var changed = try inputs.Snapshot.init(a, .{ .aliases = &aliases });
    defer changed.deinit();
    try std.testing.expect(!try changed.equalsPrevious(io, frozen.view()));
    try std.testing.expectEqualStrings(text, frozen.capturedSource(canonical).?);
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = text });
    var failed = try inputs.Snapshot.init(a, .{});
    _ = try failed.read(io, canonical);
    try std.testing.expectError(error.InvalidPath, failed.resolve(path, "unknown/dep"));
    var auxiliary = failed.freeze();
    defer auxiliary.deinit();
    var retry = try inputs.Snapshot.init(a, .{});
    defer retry.deinit();
    try std.testing.expect(!try retry.equalsPrevious(io, auxiliary.view()));
    try std.testing.expectEqual(@as(usize, 1), auxiliary.record.dependencies.imports.items.len);
}

test "trivia-only source changes keep tokens and adjacency; layout and adjacency changes do not" {
    const same = inputs.Snapshot.sameTokens;
    const base =
        \\// a leading comment
        \\const helper = func (x: U32) : U32 => return x
        \\entry const answer = func () => return do:
        \\  let values: Array U32 = #[1, 2]
        \\  break helper values[0]
        \\
    ;
    const cases = [_]struct { from: []const u8, to: []const u8, trivia: bool }{
        .{ .from = "// a leading comment", .to = "// another comment, longer", .trivia = true },
        .{ .from = "=> return x\n", .to = "=> return x // trailing note\n", .trivia = true },
        .{ .from = "func (x: U32)", .to = "func (x:   U32)", .trivia = true },
        // A space between a value and `[` turns indexing into an argument.
        .{ .from = "values[0]", .to = "values [0]", .trivia = false },
        // Adjacent parentheses call; spaced ones group an argument.
        .{ .from = "helper values[0]", .to = "helper(values[0])", .trivia = false },
        // Moving a statement out of the suite changes layout tokens.
        .{ .from = "  break helper", .to = "break helper", .trivia = false },
        .{ .from = "#[1, 2]", .to = "#[1, 3]", .trivia = false },
    };
    for (cases) |case| {
        const changed = try std.mem.replaceOwned(u8, a, base, case.from, case.to);
        defer a.free(changed);
        try std.testing.expect(!std.mem.eql(u8, base, changed));
        try std.testing.expectEqual(case.trivia, try same(a, base, changed));
    }
    try std.testing.expect(try same(a, base, base));
    // A source with lexer diagnostics is never trivia-equal, even to itself;
    // its exact bytes may still match.
    const tabbed = "const answer = do:\n\treturn 1\n";
    try std.testing.expect(!try same(a, tabbed, tabbed));
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, triviaScenario, .{base});
}

fn triviaScenario(allocator: std.mem.Allocator, base: []const u8) !void {
    const same = inputs.Snapshot.sameTokens;
    const changed = try std.mem.replaceOwned(u8, allocator, base, "// a leading comment", "// changed");
    defer allocator.free(changed);
    try std.testing.expect(try same(allocator, base, changed));
}

/// Every observation, looked up through the snapshot, equals a scan of its
/// list; a repeated lookup reads, resolves and digests nothing again.
fn indexScenario(allocator: std.mem.Allocator, root: []const u8, overlay: []const u8) !void {
    const aliases = [_]project.Alias{.{ .prefix = "pkg/", .root = root }};
    const sources = [_]inputs.overlays.Source{.{ .path = overlay, .contents = "const answer:U32=7\n" }};
    var snapshot = try inputs.Snapshot.initWithSources(allocator, io, .{ .aliases = &aliases }, &sources);
    var alive = true;
    defer if (alive) snapshot.deinit();
    const main_path = try std.Io.Dir.path.join(allocator, &.{ root, "main.blot" });
    defer allocator.free(main_path);
    const requests = [_][]const u8{ "./dep", "pkg/dep", "./overlay", "unknown/dep", "./missing" };
    for (0..2) |round| {
        const before = snapshot.counts;
        for (requests) |request| {
            const resolved = snapshot.resolve(main_path, request) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const canonical = snapshot.canonical(io, resolved) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const bytes = snapshot.read(io, canonical) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            const digest = try snapshot.sourceDigest(canonical, bytes);
            try std.testing.expectEqual(format.digest(bytes), digest);
            try std.testing.expectEqualStrings(bytes, snapshot.capturedSource(canonical).?);
        }
        if (round == 1) try std.testing.expectEqualDeep(before, snapshot.counts);
    }
    try std.testing.expectEqual(@as(usize, 5), snapshot.counts.resolutions);
    // Each list position is the one its index names, and keys are distinct.
    for (snapshot.paths.items, 0..) |entry, position| {
        try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.path_index.get(entry.key).?);
        for (snapshot.paths.items[0..position]) |earlier| try std.testing.expect(!std.mem.eql(u8, earlier.key, entry.key));
    }
    for (snapshot.files.items, 0..) |entry, position| try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.file_index.get(entry.key).?);
    for (snapshot.imports.items, 0..) |entry, position| try std.testing.expectEqual(@as(u32, @intCast(position)), snapshot.import_index.get(.{ .source = entry.source, .request = entry.request }).?);
    try std.testing.expectEqual(snapshot.paths.items.len, snapshot.path_index.count());
    try std.testing.expectEqual(snapshot.files.items.len, snapshot.file_index.count());
    try std.testing.expectEqual(snapshot.imports.items.len, snapshot.import_index.count());
    var frozen = snapshot.freeze();
    alive = false;
    defer frozen.deinit();
    // The frozen record answers by scan; its failed observations decline reuse.
    var next = try inputs.Snapshot.initWithSources(allocator, io, .{ .aliases = &aliases }, &sources);
    defer next.deinit();
    try std.testing.expect(!try next.equalsPrevious(io, frozen.view()));
    for (frozen.view().files) |entry| switch (entry.result) {
        .bytes => |bytes| try std.testing.expectEqualStrings(bytes, frozen.capturedSource(entry.key).?),
        .failure => try std.testing.expect(frozen.capturedSource(entry.key) == null),
    };
}

test "revision input indexes answer exactly as list scans and survive every allocation failure" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
    try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const overlay = try std.Io.Dir.path.join(a, &.{ root, "overlay.blot" });
    defer a.free(overlay);
    try indexScenario(a, root, overlay);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, indexScenario, .{ root, overlay });
}
