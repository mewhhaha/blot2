const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const lowering = @import("../check/core_builder.zig");
const structural = @import("../structural.zig");
const profile = @import("../phase_profile.zig");
const A = std.mem.Allocator;
const Frontend = @import("../work_counters.zig").Frontend;

fn expectNoParallelClocks(counts: Frontend) !void {
    inline for (.{ "parallel_prepare_us", "parallel_batch_us", "parallel_capacity_us", "parallel_worker_us", "parallel_worker_cpu_us", "parallel_worker_cpu_samples", "parallel_worker_slots", "parallel_worker_jobs" }) |field| {
        try std.testing.expectEqual(@as(u64, 0), @field(counts, field));
    }
}

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
        try expectNoParallelClocks(counts);
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

test "parallel worker trace diagnostics are bounded and preserve serial Core and rejection diagnostics" {
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |rejected| {
        var fixture = try Fixture.init(a, rejected);
        defer fixture.deinit(a);
        var serial = try checker.checkProject(a, &fixture.source);
        defer serial.deinit(a);
        fixture.source.checking = .{ .io = std.testing.io, .workers = 16 };
        var counts: Frontend = .{};
        const capture = profile.captureChecking(&counts);
        defer capture.restore();
        var trace: profile.Trace = .init(std.testing.io, 0);
        const installation = profile.installTrace(&trace);
        defer installation.restore();
        var parallel = try checker.checkProjectWithPrivateExecution(a, &fixture.source, .{ .parallel_min_nodes = 0 });
        defer parallel.deinit(a);
        try std.testing.expect(counts.parallel_prepare_us > 0);
        try std.testing.expect(counts.parallel_batch_us > 0);
        try std.testing.expect(counts.parallel_worker_us > 0);
        try std.testing.expect(counts.parallel_worker_slots >= counts.parallel_batches);
        try std.testing.expect(counts.parallel_worker_slots <= 16 * counts.parallel_batches);
        try std.testing.expect(counts.parallel_capacity_us >= counts.parallel_batch_us);
        try std.testing.expect(counts.parallel_worker_us <= counts.parallel_capacity_us);
        try std.testing.expect(counts.parallel_worker_cpu_samples <= counts.parallel_worker_slots);
        if (@import("builtin").os.tag == .linux) try std.testing.expect(counts.parallel_worker_cpu_samples > 0);
        try std.testing.expectEqual(counts.parallel_jobs, counts.parallel_worker_jobs);
        try std.testing.expectEqual(serial.diagnostics.len, parallel.diagnostics.len);
        for (serial.diagnostics, parallel.diagnostics) |expected, actual| {
            try std.testing.expectEqual(expected.unit, actual.unit);
            try std.testing.expectEqual(expected.code, actual.code);
            try std.testing.expectEqual(expected.semantic, actual.semantic);
            try std.testing.expectEqualDeep(expected.span, actual.span);
        }
        if (rejected) {
            try std.testing.expect(counts.parallel_retries > 0);
            continue;
        }
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

test "unequal independent module bodies preserve serial Core and diagnostic order under parallel dispatch" {
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |rejected| {
        const left = if (rejected) "import {identity} from \"./shared\"\nconst first: U32 = 1.5\n" else "import {identity} from \"./shared\"\nconst first = func value => return identity value\n";
        const right = if (rejected) "import {identity} from \"./shared\"\nconst second: U32 = 1.5\nconst compose = func value => return identity (identity (identity value))\n" else "import {identity} from \"./shared\"\nconst second = func value => return identity (identity (identity value))\nconst compose = func value => return second (second value)\n";
        var fixture = try Fixture.initTexts(a, "const identity = func value => return value\n", left, right, "import {first} from \"./left\"\nimport {second} from \"./right\"\nentry const answer: U32 = first (second 42)\n");
        defer fixture.deinit(a);
        var left_at: ?usize = null;
        var right_at: ?usize = null;
        for (fixture.source.order.items, 0..) |unit, at| {
            const name = fixture.source.filename(unit);
            if (std.mem.endsWith(u8, name, "left.blot")) left_at = at;
            if (std.mem.endsWith(u8, name, "right.blot")) right_at = at;
        }
        // The larger independent module appears later in serial traversal, so
        // size-first dispatch must reverse this pair while retaining its laws.
        try std.testing.expect(left_at.? < right_at.?);
        const left_unit = fixture.source.order.items[left_at.?];
        const right_unit = fixture.source.order.items[right_at.?];
        try std.testing.expect(fixture.source.unit(left_unit).tree.nodes.items.len < fixture.source.unit(right_unit).tree.nodes.items.len);
        var serial = try checker.checkProject(a, &fixture.source);
        defer serial.deinit(a);
        fixture.source.checking = .{ .io = std.testing.io, .workers = 2 };
        var counts: Frontend = .{};
        const capture = profile.captureChecking(&counts);
        defer capture.restore();
        var parallel = try checker.checkProjectWithPrivateExecution(a, &fixture.source, .{ .parallel_min_nodes = 0 });
        defer parallel.deinit(a);
        try std.testing.expect(counts.parallel_jobs >= 3);
        try std.testing.expectEqual(serial.diagnostics.len, parallel.diagnostics.len);
        for (serial.diagnostics, parallel.diagnostics) |expected, actual| {
            try std.testing.expectEqual(expected.unit, actual.unit);
            try std.testing.expectEqual(expected.code, actual.code);
            try std.testing.expectEqual(expected.semantic, actual.semantic);
            try std.testing.expectEqualDeep(expected.span, actual.span);
        }
        if (rejected) {
            try std.testing.expect(serial.diagnostics.len >= 2);
            try std.testing.expectEqual(left_unit, serial.diagnostics[0].unit);
            try std.testing.expect(counts.parallel_retries > 0);
            continue;
        }
        try std.testing.expectEqual(@as(usize, 0), serial.diagnostics.len);
        try std.testing.expectEqual(@as(u64, 0), counts.parallel_retries);
        for (fixture.source.units.items, 1..) |*unit, id| {
            var expected = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &serial.module(@intCast(id)).checked);
            defer expected.deinit(a);
            var actual = try lowering.lower(a, &unit.tree, &fixture.source.symbols, &parallel.module(@intCast(id)).checked);
            defer actual.deinit(a);
            try std.testing.expect(structural.equal(expected, actual));
        }
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
