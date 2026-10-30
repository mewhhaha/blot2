const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const lowering = @import("../check/core_builder.zig");
const structural = @import("../structural.zig");
const profile = @import("../phase_profile.zig");
const A = std.mem.Allocator;

const Fixture = struct {
    dir: std.testing.TmpDir,
    source: project.Project,
    fn init(a: A, rejected: bool) !Fixture {
        return initTexts(a, "const identity = func value => return value\n", if (rejected) "const first: U32 = 1.5\n" else "import {identity} from \"./shared\"\nconst first = func value => return identity value\n", "import {identity} from \"./shared\"\nconst second = func value => return identity value\n", "import {first} from \"./left\"\nimport {second} from \"./right\"\nentry const answer: U32 = first (second 42)\n");
    }
    fn initTexts(a: A, shared: []const u8, left: []const u8, right: []const u8, main: []const u8) !Fixture {
        var dir = std.testing.tmpDir(.{});
        errdefer dir.cleanup();
        for ([_][]const u8{ "shared.blot", "left.blot", "right.blot", "main.blot" }, [_][]const u8{ shared, left, right, main }) |name, source| {
            try dir.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = source });
        }
        const path = try dir.dir.realPathFileAlloc(std.testing.io, "main.blot", a);
        defer a.free(path);
        var source = try project.load(a, std.testing.io, path, .{});
        errdefer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        return .{ .dir = dir, .source = source };
    }
    fn deinit(self: *Fixture, a: A) void {
        self.source.deinit(a);
        self.dir.cleanup();
    }
};

test "parallel module checking preserves serial Core and counters with independent solver ownership" {
    const a = std.testing.allocator;
    var fixture = try Fixture.init(a, false);
    defer fixture.deinit(a);
    var serial = try checker.checkProject(a, &fixture.source);
    defer serial.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), serial.diagnostics.len);
    for ([_]u8{ 2, 4, 16 }) |workers| {
        fixture.source.checking = .{ .io = std.testing.io, .workers = workers };
        var counts: @import("../work_counters.zig").Frontend = .{};
        const capture = profile.captureChecking(&counts);
        defer capture.restore();
        var parallel = try checker.checkProjectWithPrivateExecution(a, &fixture.source, .{ .parallel_min_nodes = 0 });
        defer parallel.deinit(a);
        try std.testing.expectEqual(@as(u64, fixture.source.order.items.len), counts.parallel_jobs);
        try std.testing.expectEqual(@as(u64, 0), counts.parallel_retries);
        try std.testing.expectEqual(@as(usize, 0), parallel.diagnostics.len);
        try std.testing.expectEqual(serial.body_elaborations, parallel.body_elaborations);
        try std.testing.expectEqual(serial.imported_schemes, parallel.imported_schemes);
        for (fixture.source.units.items, 1..) |*unit, id| {
            var expected = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &serial.module(@intCast(id)).checked);
            defer expected.deinit(a);
            var actual = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &parallel.module(@intCast(id)).checked);
            defer actual.deinit(a);
            try std.testing.expect(structural.equal(expected, actual));
        }
    }
}

test "parallel module rejection replays serial diagnostic order" {
    const a = std.testing.allocator;
    var fixture = try Fixture.init(a, true);
    defer fixture.deinit(a);
    var serial = try checker.checkProject(a, &fixture.source);
    defer serial.deinit(a);
    fixture.source.checking = .{ .io = std.testing.io, .workers = 4 };
    var counts: @import("../work_counters.zig").Frontend = .{};
    const capture = profile.captureChecking(&counts);
    defer capture.restore();
    var parallel = try checker.checkProjectWithPrivateExecution(a, &fixture.source, .{ .parallel_min_nodes = 0 });
    defer parallel.deinit(a);
    try std.testing.expect(counts.parallel_retries != 0);
    try std.testing.expectEqual(serial.diagnostics.len, parallel.diagnostics.len);
    for (serial.diagnostics, parallel.diagnostics) |expected, actual| {
        try std.testing.expectEqual(expected.unit, actual.unit);
        try std.testing.expectEqual(expected.code, actual.code);
        try std.testing.expectEqual(expected.semantic, actual.semantic);
        try std.testing.expectEqualDeep(expected.span, actual.span);
    }
}

fn faultScenario(a: A, source: *project.Project) !void {
    var result = try checker.checkProjectWithPrivateExecution(a, source, .{ .parallel_min_nodes = 0 });
    defer result.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.len);
}
test "parallel module workers release joined results and solver allocators across concurrent allocation failures" {
    const a = std.testing.allocator;
    var fixture = try Fixture.init(a, false);
    defer fixture.deinit(a);
    // Symbol preparation stays outside the failing allocator's lifetime.
    var serial = try checker.checkProject(a, &fixture.source);
    defer serial.deinit(a);
    _ = try fixture.source.symbols.intern(a, "result");
    _ = try fixture.source.symbols.intern(a, "effects");
    fixture.source.checking = .{ .io = std.testing.io, .workers = 4 };
    try @import("../allocation_failures.zig").checkObservedConcurrentFailures(a, faultScenario, .{&fixture.source});
}

fn summaryScenario(a: A) !void {
    var fixture = try Fixture.initTexts(a, "const read = func value => return value.field\nconst apply = func callback => return func value => return callback value\n", "import {read, apply} from \"./shared\"\nconst first = func value => return apply read value\n", "import {read, apply} from \"./shared\"\nconst second = func value => return apply read value\n", "import {first} from \"./left\"\nimport {second} from \"./right\"\nentry const answer: U32 = first {field: 42}\nentry const fraction: F32 = second {field: 1.5}\n");
    defer fixture.deinit(a);
    var expected = try checker.checkProjectWithPrivateExecution(a, &fixture.source, .{ .imported_summary_reuse = false });
    defer expected.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), expected.diagnostics.len);
    var counts: @import("../work_counters.zig").Frontend = .{};
    const capture = profile.captureChecking(&counts);
    defer capture.restore();
    var actual = try checker.checkProject(a, &fixture.source);
    defer actual.deinit(a);
    try std.testing.expect(counts.imported_summary_reuses > 0);
    try std.testing.expectEqual(@as(usize, 0), actual.diagnostics.len);
    for (fixture.source.units.items, 1..) |*unit, id| {
        var expected_core = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &expected.module(@intCast(id)).checked);
        defer expected_core.deinit(a);
        var actual_core = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &actual.module(@intCast(id)).checked);
        defer actual_core.deinit(a);
        try std.testing.expect(structural.equal(expected_core, actual_core));
    }
}
test "immutable imported sharing summaries preserve fresh quantifiers callback rows and Core through OOM" {
    try @import("../allocation_failures.zig").checkAllAllocationFailures(std.testing.allocator, summaryScenario, .{});
}
