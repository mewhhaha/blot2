//! Laws for restart-cache dependency seeds: a session started from one checks
//! only what changed and equals fresh builds, and foreign or damaged seeds are
//! refused.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const format = @import("dependency_format.zig");
const settings = @import("dependency_cli.zig").settings;
const a = std.testing.allocator;
const io = std.testing.io;
const compiler: [32]u8 = @splat(9);
const main = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\n";
const main_edited = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\nentry const other:U32=7\n";
const original = "const value:U32=42\nconst read:Unit->U32=func () => return value\n";
const edited = "const value:U32=43\nconst read:Unit->U32=func () => return value\n";

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
        return .{ .dir = dir, .path = try dir.dir.realPathFileAlloc(io, "main.blot", a) };
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        self.dir.cleanup();
    }
};
fn fresh(fixture: *const Fixture) ![]u8 {
    var source = try project.load(a, io, fixture.path, .{});
    defer source.deinit(a);
    const empty: dependency.FrozenDependency = .{ .symbols = &.{}, .modules = &.{} };
    var preparation = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    defer preparation.deinit(a);
    var result = try preparation.ready.emit(a);
    defer result.deinit(a);
    return a.dupe(u8, result.result.compiled.bytes);
}
/// The seed bytes a session's first build of `fixture` persists.
fn populated(fixture: *const Fixture) ![]u8 {
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    return (try session.encodeSeed(a, compiler)).?;
}
fn seeded(allocator: std.mem.Allocator, bytes: []const u8) !retained.Session {
    var session = try retained.Session.initEmpty(allocator, .{});
    errdefer session.deinit();
    var seed = try retained.decodeSeed(allocator, compiler, settings(.{}), bytes);
    session.adoptCachedSeed(seed) catch |err| {
        format.deinit(allocator, &seed);
        return err;
    };
    return session;
}
fn expectFresh(session: *retained.Session, fixture: *const Fixture, rebuilt: bool) !void {
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    try std.testing.expect(result.result.diagnostic == null and result.result.compiled.diagnostic == null);
    const expected = try fresh(fixture);
    defer a.free(expected);
    try std.testing.expectEqualSlices(u8, expected, result.result.compiled.bytes);
    try std.testing.expectEqual(rebuilt, session.last.rebuilt_seed);
}

test "restart cache: a cached seed checks only what changed and equals fresh builds" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    {
        // Unchanged dependencies admit the seed: no rebuild, entry checked
        // against it; then an entry edit and a dependency edit.
        var session = try seeded(a, bytes);
        defer session.deinit();
        try expectFresh(&session, &fixture, false);
        try fixture.write("main.blot", main_edited);
        try expectFresh(&session, &fixture, false);
        try fixture.write("dep.blot", edited);
        try expectFresh(&session, &fixture, true);
    }
    // A dependency that changed before the first build rebuilds from the
    // stale seed.
    try fixture.write("main.blot", main);
    var session = try seeded(a, bytes);
    defer session.deinit();
    try expectFresh(&session, &fixture, true);
    try fixture.write("dep.blot", original);
    try expectFresh(&session, &fixture, true);
}

test "restart cache: seeds from other compilers or settings, or damaged, are refused" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, retained.decodeSeed(a, @splat(8), settings(.{}), bytes));
    try std.testing.expectError(error.StaleArtifact, retained.decodeSeed(a, compiler, settings(.{ .prelude_path = "/other/prelude.blot" }), bytes));
    const damaged = try a.dupe(u8, bytes);
    defer a.free(damaged);
    damaged[damaged.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, retained.decodeSeed(a, compiler, settings(.{}), damaged));
    // Only a session with nothing compiled takes a cached seed.
    var session = try seeded(a, bytes);
    defer session.deinit();
    var again = try retained.decodeSeed(a, compiler, settings(.{}), bytes);
    defer format.deinit(a, &again);
    try std.testing.expectError(error.SeedInUse, session.adoptCachedSeed(again));
}

fn seedOnce(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var session = try seeded(allocator, bytes);
    session.deinit();
}

test "restart cache: cached seeds decode and adopt under allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, seedOnce, .{bytes});
}
