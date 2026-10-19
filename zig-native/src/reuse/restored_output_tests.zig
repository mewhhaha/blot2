//! Laws for restoring a previous process's output from the restart cache: it
//! publishes only on exactly equal inputs, equals a fresh build, and rejects
//! foreign or damaged bytes.
const std = @import("std");
const retained = @import("retained_revision.zig");
const project = @import("project.zig");
const partial = @import("partial_dependency.zig");
const dependency = @import("frozen_dependency.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const compiler: [32]u8 = @splat(5);
const main = "import * as dep from \"./dep\"\nentry const answer:U32=dep.read ()\n";
const original = "const value:U32=42\nconst read:Unit->U32=fn () => value\n";
const edited = "const value:U32=43\nconst read:Unit->U32=fn () => value\n";

const Fixture = struct {
    dir: std.testing.TmpDir,
    path: [:0]u8,
    prelude: [:0]u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = main });
        try dir.dir.writeFile(io, .{ .sub_path = "dep.blot", .data = original });
        try dir.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "const chosen:U32=41\n" });
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        const prelude = try dir.dir.realPathFileAlloc(io, "prelude.blot", a);
        return .{ .dir = dir, .path = path, .prelude = prelude };
    }
    fn write(self: *Fixture, name: []const u8, text: []const u8) !void {
        try self.dir.dir.writeFile(io, .{ .sub_path = name, .data = text });
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        a.free(self.prelude);
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
/// The restored-output bytes of a session's first build of `fixture`.
fn populated(fixture: *const Fixture) ![]u8 {
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    return (try session.encodeRestored(a, compiler, null)).?;
}
fn restoredSession(bytes: []const u8) !retained.Session {
    var session = try retained.Session.initEmpty(a, .{});
    errdefer session.deinit();
    session.restored = try retained.Restored.decode(a, compiler, bytes);
    return session;
}

test "restart cache: a restored output publishes only on equal inputs and equals a fresh build" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const expected = try fresh(&fixture);
    defer a.free(expected);
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    {
        var session = try restoredSession(bytes);
        defer session.deinit();
        var preparation = (try session.prepareRestored(io, fixture.path, null, .{}, &.{})).?;
        defer preparation.deinit();
        const candidate = preparation.ready;
        try std.testing.expect(candidate.stats.restored_output and candidate.stats.reused_output);
        try std.testing.expectEqualSlices(u8, expected, candidate.result().?.result.compiled.bytes);
        try std.testing.expect(session.commit(candidate));
        try std.testing.expect(session.current == null and session.restored != null and session.revisions == 1);
        // The next compiled revision takes over and releases the restored output.
        try fixture.write("dep.blot", edited);
        var changed = try session.revise(io, fixture.path, null, .{});
        defer changed.deinit(a);
        const edited_bytes = try fresh(&fixture);
        defer a.free(edited_bytes);
        try std.testing.expectEqualSlices(u8, edited_bytes, changed.result.compiled.bytes);
        try std.testing.expect(session.restored == null and session.current != null);
        try fixture.write("dep.blot", original);
    }
    // Each difference declines before anything is published.
    const Case = struct { options: project.Options = .{}, identity: ?[]const u8 = null, tier: @import("../compilation_tier.zig").Tier = .optimized, explain: bool = false, source: ?[]const u8 = null };
    const cases = [_]Case{ .{ .source = edited }, .{ .options = .{ .prelude_path = fixture.prelude } }, .{ .identity = "/other.wasm" }, .{ .tier = .development }, .{ .explain = true } };
    for (cases) |case| {
        if (case.source) |text| try fixture.write("dep.blot", text);
        defer fixture.write("dep.blot", original) catch {};
        var session = try restoredSession(bytes);
        defer session.deinit();
        session.policy.codegen_tier = case.tier;
        session.explain_demands = case.explain;
        try std.testing.expect(try session.prepareRestored(io, fixture.path, case.identity, case.options, &.{}) == null);
        try std.testing.expectEqual(@as(usize, 0), session.revisions);
    }
}

test "restart cache: restored output bytes from another compiler, or damaged, never decode" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    try std.testing.expectError(error.StaleArtifact, retained.Restored.decode(a, @splat(6), bytes));
    const damaged = try a.dupe(u8, bytes);
    defer a.free(damaged);
    damaged[damaged.len - 1] ^= 1;
    try std.testing.expectError(error.InvalidArtifact, retained.Restored.decode(a, compiler, damaged));
    try std.testing.expect(std.meta.isError(retained.Restored.decode(a, compiler, bytes[0 .. bytes.len / 2])));
    try std.testing.expect(std.meta.isError(retained.Restored.decode(a, compiler, "truncated checkpoint")));
}

fn decodeAndPublish(allocator: std.mem.Allocator, fixture: *const Fixture, bytes: []const u8, expected: []const u8) !void {
    var session = try retained.Session.initEmpty(allocator, .{});
    defer session.deinit();
    session.restored = try retained.Restored.decode(allocator, compiler, bytes);
    var preparation = (try session.prepareRestored(io, fixture.path, null, .{}, &.{})) orelse return error.NotRestored;
    defer preparation.deinit();
    try std.testing.expectEqualSlices(u8, expected, preparation.ready.result().?.result.compiled.bytes);
    try std.testing.expect(session.commit(preparation.ready));
}
fn encodeOnce(allocator: std.mem.Allocator, session: *const retained.Session, expected: []const u8) !void {
    const bytes = (try session.encodeRestored(allocator, compiler, "checkpoint")).?;
    defer allocator.free(bytes);
    try std.testing.expectEqualSlices(u8, expected, bytes[0..expected.len]);
}

test "restart cache: restored outputs encode, decode and publish under allocation failure" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    const expected = try fresh(&fixture);
    defer a.free(expected);
    const bytes = try populated(&fixture);
    defer a.free(bytes);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, decodeAndPublish, .{ &fixture, bytes, expected });
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var result = try session.revise(io, fixture.path, null, .{});
    defer result.deinit(a);
    const header = (try session.encodeRestored(a, compiler, "checkpoint")).?;
    defer a.free(header);
    try @import("../allocation_failures.zig").checkAllAllocationFailures(a, encodeOnce, .{ &session, header[0..64] });
}

test "restart cache: restored outputs past the default element limit round-trip" {
    // Wasm and sources are byte slices, which the format counts as elements.
    const wasm = try a.alloc(u8, 5 * 1024 * 1024);
    defer a.free(wasm);
    @memset(wasm, 0x2a);
    const files = [_]@import("revision_inputs.zig").Persisted.Pair{.{ .key = "/p/main.blot", .value = "entry const x: U32 = 1\n" }};
    const bytes = try retained.Restored.encodeWire(a, compiler, .{
        .settings = @splat(3),
        .entry_request = "/p/main.blot",
        .entry_canonical = "/p/main.blot",
        .output_identity = null,
        .policy = .{},
        .wasm = wasm,
        .source_bytes = files[0].value.len,
        .modules = 1,
        .checkpoint_digest = null,
        .inputs = .{ .options = .{}, .paths = &.{}, .files = &files, .imports = &.{} },
    });
    defer a.free(bytes);
    var restored = try retained.Restored.decode(a, compiler, bytes);
    defer restored.deinit();
    try std.testing.expectEqualSlices(u8, wasm, restored.output.bytes);
}
