const std = @import("std");
const project = @import("../reuse/project.zig");
const checker = @import("../reuse/project_check.zig");
const C = @import("../check/core.zig");
const a = std.testing.allocator;
const io = std.testing.io;
const Source = struct { name: []const u8, text: []const u8 };
fn scenario(allocator: std.mem.Allocator, path: []const u8, expected: ?[]const u8) !void {
    var source = try project.load(allocator, io, path, .{});
    defer source.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), source.diagnostics.items.len);
    var checked = try checker.checkProject(allocator, &source);
    defer checked.deinit(allocator);
    if (expected) |code| {
        for (checked.diagnostics) |issue| if (std.mem.eql(u8, issue.codeName(), code)) return;
        for (checked.diagnostics) |issue| std.debug.print("implementation project {s} unit{d} at{d}\n", .{ issue.codeName(), issue.unit, issue.span.start });
        return error.TestUnexpectedResult;
    }
    for (checked.diagnostics) |issue| std.debug.print("implementation project {s} unit{d} at{d}\n", .{ issue.codeName(), issue.unit, issue.span.start });
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    const units = try allocator.alloc(C.Module, source.units.items.len);
    defer allocator.free(units);
    var initialized: usize = 0;
    defer for (units[0..initialized]) |*unit| unit.deinit(allocator);
    for (units, 1..) |*unit, id| {
        unit.* = try C.lower(allocator, &source.unit(@intCast(id)).tree, &source.symbols, &checked.module(@intCast(id)).checked);
        initialized += 1;
        unit.unit = @intCast(id);
    }
    var session = try @import("core_eval.zig").Session.init(allocator, units);
    defer session.deinit();
    for (units[source.entry - 1].bodies) |body| if (body.exported) {
        const value = session.value(.{ .unit = source.entry, .binding = body.binding }) catch |err| {
            if (session.diagnostic) |issue| std.debug.print("implementation project execution {s} unit{d} at{d}\n", .{ @tagName(issue.code), issue.unit, issue.span.start });
            return err;
        };
        try std.testing.expectEqual(@as(u32, 42), value.bits);
    };
    var compiled = try @import("../backend/core_backend.zig").compile(allocator, units, source.entry);
    defer compiled.deinit(allocator);
    if (compiled.diagnostic) |issue| std.debug.print("implementation project emit {s} unit{d} at{d}\n", .{ @tagName(issue.code), issue.unit, issue.span.start });
    try std.testing.expect(compiled.diagnostic == null and compiled.bytes.len > 8);
}
fn files(sources: []const Source, expected: ?[]const u8, sweep: bool) !void {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    for (sources) |source| try dir.dir.writeFile(io, .{ .sub_path = source.name, .data = source.text });
    const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(path);
    try scenario(a, path, expected);
    if (sweep) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, scenario, .{ path, expected });
}
const producer = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl ArraySource a : Source (Array a) = { type Item = a, const first = fn values => @array.get values 0 }\n";
test "implementation imported forwarding aliases deduplicate original evidence and execute producer methods" {
    try files(&.{
        .{ .name = "main.blot", .text = "import { Source } from \"./source\"\nimport * as public from \"./forward\"\nentry const answer: U32 = @u32.add (Source.first #[20]) (public.Protocol.first #[22])\n" },
        .{ .name = "forward.blot", .text = "export { Source as Protocol, ArraySource as Witness } from \"./source\"\n" },
        .{ .name = "source.blot", .text = producer },
    }, null, true);
}
test "implementation orphan anchor ownership and graph coherence use original producers" {
    try files(&.{
        .{ .name = "main.blot", .text = "import { Source } from \"./source\"\nimport { Token } from \"./token\"\nimpl Foreign : Source Token = { type Item = U32 }\nentry const answer = 42\n" },
        .{ .name = "source.blot", .text = "type Source s is contract = { type Item }\n" },
        .{ .name = "token.blot", .text = "opaque type Token = U32\n" },
    }, "orphan_implementation", false);
    try files(&.{
        .{ .name = "main.blot", .text = "import { Source } from \"./source\"\nimport { read } from \"./token\"\nentry const answer: U32 = read ()\n" },
        .{ .name = "source.blot", .text = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\n" },
        .{ .name = "token.blot", .text = "import { Source } from \"./source\"\nopaque type Token = U32\nimpl TokenSource : Source Token = { type Item = U32, const first = fn value => do:\n  let #Token number = value\n  break number }\nconst read: Unit -> U32 = fn () => Source.first (#Token 42)\n" },
    }, null, false);
    try files(&.{
        .{ .name = "main.blot", .text = "import { Source } from \"./left\"\nimport { marker } from \"./right\"\nentry const answer: U32 = Source.first #[42]\n" },
        .{ .name = "left.blot", .text = producer },
        .{ .name = "right.blot", .text = "import { Source } from \"./left\"\nimpl Everything a : Source a = { type Item = a, const first = fn value => value }\nconst marker = 0\n" },
    }, "overlapping_implementation", false);
}
test "implementation private helpers retain lexical evidence while public generics need caller witnesses" {
    const hidden = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nprivate impl Hidden : Source U32 = { type Item = U32, const first = fn value => value }\nconst read: U32 -> U32 = fn value => Source.first value\nconst generic: s -> (Source.Item s) where { Source s } = fn value => Source.first value\n";
    try files(&.{
        .{ .name = "main.blot", .text = "import { read } from \"./hidden\"\nentry const answer: U32 = read 42\n" },
        .{ .name = "hidden.blot", .text = hidden },
    }, null, true);
    try files(&.{
        .{ .name = "main.blot", .text = "import { generic } from \"./hidden\"\nentry const answer: U32 = generic 42\n" },
        .{ .name = "hidden.blot", .text = hidden },
    }, "missing_implementation", false);
}

const revision_sources = [_]Source{
    .{ .name = "main.blot", .text = "import { Source } from \"./dep\"\nentry const answer: Unit -> U32 = fn () => Source.first 42\n" },
    .{ .name = "dep.blot", .text = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = U32, const first = fn value => value }\n" },
};
fn canonicalOverlap(allocator: std.mem.Allocator, path: []const u8) !void {
    var source = try project.load(allocator, io, path, .{});
    defer source.deinit(allocator);
    try std.testing.expect(source.diagnostics.items.len == 0);
    var checked = try checker.checkProject(allocator, &source);
    defer checked.deinit(allocator);
    for (checked.diagnostics) |issue| {
        if (!std.mem.eql(u8, issue.codeName(), "overlapping_implementation")) continue;
        try std.testing.expect(std.mem.endsWith(u8, source.filename(issue.unit), "/z.blot"));
        try std.testing.expect(std.mem.startsWith(u8, source.unit(issue.unit).source[issue.span.start..], "impl All"));
        const explanation = issue.explanation orelse return error.TestUnexpectedResult;
        try std.testing.expect(explanation.candidates.len == 2);
        try std.testing.expectEqualStrings("Other", explanation.candidates[0].origin.?.name.?);
        try std.testing.expectEqualStrings("All", explanation.candidates[1].origin.?.name.?);
        return;
    }
    return error.TestUnexpectedResult;
}
test "implementation overlap diagnostics keep canonical producer source origins across import order" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    try dir.dir.writeFile(io, .{ .sub_path = "z.blot", .data = "type Source s is contract = { type Item }\nimpl All a : Source a = { type Item = a }\n" });
    try dir.dir.writeFile(io, .{ .sub_path = "a.blot", .data = "import { Source } from \"./z\"\ntype Token is data = #Token U32\nimpl Other : Source Token = { type Item = U32 }\nconst marker = 0\n" });
    for ([_][]const u8{
        "import { marker } from \"./a\"\nimport { Source } from \"./z\"\nentry const answer = 42\n",
        "import { Source } from \"./z\"\nimport { marker } from \"./a\"\nentry const answer = 42\n",
    }, 0..) |text, index| {
        try dir.dir.writeFile(io, .{ .sub_path = "main.blot", .data = text });
        const path = try dir.dir.realPathFileAlloc(io, "main.blot", a);
        defer a.free(path);
        try canonicalOverlap(a, path);
        if (index == 0) try @import("../allocation_failures.zig").checkAllAllocationFailures(a, canonicalOverlap, .{path});
    }
}
const revision_edit = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = U32, const first = fn value => @u32.add value 1 }\n";
fn sameRevision(actual: *const @import("../reuse/partial_dependency.zig").Result, expected: *const @import("../reuse/partial_dependency.zig").Result) !void {
    try std.testing.expectEqualDeep(expected.result.diagnostic, actual.result.diagnostic);
    try std.testing.expectEqualDeep(expected.result.compiled.diagnostic, actual.result.compiled.diagnostic);
    try std.testing.expectEqualSlices(u8, expected.result.compiled.bytes, actual.result.compiled.bytes);
}
fn retainedImplementationFailure(allocator: std.mem.Allocator, session: *@import("../reuse/retained_revision.zig").Session, entry: []const u8, dependency: []const u8, expected: []const u8) !void {
    const previous = session.allocator;
    session.allocator = allocator;
    defer session.allocator = previous;
    const revision = session.revisions;
    const before = @import("../reuse/code_artifacts.zig").stamp(session.seed);
    defer {
        std.testing.expectEqual(revision, session.revisions) catch @panic("Failed implementation edit published a revision");
        std.testing.expectEqualSlices(u8, &before, &@import("../reuse/code_artifacts.zig").stamp(session.seed)) catch @panic("Failed implementation edit changed owned evidence");
    }
    var candidate = try session.prepareRevisionWithSources(io, entry, null, .{}, &.{.{ .path = dependency, .contents = revision_edit }});
    defer candidate.deinit();
    try std.testing.expect(candidate == .ready);
    try std.testing.expect(candidate.ready.result().?.result.diagnostic == null and candidate.ready.result().?.result.compiled.diagnostic == null);
    try std.testing.expectEqualSlices(u8, expected, candidate.ready.result().?.result.compiled.bytes);
}
test "implementation retained body equation and reference edits preserve failed revisions through OOM" {
    var dir = std.testing.tmpDir(.{});
    defer dir.cleanup();
    for (revision_sources) |source| try dir.dir.writeFile(io, .{ .sub_path = source.name, .data = source.text });
    const entry = try dir.dir.realPathFileAlloc(io, "main.blot", a);
    defer a.free(entry);
    const dependency = try dir.dir.realPathFileAlloc(io, "dep.blot", a);
    defer a.free(dependency);
    const retained = @import("../reuse/retained_revision.zig");
    var session = try retained.Session.initEmpty(a, .{});
    defer session.deinit();
    var initial = try session.revise(io, entry, null, .{});
    defer initial.deinit(a);
    try std.testing.expect(initial.result.diagnostic == null and initial.result.compiled.diagnostic == null);
    const edits = [_]struct { consumer: []const u8, producer: []const u8 }{
        .{ .consumer = revision_sources[0].text, .producer = revision_edit },
        .{ .consumer = "import { Source } from \"./dep\"\nentry const answer: Unit -> F32 = fn () => Source.first 42\n", .producer = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = F32, const first = fn value => @u32.to_f32 value }\n" },
        .{ .consumer = "import { Source } from \"./dep\"\nentry const answer: Unit -> Array U32 = fn () => Source.first 42\n", .producer = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 = { type Item = Array U32, const first = fn value => #[value] }\n" },
        .{ .consumer = revision_sources[0].text, .producer = "type Source s is contract = { type Item, const first: s -> (Source.Item s) }\nimpl Scalar : Source U32 where { type_eq U32 F32 } = { type Item = U32, const first = fn value => value }\n" },
        .{ .consumer = revision_sources[0].text, .producer = revision_sources[1].text },
    };
    for (edits, 0..) |edit, index| {
        const sources = [_]@import("../reuse/source_overlays.zig").Source{ .{ .path = entry, .contents = edit.consumer }, .{ .path = dependency, .contents = edit.producer } };
        var fresh = try retained.Session.initEmpty(a, .{});
        defer fresh.deinit();
        var expected = try fresh.prepareRevisionWithSources(io, entry, null, .{}, &sources);
        defer expected.deinit();
        const revision = session.revisions;
        const before = @import("../reuse/code_artifacts.zig").stamp(session.seed);
        var actual = try session.prepareRevisionWithSources(io, entry, null, .{}, &sources);
        defer actual.deinit();
        if (expected == .rejected) {
            try std.testing.expect(actual == .rejected);
            try sameRevision(&actual.rejected.result, &expected.rejected.result);
            try std.testing.expectEqual(revision, session.revisions);
            try std.testing.expectEqualSlices(u8, &before, &@import("../reuse/code_artifacts.zig").stamp(session.seed));
        } else {
            try std.testing.expect(actual == .ready);
            try sameRevision(actual.ready.result().?, expected.ready.result().?);
            if (index == 0) {
                try std.testing.expect(!std.mem.eql(u8, initial.result.compiled.bytes, actual.ready.result().?.result.compiled.bytes));
                try std.testing.expect(session.discard(actual.ready));
                try @import("../allocation_failures.zig").checkAllAllocationFailures(a, retainedImplementationFailure, .{ &session, entry, dependency, expected.ready.result().?.result.compiled.bytes });
                var retry = try session.prepareRevisionWithSources(io, entry, null, .{}, &sources);
                defer retry.deinit();
                try std.testing.expect(retry == .ready);
                try sameRevision(retry.ready.result().?, expected.ready.result().?);
                try std.testing.expect(session.commit(retry.ready));
            } else try std.testing.expect(session.commit(actual.ready));
        }
    }
}
