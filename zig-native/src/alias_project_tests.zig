const std = @import("std");
const project = @import("project.zig");
const checker = @import("project_check.zig");
const check = @import("check.zig");
const pipeline = @import("alias_project_pipeline.zig");
const artifacts = @import("code_artifacts.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const Source = struct { name: []const u8, text: []const u8 };
const Fixture = struct {
    tmp: std.testing.TmpDir,
    path: [:0]u8,
    prelude: ?[:0]u8,
    fn init(sources: []const Source, has_prelude: bool) !Fixture {
        var tmp = std.testing.tmpDir(.{});
        errdefer tmp.cleanup();
        for (sources) |source| try tmp.dir.writeFile(io, .{ .sub_path = source.name, .data = source.text });
        const path = try tmp.dir.realPathFileAlloc(io, "main.blot", a);
        errdefer a.free(path);
        const prelude = if (has_prelude) try tmp.dir.realPathFileAlloc(io, "prelude.blot", a) else null;
        return .{ .tmp = tmp, .path = path, .prelude = prelude };
    }
    fn deinit(self: *Fixture) void {
        a.free(self.path);
        if (self.prelude) |path| a.free(path);
        self.tmp.cleanup();
    }
    fn options(self: *const Fixture, mode: project.InputMode) project.Options {
        return .{ .input_mode = mode, .prelude_path = self.prelude };
    }
};
const Trace = struct {
    values: [256]check.GlobalTrace = undefined,
    len: usize = 0,
    fn observe(context: ?*anyopaque, value: check.GlobalTrace) void {
        const self: *Trace = @ptrCast(@alignCast(context.?));
        std.debug.assert(self.len < self.values.len);
        self.values[self.len] = value;
        self.len += 1;
    }
};
fn jsonEqual(left: anytype, right: anytype) !void {
    const l = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(l);
    const r = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(r);
    try std.testing.expectEqualStrings(l, r);
}
fn stateEqual(left: *const check.Checked, right: *const check.Checked) !void {
    inline for (@typeInfo(check.Checked).@"struct".field_names) |name| {
        if (comptime !std.mem.eql(u8, name, "types") and !std.mem.eql(u8, name, "parameter_patterns")) try jsonEqual(@field(left, name), @field(right, name));
    }
    inline for (.{ "nodes", "extra", "variables", "versions", "operations" }) |name| try jsonEqual(@field(left.types, name).items, @field(right.types, name).items);
    inline for (.{ "rows", "labels", "variables", "versions" }) |name| try jsonEqual(@field(left.types.effects, name).items, @field(right.types.effects, name).items);
    try std.testing.expectEqual(left.types.effects.next_position, right.types.effects.next_position);
    try std.testing.expectEqual(left.types.mutation_epoch, right.types.mutation_epoch);
    try std.testing.expectEqual(left.types.effects.mutation_epoch, right.types.effects.mutation_epoch);
    try std.testing.expectEqual(left.types.variable_views.count(), right.types.variable_views.count());
    var views = left.types.variable_views.iterator();
    while (views.next()) |view| try std.testing.expectEqual(view.value_ptr.*, right.types.variable_views.get(view.key_ptr.*).?);
    try jsonEqual(left.parameter_patterns.nodes.items, right.parameter_patterns.nodes.items);
    try jsonEqual(left.parameter_patterns.extra.items, right.parameter_patterns.extra.items);
}
fn projectEqual(left: *const checker.CheckedProject, right: *const checker.CheckedProject) !void {
    try jsonEqual(left.diagnostics, right.diagnostics);
    try std.testing.expectEqual(left.body_elaborations, right.body_elaborations);
    try std.testing.expectEqual(left.imported_schemes, right.imported_schemes);
    try std.testing.expectEqual(left.modules.len, right.modules.len);
    for (left.modules, right.modules) |l, r| {
        if (l) |lm| {
            const rm = r orelse return error.MissingCurrentModule;
            try std.testing.expectEqual(lm.valid, rm.valid);
            try jsonEqual(lm.exports, rm.exports);
            try stateEqual(&lm.checked, &rm.checked);
        } else try std.testing.expect(r == null);
    }
}
const prelude_source = "const identity = fn value => value\n";
const Cases = struct { name: []const u8, sources: []const Source, has_prelude: bool = false, mode: project.InputMode = .project, semantic_reject: bool = false, no_worker: bool = false };
const cases = [_]Cases{
    .{ .name = "no-import", .sources = &.{.{ .name = "main.blot", .text = "let first: U32 = second\nlet second: U32 = 42\nentry const answer = fn () => first\n" }} },
    .{ .name = "source", .mode = .source, .sources = &.{.{ .name = "main.blot", .text = "const first: U32 = second\nconst second: U32 = 42\nentry const answer = fn () => first\n" }} },
    .{ .name = "import", .has_prelude = true, .sources = &.{ .{ .name = "prelude.blot", .text = prelude_source }, .{ .name = "helper.blot", .text = "const supply: U32 = 0\n" }, .{ .name = "main.blot", .text = "import {supply} from \"./helper\"\nlet local: U32 = 42\nentry const answer = fn () => identity (@u32.add supply local)\n" } } },
    .{ .name = "nominal", .has_prelude = true, .sources = &.{ .{ .name = "prelude.blot", .text = prelude_source }, .{ .name = "main.blot", .text = "type Box is data = #Box U32\nlet local: U32 = 42\nlet boxed = #Box local\nentry const answer = fn () => case boxed of\n  #Box value => identity value\n" } } },
    .{ .name = "effect", .has_prelude = true, .sources = &.{ .{ .name = "prelude.blot", .text = prelude_source }, .{ .name = "main.blot", .text = "effect Read: Unit -> U32\nlet local: U32 = 42\nconst reader = @effect.provider Read (fn () => local)\nentry const answer = fn () => do reader:\n  return Read ()\n" } } },
    .{ .name = "mismatch", .semantic_reject = true, .sources = &.{.{ .name = "main.blot", .text = "const first: U32 = second\nconst second: F32 = 1.25\nentry const answer = fn () => 42\n" }} },
    .{ .name = "cycle", .sources = &.{.{ .name = "main.blot", .text = "let first: U32 = second\nlet second: U32 = first\nentry const answer = fn () => first\n" }} },
    .{ .name = "source-import-boundary", .mode = .source, .semantic_reject = true, .no_worker = true, .sources = &.{ .{ .name = "helper.blot", .text = "const supply = 42\n" }, .{ .name = "main.blot", .text = "import {supply} from \"./helper\"\nentry const answer = fn () => supply\n" } } },
};

test "project alias forwarding preserves every typed state history global trace and Wasm or diagnostic" {
    for (cases) |case_| {
        var fixture = try Fixture.init(case_.sources, case_.has_prelude);
        defer fixture.deinit();
        var source = try project.load(a, io, fixture.path, fixture.options(case_.mode));
        defer source.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
        const syntax = artifacts.stamp(.{ source.unit(source.entry).tree.nodes.items, source.unit(source.entry).tree.extra.items });
        var off_trace: Trace = .{};
        var on_trace: Trace = .{};
        var stats: check.AliasGlobalStats = .{};
        var off = try checker.checkProjectWithPrivateExecution(a, &source, .{ .context = &off_trace, .observe = Trace.observe });
        defer off.deinit(a);
        var on = try checker.checkProjectWithPrivateExecution(a, &source, .{ .alias_globals = true, .stats = &stats, .context = &on_trace, .observe = Trace.observe });
        defer on.deinit(a);
        try projectEqual(&off, &on);
        try jsonEqual(off_trace.values[0..off_trace.len], on_trace.values[0..on_trace.len]);
        try std.testing.expectEqualSlices(u8, &syntax, &artifacts.stamp(.{ source.unit(source.entry).tree.nodes.items, source.unit(source.entry).tree.extra.items }));
        if (case_.no_worker) try std.testing.expectEqual(@as(usize, 0), stats.frames) else try std.testing.expect(stats.frames > 0);
        if (case_.semantic_reject) {
            try std.testing.expect(on.diagnostics.len != 0);
            continue;
        }
        if (on.diagnostics.len != 0) {
            std.debug.print("project alias control {s} unexpectedly rejected\n", .{case_.name});
            return error.UnexpectedSemanticRejection;
        }
        var old_core = try pipeline.lowerChecked(a, &source, &off);
        defer old_core.deinit(a);
        var current_core = try pipeline.lowerChecked(a, &source, &on);
        defer current_core.deinit(a);
        for (old_core.units, current_core.units) |l, r| try std.testing.expectEqualSlices(u8, &artifacts.stamp(l), &artifacts.stamp(r));
        var l = try old_core.emit(a);
        defer l.deinit(a);
        var r = try current_core.emit(a);
        defer r.deinit(a);
        try std.testing.expectEqualSlices(u8, l.bytes, r.bytes);
        try jsonEqual(l.diagnostic, r.diagnostic);
        try std.testing.expectEqual(l.constant_steps, r.constant_steps);
    }
}

const long_source = @embedFile("alias-project-fixtures/logical-long-2048.blot");
test "project alias forwarding compiles the physical 2048 component only through enabled full project API" {
    var fixture = try Fixture.init(&.{.{ .name = "main.blot", .text = long_source }}, false);
    defer fixture.deinit();
    for ([_]project.InputMode{ .source, .project }) |mode| {
        var frozen = frontend: {
            var source = try project.load(a, io, fixture.path, fixture.options(mode));
            defer source.deinit(a);
            try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
            try std.testing.expectError(error.TypeLimit, checker.checkProject(a, &source));
            try std.testing.expectError(error.TypeLimit, checker.checkProjectWithPrivateExecution(a, &source, .{}));
            var stats: check.AliasGlobalStats = .{};
            var checked = try checker.checkProjectWithPrivateExecution(a, &source, .{ .alias_globals = true, .stats = &stats });
            defer checked.deinit(a);
            try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
            try std.testing.expectEqual(@as(usize, 2048), stats.peak_frames);
            try std.testing.expectEqual(@as(usize, 2048), stats.frames);
            break :frontend try pipeline.lowerChecked(a, &source, &checked);
        };
        defer frozen.deinit(a);
        var result = try frozen.emit(a);
        defer result.deinit(a);
        try std.testing.expect(result.diagnostic == null and result.bytes.len > 0);
    }
}

fn wholeProjectFailure(allocator: std.mem.Allocator, fixture: *const Fixture, expected: []const u8, work: usize) !void {
    var frozen = frontend: {
        var source = try project.load(allocator, io, fixture.path, fixture.options(.project));
        defer source.deinit(allocator);
        var stats: check.AliasGlobalStats = .{};
        var checked = try checker.checkProjectWithPrivateExecution(allocator, &source, .{ .alias_globals = true, .stats = &stats });
        defer checked.deinit(allocator);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        try std.testing.expect(stats.frames > 0);
        break :frontend try pipeline.lowerChecked(allocator, &source, &checked);
    };
    defer frozen.deinit(allocator);
    var result = try frozen.emit(allocator);
    defer result.deinit(allocator);
    try std.testing.expect(result.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, result.bytes);
    try std.testing.expectEqual(work, result.constant_steps);
}

test "project alias forwarding owns source free Core and releases every whole project allocation failure" {
    const sources = [_]Source{
        .{ .name = "prelude.blot", .text = prelude_source },
        .{ .name = "helper.blot", .text = "const supply: U32 = 0\n" },
        .{ .name = "main.blot", .text = "import {supply} from \"./helper\"\nlet first: U32 = second\nlet second: U32 = 42\nentry const answer = fn () => identity (@u32.add supply first)\n" },
    };
    var fixture = try Fixture.init(&sources, true);
    defer fixture.deinit();
    var frozen = frontend: {
        var source = try project.load(a, io, fixture.path, fixture.options(.project));
        defer source.deinit(a);
        var checked = try checker.checkProject(a, &source);
        defer checked.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
        break :frontend try pipeline.lowerChecked(a, &source, &checked);
    };
    defer frozen.deinit(a);
    var expected = try frozen.emit(a);
    defer expected.deinit(a);
    try std.testing.expect(expected.diagnostic == null);
    try @import("allocation_failures.zig").checkAllAllocationFailures(a, wholeProjectFailure, .{ &fixture, expected.bytes, expected.constant_steps });
    for (sources) |source| {
        const bytes = try fixture.tmp.dir.readFileAlloc(io, source.name, a, .limited(65536));
        defer a.free(bytes);
        try std.testing.expectEqualStrings(source.text, bytes);
    }
}

test "project alias forwarding keeps unsupported callable leading long source on ordinary TypeLimit" {
    const last_line = "entry const answer = fn () => cell0\n";
    try std.testing.expect(std.mem.endsWith(u8, long_source, last_line));
    const source = try std.mem.concat(a, u8, &.{ last_line, long_source[0 .. long_source.len - last_line.len] });
    defer a.free(source);
    var fixture = try Fixture.init(&.{.{ .name = "main.blot", .text = source }}, false);
    defer fixture.deinit();
    var loaded = try project.load(a, io, fixture.path, fixture.options(.project));
    defer loaded.deinit(a);
    try std.testing.expectError(error.TypeLimit, checker.checkProject(a, &loaded));
    var stats: check.AliasGlobalStats = .{};
    try std.testing.expectError(error.TypeLimit, checker.checkProjectWithPrivateExecution(a, &loaded, .{ .alias_globals = true, .stats = &stats }));
    try std.testing.expectEqual(@as(usize, 0), stats.frames);
}

test "project alias forwarding preserves ordinary partial preparation qualified import origins and Core bytes" {
    const partial = @import("partial_dependency.zig");
    const Dependency = @import("frozen_dependency.zig").FrozenDependency;
    var fixture = try Fixture.init(&.{
        .{ .name = "prelude.blot", .text = prelude_source },
        .{ .name = "helper.blot", .text = "type Box is data = #Box U32\nconst wrap = fn (value: U32) => #Box value\n" },
        .{ .name = "main.blot", .text = "import {Box, wrap} from \"./helper\"\nlet scalar: U32 = 42\nconst boxed = wrap 42\nentry const answer = fn () => case boxed of\n  #Box value => identity value\n" },
    }, true);
    defer fixture.deinit();
    var source = try project.load(a, io, fixture.path, fixture.options(.project));
    defer source.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    const empty: Dependency = .{ .modules = &.{}, .symbols = &.{} };
    var ordinary = try partial.prepareProject(a, &source, fixture.path, null, &empty);
    defer ordinary.deinit(a);
    const prepared = switch (ordinary) {
        .ready => |*ready| ready,
        .rejected => return error.UnexpectedOrdinaryRejection,
    };
    var stats: check.AliasGlobalStats = .{};
    var checked = try checker.checkProjectWithPrivateExecution(a, &source, .{ .alias_globals = true, .stats = &stats });
    defer checked.deinit(a);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(stats.frames > 0);
    var candidate = try pipeline.lowerChecked(a, &source, &checked);
    defer candidate.deinit(a);
    try std.testing.expectEqual(prepared.entry, candidate.entry);
    try std.testing.expectEqual(prepared.prelude, candidate.prelude);
    try std.testing.expectEqualSlices(u32, prepared.unit_order, candidate.order);
    try jsonEqual(prepared.identity.view(), candidate.names.view());
    for (prepared.units, candidate.units) |l, r| try std.testing.expectEqualSlices(u8, &artifacts.stamp(l), &artifacts.stamp(r));
    var output = try prepared.emit(a);
    defer output.deinit(a);
    var result = try candidate.emit(a);
    defer result.deinit(a);
    try std.testing.expect(result.diagnostic == null and output.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, output.result.compiled.bytes, result.bytes);
    try std.testing.expectEqual(output.result.compiled.constant_steps, result.constant_steps);
}
