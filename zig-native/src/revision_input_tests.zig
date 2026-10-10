//! Actual source edits exercise snapshot admission and transactional fallback.
const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const retained = @import("retained_revision.zig");
const inputs = @import("revision_inputs.zig");
const metadata = @import("code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const original = "const value:U32 = 42\nconst read:Unit->U32 = fn () => value\n";
const edited = "const value:U32 = 43\nconst read:Unit->U32 = fn () => value\n";
const main = "import * as dep from \"./dep\"\nentry const answer:Unit->U32 = fn () => dep.read ()\n";
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
const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    seed_bytes: []u8,
    initial_bytes: []u8,
    edited_bytes: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        var value = try seed(a, path, .{});
        defer format.deinit(a, &value);
        const bytes = try format.encode(a, key, value);
        errdefer a.free(bytes);
        var initial = try fresh(path, .{});
        defer initial.deinit(a);
        try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
        const initial_bytes = try a.dupe(u8, initial.result.compiled.bytes);
        errdefer a.free(initial_bytes);
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = edited });
        var changed = try fresh(path, .{});
        defer changed.deinit(a);
        const changed_bytes = try a.dupe(u8, changed.result.compiled.bytes);
        try std.testing.expect(!std.mem.eql(u8, initial_bytes, changed_bytes));
        return .{ .dir = dir, .path = path, .seed_bytes = bytes, .initial_bytes = initial_bytes, .edited_bytes = changed_bytes };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.seed_bytes);
        a.free(self.initial_bytes);
        a.free(self.edited_bytes);
        self.dir.cleanup();
    }
    fn write(self: *Fixture, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = text });
    }
    fn session(self: *const Fixture, allocator: std.mem.Allocator) !retained.Session {
        return retained.Session.init(allocator, try format.decode(D.FrozenDependency, allocator, self.seed_bytes, key), .{});
    }
};
fn currentBytes(session: *const retained.Session, expected: []const u8) !void {
    var result = try session.current.?.prepared.emit(a);
    defer result.deinit(a);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.result.compiled.bytes);
    var emission = try session.current.?.artifacts.emission.materialize(a);
    defer emission.deinit();
    const bytes = try emission.assemble();
    defer a.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes);
}

test "revision input dependency scalar and body edits rebuild exact fresh closure then resume fixed-seed reuse" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    var session = try fixture.session(a);
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    try std.testing.expectEqualSlices(u8, fixture.initial_bytes, initial.result.compiled.bytes);
    try std.testing.expect(!session.last.rebuilt_seed);
    const old_core = session.seed.modules[0].core.nodes.ptr;
    try fixture.write(edited);
    var changed = try session.revise(io, fixture.path, null, .{});
    defer changed.deinit(a);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, changed.result.compiled.bytes);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expect(session.seed.modules[0].core.nodes.ptr != old_core);
    try std.testing.expectEqual(@as(usize, 0), changed.result.compiled.reuse.reused_named + changed.result.compiled.reuse.reused_closures);
    try std.testing.expectEqual(@as(usize, 2), session.last.inputs.source_reads);
    var repeated = try session.revise(io, fixture.path, null, .{});
    defer repeated.deinit(a);
    try std.testing.expect(!session.last.rebuilt_seed);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, repeated.result.compiled.bytes);
    const changed_body = "const value:U32 = 43\nconst read:Unit->U32 = fn () => @u32.add value 1\n";
    try fixture.write(changed_body);
    var expected = try fresh(fixture.path, .{});
    defer expected.deinit(a);
    var body = try session.revise(io, fixture.path, null, .{});
    defer body.deinit(a);
    try equal(&body, &expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expect(!std.mem.eql(u8, changed.result.compiled.bytes, body.result.compiled.bytes));
}

test "revision input changed interface failure recovery and revert leave old seed Core capture and settings intact" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    var session = try fixture.session(a);
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(a);
    const old_core = metadata.stamp(session.current.?.prepared.units);
    const old_emission = metadata.stamp(session.current.?.artifacts.emission.instructions);
    const old_settings = session.seed_settings;
    try fixture.write("const value:F32 = 42.0\nconst read:Unit->F32 = fn () => value\n");
    var expected = try fresh(fixture.path, .{});
    defer expected.deinit(a);
    try std.testing.expect(expected.result.diagnostic != null);
    var failed = try session.revise(io, fixture.path, null, .{});
    defer failed.deinit(a);
    try std.testing.expectEqualStrings(expected.result.diagnostic.?.code, failed.result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
    try std.testing.expectEqualSlices(u8, &old_core, &metadata.stamp(session.current.?.prepared.units));
    try std.testing.expectEqualSlices(u8, &old_emission, &metadata.stamp(session.current.?.artifacts.emission.instructions));
    try std.testing.expectEqualSlices(u8, &old_settings, &session.seed_settings);
    const encoded = try format.encode(a, key, session.seed);
    defer a.free(encoded);
    try std.testing.expectEqualSlices(u8, fixture.seed_bytes, encoded);
    try currentBytes(&session, fixture.initial_bytes);
    // A cached non-OOM filesystem failure travels through Outcome.failure;
    // it must remain an error when the fresh loader consumes that same fact.
    try fixture.dir.dir.deleteFile(io, "dep.blot");
    var missing_expected = try fresh(fixture.path, .{});
    defer missing_expected.deinit(a);
    var missing = try session.revise(io, fixture.path, null, .{});
    defer missing.deinit(a);
    try std.testing.expectEqualStrings("missing_file", missing.result.diagnostic.?.code);
    try std.testing.expectEqualStrings(missing_expected.result.diagnostic.?.code, missing.result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
    try currentBytes(&session, fixture.initial_bytes);
    try fixture.write(edited);
    var correction = try session.revise(io, fixture.path, null, .{});
    defer correction.deinit(a);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, correction.result.compiled.bytes);
    try std.testing.expect(session.last.rebuilt_seed);
    try fixture.write(original);
    var reverted = try session.revise(io, fixture.path, null, .{});
    defer reverted.deinit(a);
    try std.testing.expectEqualSlices(u8, fixture.initial_bytes, reverted.result.compiled.bytes);
    try std.testing.expect(session.last.rebuilt_seed);
}

test "revision input import resolution settings and closure membership changes rebuild instead of borrowing old catalog" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "other.blot", .data = edited });
    var session = try fixture.session(a);
    defer session.deinit();
    var first = try session.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import * as dep from \"./other\"\nentry const answer:Unit->U32 = fn () => dep.read ()\n" });
    var expected = try fresh(fixture.path, .{});
    defer expected.deinit(a);
    var moved = try session.revise(io, fixture.path, null, .{});
    defer moved.deinit(a);
    try equal(&moved, &expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expect(std.mem.endsWith(u8, session.seed.modules[0].identity.normalized_path, "other.blot"));
    const before = session.seed_settings;
    const options: project.Options = .{ .max_files = 16 };
    var settings_expected = try fresh(fixture.path, options);
    defer settings_expected.deinit(a);
    var configured = try session.revise(io, fixture.path, null, options);
    defer configured.deinit(a);
    try equal(&configured, &settings_expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expect(!std.mem.eql(u8, &before, &session.seed_settings));
    const limit: project.Options = .{ .max_files = 1 };
    var rejected = try session.revise(io, fixture.path, null, limit);
    defer rejected.deinit(a);
    try std.testing.expectEqualStrings("file_limit", rejected.result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 3), session.revisions);
    try currentBytes(&session, configured.result.compiled.bytes);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import * as other from \"./other\"\nimport * as dep from \"./dep\"\nentry const answer:Unit->U32=fn () => @u32.add (other.read ()) (dep.read ())\n" });
    var enlarged_expected = try fresh(fixture.path, options);
    defer enlarged_expected.deinit(a);
    var enlarged = try session.revise(io, fixture.path, null, options);
    defer enlarged.deinit(a);
    try equal(&enlarged, &enlarged_expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expectEqual(@as(usize, 2), session.seed.modules.len);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "entry const answer:Unit->U32 = fn () => 42\n" });
    var no_dep_expected = try fresh(fixture.path, options);
    defer no_dep_expected.deinit(a);
    var no_dep = try session.revise(io, fixture.path, null, options);
    defer no_dep.deinit(a);
    try equal(&no_dep, &no_dep_expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expectEqual(@as(usize, 0), session.seed.modules.len);
}

test "revision input snapshot owns mutable options and reuses captured bytes and canonical decisions after filesystem changes" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    const root = std.Io.Dir.path.dirname(fixture.path).?;
    const alias_root = try a.dupe(u8, root);
    defer a.free(alias_root);
    var aliases = [_]project.Alias{.{ .prefix = "pkg/", .root = alias_root }};
    var snapshot = try inputs.Snapshot.init(a, .{ .aliases = &aliases });
    defer snapshot.deinit();
    @memset(alias_root, 'x');
    aliases[0].prefix = "changed/";
    const resolved = try snapshot.resolve(fixture.path, "pkg/dep");
    const canonical = try snapshot.canonical(io, resolved);
    const captured = try snapshot.read(io, canonical);
    try std.testing.expectEqualStrings(original, captured);
    try fixture.write(edited);
    var source = try project.loadWithInputs(a, io, fixture.path, snapshot.options, snapshot.provider());
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    try std.testing.expectEqualStrings(original, source.unit(2).source);
    try std.testing.expectEqualStrings(original, try snapshot.read(io, canonical));
    try std.testing.expectEqual(@as(usize, 2), snapshot.counts.source_reads);
    _ = try snapshot.resolve(fixture.path, "pkg/dep");
    try std.testing.expectEqual(@as(usize, 2), snapshot.counts.resolutions); // pkg/dep + actual ./dep
    var next = try inputs.Snapshot.init(a, .{});
    defer next.deinit();
    try std.testing.expectEqualStrings(edited, try next.read(io, canonical));
}

test "revision input unchanged producer text with retargeted dependency symlink uses actual canonical closure" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import * as lib from \"./library\"\nentry const answer:U32=lib.answer\n" });
    try dir.dir.writeFile(io, .{ .sub_path = "library.blot", .data = "import * as dep from \"./chosen\"\nconst answer:U32=dep.answer\n" });
    try dir.dir.writeFile(io, .{ .sub_path = "a.blot", .data = "const answer:U32=42\n" });
    try dir.dir.writeFile(io, .{ .sub_path = "b.blot", .data = "const answer:U32=43\n" });
    try dir.dir.symLink(io, "a.blot", "chosen.blot", .{});
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    var session = retained.Session.init(a, try seed(a, path, .{}), .{});
    defer session.deinit();
    var first = try session.revise(io, path, null, .{});
    defer first.deinit(a);
    try dir.dir.deleteFile(io, "chosen.blot");
    try dir.dir.symLink(io, "b.blot", "chosen.blot", .{});
    var expected = try fresh(path, .{});
    defer expected.deinit(a);
    var changed = try session.revise(io, path, null, .{});
    defer changed.deinit(a);
    try equal(&changed, &expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expect(!std.mem.eql(u8, first.result.compiled.bytes, changed.result.compiled.bytes));
    try dir.dir.deleteFile(io, "chosen.blot");
    try dir.dir.symLink(io, "a.blot", "chosen.blot", .{});
    var reverted = try session.revise(io, path, null, .{});
    defer reverted.deinit(a);
    try std.testing.expectEqualSlices(u8, first.result.compiled.bytes, reverted.result.compiled.bytes);
    try std.testing.expect(session.last.rebuilt_seed);
}

test "revision input backend staging failure after fresh dependency freeze retains published old owners" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\n" });
    var session = retained.Session.init(a, try seed(a, fixture.path, .{}), .{});
    defer session.deinit();
    var first = try session.revise(io, fixture.path, null, .{});
    defer first.deinit(a);
    const old_seed = try format.encode(a, key, session.seed);
    defer a.free(old_seed);
    try fixture.write("const value:U32=42\nconst read:Unit->U32=fn () => read ()\n");
    var reference = try fresh(fixture.path, .{});
    defer reference.deinit(a);
    try std.testing.expect(reference.result.diagnostic == null and reference.result.compiled.diagnostic != null);
    var failed = try session.revise(io, fixture.path, null, .{});
    defer failed.deinit(a);
    try std.testing.expectEqual(reference.result.compiled.diagnostic.?.code, failed.result.compiled.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
    const after = try format.encode(a, key, session.seed);
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, old_seed, after);
    try currentBytes(&session, first.result.compiled.bytes);
    try fixture.write(original);
    var recovered = try session.revise(io, fixture.path, null, .{});
    defer recovered.deinit(a);
    try std.testing.expectEqualSlices(u8, first.result.compiled.bytes, recovered.result.compiled.bytes);
    try std.testing.expect(!session.last.rebuilt_seed);
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
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, freezeInputs, .{path});
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

fn allocationCandidate(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    try fixture.write(original);
    var session = try fixture.session(allocator);
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(allocator);
    try fixture.write(edited);
    var candidate = session.revise(io, fixture.path, null, .{}) catch |err| {
        if (err == error.OutOfMemory) {
            try std.testing.expectEqual(@as(usize, 1), session.revisions);
            const encoded = try format.encode(a, key, session.seed);
            defer a.free(encoded);
            try std.testing.expectEqualSlices(u8, fixture.seed_bytes, encoded);
            try currentBytes(&session, fixture.initial_bytes);
        }
        return err;
    };
    defer candidate.deinit(allocator);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, candidate.result.compiled.bytes);
    try std.testing.expect(session.last.rebuilt_seed);
}
test "revision input every candidate allocation failure preserves old dependency and published capture" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, allocationCandidate, .{&fixture});
    try fixture.write(edited);
    var session = try fixture.session(a);
    defer session.deinit();
    var retry = try session.revise(io, fixture.path, null, .{});
    defer retry.deinit(a);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, retry.result.compiled.bytes);
}

test "revision input failed candidate retries in same Session then reverts without stale owner publication" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    var failing = std.testing.FailingAllocator.init(a, .{});
    const allocator = failing.allocator();
    var session = try fixture.session(allocator);
    defer session.deinit();
    var initial = try session.revise(io, fixture.path, null, .{});
    defer initial.deinit(allocator);
    try fixture.write(edited);
    failing.fail_index = failing.alloc_index + 96;
    try std.testing.expectError(error.OutOfMemory, session.revise(io, fixture.path, null, .{}));
    try std.testing.expectEqual(@as(usize, 1), session.revisions);
    try currentBytes(&session, fixture.initial_bytes);
    failing.fail_index = std.math.maxInt(usize);
    var retry = try session.revise(io, fixture.path, null, .{});
    defer retry.deinit(allocator);
    try std.testing.expectEqualSlices(u8, fixture.edited_bytes, retry.result.compiled.bytes);
    try fixture.write(original);
    var revert = try session.revise(io, fixture.path, null, .{});
    defer revert.deinit(allocator);
    try std.testing.expectEqualSlices(u8, fixture.initial_bytes, revert.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, 3), session.revisions);
}

test "revision input removed dependencies use fresh byte limits before returning a cached-prefix rejection" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try fixture.write(original);
    const options: project.Options = .{ .max_total_source_bytes = main.len + original.len + 8 };
    var session = retained.Session.init(a, try seed(a, fixture.path, options), options);
    defer session.deinit();
    var first = try session.revise(io, fixture.path, null, options);
    defer first.deinit(a);
    const prefix = "entry const answer:Unit->U32=fn () => 42\n//";
    const enlarged = try a.alloc(u8, options.max_total_source_bytes - 8);
    defer a.free(enlarged);
    @memcpy(enlarged[0..prefix.len], prefix);
    @memset(enlarged[prefix.len..], 'x');
    try std.testing.expect(enlarged.len <= options.max_total_source_bytes and enlarged.len > options.max_total_source_bytes - original.len);
    try fixture.dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = enlarged });
    var expected = try fresh(fixture.path, options);
    defer expected.deinit(a);
    var changed = try session.revise(io, fixture.path, null, options);
    defer changed.deinit(a);
    try equal(&changed, &expected);
    try std.testing.expect(session.last.rebuilt_seed);
    try std.testing.expectEqual(@as(usize, 0), session.seed.modules.len);
}
