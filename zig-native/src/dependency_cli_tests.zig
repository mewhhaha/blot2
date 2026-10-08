const std = @import("std");
const cli = @import("dependency_cli.zig");
const project = @import("project.zig");
const a = std.testing.allocator;
const compiler = @as([32]u8, @splat(31));
const io = std.testing.io;

fn canonicalFail(allocator: std.mem.Allocator, options: project.Options) !void {
    var owned = try cli.CanonicalOptions.init(allocator, io, options);
    defer owned.deinit(allocator);
    try std.testing.expect(owned.prelude_path != null and owned.aliases.len == 2);
}
test "cache options preserve arbitrary alias order with owned canonical roots and OOM cleanup" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "prelude.blot", .data = "const identity=fn value=>value\n" });
    const prelude = try dir.dir.realPathFileAlloc(io, "prelude.blot", a);
    defer a.free(prelude);
    const root = try dir.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const dotted = try a.print("{s}/.", .{root});
    defer a.free(dotted);
    const options: project.Options = .{ .prelude_path = prelude, .std_root = dotted, .aliases = &.{ .{ .prefix = "one/", .root = dotted }, .{ .prefix = "two/", .root = root } } };
    var first = try cli.CanonicalOptions.init(a, io, options);
    defer first.deinit(a);
    var second = try cli.CanonicalOptions.init(a, io, .{ .prelude_path = prelude, .std_root = root, .aliases = &.{ .{ .prefix = "one/", .root = root }, .{ .prefix = "two/", .root = dotted } } });
    defer second.deinit(a);
    try std.testing.expectEqualSlices(u8, &cli.settings(first.view(options)), &cli.settings(second.view(options)));
    try std.testing.expectEqualStrings("one/", first.aliases[0].prefix);
    try std.testing.expectEqualStrings(root, first.aliases[0].root);
    try std.testing.expectError(error.InputModeUnsupported, cli.CanonicalOptions.init(a, io, .{ .input_mode = .source }));
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, canonicalFail, .{options});
}

const Fixture = struct {
    dir: std.testing.TmpDir,
    entry: [:0]u8,
    artifact: []u8,
    output: []u8,
    fn init() !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        try dir.dir.writeFile(io, .{ .sub_path = "library.blot", .data = "const identity=fn value=>value\n" });
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = "import {identity} from \"./library\"\nentry const answer:Unit->U32=fn()=>identity 42\n" });
        const entry = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(entry);
        const root = try dir.dir.realPathFileAlloc(io, ".", a);
        defer a.free(root);
        const artifact = try std.Io.Dir.path.join(a, &.{ root, "dependencies.blotdep" });
        errdefer a.free(artifact);
        return .{ .dir = dir, .entry = entry, .artifact = artifact, .output = try std.Io.Dir.path.join(a, &.{ root, "output.wasm" }) };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.entry);
        a.free(self.artifact);
        a.free(self.output);
        self.dir.cleanup();
    }
};
fn runWork(allocator: std.mem.Allocator, create: bool, f: *const Fixture) !void {
    var buffer: [256]u8 = undefined;
    var discarding: std.Io.Writer.Discarding = .init(&buffer);
    var stats: cli.Metrics = .{};
    try std.testing.expect(try cli.work(io, allocator, &discarding.writer, create, f.entry, if (create) f.artifact else f.output, if (create) null else f.artifact, .{}, compiler, &stats));
}
test "CLI creation and cached consumer release owners at every allocation failure" {
    var f = try Fixture.init();
    defer f.deinit();
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, runWork, .{ true, &f });
    const before = try f.dir.dir.readFileAlloc(io, "dependencies.blotdep", a, .limited(1024 * 1024));
    defer a.free(before);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, runWork, .{ false, &f });
    const after = try f.dir.dir.readFileAlloc(io, "dependencies.blotdep", a, .limited(1024 * 1024));
    defer a.free(after);
    try std.testing.expectEqualSlices(u8, before, after);
}

test "CLI declined admission preserves an existing destination and emits teardown-zero metrics" {
    var f = try Fixture.init();
    defer f.deinit();
    try runWork(a, true, &f);
    try f.dir.dir.writeFile(io, .{ .sub_path = "output.wasm", .data = "previous complete output" });
    try f.dir.dir.writeFile(io, .{ .sub_path = "library.blot", .data = "const identity=fn value=>@u32.add value 1\n" });
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    try std.testing.expect(!try cli.process(io, a, &output.writer, false, f.entry, f.output, f.artifact, .{}, compiler));
    try std.testing.expect(std.mem.find(u8, output.written(), "InvalidArtifact") != null);
    try std.testing.expect(std.mem.find(u8, output.written(), "\"live_bytes\":0") != null);
    const kept = try f.dir.dir.readFileAlloc(io, "output.wasm", a, .limited(1024));
    defer a.free(kept);
    try std.testing.expectEqualStrings("previous complete output", kept);
}
