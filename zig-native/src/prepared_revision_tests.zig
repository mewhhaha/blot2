const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const core = @import("core.zig");
const backend = @import("core_backend.zig");
const identity = @import("runtime_identity.zig");
const closure = @import("dependency_closure.zig");
const format = @import("dependency_format.zig");
const D = @import("frozen_dependency.zig");
const partial = @import("partial_dependency.zig");
const a = std.testing.allocator;
const key: format.Key = .{ .compiler = @splat(7), .settings = @splat(8), .source = @splat(9), .dependencies = @splat(10) };
const source = @embedFile("partial-runtime-fixtures/namespace-ab.blot");
const second_source = blk: {
    @setEvalBranchQuota(10000);
    const at = std.mem.indexOf(u8, replace_provider, "effect Local").?;
    break :blk replace_provider[0..at] ++ "const unrelated=fn value=>identity value\ndata Before=#Before U32\n" ++ replace_provider[at..];
};
const replace_provider = blk: {
    @setEvalBranchQuota(10000);
    const needle = "fn () => 0.75";
    const at = std.mem.indexOf(u8, source, needle).?;
    break :blk source[0..at] ++ "fn () => 1.75" ++ source[at + needle.len ..];
};
const invalid_source = "entry const invalid=identity 4294967296\n";
const prelude = "const identity=fn value=>value\n";

fn preparedContext(allocator: std.mem.Allocator, path: []const u8) !void {
    for ([_]project.InputMode{ .project, .source }) |mode| {
        var loaded = try project.load(allocator, std.testing.io, path, .{ .input_mode = mode });
        var loaded_alive = true;
        defer if (loaded_alive) loaded.deinit(allocator);
        const empty: D.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
        var preparation = try partial.prepareProject(allocator, &loaded, path, null, &empty);
        var preparation_alive = true;
        defer if (preparation_alive) preparation.deinit(allocator);
        try std.testing.expect(preparation == .ready);
        loaded.deinit(allocator);
        loaded_alive = false;
        var result = try preparation.ready.emitWithOptions(allocator, .{});
        defer result.deinit(allocator);
        preparation.deinit(allocator);
        preparation_alive = false;
        const diagnostic = result.result.compiled.diagnostic orelse return error.MissingDiagnostic;
        try std.testing.expectEqual(backend.Code.missing_field, diagnostic.code);
        try std.testing.expectEqual(core.Span{ .start = 81, .end = 81 }, diagnostic.span);
        try std.testing.expectEqualStrings(if (mode == .source)
            "no field read on main::Box"
        else
            "no field read on renamed.blot::Box", diagnostic.message());
        try std.testing.expectEqualStrings(path, result.diagnostic_filename.?);
    }
}

fn contextFixture() !std.testing.TmpDir {
    var dir = std.testing.tmpDir(.{});
    errdefer dir.cleanup();
    try dir.dir.writeFile(std.testing.io, .{ .sub_path = "renamed.blot", .data = "type Box is data = #Box U32\nconst Box.read = fn value => 42\nconst select: a -> b where {field \"read\" a b} = fn value => value.read\nentry const answer = fn () => select (#Box 1)\n" });
    return dir;
}

test "Prepared context preserves actual source mode after frontend Core and identity teardown" {
    var dir = try contextFixture();
    defer dir.cleanup();
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "renamed.blot", a);
    defer a.free(path);
    try preparedContext(a, path);
}

test "Prepared context publication releases every failed allocation" {
    var dir = try contextFixture();
    defer dir.cleanup();
    const path = try dir.dir.realPathFileAlloc(std.testing.io, "renamed.blot", a);
    defer a.free(path);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, preparedContext, .{path});
}

const SourceReady = struct {
    units: []core.Module,
    names: identity.Metadata,
    entry: u32,
    fn deinit(self: *SourceReady, allocator: std.mem.Allocator) void {
        self.names.deinit(allocator);
        for (self.units) |*unit| unit.deinit(allocator);
        allocator.free(self.units);
    }
};
fn lowerSource(allocator: std.mem.Allocator, path: []const u8, prelude_path: []const u8) !SourceReady {
    var loaded = try project.load(allocator, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    try std.testing.expectEqual(@as(usize, 4), loaded.units.items.len);
    var checked = try checker.checkProject(allocator, &loaded);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| std.debug.print("source {s}:{d}\n", .{ issue.codeName(), issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try allocator.alloc(core.Module, loaded.units.items.len);
    var initialized: usize = 0;
    var transferred = false;
    defer if (!transferred) {
        for (units[0..initialized]) |*unit| unit.deinit(allocator);
        allocator.free(units);
    };
    for (units, 1..) |*unit, id| {
        unit.* = try core.lower(allocator, &loaded.unit(@intCast(id)).tree, &loaded.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
        try std.testing.expectEqual(@as(usize, 0), unit.diagnostics.len);
    }
    const owners = try allocator.alloc(identity.Owner, units.len);
    defer allocator.free(owners);
    for (owners, 1..) |*owner, id| owner.* = .{ .unit = @intCast(id), .path = loaded.filename(@intCast(id)) };
    const names = try identity.Metadata.capture(allocator, &loaded.symbols, owners, owners.len);
    transferred = true;
    return .{ .units = units, .names = names, .entry = loaded.entry };
}
fn compileSource(allocator: std.mem.Allocator, path: []const u8, prelude_path: []const u8) !backend.Result {
    // No source, syntax, symbol pool or inference owner survives lowerSource.
    var ready = try lowerSource(allocator, path, prelude_path);
    defer ready.deinit(allocator);
    return backend.compileWithIdentity(allocator, ready.units, ready.entry, ready.names.view());
}
fn freeze(path: []const u8, prelude_path: []const u8) ![]u8 {
    var loaded = try project.load(a, std.testing.io, path, .{ .prelude_path = prelude_path });
    defer loaded.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), loaded.diagnostics.items.len);
    var checked = try checker.checkProject(a, &loaded);
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    var frozen = try closure.freeze(a, &loaded, &checked);
    defer format.deinit(a, &frozen);
    return format.encode(a, key, frozen);
}

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude_path: [:0]u8,
    seed: []u8,
    first_expected: []u8,
    second_expected: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        inline for (.{ .{ "a.blot", @embedFile("partial-runtime-fixtures/a.blot") }, .{ "b.blot", @embedFile("partial-runtime-fixtures/b.blot") }, .{ "main.blot", source }, .{ "prelude.blot", prelude }, .{ "seed.blot", "entry const initial:Unit->U32=fn()=>0\n" } }) |file| try dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        errdefer a.free(path);
        const prelude_path = try dir.dir.realPathFileAlloc(std.testing.io, "prelude.blot", a);
        errdefer a.free(prelude_path);
        const seed_path = try dir.dir.realPathFileAlloc(std.testing.io, "seed.blot", a);
        defer a.free(seed_path);
        const seed = try freeze(seed_path, prelude_path);
        errdefer a.free(seed);
        var first = try compileSource(a, path, prelude_path);
        defer first.deinit(a);
        try std.testing.expect(first.diagnostic == null);
        const first_expected = try a.dupe(u8, first.bytes);
        errdefer a.free(first_expected);
        try dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = second_source });
        var second = try compileSource(a, path, prelude_path);
        defer second.deinit(a);
        try std.testing.expect(second.diagnostic == null);
        try std.testing.expect(!std.mem.eql(u8, first.bytes, second.bytes));
        return .{ .dir = dir, .path = path, .prelude_path = prelude_path, .seed = seed, .first_expected = first_expected, .second_expected = try a.dupe(u8, second.bytes) };
    }
    fn reset(self: *Fixture) !void {
        inline for (.{ .{ "a.blot", @embedFile("partial-runtime-fixtures/a.blot") }, .{ "b.blot", @embedFile("partial-runtime-fixtures/b.blot") }, .{ "main.blot", source }, .{ "prelude.blot", prelude } }) |file| try self.dir.dir.writeFile(std.testing.io, .{ .sub_path = file[0], .data = file[1] });
    }
    fn removeSources(self: *Fixture) !void {
        inline for (.{ "a.blot", "b.blot", "main.blot", "prelude.blot" }) |file| try self.dir.dir.deleteFile(std.testing.io, file);
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude_path);
        a.free(self.seed);
        a.free(self.first_expected);
        a.free(self.second_expected);
        self.dir.cleanup();
    }
};
fn prepareReady(allocator: std.mem.Allocator, fixture: *Fixture, dependency: *D.FrozenDependency) !partial.Prepared {
    switch (try partial.prepare(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, dependency)) {
        .ready => |prepared| return prepared,
        .rejected => |rejected| {
            var result = rejected;
            defer result.deinit(allocator);
            if (result.result.diagnostic) |issue| std.debug.print("prepare {s}:{d} {s}\n", .{ issue.code, issue.start, issue.message });
            return error.TestUnexpectedResult;
        },
    }
}
fn checkEmission(allocator: std.mem.Allocator, prepared: *const partial.Prepared, expected: []const u8) !void {
    var result = try prepared.emit(allocator);
    defer result.deinit(allocator);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.result.compiled.bytes);
    try std.testing.expectEqual(@as(usize, 1), result.cached_modules);
    try std.testing.expectEqual(@as(usize, 3), result.fresh_modules);
}
fn unchangedSeed(allocator: std.mem.Allocator, fixture: *const Fixture, dependency: *const D.FrozenDependency) !void {
    const after = try format.encode(allocator, key, dependency.*);
    defer allocator.free(after);
    try std.testing.expectEqualSlices(u8, fixture.seed, after);
}
fn revisions(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    try fixture.reset();
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.seed, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    var first = try prepareReady(allocator, fixture, &dependency);
    defer first.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 4), first.units.len);
    try std.testing.expectEqual(@as(usize, 1), first.cached);
    try std.testing.expectEqualStrings(fixture.path, first.paths[first.entry - 1]);
    try std.testing.expectEqualStrings(fixture.path, first.identity.view().owner(first.entry).?);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = second_source });
    var second = try prepareReady(allocator, fixture, &dependency);
    defer second.deinit(allocator);
    try std.testing.expect(first.identity.bytes.ptr != second.identity.bytes.ptr);
    try std.testing.expect(first.units[first.entry - 1].nodes.ptr != second.units[second.entry - 1].nodes.ptr);
    try std.testing.expectEqual(dependency.modules[0].core.nodes.ptr, first.units[0].nodes.ptr);
    try std.testing.expectEqual(dependency.modules[0].core.nodes.ptr, second.units[0].nodes.ptr);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = invalid_source });
    var third = partial.prepare(allocator, std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }, &dependency) catch |err| {
        if (err != error.OutOfMemory) return err;
        // The third candidate's allocation failure must not damage either live
        // prepared revision. Emission uses the independent validating backing
        // allocator because the injected allocator is now intentionally failing.
        try unchangedSeed(a, fixture, &dependency);
        try fixture.removeSources();
        try checkEmission(a, &first, fixture.first_expected);
        try checkEmission(a, &second, fixture.second_expected);
        return error.OutOfMemory;
    };
    defer third.deinit(allocator);
    switch (third) {
        .ready => return error.TestUnexpectedResult,
        .rejected => |result| {
            try std.testing.expectEqualStrings("integer_range", result.result.diagnostic.?.code);
            try std.testing.expectEqualStrings(fixture.path, result.diagnostic_filename.?);
            try std.testing.expectEqual(@as(usize, 0), result.result.stats.body_elaborations);
            try std.testing.expectEqual(@as(usize, 0), result.result.compiled.bytes.len);
        },
    }
    try unchangedSeed(allocator, fixture, &dependency);
    // Deleting every source file makes any accidental source/loader lookup by
    // emission fail. All frontend and inference owners were already destroyed.
    try fixture.removeSources();
    try checkEmission(allocator, &first, fixture.first_expected);
    try checkEmission(allocator, &second, fixture.second_expected);
    // Repeating after independent emission must preserve both retained bodies.
    try checkEmission(allocator, &first, fixture.first_expected);
    try unchangedSeed(allocator, fixture, &dependency);
}
test "prepared revisions independently own Core and runtime identity after rejected revision and source removal" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try revisions(a, &fixture);
}
test "prepared simultaneous revisions preserve prior emissions and seed across every failed allocation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, revisions, .{&fixture});
}

const deferred_witness_source = "entry const failure = @type.same (@panic \"left witness\") (@panic \"right witness\")\n";
fn checkDeferredWitness(result: *const partial.Result, fixture: *const Fixture) !void {
    try std.testing.expect(result.result.diagnostic == null);
    const diagnostic = result.result.compiled.diagnostic.?;
    try std.testing.expectEqual(backend.Code.invalid_annotation, diagnostic.code);
    try std.testing.expectEqualStrings("Never is an internal control-flow type", diagnostic.message());
    try std.testing.expectEqualStrings(fixture.path, result.diagnostic_filename.?);
    try std.testing.expect(result.diagnostic_filename.?.ptr != fixture.path.ptr);
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.constant_steps);
    try std.testing.expectEqual(@as(usize, 0), result.result.compiled.bytes.len);
}
fn deferredWitnessRevision(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    try fixture.reset();
    var dependency = try format.decode(D.FrozenDependency, allocator, fixture.seed, key);
    defer format.deinit(allocator, &dependency);
    try closure.validate(allocator, &dependency);
    var first = try prepareReady(allocator, fixture, &dependency);
    defer first.deinit(allocator);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = second_source });
    var second = try prepareReady(allocator, fixture, &dependency);
    defer second.deinit(allocator);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = deferred_witness_source });
    // Frontend lowering succeeds. Entry/witness validation belongs to emission
    // and must still diagnose after every source/frontend owner disappears.
    var rejected = prepareReady(allocator, fixture, &dependency) catch |err| {
        try fixture.removeSources();
        try checkEmission(a, &first, fixture.first_expected);
        try checkEmission(a, &second, fixture.second_expected);
        try unchangedSeed(a, fixture, &dependency);
        return err;
    };
    var rejected_alive = true;
    defer if (rejected_alive) rejected.deinit(allocator);
    try fixture.removeSources();
    var failure = rejected.emit(allocator) catch |err| {
        try checkEmission(a, &first, fixture.first_expected);
        try checkEmission(a, &second, fixture.second_expected);
        try unchangedSeed(a, fixture, &dependency);
        return err;
    };
    defer failure.deinit(allocator);
    // A failed emitted candidate owns its message/path independently from its
    // Prepared. Retain it while emitting earlier revisions more than once.
    rejected.deinit(allocator);
    rejected_alive = false;
    try checkDeferredWitness(&failure, fixture);
    try checkEmission(allocator, &first, fixture.first_expected);
    try checkEmission(allocator, &second, fixture.second_expected);
    try checkEmission(allocator, &first, fixture.first_expected);
    try unchangedSeed(allocator, fixture, &dependency);
    try checkDeferredWitness(&failure, fixture);
}
test "prepared deferred witness rejection owns diagnostics after teardown and preserves earlier revisions and seed" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try deferredWitnessRevision(a, &fixture);
}
test "prepared deferred witness candidates preserve earlier revisions through every preparation and emission allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, deferredWitnessRevision, .{&fixture});
}

const retained = @import("retained_revision.zig");
const metadata = @import("code_artifacts.zig");
const retained_prelude = "const identity=fn value=>value\nconst factory=fn value=>fn more=>@f32.add value more\n";
const retained_first =
    \\import * as alpha from "./a"
    \\import * as beta from "./b"
    \\entry const answer: F32 -> F32 = fn value => do:
    \\  let add = factory value
    \\  return identity (add 1.25)
    \\entry const folded = identity 11
;
const retained_second =
    \\import * as alpha from "./a"
    \\import * as beta from "./b"
    \\entry const answer: F32 -> F32 = fn value => do:
    \\  let add = factory value
    \\  return identity (add 2.25)
    \\entry const folded = identity 12
;
fn retainedFixture() !Fixture {
    var fixture = try Fixture.init();
    errdefer fixture.deinit();
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "prelude.blot", .data = retained_prelude });
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = retained_first });
    // Retained entry laws now start from the complete admitted dependency
    // closure; incomplete seeds use the new explicit checked rebuild gate.
    const encoded = try freeze(fixture.path, fixture.prelude_path);
    errdefer a.free(encoded);
    var first = try compileSource(a, fixture.path, fixture.prelude_path);
    defer first.deinit(a);
    try std.testing.expect(first.diagnostic == null);
    const first_expected = try a.dupe(u8, first.bytes);
    errdefer a.free(first_expected);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = retained_second });
    var second = try compileSource(a, fixture.path, fixture.prelude_path);
    defer second.deinit(a);
    try std.testing.expect(second.diagnostic == null);
    const second_expected = try a.dupe(u8, second.bytes);
    a.free(fixture.seed);
    a.free(fixture.first_expected);
    a.free(fixture.second_expected);
    fixture.seed = encoded;
    fixture.first_expected = first_expected;
    fixture.second_expected = second_expected;
    return fixture;
}
fn checkRetainedResult(result: *const partial.Result, expected: []const u8) !void {
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.result.compiled.bytes);
    try std.testing.expect(result.result.compiled.capture == null);
}
fn checkCurrent(session: *const retained.Session, fixture: *const Fixture, expected: []const u8) !void {
    try unchangedSeed(a, fixture, &session.seed);
    const current = &session.current.?;
    var emitted = try current.prepared.emit(a);
    defer emitted.deinit(a);
    try checkRetainedResult(&emitted, expected);
    var replayed = try current.artifacts.emission.materialize(a);
    defer replayed.deinit();
    const bytes = try replayed.assemble();
    defer a.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes);
}
fn retainedRevisions(allocator: std.mem.Allocator, fixture: *Fixture) !void {
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = retained_first });
    var admitted = try format.decode(D.FrozenDependency, allocator, fixture.seed, key);
    var admitted_alive = true;
    defer if (admitted_alive) format.deinit(allocator, &admitted);
    try closure.validate(allocator, &admitted);
    var session = retained.Session.init(allocator, admitted, .{ .prelude_path = fixture.prelude_path });
    admitted_alive = false;
    defer session.deinit();
    var first = try session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path });
    defer first.deinit(allocator);
    try checkRetainedResult(&first, fixture.first_expected);
    const core_stamp = metadata.stamp(session.current.?.prepared.units);
    const body_stamp = metadata.stamp(session.current.?.artifacts.emission.instructions);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = retained_second });
    var second = session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path }) catch |err| {
        if (err == error.OutOfMemory) {
            try std.testing.expectEqualSlices(u8, &core_stamp, &metadata.stamp(session.current.?.prepared.units));
            try std.testing.expectEqualSlices(u8, &body_stamp, &metadata.stamp(session.current.?.artifacts.emission.instructions));
            try checkCurrent(&session, fixture, fixture.first_expected);
        }
        return err;
    };
    defer second.deinit(allocator);
    try checkRetainedResult(&second, fixture.second_expected);
    const counts = second.result.compiled.reuse;
    std.debug.print("retained counts {any}\n", .{counts});
    try std.testing.expect(counts.reused_named + counts.reused_closures > 0);
    try std.testing.expect(counts.fresh_named > 0); // Entry stays fresh.
    try checkCurrent(&session, fixture, fixture.second_expected);
}
test "retained revision performs valid pre-refinement hits with fresh entry and staging roots" {
    var fixture = try retainedFixture();
    defer fixture.deinit();
    try retainedRevisions(a, &fixture);
}

test "retained history keeps prior ownership through error correction revert and catalog changes" {
    var fixture = try retainedFixture();
    defer fixture.deinit();
    const seed = try format.decode(D.FrozenDependency, a, fixture.seed, key);
    var session = retained.Session.init(a, seed, .{ .prelude_path = fixture.prelude_path });
    defer session.deinit();
    for ([_][]const u8{ retained_first, retained_second }) |text| {
        try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = text });
        var result = try session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path });
        defer result.deinit(a);
        try checkRetainedResult(&result, if (std.mem.eql(u8, text, retained_first)) fixture.first_expected else fixture.second_expected);
    }
    const before_core = metadata.stamp(session.current.?.prepared.units);
    const before_bodies = metadata.stamp(session.current.?.artifacts.emission.instructions);
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = invalid_source });
    var rejected = try session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path });
    defer rejected.deinit(a);
    try std.testing.expectEqualStrings("integer_range", rejected.result.diagnostic.?.code);
    try std.testing.expectEqual(@as(usize, 2), session.revisions);
    try std.testing.expectEqualSlices(u8, &before_core, &metadata.stamp(session.current.?.prepared.units));
    try std.testing.expectEqualSlices(u8, &before_bodies, &metadata.stamp(session.current.?.artifacts.emission.instructions));
    try checkCurrent(&session, &fixture, fixture.second_expected);
    for ([_][]const u8{ retained_first, retained_second, retained_first }) |text| {
        try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = text });
        var result = try session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path });
        defer result.deinit(a);
        try checkRetainedResult(&result, if (std.mem.eql(u8, text, retained_first)) fixture.first_expected else fixture.second_expected);
        try std.testing.expect(result.result.compiled.reuse.reused_named > 0);
        try unchangedSeed(a, &fixture, &session.seed);
    }
    const changed_catalog =
        \\import * as alpha from "./a"
        \\import * as beta from "./b"
        \\effect Added: Unit -> Unit
        \\data Extra = #Extra U32
        \\entry const answer: F32 -> F32 = fn value => do:
        \\  let add = factory value
        \\  return identity (add 1.25)
        \\entry const folded = identity 11
    ;
    try fixture.dir.dir.writeFile(std.testing.io, .{ .sub_path = "main.blot", .data = changed_catalog });
    var expected = try compileSource(a, fixture.path, fixture.prelude_path);
    defer expected.deinit(a);
    var changed = try session.revise(std.testing.io, fixture.path, null, .{ .prelude_path = fixture.prelude_path });
    defer changed.deinit(a);
    try checkRetainedResult(&changed, expected.bytes);
    try std.testing.expectEqual(@as(usize, 0), changed.result.compiled.reuse.reused_named + changed.result.compiled.reuse.reused_closures);
    try unchangedSeed(a, &fixture, &session.seed);
}

test "retained candidate allocation failures leave seed and successful prior Core and capture unchanged" {
    var fixture = try retainedFixture();
    defer fixture.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, retainedRevisions, .{&fixture});
}
